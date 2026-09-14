import 'dart:async';

import '../../../core/network/api_client.dart';
import '../../../core/perf/perf_log.dart';
import '../../../core/result/result.dart';
import '../../../core/storage/json_disk_cache.dart';
import '../domain/catalog.dart';
import 'catalog_dto.dart';

/// Joins countries and packs into destinations.
///
/// Two calls, run concurrently, joined on the device — the same shape the old
/// app used and one of the few things worth keeping (api-contract.md §3):
///
///   GET /v1/countries/all   -> [Country]        public
///   GET /v1/packs/all       -> {content: [...]} public, the ONLY Page envelope
///
/// `packs/all` is ~1.4 MB behind a 3-4 s server wait, so it is asked for as
/// rarely as correctness allows: a catalogue younger than [freshFor] comes
/// from memory, else from disk, and only then from the network. Callers that
/// overlap share one fetch. The old app refetched the whole catalogue on every
/// screen entry (`ANALYSE-EXISTANT.md` §3).
class CatalogRepositoryImpl implements CatalogRepository {
  /// How long a catalogue is used without asking the server. Checkout charges
  /// the price the card shows, so this is also how long a backend price change
  /// can take to reach the app. Pull-to-refresh ignores it.
  static const freshFor = Duration(hours: 1);

  final ApiClient _api;
  final String _currencyCode;

  /// The raw `countries/all` and `packs/all` bodies as last received, so the
  /// parsers stay the only code that reads the wire shape.
  final JsonDiskCache? _disk;
  final DateTime Function() _now;

  ({DateTime at, List<Destination> destinations})? _memory;
  Future<List<Destination>>? _inFlight;

  CatalogRepositoryImpl({
    required ApiClient api,
    required String currencyCode,
    JsonDiskCache? disk,
    DateTime Function()? now,
  })  : _api = api,
        _currencyCode = currencyCode,
        _disk = disk,
        _now = now ?? DateTime.now;

  @override
  Future<List<Destination>> destinations({bool refresh = false}) {
    final memory = _memory;
    if (!refresh && memory != null && _isFresh(memory.at)) {
      return Future.value(memory.destinations);
    }
    // Whoever asks while a load is running waits on that load — the Store
    // opened during the launch prefetch does not start a second one. A
    // refresh does not join: the running load may be serving the disk copy.
    final running = _inFlight;
    if (!refresh && running != null) return running;

    late final Future<List<Destination>> run;
    run = (refresh ? _fetch() : _load()).whenComplete(() {
      if (identical(_inFlight, run)) _inFlight = null;
    });
    return _inFlight = run;
  }

  Future<List<Destination>> _load() async {
    final saved = await _disk?.read();
    final body = saved?.body;
    if (saved != null && _isFresh(saved.savedAt) && body is Map && body['countries'] is List) {
      try {
        final out = _join(body['countries'] as List, body['packs']);
        perfLog('catalog from disk: ${out.length} destinations');
        return _remember(saved.savedAt, out);
      } on CatalogFailure {
        // A cached body the parsers refuse is no cache.
      }
    }
    return _fetch();
  }

  Future<List<Destination>> _fetch() async {
    final results = await Future.wait([
      _api.get<dynamic>('/v1/countries/all', auth: false),
      _api.get<dynamic>('/v1/packs/all', auth: false),
    ]);
    final countries = _requireList(results[0], 'countries');
    final packs = _require(results[1], 'packs');
    final at = _now();
    final out = _join(countries, packs);
    perfLog('catalog from network: ${out.length} destinations');

    final disk = _disk;
    if (disk != null && out.isNotEmpty) {
      unawaited(disk.write(at, {'countries': countries, 'packs': packs}));
    }
    return _remember(at, out);
  }

  /// An empty catalogue is returned but not kept: an outage answering `[]`
  /// must not pin an empty store for an hour.
  List<Destination> _remember(DateTime at, List<Destination> out) {
    if (out.isNotEmpty) _memory = (at: at, destinations: out);
    return out;
  }

  bool _isFresh(DateTime at) {
    final age = _now().difference(at);
    // A clock set backwards would make every copy look new: stale instead.
    return !age.isNegative && age < freshFor;
  }

  List<Destination> _join(List<dynamic> countries, Object? packsBody) {
    final packsRaw = _unwrapPage(packsBody);

    final names = <String, String>{};
    for (final row in countries) {
      final parsed = CountryParser.parse(row);
      if (parsed != null) names[parsed.$1] = parsed.$2;
    }

    final packs = <Pack>[];
    for (final row in packsRaw) {
      final p = PackParser.parse(row, currencyCode: _currencyCode);
      // A row that cannot be parsed is skipped, not fatal. One malformed pack
      // must never empty the catalogue.
      if (p != null && p.isPurchasable) packs.add(p);
    }

    final byCountry = <String, List<Pack>>{};
    for (final pack in packs) {
      for (final code in pack.countryCodes) {
        byCountry.putIfAbsent(code, () => <Pack>[]).add(pack);
      }
    }

    final out = <Destination>[];
    for (final entry in byCountry.entries) {
      final name = names[entry.key];
      // A pack pointing at a country the catalogue does not describe is not
      // shown: a tile reading "FR" with no name is worse than no tile.
      if (name == null) continue;
      final sorted = entry.value..sort(_byPriceThenData);
      out.add(Destination(code: entry.key, name: name, packs: sorted));
    }

    out.sort((a, b) {
      final pa = a.cheapestPrice, pb = b.cheapestPrice;
      if (pa == null && pb == null) return a.name.compareTo(b.name);
      if (pa == null) return 1;
      if (pb == null) return -1;
      final byPrice = pa.compareTo(pb);
      return byPrice != 0 ? byPrice : a.name.compareTo(b.name);
    });
    return out;
  }

  @override
  Future<Destination?> destination(String code) async {
    final all = await destinations();
    for (final d in all) {
      if (d.code.toUpperCase() == code.toUpperCase()) return d;
    }
    return null;
  }

  static int _byPriceThenData(Pack a, Pack b) {
    final pa = a.price, pb = b.price;
    if (pa != null && pb != null) {
      final c = pa.compareTo(pb);
      if (c != 0) return c;
    }
    return (a.data.kilobytes ?? 0).compareTo(b.data.kilobytes ?? 0);
  }

  /// `/v1/packs/all` is the only list endpoint wrapped in a Spring `Page`.
  /// Both shapes are accepted so that adding paging to another endpoint cannot
  /// crash the app — the old client cast every other response to `List` and
  /// would have thrown rather than degraded.
  List<dynamic> _unwrapPage(Object? value) {
    if (value is List) return value;
    if (value is Map) {
      final content = value['content'];
      if (content is List) return content;
    }
    throw CatalogFailure(ContractViolation('packs: expected a list or a page envelope'));
  }

  List<dynamic> _requireList(Result<dynamic> result, String what) {
    final value = _require(result, what);
    if (value is List) return value;
    throw CatalogFailure(ContractViolation('$what: expected a list'));
  }

  Object? _require(Result<dynamic> result, String what) => switch (result) {
        Ok(:final value) => value,
        Err(:final error) => throw CatalogFailure(error),
      };
}

/// Carries a typed [AppError] out of the repository so the controller can
/// translate it at the edge rather than showing a raw exception string.
class CatalogFailure implements Exception {
  final AppError error;
  const CatalogFailure(this.error);

  @override
  String toString() => 'CatalogFailure(${error.code})';
}
