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
  const CheckoutFailure(this.messageKey);

  factory CheckoutFailure.fromError(AppError error) =>
      CheckoutFailure('error.${error.code}');

  @override
  String toString() => 'CheckoutFailure($messageKey)';
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
  PendingOrderStore(this._prefs);

  Future<void> write(PendingOrder order) =>
      _prefs.setString(_key, jsonEncode(order.toJson()));

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

  Future<void> clear() => _prefs.remove(_key);
}
