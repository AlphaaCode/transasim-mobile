/// The money path, as a state machine. ARCHITECTURE-MOBILE.md §7.2.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/brand/brand_providers.dart';
import '../../../core/commerce/money.dart';
import '../../../core/network/network_providers.dart';
import '../../../core/storage/preferences.dart';
import '../../../core/sync/entitlements.dart';
import '../data/checkout_repository_impl.dart';
import '../domain/checkout.dart';

export '../../../core/storage/preferences.dart' show sharedPreferencesProvider;

final checkoutRepositoryProvider = Provider<CheckoutRepository>(
  (ref) => CheckoutRepositoryImpl(ref.watch(apiClientProvider)),
);


/// Bumped by the store after every write and clear.
///
/// The indirection is what keeps the graph acyclic: [pendingOrderProvider]
/// watches the store, so the store cannot invalidate it directly without
/// Riverpod — correctly — calling that a circular dependency. Both watch this
/// instead, and nothing watches its own watcher.
final pendingOrderRevisionProvider =
    NotifierProvider<RevisionCounter, int>(RevisionCounter.new);

final Provider<PendingOrderStore> pendingOrderStoreProvider = Provider<PendingOrderStore>(
  (ref) => PendingOrderStore(
    ref.watch(sharedPreferencesProvider),
    // Every write and every clear re-reads [pendingOrderProvider], wherever
    // the mutation came from — including `resumePendingOrder`, which takes a
    // store rather than a Ref and so cannot invalidate anything itself.
    onChanged: () => ref.read(pendingOrderRevisionProvider.notifier).bump(),
  ),
);

/// What the Stripe sheet is asked to do, injected so tests drive every branch
/// without a payment sheet — and so the module has no hard dependency on the
/// SDK in its own logic.
typedef PresentSheet = Future<SheetResult> Function({
  required String clientSecret,
  required String merchantName,
});

enum SheetResult { completed, cancelled, failed }

final presentSheetProvider = Provider<PresentSheet>(
  (ref) => throw UnimplementedError('presentSheetProvider must be overridden by bootstrap'),
);

/// Whether this brand can actually take money.
///
/// Sabily ships `pk_test_PLACEHOLDER_AWAITING_CLIENT`. The config validator
/// only checks the `pk_`/`sk_` prefix, so a placeholder PASSES — the app starts
/// and fails at the payment sheet instead of at parse time. Checkout asks this
/// first and says so plainly, rather than presenting a sheet that cannot work.
final canTakePaymentsProvider = Provider<bool>((ref) {
  final key = ref.watch(brandConfigProvider.select((b) => b.mobile.stripePublishableKey));
  return isUsableStripeKey(key);
});

/// A real key is `pk_(test|live)_` followed by base62. A placeholder is not.
bool isUsableStripeKey(String key) {
  final m = RegExp(r'^pk_(test|live)_([A-Za-z0-9]+)$').firstMatch(key);
  if (m == null) return false;
  // Stripe's shortest historical keys are around 24 characters after the
  // prefix; anything shorter is a stand-in.
  return m.group(2)!.length >= 24;
}

sealed class CheckoutState {
  const CheckoutState();
}

final class CheckoutIdle extends CheckoutState {
  const CheckoutIdle();
}

/// Undismissable from here on. §7: a payment in flight must not be tappable
/// away from mid-charge.
final class CheckoutBusy extends CheckoutState {
  /// A dictionary key describing the step, so the user knows what is happening.
  final String stepKey;
  const CheckoutBusy(this.stepKey);
}

final class CheckoutDone extends CheckoutState {
  const CheckoutDone();
}

/// Paid, not yet provisioned. The order is on disk and will be retried.
final class CheckoutAwaitingProvisioning extends CheckoutState {
  const CheckoutAwaitingProvisioning();
}

final class CheckoutError extends CheckoutState {
  final String messageKey;
  const CheckoutError(this.messageKey);
}

class CheckoutController extends Notifier<CheckoutState> {
  @override
  CheckoutState build() => const CheckoutIdle();

  /// The whole flow, in the order §7.2 specifies.
  Future<void> pay(PurchaseRequest request) async {
    if (state is CheckoutBusy) return;

    final repo = ref.read(checkoutRepositoryProvider);
    final store = ref.read(pendingOrderStoreProvider);

    try {
      // 1-2. Create the server-side Payment row and learn the intent.
      state = const CheckoutBusy('checkout.step.preparing');
      final init = await repo.init(amount: request.amount);

      // 2b. PERSIST BEFORE PRESENTING ANYTHING. If the process dies between
      //     the sheet and finalisation, this is the only record that the user
      //     may have been charged.
      final order = PendingOrder(
        paymentId: init.paymentId,
        packId: request.packId,
        packName: request.packName,
        paymentIntentId: init.paymentIntentId,
        amount: request.amount.wireAmount,
        currency: request.amount.currencyCode,
        startedAt: DateTime.now(),
      );
      await store.write(order);

      // 3. Stripe.
      state = const CheckoutBusy('checkout.step.authorising');
      final sheet = await ref.read(presentSheetProvider)(
        clientSecret: init.clientSecret,
        merchantName: ref.read(brandConfigProvider).name,
      );

      switch (sheet) {
        case SheetResult.cancelled:
          // 6. NOTHING is posted. The old app called subscribe anyway and then
          //    reported the cancellation as a failed attempt.
          await store.clear();
          state = const CheckoutIdle();
          return;
        case SheetResult.failed:
          await store.clear();
          state = const CheckoutError('checkout.error.declined');
          return;
        case SheetResult.completed:
          break;
      }

      // 4. Provision, with retry.
      state = const CheckoutBusy('checkout.step.provisioning');
      final provisioned = await _finalizeWithRetry(order);
      // The eSIM exists on the server now. Say so, or the customer lands on a
      // list that was fetched before they bought it.
      if (provisioned) ref.read(entitlementsRevisionProvider.notifier).bump();
      state = provisioned ? const CheckoutDone() : const CheckoutAwaitingProvisioning();
    } on CheckoutFailure catch (e) {
      await store.clear();
      state = CheckoutError(e.messageKey);
    }
  }

