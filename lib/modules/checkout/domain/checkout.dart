/// The money path. ARCHITECTURE-MOBILE.md §7.
///
/// No Flutter, no HTTP — rule L3.
library;

import '../../../core/commerce/money.dart';

/// What `POST /v1/payments/init` gives back, identified BY SHAPE.
///
/// §7.3: the deployed backend swaps `clientSecret` and `paymentIntentId`, and
/// never assigns `id` at all — established on bytecode, but from a JAR five
/// weeks older than the last mobile commit. Rather than depend on which is
/// true, both values are recognised by their form:
///
///   a client secret   `pi_XXX_secret_YYY`
///   an intent id      `pi_XXX`, with no `_secret_`
///
/// The payment then works whether or not the backend is ever corrected, R3
/// leaves the critical path, and the field names can change server-side with
/// no coordinated mobile release. [arrivedAs] records which key each actually
/// came in under, so production settles the question by itself.
class PaymentInit {
  /// The server's `Payment` row id. §7.1: there is no separate order entity in
  /// this backend — `/api/v1/packs` exposes no purchase route — so this row IS
  /// the order.
  final int? paymentId;

  final String clientSecret;
  final String paymentIntentId;

  /// field name -> what was found there. Reported once per version.
  final Map<String, String> arrivedAs;

  const PaymentInit({
    required this.paymentId,
    required this.clientSecret,
    required this.paymentIntentId,
    required this.arrivedAs,
  });

  /// `pi_ABC_secret_XYZ`. Anchored, because a secret contains an id as a
  /// prefix and an unanchored test would match both.
  static final RegExp secretPattern = RegExp(r'^pi_[A-Za-z0-9]+_secret_[A-Za-z0-9]+$');

  /// `pi_ABC`, and explicitly NOT a secret.
  static final RegExp intentPattern = RegExp(r'^pi_[A-Za-z0-9]+$');

  /// Reads a response without caring what anything is called.
  ///
  /// Returns null when either value is absent — which is a failure, not a
  /// half-success to paper over: without both, there is nothing to present and
  /// nothing to finalise.
  static PaymentInit? parse(Map<String, dynamic> json) {
    String? secret, intentId;
    final arrivedAs = <String, String>{};

    for (final entry in json.entries) {
      final v = entry.value;
      if (v is! String) continue;
      if (secret == null && secretPattern.hasMatch(v)) {
        secret = v;
        arrivedAs[entry.key] = 'clientSecret';
      } else if (intentId == null && intentPattern.hasMatch(v)) {
        intentId = v;
        arrivedAs[entry.key] = 'paymentIntentId';
      }
    }

    // A secret always contains its own intent id. If the server sent only the
    // secret, the id is still recoverable — and that is strictly better than
    // failing a payment the user has already authorised.
    if (secret != null && intentId == null) {
      intentId = secret.split('_secret_').first;
      arrivedAs['(derived)'] = 'paymentIntentId';
    }

    if (secret == null || intentId == null) return null;

    final rawId = json['paymentId'] ?? json['id'];
    return PaymentInit(
      paymentId: rawId is num ? rawId.toInt() : null,
      clientSecret: secret,
      paymentIntentId: intentId,
      arrivedAs: arrivedAs,
    );
  }
}

/// A payment the user has started, written to disk BEFORE anything is shown.
///
/// §7.2 step 2: if the app is killed between authorising with Stripe and
/// telling the server about it, this record is the only thing standing between
/// the user and a charge with no eSIM. It is what makes the next launch able
/// to finish the job.
class PendingOrder {
  final int? paymentId;
  final int packId;
  final String packName;
  final String paymentIntentId;

  /// The exact decimal, as a string. Never a double, never re-parsed.
  final String amount;
  final String currency;

  final DateTime startedAt;

  /// How many times finalisation has been attempted. Kept so a permanently
  /// failing order stops retrying forever and surfaces instead.
  final int attempts;

  const PendingOrder({
    required this.paymentId,
    required this.packId,
    required this.packName,
    required this.paymentIntentId,
    required this.amount,
    required this.currency,
    required this.startedAt,
    this.attempts = 0,
  });

  PendingOrder withAttempt() => PendingOrder(
        paymentId: paymentId,
        packId: packId,
        packName: packName,
        paymentIntentId: paymentIntentId,
        amount: amount,
        currency: currency,
        startedAt: startedAt,
        attempts: attempts + 1,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'paymentId': paymentId,
        'packId': packId,
        'packName': packName,
        'paymentIntentId': paymentIntentId,
        'amount': amount,
        'currency': currency,
        'startedAt': startedAt.toIso8601String(),
        'attempts': attempts,
      };

  static PendingOrder? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final packId = raw['packId'];
    final intentId = raw['paymentIntentId'];
    final amount = raw['amount'];
    if (packId is! num || intentId is! String || amount is! String) return null;
    return PendingOrder(
      paymentId: raw['paymentId'] is num ? (raw['paymentId'] as num).toInt() : null,
      packId: packId.toInt(),
      packName: raw['packName']?.toString() ?? '',
      paymentIntentId: intentId,
      amount: amount,
      currency: raw['currency']?.toString() ?? '',
      startedAt: DateTime.tryParse(raw['startedAt']?.toString() ?? '') ?? DateTime.now(),
      attempts: raw['attempts'] is num ? (raw['attempts'] as num).toInt() : 0,
    );
  }

  /// Beyond this, stop retrying automatically and show the order instead. An
  /// order that has failed six times is not going to succeed on the seventh
  /// without someone looking at it.
  static const int maxAutomaticAttempts = 6;

  bool get exhausted => attempts >= maxAutomaticAttempts;
}

/// What finalisation did. Distinguished because the UI must not call a
/// cancellation a failure — §7.2 difference #4.
sealed class CheckoutOutcome {
  const CheckoutOutcome();
}

/// Provisioned. The server confirmed it; the app did not assume it.
final class CheckoutProvisioned extends CheckoutOutcome {
  const CheckoutProvisioned();
}

/// The user dismissed Stripe's sheet. NOTHING is posted — the old app called
/// subscribe anyway and reported the cancel as a failed attempt.
final class CheckoutCancelled extends CheckoutOutcome {
  const CheckoutCancelled();
}

/// Paid, but the server has not confirmed provisioning yet. The pending order
/// survives and is retried.
final class CheckoutPendingProvisioning extends CheckoutOutcome {
  final PendingOrder order;
  const CheckoutPendingProvisioning(this.order);
}

final class CheckoutFailed extends CheckoutOutcome {
  /// A dictionary key, never a server string.
  final String messageKey;
  const CheckoutFailed(this.messageKey);
}

abstract class CheckoutRepository {
  /// `POST /v1/payments/init?amount=<exact decimal>&currency=<code>`.
  ///
  /// The two parameters are `@RequestParam`; there is no `@RequestBody`.
  Future<PaymentInit> init({required Money amount});

  /// `POST /v1/subscriptions/card` with `{ packId, paymentIntentId }`.
  ///
  /// Idempotent SERVER-SIDE, keyed on the Stripe intent via
  /// `externalReference`: a payment already at `COMPLETED_AND_CONSUMED` makes
  /// the server throw instead of provisioning twice. That guarantee is why
  /// retrying is safe, and why this client invents no idempotency key of its
  /// own on top of it.
  Future<void> finalize({required int packId, required String paymentIntentId});
}
