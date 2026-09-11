/// Wire -> domain mapping for the catalogue.
///
/// Optionality here mirrors what the backend actually guarantees, which is very
/// little. The old app hard-cast four SubPlan fields and asserted
/// `a.countries!.length` while sorting, so ONE row with a null array killed the
/// entire catalogue parse (`ANALYSE-EXISTANT.md` §2.2, api-contract.md §3).
/// Nothing here throws on a malformed row: it skips the row and keeps the rest.
library;

import '../domain/catalog.dart';

/// The backend's field for the customer-facing price.
///
/// It is named after the first client. We do not control this API, so the
/// string appears exactly once, here, rather than spreading through the app the
/// way it did before (8 occurrences in `price.dart` alone).
const String kCustomerPriceField = 'sabilyAmount'; // wire-contract

const String kFallbackPriceField = 'amount';

/// Statuses that mean "sellable". The API spells them upper-case
/// (AVAILABLE/ENABLED/…); the old client compared against lower-case literals,
/// so comparisons are done case-insensitively here rather than relying on
/// either side's casing.
const Set<String> _sellableStatuses = {'available', 'active', 'enabled'};

class PackParser {
  /// Parse one pack. Returns null when the row cannot be trusted.
  ///
  /// [currencyCode] is the brand's currency: a pack with no price in it is not
  /// purchasable, and the UI must be able to say so rather than showing a price
  /// in someone else's money. That is the defect behind the old currency
  /// selector, which displayed a converted price and charged the base one.
  static Pack? parse(Object? row, {required String currencyCode}) {
    if (row is! Map) return null;
    final json = row.cast<String, dynamic>();

    final id = _int(json['id']);
    if (id == null) return null;

    final name = _string(json['name']);
    if (name == null) return null;

    final status = _string(json['status'])?.toLowerCase();
    if (status != null && !_sellableStatuses.contains(status)) return null;

    return Pack(
      id: id,
      name: name,
      description: _string(json['description']),
      data: DataAllowance(
        kilobytes: _int(json['dataValue']),
        unlimited: json['unlimited'] == true,
      ),
      validity: Validity(
        amount: _int(json['validityDuration']),
        unit: _string(json['validityDurationUnit']),
      ),
      price: _price(json['prices'], currencyCode),
      tags: _stringList(json['tags']),
      countryCodes: _countryCodes(json['countries']),
      // Deliberately not synthesised from any host. See Pack.coverImageUrl.
      coverImageUrl: _string(json['coverImage']),
    );
  }

  /// Pick the price in the brand's currency, preferring the customer-facing
  /// field over the cost basis.
  static Money? _price(Object? raw, String currencyCode) {
    if (raw is! List) return null;
    for (final entry in raw) {
      if (entry is! Map) continue;
      final p = entry.cast<String, dynamic>();

      final currency = p['currency'];
      final code = currency is Map ? _string(currency['code']) : null;
      if (code == null || code.toUpperCase() != currencyCode.toUpperCase()) continue;

      final amount = _amount(p[kCustomerPriceField]) ?? _amount(p[kFallbackPriceField]);
      if (amount == null) continue;

      return Money(
        wireAmount: amount,
        currencyCode: code.toUpperCase(),
        symbol: currency is Map ? _string(currency['symbol']) : null,
      );
    }
    return null;
  }

  /// Keep the server's own representation. `num.toString()` on a JSON double
  /// round-trips exactly, and a string passes straight through — so a price of
  /// 9.99 stays "9.99" all the way to the payment call.
  static String? _amount(Object? v) {
    if (v == null) return null;
    if (v is num) return v.toString();
    if (v is String && v.trim().isNotEmpty && double.tryParse(v.trim()) != null) {
      return v.trim();
    }
    return null;
  }

  static List<String> _countryCodes(Object? raw) {
    if (raw is! List) return const [];
    final out = <String>[];
    for (final c in raw) {
      if (c is! Map) continue;
      final code = _string(c['code']) ?? _string(c['alpha2']);
      if (code != null) out.add(code.toUpperCase());
    }
    return out;
  }

  static List<String> _stringList(Object? raw) {
    if (raw is! List) return const [];
    return raw.map(_string).whereType<String>().toList();
  }
}

class CountryParser {
  /// (code, name), or null for a row without both.
  static (String, String)? parse(Object? row) {
    if (row is! Map) return null;
    final json = row.cast<String, dynamic>();
    final code = _string(json['code']) ?? _string(json['alpha2']);
    final name = _string(json['name']) ?? _string(json['country']);
    if (code == null || name == null) return null;
    return (code.toUpperCase(), name);
  }
}

int? _int(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

String? _string(Object? v) {
  if (v is String && v.trim().isNotEmpty) return v.trim();
  if (v is num) return v.toString();
  return null;
}
