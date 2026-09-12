/// Catalogue domain. No Flutter, no HTTP, no DTOs — rule L3.
///
/// Everything here is expressible without knowing there is a screen or a server,
/// which is what makes these types testable in isolation and reusable by
/// TransaPay later.
library;

import '../../../core/commerce/money.dart';

export '../../../core/commerce/money.dart' show Money;

enum DataUnit { kilobyte, megabyte, gigabyte, unlimited, none }

/// A size with its unit left unnamed, for the presentation layer to localise.
class DataSize {
  final String amount;
  final DataUnit unit;
  const DataSize({required this.amount, required this.unit});
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

  /// The size, split into a number and a UNIT the presentation layer names.
  ///
  /// The domain deliberately does not produce "10 GB": the unit is a
  /// user-facing string, and hardcoding a Latin one made Arabic render "GB 5"
  /// — caught by the RTL golden, which is the point of doing RTL per screen
  /// rather than as a pass at the end.
  DataSize get size {
    if (unlimited) return const DataSize(amount: '', unit: DataUnit.unlimited);
    final kb = kilobytes;
    if (kb == null || kb <= 0) return const DataSize(amount: '—', unit: DataUnit.none);
    if (kb >= 1024 * 1024) {
      return DataSize(amount: _trim(kb / (1024 * 1024)), unit: DataUnit.gigabyte);
    }
    if (kb >= 1024) return DataSize(amount: _trim(kb / 1024), unit: DataUnit.megabyte);
    return DataSize(amount: '$kb', unit: DataUnit.kilobyte);
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
