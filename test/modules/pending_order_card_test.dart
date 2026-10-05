/// The stuck-order card appears and disappears WITHIN a session.
///
/// ⚠️ THE DEFECT THESE TESTS EXIST TO PREVENT. `pendingOrderProvider` was a
/// plain `Provider` over `store.read()`. A plain provider caches, so it
/// answered once per session: an order written mid-session — which is exactly
/// the charged-but-unprovisioned case the card exists for — never reached the
/// card, and one cleared by a successful retry lingered on it.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transasim_mobile/core/sync/pending_order_notice.dart';
import 'package:transasim_mobile/modules/checkout/data/checkout_repository_impl.dart';
import 'package:transasim_mobile/modules/checkout/domain/checkout.dart';
import 'package:transasim_mobile/modules/checkout/presentation/checkout_controllers.dart';

PendingOrder order({String intent = 'pi_ABC', int attempts = 0}) {
  var o = PendingOrder(
    paymentId: 1,
    packId: 42,
    packName: 'France 10GB',
    paymentIntentId: intent,
    amount: '9.99',
    currency: 'EUR',
    startedAt: DateTime(2026, 10, 5, 12),
  );
  for (var i = 0; i < attempts; i++) {
    o = o.withAttempt();
  }
  return o;
}

/// A container carrying the same binding `main_common.dart` installs, so the
/// test exercises the wiring the app runs rather than a stand-in for it.
Future<ProviderContainer> containerWithEmptyPrefs() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    pendingOrderNoticeProvider.overrideWith((ref) {
      final o = ref.watch(pendingOrderProvider);
      if (o == null) return null;
      return PendingOrderNotice(
        reference: o.paymentIntentId,
        packName: o.packName,
        exhausted: o.exhausted,
      );
    }),
  ]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the card follows the store without a restart', () {
    test('absent, then written mid-session, then cleared', () async {
      final c = await containerWithEmptyPrefs();
      addTearDown(c.dispose);

      // Nothing outstanding: no card.
      expect(c.read(pendingOrderNoticeProvider), isNull);

      // The customer is charged and provisioning has not finished. The order
      // is written by the SAME store the providers read through.
      await c.read(pendingOrderStoreProvider).write(order());

      final notice = c.read(pendingOrderNoticeProvider);
      expect(notice, isNotNull, reason: 'the card must appear without a restart');
      expect(notice!.reference, 'pi_ABC');
      expect(notice.packName, 'France 10GB');
      expect(notice.exhausted, isFalse);

      // Provisioning succeeds and the order is cleared.
      await c.read(pendingOrderStoreProvider).clear();

      expect(c.read(pendingOrderNoticeProvider), isNull,
          reason: 'the card must leave once the eSIM has arrived');
    });

    test('a retry that provisions removes the card', () async {
      final c = await containerWithEmptyPrefs();
      addTearDown(c.dispose);

      await c.read(pendingOrderStoreProvider).write(order());
      expect(c.read(pendingOrderNoticeProvider), isNotNull);

      final done = await resumePendingOrder(
        // The store from the container, so its change signal is wired.
        store: c.read(pendingOrderStoreProvider),
        repository: _OkRepository(),
        force: true,
      );

      expect(done, isTrue);
      expect(c.read(pendingOrderNoticeProvider), isNull);
    });

    test('an exhausted order still shows, and says so', () async {
      final c = await containerWithEmptyPrefs();
      addTearDown(c.dispose);

      await c
          .read(pendingOrderStoreProvider)
          .write(order(attempts: PendingOrder.maxAutomaticAttempts));

      final notice = c.read(pendingOrderNoticeProvider);
      expect(notice, isNotNull, reason: 'giving up retrying is not giving up telling them');
      expect(notice!.exhausted, isTrue);
    });
  });

  group('an already-consumed payment is a success, not a failure', () {
    // `subscribeByCard` finds the payment by `externalReference` and throws
    // when it is already COMPLETED_AND_CONSUMED. That is the server saying the
    // eSIM exists. Read as a failure it left a provisioned order on disk,
    // retrying forever, with the card promising an eSIM that had arrived.

    test('the retry loop stops and clears the order', () async {
      final c = await containerWithEmptyPrefs();
      addTearDown(c.dispose);

      final repo = _ConsumedRepository();
      await c.read(pendingOrderStoreProvider).write(order());

      final done = await resumePendingOrder(
        store: c.read(pendingOrderStoreProvider),
        repository: repo,
      );

      expect(done, isTrue, reason: 'the eSIM is provisioned');
      expect(c.read(pendingOrderStoreProvider).read(), isNull);
      expect(c.read(pendingOrderNoticeProvider), isNull);
      expect(repo.calls, 1, reason: 'there is nothing to retry');
    });

    test('the failure carries the key instead of flattening it', () {
      // Every HttpFailure used to arrive as `error.generic`, so nothing
      // downstream could tell this refusal from any other.
      const consumed = CheckoutFailure(
        'error.generic',
        serverCode: 'error.payment_already_consumed',
      );
      expect(consumed.isAlreadyConsumed, isTrue);

      const declined = CheckoutFailure('error.generic', serverCode: 'error.card_declined');
      expect(declined.isAlreadyConsumed, isFalse);

      const bare = CheckoutFailure('error.generic');
      expect(bare.isAlreadyConsumed, isFalse,
          reason: 'no key is not evidence of success');
    });
  });
}

/// Provisions on the first call.
class _OkRepository implements CheckoutRepository {
  @override
  Future<PaymentInit> init({required dynamic amount}) => throw UnimplementedError();

  @override
  Future<void> finalize({required int packId, required String paymentIntentId}) async {}
}

/// Answers the way the server does for a payment it has already consumed.
class _ConsumedRepository implements CheckoutRepository {
  int calls = 0;

  @override
  Future<PaymentInit> init({required dynamic amount}) => throw UnimplementedError();

  @override
  Future<void> finalize({required int packId, required String paymentIntentId}) async {
    calls++;
    throw const CheckoutFailure(
      'error.generic',
      serverCode: 'error.payment_already_consumed',
    );
  }
}
