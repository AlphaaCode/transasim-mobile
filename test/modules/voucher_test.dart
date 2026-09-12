import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transasim_mobile/core/network/api_client.dart';
import 'package:transasim_mobile/modules/checkout/data/voucher_repository_impl.dart';
import 'package:transasim_mobile/modules/checkout/domain/voucher.dart';

/// The old client discarded the server response and returned a hard-coded
/// `Voucher(status: 'valid')`, so EVERY 2xx was announced to the user as a
/// valid voucher. These tests are that defect, inverted.

class FakeWire {
  final Dio dio = Dio();
  final int status;
  final Object? body;
  final List<RequestOptions> sent = [];

  FakeWire({this.status = 200, this.body});

  void arm() {
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      sent.add(options);
      handler.resolve(
          Response<dynamic>(requestOptions: options, statusCode: status, data: body));
    }));
  }
}

VoucherRepositoryImpl repoOn(FakeWire wire) {
  final api = ApiClient(
    baseUrl: 'https://example.test/api',
    token: () => 'token',
    language: () => 'en',
    dio: wire.dio,
  );
  wire.arm();
  return VoucherRepositoryImpl(api);
}

void main() {
  group('a 2xx is necessary, never sufficient', () {
    test('200 carrying a REDEEMED status is a refusal', () async {
      // The exact case the old app got wrong. `VoucherDTO.status` can be
      // REDEEMED, and the endpoint returns a ResponseEntity able to carry it.
      final wire = FakeWire(status: 200, body: {'status': 'REDEEMED'});
      final result = await repoOn(wire).redeem('ABC123');

      expect(result, isA<VoucherRejected>());
      expect((result as VoucherRejected).messageKey, 'voucher.error.redeemed');
    });

    test('200 carrying EXPIRED or REVOKED is a refusal too', () async {
      for (final (raw, key) in [
        ('EXPIRED', 'voucher.error.expired'),
        ('REVOKED', 'voucher.error.revoked'),
      ]) {
        final wire = FakeWire(status: 200, body: {'status': raw});
        final result = await repoOn(wire).redeem('ABC123');
        expect((result as VoucherRejected).messageKey, key);
      }
    });

    test('200 with a usable status is accepted', () async {
      for (final raw in ['ACTIVE', 'CREATED', 'SENT']) {
        final wire = FakeWire(status: 200, body: {'status': raw, 'pack': {'name': 'Umrah 10GB'}});
        final result = await repoOn(wire).redeem('ABC123');
        expect(result, isA<VoucherAccepted>(), reason: '$raw should be usable');
        expect((result as VoucherAccepted).packName, 'Umrah 10GB');
      }
    });

    test('a status this build does not know is NOT treated as valid', () async {
      // A voucher the app cannot vouch for must not be announced as valid.
      final wire = FakeWire(status: 200, body: {'status': 'SOMETHING_NEW'});
      expect(await repoOn(wire).redeem('ABC123'), isA<VoucherRejected>());
    });

    test('200 with an opaque body falls back to the status code', () async {
      // This build's real success body: a fixed string with no status field at
      // all. There is nothing else to go on, so the code decides — and that is
      // the ONLY case where it does.
      final wire = FakeWire(status: 200, body: {'data': 'voucher redeemed successfully'});
      expect(await repoOn(wire).redeem('ABC123'), isA<VoucherAccepted>());
    });

    test('a 4xx is a refusal, and its reason is read when there is one', () async {
      final wire = FakeWire(status: 400, body: {'message': 'error.voucherexpired'});
      expect(await repoOn(wire).redeem('ABC123'), isA<VoucherRejected>());
    });
  });

  group('the request is the shape the endpoint takes', () {
    test('voucherToken in the body of /v1/subscriptions/voucher', () async {
      // `SubscriptionModel` carries voucherToken; only that field is populated.
      final wire = FakeWire(status: 200, body: {'status': 'ACTIVE'});
      await repoOn(wire).redeem('ABC123');

      expect(wire.sent.single.path, '/v1/subscriptions/voucher');
      expect(wire.sent.single.data, {'voucherToken': 'ABC123'});
    });
  });

  group('a scanned code is normalised before it is sent', () {
    test('a bare token passes through', () {
      expect(normaliseVoucherCode('ABC123'), 'ABC123');
    });

    test('spaces and dashes are how people group a printed code, not part of it', () {
      expect(normaliseVoucherCode('  ABC 123  '), 'ABC123');
      expect(normaliseVoucherCode('ABC 123'), 'ABC123');
    });

    test('a URL QR yields the token, from the path or the query', () {
      // A pilgrim holding a printed slip should not have to know which kind of
      // code an agency chose to print.
      expect(normaliseVoucherCode('https://sabily.fr/v/ABC123'), 'ABC123');
      expect(normaliseVoucherCode('https://sabily.fr/redeem?token=ABC123'), 'ABC123');
      expect(normaliseVoucherCode('https://sabily.fr/r?voucher=ABC123'), 'ABC123');
    });

    test('a trailing slash does not yield an empty token', () {
      expect(normaliseVoucherCode('https://sabily.fr/v/ABC123/'), 'ABC123');
    });

    test('nothing usable is null, not an empty request', () {
      expect(normaliseVoucherCode(''), isNull);
      expect(normaliseVoucherCode('   '), isNull);
    });
  });

  group('the status vocabulary matches the deployed enum', () {
    test('every VoucherStatus value the backend declares is handled', () {
      // Read off `VoucherStatus` in the JAR: ACTIVE, CREATED, EXPIRED,
      // REDEEMED, REVOKED, SENT.
      for (final raw in ['ACTIVE', 'CREATED', 'EXPIRED', 'REDEEMED', 'REVOKED', 'SENT']) {
        expect(VoucherStatus.parse(raw), isNot(VoucherStatus.unknown),
            reason: '$raw is a real server value and must not fall through');
      }
    });

    test('only three of the six are usable', () {
      final usable = VoucherStatus.values.where((s) => s.isUsable).toList();
      expect(usable, <VoucherStatus>[
        VoucherStatus.active,
        VoucherStatus.created,
        VoucherStatus.sent,
      ]);
    });

    test('casing and padding from the wire do not change the verdict', () {
      expect(VoucherStatus.parse(' redeemed '), VoucherStatus.redeemed);
      expect(VoucherStatus.parse('Active'), VoucherStatus.active);
      expect(VoucherStatus.parse(null), VoucherStatus.unknown);
    });
  });
}
