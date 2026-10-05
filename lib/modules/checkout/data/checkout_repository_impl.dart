import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/commerce/money.dart';
import '../../../core/network/api_client.dart';
import '../../../core/result/result.dart';
import '../domain/checkout.dart';

/// Talks to the payment endpoints. Shapes read off the deployed JAR:
/// `PaymentResourceExt` (`@PostMapping("init")` under `/api/v1/payments`, with
/// `amount` and `currency` as `@RequestParam`) and `SubscriptionResourceExt`
/// (`/card`, taking a `SubscriptionModel`).
class CheckoutRepositoryImpl implements CheckoutRepository {
  final ApiClient _api;

  CheckoutRepositoryImpl(this._api);

  @override
  Future<PaymentInit> init({required Money amount}) async {
    final result = await _api.post<Map<String, dynamic>>(
      '/v1/payments/init',
      // QUERY, not body: both parameters are @RequestParam and there is no
      // @RequestBody on the method.
      query: <String, dynamic>{
        // `wireAmount`, verbatim. This is the single most important line in
        // the module: it is the exact decimal string the server sent for this
        // pack, passed straight back. Nothing parses it to a number on the way
        // out, so nothing can truncate it. The backend compares what was paid
        // against `sabilyAmount` and throws on a mismatch, which is what turns
        // a lost cent into an undelivered eSIM.
        'amount': amount.wireAmount,
        'currency': amount.currencyCode,
      },
    );

    final body = _require(result);
    final init = PaymentInit.parse(body);
    if (init == null) {
      throw const CheckoutFailure('checkout.error.initShape');
    }
    _reportShape(init);
    return init;
  }

  @override
  Future<void> finalize({required int packId, required String paymentIntentId}) async {
    _require(await _api.post<dynamic>(
      '/v1/subscriptions/card',
      body: <String, dynamic>{
        'packId': packId,
        'paymentIntentId': paymentIntentId,
      },
    ));
  }

  /// Which field each value actually arrived in, once per version.
  ///
  /// §7.3: this is how production answers R3 on its own, and how the backend
  /// can later rename its fields without a coordinated mobile release. It is a
  /// debug trace today because there is no analytics sink yet; the shape of
  /// the call is what matters, and it is deliberately not per-payment — a
  /// report on every purchase would be noise, and the answer cannot change
  /// within a version.
  static final Set<String> _reported = <String>{};

  void _reportShape(PaymentInit init) {
    final signature = init.arrivedAs.entries.map((e) => '${e.key}=${e.value}').join(',');
    if (!_reported.add(signature)) return;
    debugPrint('[checkout] payments/init response shape: $signature');
  }

  T _require<T>(Result<T> result) => switch (result) {
        Ok(:final value) => value,
        Err(:final error) => throw CheckoutFailure.fromError(error),
      };
}

class CheckoutFailure implements Exception {
  final String messageKey;

  /// The backend's own error key, when it sent one.
  ///
  /// ⚠️ It used to be thrown away here. `HttpFailure.code` is the constant
  /// `'generic'`, so EVERY server refusal reached the controller as
  /// `error.generic` and nothing downstream could tell one apart from another
  /// — including the one refusal that actually means success. See
  /// [isAlreadyConsumed].
  final String? serverCode;
  final String? serverMessage;

  const CheckoutFailure(this.messageKey, {this.serverCode, this.serverMessage});

  factory CheckoutFailure.fromError(AppError error) => CheckoutFailure(
        'error.${error.code}',
        serverCode: error is HttpFailure ? error.serverCode : null,
        serverMessage: error is HttpFailure ? error.serverMessage : null,
      );

  /// The payment was already provisioned, so this refusal is a SUCCESS.
  ///
  /// `subscribeByCard` finds the payment by `externalReference` and throws
  /// when it is already `COMPLETED_AND_CONSUMED` (ARCHITECTURE-MOBILE.md
  /// §7.1, read off the bytecode). That is the server saying the eSIM exists
  /// — treating it as a failure leaves a provisioned order sitting on disk,
  /// retrying forever, with the card telling the customer their eSIM is still
  /// coming when it has already arrived.
  ///
  /// ⚠️ The literal key is NOT recorded anywhere in this repository — only
  /// the behaviour is — so this matches the concept across the spellings the
  /// backend plausibly uses. Pin it to the exact string here once it has been
  /// read off a real 4xx body; nothing else has to change.
  bool get isAlreadyConsumed {
    final raw = '${serverCode ?? ''} ${serverMessage ?? ''}'.toLowerCase();
    if (raw.trim().isEmpty) return false;
    return raw.contains('consumed') ||
        raw.contains('already_subscribed') ||
        raw.contains('already subscribed') ||
        (raw.contains('already') && raw.contains('paid'));
  }

  @override
  String toString() =>
      'CheckoutFailure($messageKey${serverCode == null ? '' : ', $serverCode'})';
}

/// Where a pending order lives between authorising and provisioning.
///
/// SharedPreferences rather than the secure store: this holds no secret. The
/// Stripe client secret is deliberately NOT persisted — it is single-use, it
/// authorises a charge, and it is of no help on a later launch, where the
/// intent id is the only thing finalisation needs.
class PendingOrderStore {
  static const String _key = 'checkout.pending';

  final SharedPreferences _prefs;

  /// Fired after every mutation, so a provider over this store can re-read.
  ///
  /// ⚠️ THE DEFECT THIS EXISTS TO PREVENT. `pendingOrderProvider` was a plain
  /// `Provider` over `read()`, and a plain provider caches: it answered once
  /// per session. An order written mid-session — which is exactly the
  /// charged-but-unprovisioned case the card is for — never reached the card
  /// at all, and one cleared after a successful retry lingered on it. The
  /// store is the single choke point every mutation goes through, so the
  /// signal belongs here rather than at each of the five call sites, where it
  /// only has to be forgotten once.
  final void Function()? onChanged;

  PendingOrderStore(this._prefs, {this.onChanged});

  Future<void> write(PendingOrder order) async {
    await _prefs.setString(_key, jsonEncode(order.toJson()));
    onChanged?.call();
  }

  PendingOrder? read() {
    final raw = _prefs.getString(_key);
    if (raw == null) return null;
    try {
      return PendingOrder.fromJson(jsonDecode(raw));
    } catch (_) {
      // A corrupt record must not wedge every future launch.
      _prefs.remove(_key);
      return null;
    }
  }

  Future<void> clear() async {
    await _prefs.remove(_key);
    onChanged?.call();
  }
}
