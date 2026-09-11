import '../../../core/network/api_client.dart';
import '../../../core/result/result.dart';
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
/// The result is cached in memory for the session. The old app refetched the
/// whole catalogue on every screen entry and had no offline story at all
/// ("airplane mode = empty screens", `ANALYSE-EXISTANT.md` §3).
class CatalogRepositoryImpl implements CatalogRepository {
  final ApiClient _api;
  final String _currencyCode;

  List<Destination>? _cache;

  CatalogRepositoryImpl({required ApiClient api, required String currencyCode})
      : _api = api,
        _currencyCode = currencyCode;

  @override
  Future<List<Destination>> destinations() async {
    final cached = _cache;
    if (cached != null) return cached;

    final results = await Future.wait([
      _api.get<dynamic>('/v1/countries/all', auth: false),
      _api.get<dynamic>('/v1/packs/all', auth: false),
    ]);

    final countries = _requireList(results[0], 'countries');
    final packsRaw = _unwrapPage(results[1]);

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

    _cache = out;
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
  List<dynamic> _unwrapPage(Result<dynamic> result) {
    final value = _require(result, 'packs');
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
