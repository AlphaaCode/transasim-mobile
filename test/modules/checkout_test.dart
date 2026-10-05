import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transasim_mobile/core/sync/entitlements.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transasim_mobile/core/brand/brand_config.dart';
import 'package:transasim_mobile/core/brand/brand_providers.dart';
import 'package:transasim_mobile/core/commerce/money.dart';
import 'package:transasim_mobile/core/network/api_client.dart';
import 'package:transasim_mobile/modules/checkout/data/checkout_repository_impl.dart';
import 'package:transasim_mobile/modules/checkout/domain/checkout.dart';
import 'package:transasim_mobile/modules/checkout/presentation/checkout_controllers.dart';

import '../core/brand_config_test.dart' show validJson;

/// This is the module the rebuild exists for. Every test here corresponds to a
/// measured defect in the old app, or to a guarantee §7 depends on.

class FakeWire {
  final List<RequestOptions> sent = <RequestOptions>[];
  final Dio dio = Dio();

  /// path -> (status, body). A list cycles through responses per call.
  final Map<String, List<(int, Object?)>> routes;

  FakeWire(this.routes);

  void arm() {
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      sent.add(options);
      final queue = routes[options.path];
      final (status, body) = (queue == null || queue.isEmpty)
          ? (404, null)
          : (queue.length == 1 ? queue.first : queue.removeAt(0));
      handler.resolve(
          Response<dynamic>(requestOptions: options, statusCode: status, data: body));
    }));
  }

  RequestOptions get last => sent.last;
  int callsTo(String path) => sent.where((r) => r.path == path).length;
}

CheckoutRepositoryImpl repoOn(FakeWire wire) {
  final api = ApiClient(
    baseUrl: 'https://example.test/api',
    token: () => 'token',
    language: () => 'en',
    dio: wire.dio,
  );
  wire.arm();
  return CheckoutRepositoryImpl(api);
}

const money = Money(wireAmount: '9.99', currencyCode: 'EUR', symbol: '€');

const request = PurchaseRequest(
  packId: 42,
  packName: 'France 10GB',
  summary: '10 GB · 7 days',
  amount: money,
);

BrandConfig brand({String? stripeKey}) {
  final json = validJson();
  if (stripeKey != null) {
    (json['mobile'] as Map)['stripePublishableKey'] = stripeKey;
  }
  final r = BrandConfig.parse(json, expectedSlug: 'acme');
  if (r.errors.isNotEmpty) throw StateError(r.describe('acme'));
  return r.config as BrandConfig;
}

/// Records every call so "posts nothing" is assertable.
class SpyRepository implements CheckoutRepository {
  final PaymentInit? initResult;
  final String? initError;

  /// Outcomes for successive finalize calls; the last repeats.
  final List<String?> finalizeErrors;

  int initCalls = 0;
  final List<(int, String)> finalized = [];

  SpyRepository({
    this.initResult,
    this.initError,
    this.finalizeErrors = const [null],
  });

  @override
  Future<PaymentInit> init({required Money amount}) async {
    initCalls++;
    if (initError != null) throw CheckoutFailure(initError!);
    return initResult ??
        const PaymentInit(
          paymentId: 7,
          clientSecret: 'pi_ABC_secret_XYZ',
          paymentIntentId: 'pi_ABC',
          arrivedAs: {},
        );
  }

  @override
  Future<void> finalize({required int packId, required String paymentIntentId}) async {
    final i = finalized.length;
    finalized.add((packId, paymentIntentId));
    final err = i < finalizeErrors.length ? finalizeErrors[i] : finalizeErrors.last;
    if (err != null) throw CheckoutFailure(err);
  }
}

