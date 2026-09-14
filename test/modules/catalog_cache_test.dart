import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transasim_mobile/core/network/api_client.dart';
import 'package:transasim_mobile/core/storage/json_disk_cache.dart';
import 'package:transasim_mobile/modules/catalog/data/catalog_repository_impl.dart';
import 'package:transasim_mobile/modules/catalog/presentation/catalog_controllers.dart';

/// The launch prefetch and the catalogue cache, counted on the wire: the Store
/// opened mid-prefetch starts no second fetch, a recent copy costs no request,
/// and an old one or a pull-to-refresh does.

class _Wire {
  final Dio dio = Dio();
  final List<String> sent = [];

  /// Held until released, so "the Store opened while the prefetch runs" is a
  /// real overlap, not a race the test happens to win.
  Completer<void> gate = Completer<void>()..complete();

  _Wire() {
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) async {
      sent.add(options.path);
      await gate.future;
      handler.resolve(Response<dynamic>(
        requestOptions: options,
        statusCode: 200,
        data: options.path.endsWith('countries/all')
            ? [
                {'code': 'FRA', 'country': 'France'},
              ]
            : {
                'content': [
                  {
                    'id': 1,
                    'name': 'France 1GB',
                    'dataValue': 1024 * 1024,
                    'validityDuration': 7,
                    'validityDurationUnit': 'DAYS',
                    'countries': [
                      {'code': 'FRA'},
                    ],
                    'prices': [
                      {
                        'sabilyAmount': 4.5,
                        'currency': {'code': 'EUR'},
                      },
                    ],
                  },
                ],
              },
      ));
    }));
  }

  int get packsCalls => sent.where((p) => p.endsWith('packs/all')).length;
}

void main() {
  late Directory dir;
  late _Wire wire;
  late DateTime now;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('catalog_cache_test');
    wire = _Wire();
    now = DateTime(2026, 9, 14, 12);
  });
  // The disk write is fire-and-forget; one may still be landing.
  tearDown(() async {
    for (var i = 0;; i++) {
      try {
        return dir.deleteSync(recursive: true);
      } on FileSystemException {
        if (i == 50) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }
  });

  CatalogRepositoryImpl repo() => CatalogRepositoryImpl(
        api: ApiClient(
          baseUrl: 'https://example.test/api',
          token: () => null,
          language: () => 'fr',
          dio: wire.dio,
        ),
        currencyCode: 'EUR',
        disk: JsonDiskCache(
          name: 'catalog',
          source: 'https://example.test/api',
          directory: () async => dir,
        ),
        now: () => now,
      );

  /// The disk write is fire-and-forget; wait for the file rather than a delay.
  Future<void> savedToDisk() async {
    final file = File('${dir.path}/catalog.json');
    for (var i = 0; i < 200 && !file.existsSync(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(file.existsSync(), isTrue);
  }

  test('asked again while the first load runs: one fetch, shared', () async {
    final r = repo();
    wire.gate = Completer<void>();
    final prefetch = r.destinations();
    await Future<void>.delayed(Duration.zero);
    final store = r.destinations();
    wire.gate.complete();

    expect((await prefetch).single.name, 'France');
    expect(identical(await store, await prefetch), isTrue);
    expect(wire.packsCalls, 1);
  });

  test('a cold start within the hour uses the disk copy, no request', () async {
    await repo().destinations();
    await savedToDisk();
    expect(wire.packsCalls, 1);

    now = now.add(const Duration(minutes: 59));
    final restarted = await repo().destinations();
    expect(restarted.single.packs.single.price!.wireAmount, '4.5');
    expect(wire.packsCalls, 1, reason: 'fresh copy on disk');
  });

  test('a copy an hour old is refetched', () async {
    await repo().destinations();
    await savedToDisk();

    now = now.add(CatalogRepositoryImpl.freshFor);
    await repo().destinations();
    expect(wire.packsCalls, 2);
  });

  test('the same process past the hour refetches too', () async {
    final r = repo();
    await r.destinations();
    now = now.add(const Duration(minutes: 61));
    await r.destinations();
    expect(wire.packsCalls, 2);
  });

  test('a clock set backwards does not make an old copy fresh forever', () async {
    await repo().destinations();
    await savedToDisk();
    now = now.subtract(const Duration(days: 1));
    await repo().destinations();
    expect(wire.packsCalls, 2);
  });

  test('pull-to-refresh asks the server even with a fresh copy', () async {
    final r = repo();
    await r.destinations();
    await r.destinations(refresh: true);
    expect(wire.packsCalls, 2);
  });

  test('a copy saved from another backend is not used', () async {
    await repo().destinations();
    await savedToDisk();
    final other = CatalogRepositoryImpl(
      api: ApiClient(baseUrl: 'https://other.test/api', token: () => null, language: () => 'fr', dio: wire.dio),
      currencyCode: 'EUR',
      disk: JsonDiskCache(name: 'catalog', source: 'https://other.test/api', directory: () async => dir),
      now: () => now,
    );
    await other.destinations();
    expect(wire.packsCalls, 2);
  });

  test('a corrupt file is no cache, not a crash', () async {
    File('${dir.path}/catalog.json').writeAsStringSync('{not json');
    expect((await repo().destinations()).single.name, 'France');
    expect(wire.packsCalls, 1);
  });

  test('the launch prefetch is the Store\'s own load: opening it adds no request', () async {
    final container = ProviderContainer(overrides: [
      catalogRepositoryProvider.overrideWithValue(repo()),
    ]);
    addTearDown(container.dispose);
    wire.gate = Completer<void>();

    // What _PrefetchCatalog does at launch.
    container.read(catalogControllerProvider);
    await Future<void>.delayed(Duration.zero);

    // The Store opens while it is still running: it sees the loading state.
    final sub = container.listen(catalogControllerProvider, (_, _) {});
    addTearDown(sub.close);
    expect(sub.read().isLoading, isTrue);

    wire.gate.complete();
    final state = await container.read(catalogControllerProvider.future);
    expect(state, isA<CatalogReady>());
    expect(wire.packsCalls, 1);
  });
}
