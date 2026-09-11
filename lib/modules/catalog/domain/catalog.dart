/// Catalogue domain. No Flutter, no HTTP, no DTOs — rule L3.
///
/// Everything here is expressible without knowing there is a screen or a server,
/// which is what makes these types testable in isolation and reusable by
/// TransaPay later.
library;

/// A price, holding the EXACT value the server sent.
///
/// [wireAmount] is kept as the original string on purpose. The single most
/// expensive defect in the old app was `double.parse(x).toInt()` on the way to
/// `/v1/payments/init`, which turned a €9.99 pack into a €9.00 charge and then
/// failed provisioning on the server's amount check
/// (`ANALYSE-EXISTANT.md` §7.2). Money is carried, not recomputed.
class Money implements Comparable<Money> {
  final String wireAmount;
  final String currencyCode;
  final String? symbol;

  const Money({
    required this.wireAmount,
    required this.currencyCode,
    this.symbol,
  });

  /// For comparison and per-GB maths only. Never for transmission.
  double get value => double.tryParse(wireAmount) ?? 0;

  bool get isZero => value == 0;

  String format() {
    final n = double.tryParse(wireAmount);
    final shown = n == null ? wireAmount : n.toStringAsFixed(2);
    final s = symbol;
    return s == null ? '$shown $currencyCode' : '$s$shown';
  }

  @override
  int compareTo(Money other) => value.compareTo(other.value);

  @override
  bool operator ==(Object other) =>
      other is Money && other.wireAmount == wireAmount && other.currencyCode == currencyCode;

  @override
  int get hashCode => Object.hash(wireAmount, currencyCode);
}

/// How much data a pack carries.
class DataAllowance {
  /// Kilobytes, as the API reports them. Null when [unlimited].
  final int? kilobytes;
  final bool unlimited;

  const DataAllowance({required this.kilobytes, required this.unlimited});

  double? get gigabytes {
    final kb = kilobytes;
    if (kb == null || kb <= 0) return null;
    return kb / (1024 * 1024);
  }

  /// "10 GB", "500 MB", "Unlimited" — the unit follows the size rather than
  /// trusting the API's `dataUnit`, which the old app rendered verbatim and so
  /// produced "1 days"-class output.
  String label({required String unlimitedLabel}) {
    if (unlimited) return unlimitedLabel;
    final kb = kilobytes;
    if (kb == null || kb <= 0) return '—';
    if (kb >= 1024 * 1024) {
      final gb = kb / (1024 * 1024);
      return '${_trim(gb)} GB';
    }
    if (kb >= 1024) return '${_trim(kb / 1024)} MB';
    return '$kb KB';
  }

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
}

/// How long a pack lasts.
class Validity {
  final int? amount;

  /// DAY / MONTH / … as the API spells it.
  final String? unit;

  const Validity({required this.amount, required this.unit});

  bool get isKnown => amount != null && amount! > 0;
}

class Pack {
  final int id;
  final String name;
  final String? description;
  final DataAllowance data;
  final Validity validity;

  /// Null when the pack has no price in the brand's currency — such a pack is
  /// not purchasable and the catalogue must not pretend otherwise.
  final Money? price;

  final List<String> tags;
  final List<String> countryCodes;

  /// Cover art, when the backend supplies one.
  ///
  /// The old app SYNTHESISED this as `sabily.fr/wp-content/uploads/{productId}.png`
  /// inside the data model — a client's WordPress host baked into the contract
  /// (`ANALYSE-EXISTANT.md` §4.6). Nothing is synthesised here: absent means
  /// absent, and the card draws its branded placeholder.
  final String? coverImageUrl;

  const Pack({
    required this.id,
    required this.name,
    required this.description,
    required this.data,
    required this.validity,
    required this.price,
    required this.tags,
    required this.countryCodes,
    required this.coverImageUrl,
  });

  bool get isPurchasable => price != null;

  /// Price per gigabyte, for the "from €4.00 / GB" line. Null when either side
  /// is unknown or the pack is unlimited.
  double? get pricePerGigabyte {
    final gb = data.gigabytes;
    final p = price;
    if (gb == null || gb <= 0 || p == null || p.isZero) return null;
    return p.value / gb;
  }

  bool get isPopular =>
      tags.any((t) => const {'popular', 'featured', 'best-seller'}.contains(t.toLowerCase()));
}

/// A country, with the packs that cover it.
class Destination {
  final String code;
  final String name;
  final List<Pack> packs;

  const Destination({required this.code, required this.name, required this.packs});

  bool get hasPacks => packs.isNotEmpty;

  Money? get cheapestPrice {
    final priced = packs.map((p) => p.price).whereType<Money>().toList();
    if (priced.isEmpty) return null;
    priced.sort();
    return priced.first;
  }

  /// The best per-GB rate across this destination's packs.
  double? get bestPricePerGigabyte {
    final rates = packs.map((p) => p.pricePerGigabyte).whereType<double>().toList();
    if (rates.isEmpty) return null;
    rates.sort();
    return rates.first;
  }
}

/// What the presentation layer asks for. The implementation lives in `data/`
/// and this contract knows nothing about it.
abstract class CatalogRepository {
  /// Destinations that have at least one purchasable pack, cheapest first.
  Future<List<Destination>> destinations();

  Future<Destination?> destination(String code);
}
