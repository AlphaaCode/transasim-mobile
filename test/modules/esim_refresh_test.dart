/// The list is refetched after a purchase, after a redemption, and on a
/// throttled schedule — not once per session.
///
/// ⚠️ THE DEFECT THESE TESTS EXIST TO PREVENT. `esimPlansProvider` is kept
/// alive for the session, so it ran its request once and never again. Someone
/// who bought a pack came back to a list rendered BEFORE their own order, and
/// it stayed that way until the app was killed.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transasim_mobile/core/session/session.dart';
import 'package:transasim_mobile/core/sync/entitlements.dart';
import 'package:transasim_mobile/modules/checkout/domain/voucher.dart';
import 'package:transasim_mobile/modules/esim/domain/esim.dart';
import 'package:transasim_mobile/modules/esim/presentation/esim_controllers.dart';
import 'package:transasim_mobile/modules/checkout/presentation/voucher_controllers.dart';

void main() {
  group('the revision is what makes the list refetch', () {
    test('a bump changes the value every watcher reads', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(entitlementsRevisionProvider), 0);
      container.read(entitlementsRevisionProvider.notifier).bump();
      expect(container.read(entitlementsRevisionProvider), 1);
      container.read(entitlementsRevisionProvider.notifier).bump();
      expect(container.read(entitlementsRevisionProvider), 2);
    });

    test('a provider watching it re-runs on every bump', () async {
      // This is exactly the shape `esimPlansProvider` has.
      var runs = 0;
      final derived = FutureProvider<int>((ref) {
        ref.watch(entitlementsRevisionProvider);
        runs++;
        return Future.value(runs);
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(derived.future);
      expect(runs, 1);

      container.read(entitlementsRevisionProvider.notifier).bump();
      await container.read(derived.future);
      expect(runs, 2, reason: 'the purchase reaches the list');

      container.read(entitlementsRevisionProvider.notifier).bump();
      await container.read(derived.future);
      expect(runs, 3, reason: 'and so does the voucher');
    });

    test('the bump survives nothing watching it in between', () {
      // Riverpod 3 disposes an unwatched provider. Between paying and opening
      // the eSIM tab, nothing watches this — without keepAlive the bump would
      // be forgotten, which is the bug it exists to fix.
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(entitlementsRevisionProvider.notifier).bump();
      // Nothing holds a subscription here at all.
      expect(container.read(entitlementsRevisionProvider), 1);
    });
  });

  group('focus and resume are throttled', () {
    test('the first ask is allowed', () {
      final throttle = RefreshThrottle();
      expect(throttle.allow(DateTime(2026, 10, 5, 12)), isTrue);
    });

    test('a second ask inside the window is refused', () {
      final throttle = RefreshThrottle();
      final now = DateTime(2026, 10, 5, 12);
      expect(throttle.allow(now), isTrue);
      expect(throttle.allow(now.add(const Duration(seconds: 1))), isFalse);
      expect(throttle.allow(now.add(const Duration(seconds: 29))), isFalse);
    });

    test('once the window has passed it is allowed again', () {
      final throttle = RefreshThrottle();
      final now = DateTime(2026, 10, 5, 12);
      expect(throttle.allow(now), isTrue);
      expect(throttle.allow(now.add(const Duration(seconds: 30))), isTrue);
    });

    test('flicking between tabs costs one request, not one per visit', () {
      final throttle = RefreshThrottle();
      final now = DateTime(2026, 10, 5, 12);
      var allowed = 0;
      for (var i = 0; i < 20; i++) {
        if (throttle.allow(now.add(Duration(seconds: i)))) allowed++;
      }
      expect(allowed, 1);
    });

    test('a reset makes the next ask allowed', () {
      final throttle = RefreshThrottle();
      final now = DateTime(2026, 10, 5, 12);
      expect(throttle.allow(now), isTrue);
      expect(throttle.allow(now.add(const Duration(seconds: 2))), isFalse);
      throttle.reset();
      expect(throttle.allow(now.add(const Duration(seconds: 3))), isTrue);
    });

    test('the window is the documented 30 seconds', () {
      expect(RefreshThrottle.window, const Duration(seconds: 30));
    });
  });

  group('a redeemed voucher tells the eSIM list to refetch', () {
    // The success screen offers "see my eSIMs", and that list must not be the
    // one fetched before the voucher was used.

    ProviderContainer containerWith(VoucherResult result) {
      final c = ProviderContainer(overrides: [
        isSignedInProvider.overrideWithValue(true),
        voucherRepositoryProvider.overrideWithValue(_StubVoucherRepo(result)),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('an accepted voucher bumps the revision', () async {
      final c = containerWith(const VoucherAccepted(packName: 'France 10GB'));
      expect(c.read(entitlementsRevisionProvider), 0);

      await c.read(voucherControllerProvider.notifier).redeem('ABCD1234');

      expect(c.read(voucherControllerProvider), isA<VoucherSucceeded>());
      expect(c.read(entitlementsRevisionProvider), 1);
    });

    test('a refused voucher bumps nothing', () async {
      final c = containerWith(const VoucherRejected('voucher.error.redeemed'));

      await c.read(voucherControllerProvider.notifier).redeem('ABCD1234');

      expect(c.read(voucherControllerProvider), isA<VoucherFailed>());
      expect(c.read(entitlementsRevisionProvider), 0,
          reason: 'nothing was provisioned, so nothing is stale');
    });

    test('an eSIM activation string never reaches the backend', () async {
      // Zero requests: the repository would otherwise be asked, and refuse.
      final repo = _CountingVoucherRepo();
      final c = ProviderContainer(overrides: [
        isSignedInProvider.overrideWithValue(true),
        voucherRepositoryProvider.overrideWithValue(repo),
      ]);
      addTearDown(c.dispose);

      await c
          .read(voucherControllerProvider.notifier)
          .redeem(r'LPA:1$rsp.truphone.com$ACT-CODE-XYZ-123');

      final state = c.read(voucherControllerProvider);
      expect(state, isA<VoucherFailed>());
      expect((state as VoucherFailed).messageKey, 'voucher.error.activationCode');
      expect(repo.calls, 0, reason: 'it costs nothing to know this is not a voucher');
    });

    test('being signed out bumps nothing', () async {
      final c = ProviderContainer(overrides: [
        isSignedInProvider.overrideWithValue(false),
        voucherRepositoryProvider
            .overrideWithValue(_StubVoucherRepo(const VoucherAccepted())),
      ]);
      addTearDown(c.dispose);

      await c.read(voucherControllerProvider.notifier).redeem('ABCD1234');

      expect(c.read(entitlementsRevisionProvider), 0);
    });
  });


  group('opening the screen costs ONE request', () {
    // ⚠️ It cost two: the provider loaded the list, then the screen's
    // first-frame focus check found an unused throttle, allowed itself, and
    // invalidated the list it had just loaded. A fetch is a fetch whoever
    // started it, so the load spends the throttle's slot.

    ProviderContainer containerOn(_CountingRepo repo) {
      final c = ProviderContainer(overrides: [
        bearerTokenProvider.overrideWithValue('token'),
        esimRepositoryProvider.overrideWithValue(repo),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('the list load spends the throttle, so the focus check stands down',
        () async {
      final repo = _CountingRepo();
      final c = containerOn(repo);

      await c.read(esimPlansProvider.future);
      expect(repo.calls, 1);

      // This is precisely what the screen does on its first frame.
      final allowed = c.read(esimRefreshThrottleProvider).allow(DateTime.now());
      expect(allowed, isFalse, reason: 'the list was just fetched');
      expect(repo.calls, 1, reason: 'opening the screen is one request, not two');
    });

    test('a later focus, past the window, is allowed', () async {
      final repo = _CountingRepo();
      final c = containerOn(repo);

      await c.read(esimPlansProvider.future);
      final throttle = c.read(esimRefreshThrottleProvider);

      // The load marked "now"; 31 seconds later the screen may ask again.
      expect(
        throttle.allow(DateTime.now().add(const Duration(seconds: 31))),
        isTrue,
      );
    });

    test('a purchase refetches without waiting for the throttle', () async {
      // The revision path invalidates directly; it does not ask.
      final repo = _CountingRepo();
      final c = containerOn(repo);

      await c.read(esimPlansProvider.future);
      expect(repo.calls, 1);

      c.read(entitlementsRevisionProvider.notifier).bump();
      await c.read(esimPlansProvider.future);
      expect(repo.calls, 2, reason: 'the eSIM just bought must appear');
    });
  });
}

/// Answers one fixed verdict. The repository's own behaviour has its suite in
/// `voucher_test.dart`; what matters here is what the controller does after.
class _StubVoucherRepo implements VoucherRepository {
  final VoucherResult result;
  const _StubVoucherRepo(this.result);

  @override
  Future<VoucherResult> redeem(String token) async => result;

}

/// Counts how many times the list was actually fetched.
class _CountingRepo implements EsimRepository {
  int calls = 0;

  @override
  Future<List<EsimPlan>> plans() async {
    calls++;
    return const <EsimPlan>[];
  }

  @override
  Future<EsimUsage?> usage(EsimPlan plan) async => null;
}

/// Counts redemption attempts, so "no request was made" is assertable.
class _CountingVoucherRepo implements VoucherRepository {
  int calls = 0;

  @override
  Future<VoucherResult> redeem(String token) async {
    calls++;
    return const VoucherAccepted();
  }
}
