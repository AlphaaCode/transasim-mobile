/// Widget -> controller -> repository. No widget touches a repository, and no
/// controller touches dio (§5.2 rule 1, rule L4).
///
/// The old app ran two paradigms side by side: blocs for some screens and
/// `serviceLocator.*Repository` called straight from `setState` in others
/// (`ANALYSE-EXISTANT.md` §3). There is one path here.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/brand/brand_providers.dart';
import '../../../core/i18n/country_names.dart';
import '../../../core/network/network_providers.dart';
import '../../../core/result/result.dart';
import '../../../core/storage/json_disk_cache.dart';
import '../data/catalog_repository_impl.dart';
import '../domain/destination_search.dart';
import '../domain/catalog.dart';
import '../domain/region.dart';

export '../domain/region.dart' show Region;


final catalogRepositoryProvider = Provider<CatalogRepository>((ref) {
  final brand = ref.watch(brandConfigProvider);
  return CatalogRepositoryImpl(
    api: ref.watch(apiClientProvider),
    currencyCode: brand.currency,
    disk: JsonDiskCache(name: 'catalog', source: brand.mobile.apiBaseUrl),
  );
});

/// Screen state as a sealed type, not three booleans that permit impossible
/// combinations (§5.2 rule 2).
sealed class CatalogState {
  const CatalogState();
}

final class CatalogLoading extends CatalogState {
  const CatalogLoading();
}

final class CatalogReady extends CatalogState {
  final List<Destination> destinations;

  /// The query currently filtering [destinations].
  final String query;

  /// The region chip in force. Null is "All".
  final Region? region;

  CatalogReady({required this.destinations, this.query = '', this.region});

  /// Computed once per state. It was a getter, and the list builder reads it
  /// for every row it lays out — a full filter pass per row.
  ///
  /// Matches a destination's name in any served language, its ISO code and its
  /// capital: "Paris", "Algérie", "الجزائر" and "Wien" all find their country
  /// (destination_search.dart).
  late final List<Destination> visible = searchDestinations(
    region == null ? destinations : destinations.where((d) => regionOf(d.code) == region).toList(),
    query,
    code: (d) => d.code,
    name: (d) => d.name,
  );

  /// Only regions the catalogue actually sells into get a chip: a chip that
  /// can only ever produce an empty list is a dead end, not a filter.
  late final List<Region> regions = () {
    final present = {for (final d in destinations) ?regionOf(d.code)};
    return kRegionOrder.where(present.contains).toList();
  }();

  bool get isEmpty => visible.isEmpty;
}

final class CatalogFailed extends CatalogState {
  /// Typed, so the screen resolves `error.<code>` in the dictionary rather than
  /// printing an exception.
  final AppError error;
  const CatalogFailed(this.error);
}

class CatalogController extends AsyncNotifier<CatalogState> {
  @override
  Future<CatalogState> build() => _load();

  Future<CatalogState> _load({bool refresh = false}) async {
    try {
      final destinations =
          await ref.read(catalogRepositoryProvider).destinations(refresh: refresh);
      return CatalogReady(destinations: destinations);
    } on CatalogFailure catch (e) {
      return CatalogFailed(e.error);
    }
  }

  Future<void> refresh() async {
    state = const AsyncValue<CatalogState>.loading();
    state = AsyncValue<CatalogState>.data(await _load(refresh: true));
  }

  void search(String query) {
    final current = state.value;
    if (current is! CatalogReady) return;
    state = AsyncValue<CatalogState>.data(
      CatalogReady(destinations: current.destinations, query: query, region: current.region),
    );
  }

  /// Null selects "All".
  void selectRegion(Region? region) {
    final current = state.value;
    if (current is! CatalogReady) return;
    state = AsyncValue<CatalogState>.data(
      CatalogReady(destinations: current.destinations, query: current.query, region: region),
    );
  }
}

final catalogControllerProvider =
    AsyncNotifierProvider<CatalogController, CatalogState>(CatalogController.new);

/// Country names by ISO3 code, from the catalogue already loaded. Every
/// country a pack covers is a destination with that pack, so this is complete
/// for coverage; a code it does not know is shown as the code.
///
/// In the interface language (CLDR), not the backend's English: this feeds the
/// pack's coverage list and the multi-country finder.
final countryNamesProvider = FutureProvider<Map<String, String>>((ref) async {
  final language = ref.watch(languageProvider);
  final all = await ref.watch(catalogRepositoryProvider).destinations();
  return {
    for (final d in all) d.code.toUpperCase(): countryName(d.code, language, fallback: d.name),
  };
});

/// The bundled photo for a destination's packs: its own override, else its
/// image region's, else `world`. Shared by the pack cards and the detail hero
/// so the two can never disagree.
final destinationImageProvider = Provider.family<String?, String>((ref, code) {
  return ref.watch(brandConfigProvider.select((b) {
    final file = b.visuals.packImage(
      destinationCode: code,
      regionKey: packImageRegion([code]),
    );
    return file == null ? null : b.assetPath(file);
  }));
});

/// One destination, resolved from the loaded catalogue rather than refetched.
final destinationProvider = FutureProvider.family<Destination?, String>(
  (ref, code) => ref.watch(catalogRepositoryProvider).destination(code),
);
