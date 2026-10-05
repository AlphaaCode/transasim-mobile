/// The scanner, the refusal reasons, and the code normaliser.
///
/// ⚠️ THE DEFECT THESE TESTS EXIST TO PREVENT. The screen cleared its one
/// in-flight flag the instant a refusal arrived, while the camera was still
/// pointed at the same slip — so it read it again, submitted again, and was
/// refused again. Measured in production: ~110 identical
/// `POST /v1/subscriptions/voucher` in 9 seconds off one voucher.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:transasim_mobile/modules/checkout/domain/voucher.dart';

void main() {
  group('the scanner cannot flood the endpoint', () {
    test('one slip held in frame submits exactly once', () async {
      // The camera fires many times a second on the same barcode. Before the
      // gate, each of those was a request.
      final gate = ScanGate();
      final now = DateTime(2026, 10, 5, 12);
      var submissions = 0;

      for (var frame = 0; frame < 120; frame++) {
        if (gate.accept('ABCD1234', now.add(Duration(milliseconds: 80 * frame)))) {
          submissions++;
        }
      }

      expect(submissions, 1, reason: '110 requests in 9 seconds is the bug');
      expect(gate.scanning, isFalse, reason: 'the camera stops on the first read');
    });

    test('a refusal does NOT re-arm the scanner', () async {
      final gate = ScanGate();
      final now = DateTime(2026, 10, 5, 12);
      expect(gate.accept('ABCD1234', now), isTrue);

      // The request comes back refused.
      gate.settle();

      // The camera is still pointed at the slip. It must not fire again.
      expect(gate.scanning, isFalse);
      expect(gate.accept('ABCD1234', now.add(const Duration(milliseconds: 100))), isFalse);
      expect(gate.accept('ABCD1234', now.add(const Duration(seconds: 30))), isFalse);
    });

    test('nothing is submitted while a request is in flight', () {
      final gate = ScanGate();
      final now = DateTime(2026, 10, 5, 12);
      expect(gate.accept('FIRST', now), isTrue);
      expect(gate.inFlight, isTrue);
      // Even a DIFFERENT code has to wait for the open request.
      expect(gate.accept('SECOND', now.add(const Duration(seconds: 10))), isFalse);
    });

    test('the same code is ignored for five seconds after a re-arm', () {
      final gate = ScanGate();
      final now = DateTime(2026, 10, 5, 12);
      expect(gate.accept('ABCD1234', now), isTrue);
      gate.settle();

      // "Scan again" deliberately forgets the last code, so the same slip can
      // be retried on purpose.
      gate.rearm();
      expect(gate.accept('ABCD1234', now.add(const Duration(seconds: 1))), isTrue);
    });

    test('only the user restarts scanning', () {
      final gate = ScanGate();
      final now = DateTime(2026, 10, 5, 12);
      gate.accept('ABCD1234', now);
      gate.settle();
      expect(gate.scanning, isFalse);

      gate.rearm();
      expect(gate.scanning, isTrue);
      expect(gate.inFlight, isFalse);
    });

    test('a second, different slip works after scanning is re-armed', () {
      final gate = ScanGate();
      final now = DateTime(2026, 10, 5, 12);
      expect(gate.accept('FIRST', now), isTrue);
      gate.settle();
      gate.rearm();
      expect(gate.accept('SECOND', now.add(const Duration(seconds: 2))), isTrue);
    });
  });

  group('the refusal says WHICH refusal it was', () {
    test('an exact key the server sent gets its own message', () {
      expect(voucherRefusalKey('error.voucher_not_found'), 'voucher.error.invalid');
      expect(voucherRefusalKey('error.voucher_expired'), 'voucher.error.expired');
      expect(voucherRefusalKey('error.voucher_revoked'), 'voucher.error.revoked');
      expect(voucherRefusalKey('error.voucher_cancelled'), 'voucher.error.revoked');
      expect(voucherRefusalKey('error.voucher_already_redeemed'),
          'voucher.error.redeemed');
    });

    test('"not available" stays neutral about WHY', () {
      // The backend uses it for a voucher it will not serve without saying
      // which reason applies, so the message must not pick one.
      expect(voucherRefusalKey('error.voucher_not_available'),
          'voucher.error.notAvailable');
    });

    test('the lumped key keeps the careful wording', () {
      // `subscribeViaVoucher` rethrows a provisioning failure on a VALID
      // voucher under this key. Calling that "already used" sends someone
      // away with a paid slip they could have redeemed.
      expect(voucherRefusalKey('error.voucher_subscription_failed'),
          'voucher.error.notRedeemed');
    });

    test('a key that merely CONTAINS a verdict word is not read as one', () {
      // The substring matcher this replaced would have called each of these a
      // definite verdict. A key the server did not send is not a diagnosis.
      expect(voucherRefusalKey('error.voucher_subscription_failed_already_used'),
          'voucher.error.notRedeemed');
      expect(voucherRefusalKey('error.some_unrelated_expired_thing'),
          'voucher.error.notRedeemed');
      expect(voucherRefusalKey('error.redeem_service_down'),
          'voucher.error.notRedeemed');
    });

    test('an unknown key falls back rather than guessing', () {
      expect(voucherRefusalKey('error.something_new'), 'voucher.error.notRedeemed');
      expect(voucherRefusalKey(null), 'voucher.error.notRedeemed');
      expect(voucherRefusalKey('   '), 'voucher.error.notRedeemed');
    });

    test('casing and surrounding space do not matter', () {
      expect(voucherRefusalKey('  ERROR.VOUCHER_EXPIRED  '), 'voucher.error.expired');
    });
  });


  group('an eSIM activation string is not a voucher', () {
    // People point this scanner at the QR on their own install screen. The
    // backend has no idea what to do with `LPA:1$...` and answers a generic
    // refusal, so the user was told their voucher was invalid — true, and
    // useless.

    test('it is recognised, in any casing, scanned or typed', () {
      expect(
        looksLikeEsimActivationCode(r'LPA:1$rsp.truphone.com$ACT-CODE-XYZ-123'),
        isTrue,
      );
      expect(looksLikeEsimActivationCode(r'  lpa:1$rsp.example.com$ABC  '), isTrue);
    });

    test('an ordinary voucher is not mistaken for one', () {
      expect(looksLikeEsimActivationCode('ABCD1234'), isFalse);
      expect(looksLikeEsimActivationCode('LPA'), isFalse);
      expect(looksLikeEsimActivationCode(''), isFalse);
      // A token that merely starts with the letters is still a token.
      expect(looksLikeEsimActivationCode('LPAX1234'), isFalse);
    });

    test('it survives normalisation, which is what the gate submits', () {
      // `normaliseVoucherCode` strips dashes and upper-cases; neither the
      // colon nor the dollar is touched, so the guard still fires on what is
      // actually handed to the controller.
      final normalised =
          normaliseVoucherCode(r'LPA:1$rsp.truphone.com$ACT-CODE-XYZ-123')!;
      expect(looksLikeEsimActivationCode(normalised), isTrue);
    });

    test('the gate still stops the camera for it', () {
      // The refusal is local, but it is still one read: the camera stops and
      // only "scan again" restarts it, so this costs zero requests AND does
      // not re-fire on the next frame.
      final gate = ScanGate();
      final now = DateTime(2026, 10, 5, 12);
      expect(gate.accept(r'LPA:1$rsp.truphone.com$ACT', now), isTrue);
      expect(gate.scanning, isFalse);
      gate.settle();
      expect(gate.accept(r'LPA:1$rsp.truphone.com$ACT', now), isFalse);
    });
  });

  group('a printed code survives being typed back in', () {
    test('dashes are stripped, not sent to the server', () {
      // The old class was `[\s ]` — whitespace and a non-breaking space,
      // which is whitespace again. It never removed a dash, so a slip printed
      // in groups was refused and retyping it by hand did not help.
      expect(normaliseVoucherCode('ABCD-1234-EFGH'), 'ABCD1234EFGH');
    });

    test('the unicode dashes a printed slip actually carries are stripped', () {
      expect(normaliseVoucherCode('ABCD‐1234'), 'ABCD1234'); // hyphen
      expect(normaliseVoucherCode('ABCD–1234'), 'ABCD1234'); // en dash
      expect(normaliseVoucherCode('ABCD—1234'), 'ABCD1234'); // em dash
      expect(normaliseVoucherCode('ABCD−1234'), 'ABCD1234'); // minus
    });

    test('the code is upper-cased', () {
      expect(normaliseVoucherCode('abcd-1234'), 'ABCD1234');
      expect(normaliseVoucherCode('  abcd 1234  '), 'ABCD1234');
    });

    test('spaces and non-breaking spaces still go', () {
      expect(normaliseVoucherCode('ABCD 1234'), 'ABCD1234');
      expect(normaliseVoucherCode('ABCD 1234'), 'ABCD1234');
    });

    test('a URL still yields its token, normalised', () {
      expect(normaliseVoucherCode('https://example.test/v/abcd-1234'), 'ABCD1234');
      expect(normaliseVoucherCode('https://example.test/r?token=abcd-1234'), 'ABCD1234');
    });

    test('nothing usable is null, not an empty token', () {
      expect(normaliseVoucherCode('   '), isNull);
      expect(normaliseVoucherCode('---'), isNull);
    });
  });
}