Future<ProviderContainer> containerWith({
  required SpyRepository repo,
  required SheetResult sheet,
  String? stripeKey,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(overrides: [
    brandConfigProvider.overrideWithValue(brand(stripeKey: stripeKey)),
    sharedPreferencesProvider.overrideWithValue(prefs),
    checkoutRepositoryProvider.overrideWithValue(repo),
    presentSheetProvider.overrideWithValue(
      ({required clientSecret, required merchantName}) async => sheet,
    ),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the exact decimal reaches the wire', () {
    // THE defect. `.toInt()` turned €9.99 into €9.00, and because the backend
    // compares the paid amount against `sabilyAmount` and throws on a mismatch,
    // it turned a lost cent into an undelivered eSIM.
    test('cents survive into the query string', () async {
      final wire = FakeWire({
        '/v1/payments/init': [
          (200, {'id': 7, 'clientSecret': 'pi_ABC_secret_XYZ', 'paymentIntentId': 'pi_ABC'})
        ],
      });
      await repoOn(wire).init(amount: money);

      expect(wire.last.queryParameters['amount'], '9.99');
      expect(wire.last.queryParameters['amount'], isA<String>(),
          reason: 'a num here is a rounding waiting to happen');
      expect(wire.last.queryParameters['currency'], 'EUR');
    });

    test('an awkward decimal is not re-formatted on the way out', () async {
      // Whatever the server said, verbatim. No parse, no toStringAsFixed.
      for (final raw in ['9.99', '0.10', '15', '1234.5', '7.005']) {
        final wire = FakeWire({
          '/v1/payments/init': [
            (200, {'clientSecret': 'pi_A_secret_B', 'paymentIntentId': 'pi_A'})
          ],
        });
        await repoOn(wire)
            .init(amount: Money(wireAmount: raw, currencyCode: 'EUR'));
        expect(wire.last.queryParameters['amount'], raw);
      }
    });

    test('the amount goes in the QUERY, never the body', () async {
      // Both parameters are @RequestParam; there is no @RequestBody on the
      // deployed method, so a body would simply be ignored and the payment
      // would fail validation server-side.
      final wire = FakeWire({
        '/v1/payments/init': [
          (200, {'clientSecret': 'pi_A_secret_B', 'paymentIntentId': 'pi_A'})
        ],
      });
      await repoOn(wire).init(amount: money);
      expect(wire.last.queryParameters, containsPair('amount', '9.99'));
      expect(wire.last.data, isNull);
    });
  });

  group('the init response is read by shape, not by name — §7.3', () {
    PaymentInit parse(Map<String, dynamic> json) {
      final r = PaymentInit.parse(json);
      expect(r, isNotNull, reason: 'should have recognised both values');
      return r!;
    }

    test('correctly named fields', () {
      final r = parse({'paymentId': 7, 'clientSecret': 'pi_A_secret_B', 'paymentIntentId': 'pi_A'});
      expect(r.clientSecret, 'pi_A_secret_B');
      expect(r.paymentIntentId, 'pi_A');
      expect(r.paymentId, 7);
    });

    test('SWAPPED fields — what the deployed backend actually does', () {
      final r = parse({'clientSecret': 'pi_A', 'paymentIntentId': 'pi_A_secret_B'});
      expect(r.clientSecret, 'pi_A_secret_B');
      expect(r.paymentIntentId, 'pi_A');
    });

    test('fields under names nobody predicted', () {
      final r = parse({'foo': 'pi_A_secret_B', 'bar': 'pi_A'});
      expect(r.clientSecret, 'pi_A_secret_B');
      expect(r.paymentIntentId, 'pi_A');
    });

    test('only a secret: the id is recovered from it', () {
      // Strictly better than failing a payment the user already authorised.
      final r = parse({'clientSecret': 'pi_ABC_secret_XYZ'});
      expect(r.paymentIntentId, 'pi_ABC');
    });

    test('a secret is never mistaken for an id', () {
      // The id pattern must be anchored, or `pi_A_secret_B` matches it too.
      expect(PaymentInit.intentPattern.hasMatch('pi_A_secret_B'), isFalse);
      expect(PaymentInit.secretPattern.hasMatch('pi_A'), isFalse);
    });

    test('nothing usable is a failure, not a half-success', () {
      expect(PaymentInit.parse({'id': 7}), isNull);
      expect(PaymentInit.parse({'clientSecret': 'garbage'}), isNull);
      expect(PaymentInit.parse(<String, dynamic>{}), isNull);
    });

    test('which field each arrived in is recorded for telemetry', () {
      final r = parse({'clientSecret': 'pi_A', 'paymentIntentId': 'pi_A_secret_B'});
      expect(r.arrivedAs['paymentIntentId'], 'clientSecret');
      expect(r.arrivedAs['clientSecret'], 'paymentIntentId');
    });
  });

  group('the order is on disk before anything is shown', () {
    test('a pending order exists by the time the sheet is presented', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = PendingOrderStore(prefs);
      final repo = SpyRepository();

      PendingOrder? seenAtSheetTime;
      final c = ProviderContainer(overrides: [
        brandConfigProvider.overrideWithValue(brand()),
        sharedPreferencesProvider.overrideWithValue(prefs),
        checkoutRepositoryProvider.overrideWithValue(repo),
        presentSheetProvider.overrideWithValue(
          ({required clientSecret, required merchantName}) async {
            // The whole point: if the process dies HERE, this is what is left.
            seenAtSheetTime = store.read();
            return SheetResult.completed;
          },
        ),
      ]);
      addTearDown(c.dispose);

      await c.read(checkoutControllerProvider.notifier).pay(request);

      expect(seenAtSheetTime, isNotNull,
          reason: 'a charge with no local record is a payment the user cannot recover');
      expect(seenAtSheetTime!.paymentIntentId, 'pi_ABC');
      expect(seenAtSheetTime!.packId, 42);
      expect(seenAtSheetTime!.amount, '9.99', reason: 'the exact decimal, stored as text');
    });

    test('the client secret is never written to disk', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final order = PendingOrder(
        paymentId: 1,
        packId: 42,
        packName: 'x',
        paymentIntentId: 'pi_ABC',
        amount: '9.99',
        currency: 'EUR',
        startedAt: DateTime.now(),
      );
      await PendingOrderStore(prefs).write(order);

      final raw = prefs.getString('checkout.pending')!;
      expect(raw, isNot(contains('_secret_')),
          reason: 'a single-use charge authorisation has no business surviving the session');
    });

    test('a corrupt record does not wedge every future launch', () async {
      SharedPreferences.setMockInitialValues({'checkout.pending': 'not json'});
      final prefs = await SharedPreferences.getInstance();
      expect(PendingOrderStore(prefs).read(), isNull);
    });
  });

  group('cancellation posts nothing — §7.2 difference #4', () {
    test('a dismissed sheet finalises nothing and clears the order', () async {
      final repo = SpyRepository();
      final c = await containerWith(repo: repo, sheet: SheetResult.cancelled);

      await c.read(checkoutControllerProvider.notifier).pay(request);

      expect(repo.finalized, isEmpty,
          reason: 'the old app posted a subscribe call after a cancel');
      expect(c.read(checkoutControllerProvider), isA<CheckoutIdle>(),
          reason: 'a cancel is not an error to report');
      expect(c.read(pendingOrderStoreProvider).read(), isNull);
    });

    test('a declined card is an error, and still posts nothing', () async {
      final repo = SpyRepository();
      final c = await containerWith(repo: repo, sheet: SheetResult.failed);

      await c.read(checkoutControllerProvider.notifier).pay(request);

      expect(repo.finalized, isEmpty);
      expect(c.read(checkoutControllerProvider), isA<CheckoutError>());
    });
  });

  group('retry leans on the server guarantee', () {
    test('a transient failure is retried and then succeeds', () async {
      final repo = SpyRepository(finalizeErrors: ['error.network_unavailable', null]);
      final c = await containerWith(repo: repo, sheet: SheetResult.completed);

      await c.read(checkoutControllerProvider.notifier).pay(request);

      expect(repo.finalized.length, 2);
      // Same intent id both times — which is exactly what makes it safe:
      // `/v1/subscriptions/card` keys on externalReference and refuses to
      // double-provision a payment already COMPLETED_AND_CONSUMED.
      expect(repo.finalized[0], repo.finalized[1]);
      expect(c.read(checkoutControllerProvider), isA<CheckoutDone>());
      expect(c.read(pendingOrderStoreProvider).read(), isNull);
    });

    test('exhausted retries leave the order on disk, not a silent loss', () async {
      final repo = SpyRepository(finalizeErrors: ['error.network_unavailable']);
      final c = await containerWith(repo: repo, sheet: SheetResult.completed);

      await c.read(checkoutControllerProvider.notifier).pay(request);

      expect(repo.finalized.length, 3, reason: 'three attempts, then stop and surface it');
      expect(c.read(checkoutControllerProvider), isA<CheckoutAwaitingProvisioning>());

      final left = c.read(pendingOrderStoreProvider).read();
      expect(left, isNotNull, reason: 'the money is gone; the record must not be');
      expect(left!.attempts, 3);
    });

    test('a resumed order finishes on the next launch', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = PendingOrderStore(prefs);
      await store.write(PendingOrder(
        paymentId: 1,
        packId: 42,
        packName: 'France 10GB',
        paymentIntentId: 'pi_ABC',
        amount: '9.99',
        currency: 'EUR',
        startedAt: DateTime.now(),
      ));

      final repo = SpyRepository();
      final c = ProviderContainer(overrides: [
        brandConfigProvider.overrideWithValue(brand()),
        sharedPreferencesProvider.overrideWithValue(prefs),
        checkoutRepositoryProvider.overrideWithValue(repo),
      ]);
      addTearDown(c.dispose);

      await resumePendingOrder(store: store, repository: repo);

      expect(repo.finalized.single, (42, 'pi_ABC'));
      expect(store.read(), isNull);
    });

    test('an order that has failed too often stops retrying by itself', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var order = PendingOrder(
        paymentId: 1,
        packId: 42,
        packName: 'x',
        paymentIntentId: 'pi_ABC',
        amount: '9.99',
        currency: 'EUR',
        startedAt: DateTime.now(),
      );
      for (var i = 0; i < PendingOrder.maxAutomaticAttempts; i++) {
        order = order.withAttempt();
      }
      await PendingOrderStore(prefs).write(order);

      final repo = SpyRepository();
      final c = ProviderContainer(overrides: [
        brandConfigProvider.overrideWithValue(brand()),
        sharedPreferencesProvider.overrideWithValue(prefs),
        checkoutRepositoryProvider.overrideWithValue(repo),
      ]);
      addTearDown(c.dispose);

      await resumePendingOrder(
          store: PendingOrderStore(prefs), repository: repo);

      expect(repo.finalized, isEmpty, reason: 'it needs a person, not a seventh attempt');
      expect(PendingOrderStore(prefs).read(), isNotNull);
    });
  });

  group('a placeholder Stripe key is not a usable one', () {
    test('the shipped placeholder is refused', () {
      // It passes the config validator, which only checks the pk_ prefix — so
      // without this the app starts and fails at the payment sheet instead.
      expect(isUsableStripeKey('pk_test_PLACEHOLDER_AWAITING_CLIENT'), isFalse);
      expect(isUsableStripeKey('pk_test_short'), isFalse);
      expect(isUsableStripeKey('sk_test_51ABCDEFGHIJKLMNOPQRSTUVWX'), isFalse);
      expect(isUsableStripeKey(''), isFalse);
    });

    test('a real-shaped key is accepted', () {
      expect(isUsableStripeKey('pk_test_51ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'), isTrue);
      expect(isUsableStripeKey('pk_live_51ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'), isTrue);
    });

    test('checkout knows it cannot take money', () async {
      final c = await containerWith(
        repo: SpyRepository(),
        sheet: SheetResult.completed,
        stripeKey: 'pk_test_PLACEHOLDER_AWAITING_CLIENT',
      );
      expect(c.read(canTakePaymentsProvider), isFalse);
    });
  });

  group('failures before the sheet leave nothing behind', () {
    test('an unreadable init response never reaches Stripe', () async {
      final repo = SpyRepository(initError: 'checkout.error.initShape');
      final c = await containerWith(repo: repo, sheet: SheetResult.completed);

      await c.read(checkoutControllerProvider.notifier).pay(request);

      expect(repo.finalized, isEmpty);
      expect((c.read(checkoutControllerProvider) as CheckoutError).messageKey,
          'checkout.error.initShape');
      expect(c.read(pendingOrderStoreProvider).read(), isNull);
    });

    test('a second tap while a charge is in flight is ignored', () async {
      final gate = Completer<void>();
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = SpyRepository();

      final c = ProviderContainer(overrides: [
        brandConfigProvider.overrideWithValue(brand()),
        sharedPreferencesProvider.overrideWithValue(prefs),
        checkoutRepositoryProvider.overrideWithValue(repo),
        presentSheetProvider.overrideWithValue(
          ({required clientSecret, required merchantName}) async {
            await gate.future;
            return SheetResult.completed;
          },
        ),
      ]);
      addTearDown(c.dispose);

      final first = c.read(checkoutControllerProvider.notifier).pay(request);
      await Future<void>.delayed(Duration.zero);
      await c.read(checkoutControllerProvider.notifier).pay(request);

      expect(repo.initCalls, 1, reason: 'one tap, one payment intent');
      gate.complete();
      await first;
    });
  });

  group('a completed purchase tells the eSIM list to refetch', () {
    // ⚠️ Without this the customer returns from checkout to a list that was
    // fetched before their own order, and it stays that way until the app is
    // killed. The eSIM they just paid for is simply not there.

    test('paying bumps the revision exactly once', () async {
      final repo = SpyRepository();
      final c = await containerWith(repo: repo, sheet: SheetResult.completed);

      expect(c.read(entitlementsRevisionProvider), 0);
      await c.read(checkoutControllerProvider.notifier).pay(request);

      expect(c.read(checkoutControllerProvider), isA<CheckoutDone>());
      expect(c.read(entitlementsRevisionProvider), 1);
    });

    test('a cancelled sheet bumps nothing', () async {
      final repo = SpyRepository();
      final c = await containerWith(repo: repo, sheet: SheetResult.cancelled);

      await c.read(checkoutControllerProvider.notifier).pay(request);

      expect(c.read(entitlementsRevisionProvider), 0,
          reason: 'nothing was bought, so nothing is stale');
    });

    test('a payment that never provisions bumps nothing', () async {
      // Charged but not provisioned: there is no eSIM to go and fetch yet,
      // and the stuck-order card is what covers this case.
      final repo = SpyRepository(finalizeErrors: ['checkout.error.declined']);
      final c = await containerWith(repo: repo, sheet: SheetResult.completed);

      await c.read(checkoutControllerProvider.notifier).pay(request);

      expect(c.read(checkoutControllerProvider),
          isA<CheckoutAwaitingProvisioning>());
      expect(c.read(entitlementsRevisionProvider), 0);
    });
  });

  group('"Retry now" is a person asking, not the app looping', () {
    test('a resumed order reports whether it provisioned', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = PendingOrderStore(prefs);
      await store.write(PendingOrder(
        paymentId: 1,
        packId: 42,
        packName: 'France 10GB',
        paymentIntentId: 'pi_ABC',
        amount: '9.99',
        currency: 'EUR',
        startedAt: DateTime.now(),
      ));

      final done = await resumePendingOrder(
        store: store,
        repository: SpyRepository(),
      );
      expect(done, isTrue, reason: 'the caller refreshes the list on true');
      expect(store.read(), isNull);
    });

    test('a failed resume reports false and keeps the record', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = PendingOrderStore(prefs);
      await store.write(PendingOrder(
        paymentId: 1,
        packId: 42,
        packName: 'France 10GB',
        paymentIntentId: 'pi_ABC',
        amount: '9.99',
        currency: 'EUR',
        startedAt: DateTime.now(),
      ));

      final done = await resumePendingOrder(
        store: store,
        repository: SpyRepository(finalizeErrors: ['checkout.error.declined']),
      );
      expect(done, isFalse);
      expect(store.read(), isNotNull, reason: 'the money is gone; the record stays');
    });

    test('force gets past the automatic attempt cap', () async {
      // The cap stops the APP retrying forever. A user pressing the button is
      // not the app, and the backend refuses a consumed payment anyway, so
      // there is nothing to protect them from here.
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var order = PendingOrder(
        paymentId: 1,
        packId: 42,
        packName: 'x',
        paymentIntentId: 'pi_ABC',
        amount: '9.99',
        currency: 'EUR',
        startedAt: DateTime.now(),
      );
      for (var i = 0; i < PendingOrder.maxAutomaticAttempts; i++) {
        order = order.withAttempt();
      }
      await PendingOrderStore(prefs).write(order);

      final repo = SpyRepository();
      final done = await resumePendingOrder(
        store: PendingOrderStore(prefs),
        repository: repo,
        force: true,
      );

      expect(done, isTrue);
      expect(repo.finalized.single, (42, 'pi_ABC'));
      expect(PendingOrderStore(prefs).read(), isNull);
    });

    test('without force an exhausted order is still left alone', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var order = PendingOrder(
        paymentId: 1,
        packId: 42,
        packName: 'x',
        paymentIntentId: 'pi_ABC',
        amount: '9.99',
        currency: 'EUR',
        startedAt: DateTime.now(),
      );
      for (var i = 0; i < PendingOrder.maxAutomaticAttempts; i++) {
        order = order.withAttempt();
      }
      await PendingOrderStore(prefs).write(order);

      final repo = SpyRepository();
      final done = await resumePendingOrder(
        store: PendingOrderStore(prefs),
        repository: repo,
      );

      expect(done, isFalse);
      expect(repo.finalized, isEmpty, reason: 'it needs a person, not a seventh attempt');
    });
  });

}
