/// The vocabulary two modules share about buying something.
///
/// In `core/`, not in `catalog/`, because `checkout` needs the same types and a
/// module may not import another module (rule L2). A shared kernel is the
/// answer to that, not a sideways import.
library;

import 'package:intl/intl.dart';

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

  /// For display, in [locale]'s own conventions: `6,00 €` in French, `€6.00`
  /// in English.
  ///
  /// The server's [symbol] is not used for this. On the live backend it holds
  /// `"EUR"`, the code again, which rendered every price as `EUR6.00`. The
  /// currency code is the reliable half, and intl knows the symbol and where a
  /// locale puts it.
  String format(String locale) {
    final n = double.tryParse(wireAmount);
    if (n == null) return '$wireAmount $currencyCode';
    return NumberFormat.simpleCurrency(locale: locale, name: currencyCode).format(n);
  }

  @override
  int compareTo(Money other) => value.compareTo(other.value);

  @override
  bool operator ==(Object other) =>
      other is Money && other.wireAmount == wireAmount && other.currencyCode == currencyCode;

  @override
  int get hashCode => Object.hash(wireAmount, currencyCode);
}

/// What the catalogue hands to checkout.
///
/// Deliberately carries the money as a [Money] — that is, as the EXACT decimal
/// string the server sent — and not as a number. The old app's single most
/// expensive defect was `.toInt()` on this value, which turned €9.99 into €9.00
/// and, because the backend compares the paid amount against `sabilyAmount`
/// and throws on a mismatch, turned a rounding error into an undelivered eSIM.
class PurchaseRequest {
  final int packId;
  final String packName;

  /// "10 GB - 14 days", already localised by the caller.
  final String summary;

  final Money amount;

  /// The destination's ISO alpha-3 code, when the caller has one. Lets
  /// checkout's order summary show the same real flag the catalogue does
  /// (country_flags.dart) instead of a generic icon — optional because not
  /// every purchase path (yet) has a single destination to point at.
  final String? destinationCode;

  const PurchaseRequest({
    required this.packId,
    required this.packName,
    required this.summary,
    required this.amount,
    this.destinationCode,
  });
}