  /// Exponential backoff against a server guarantee, not a client invention.
  ///
  /// `/v1/subscriptions/card` finds the payment by `externalReference` (the
  /// Stripe intent id) and throws if it is already `COMPLETED_AND_CONSUMED`.
  /// That is what makes a blind retry safe: the second call cannot
  /// double-provision. No client-side idempotency key is added on top, because
  /// one would only duplicate a guarantee the backend already gives.
  Future<bool> _finalizeWithRetry(PendingOrder order) async {
    final repo = ref.read(checkoutRepositoryProvider);
    final store = ref.read(pendingOrderStoreProvider);

    var current = order;
    var delay = const Duration(milliseconds: 400);

    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await repo.finalize(
          packId: current.packId,
          paymentIntentId: current.paymentIntentId,
        );
        await store.clear();
        return true;
      } on CheckoutFailure catch (e) {
        // The server refusing because the payment is already consumed is the
        // server saying the eSIM exists. Retrying that is pointless, and
        // reporting it as a failure strands a provisioned order on disk.
        if (e.isAlreadyConsumed) {
          debugPrint('[checkout] already provisioned: ${current.paymentIntentId}');
          await store.clear();
          return true;
        }
        current = current.withAttempt();
        await store.write(current);
        debugPrint('[checkout] finalize attempt ${current.attempts} failed: ${e.messageKey}');
        if (attempt == 2) break;
        await Future<void>.delayed(delay);
        delay *= 2;
      }
    }
    // The money is gone and the eSIM is not here yet. The order stays on disk,
    // the next launch retries it, and the user is told rather than left to
    // discover it.
    return false;
  }

  void reset() => state = const CheckoutIdle();
}

final checkoutControllerProvider =
    NotifierProvider<CheckoutController, CheckoutState>(CheckoutController.new);

/// The order left over from a previous run, if any.
final Provider<PendingOrder?> pendingOrderProvider = Provider<PendingOrder?>((ref) {
  ref.watch(pendingOrderRevisionProvider);
  return ref.watch(pendingOrderStoreProvider).read();
});

/// Finishes an order the app was killed in the middle of.
///
/// Takes its collaborators directly rather than a `Ref`: it is a plain
/// procedure over a store and a repository, and keeping it that way is what
/// lets the recovery path be tested without a widget tree.
///
/// Called once AFTER first frame — never before it, for the same reason the
/// remote config is not awaited at startup: nothing between process start and
/// first paint waits on a server.
/// Returns whether the eSIM was provisioned, so the caller can refresh the
/// list that is about to show it.
Future<bool> resumePendingOrder({
  required PendingOrderStore store,
  required CheckoutRepository repository,
  bool force = false,
}) async {
  final order = store.read();
  if (order == null) return false;

  // Exhausted means the app stops trying ON ITS OWN. A user pressing "Retry
  // now" is not the app trying on its own, so [force] gets through.
  if (order.exhausted && !force) {
    debugPrint('[checkout] pending order ${order.paymentIntentId} exhausted; leaving for the user');
    return false;
  }

  try {
    await repository.finalize(
      packId: order.packId,
      paymentIntentId: order.paymentIntentId,
    );
    await store.clear();
    debugPrint('[checkout] resumed and provisioned ${order.paymentIntentId}');
    return true;
  } on CheckoutFailure catch (e) {
    // Same as above: already consumed means it is done, not that it failed.
    if (e.isAlreadyConsumed) {
      await store.clear();
      debugPrint('[checkout] already provisioned: ${order.paymentIntentId}');
      return true;
    }
    await store.write(order.withAttempt());
    debugPrint('[checkout] resume failed: ${e.messageKey}');
    return false;
  }
}

/// Promo codes.
///
/// The backend takes a `voucherToken` on `SubscriptionModel` and exposes
/// `/v1/subscriptions/voucher` and `/redeem/{voucherToken}`, but there is NO
/// endpoint that prices a code before purchase — nothing to call to turn
/// "SUMMER20" into a discount on this screen. So the field is present, as the
/// design draws it, and applying one reports that it cannot be validated yet
/// rather than pretending to compute a total. Backend request B10.
final promoCodeProvider = NotifierProvider<PromoCodeController, String?>(
  PromoCodeController.new,
);

class PromoCodeController extends Notifier<String?> {
  @override
  String? build() => null;

  void apply(String code) => state = code.trim().isEmpty ? null : code.trim();
  void clear() => state = null;
}
