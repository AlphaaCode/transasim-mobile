import 'package:flutter_test/flutter_test.dart';
import 'package:transasim_mobile/modules/account/data/social_sign_in.dart';

/// Play Services reports a misconfigured Android OAuth client as a user
/// CANCELLATION, which the app then swallowed in silence: tapping "Continue
/// with Google" did nothing at all, no error, no busy state left behind.
///
/// Captured on a real device (SM-A256E) against both brands' Google projects:
///
///   [auth] google: code=GoogleSignInExceptionCode.canceled
///                  description=[16] Account reauth failed.
///
/// with logcat showing the truth underneath — `UNREGISTERED_ON_API_CONSOLE`
/// and "This android application is not registered to use OAuth2.0".
void main() {
  group('a cancellation that is really a broken OAuth client', () {
    test('the exact description a real device produced is recognised', () {
      expect(googleFailureLooksLikeConfiguration('[16] Account reauth failed.'), isTrue);
    });

    test('the underlying Play Services signatures are recognised too', () {
      for (final d in const [
        'UNREGISTERED_ON_API_CONSOLE',
        'This android application is not registered to use OAuth2.0',
        'DEVELOPER_ERROR',
      ]) {
        expect(googleFailureLooksLikeConfiguration(d), isTrue, reason: d);
      }
    });

    test('matching ignores case', () {
      expect(googleFailureLooksLikeConfiguration('[16] ACCOUNT REAUTH FAILED.'), isTrue);
    });
  });

  group('a user who simply changed their mind', () {
    // The regression this fix must not cause. A cancellation is not a failure
    // and must never paint an error (§7.2, the lesson the checkout sheet
    // already paid for), so anything unrecognised stays a silent cancel.
    test('no description at all is a real cancellation', () {
      expect(googleFailureLooksLikeConfiguration(null), isFalse);
      expect(googleFailureLooksLikeConfiguration(''), isFalse);
    });

    test('an ordinary cancellation description is a real cancellation', () {
      for (final d in const [
        'Sign in was canceled',
        '[16] Canceled by user',
        'The user closed the sheet',
      ]) {
        expect(googleFailureLooksLikeConfiguration(d), isFalse, reason: d);
      }
    });
  });
}
