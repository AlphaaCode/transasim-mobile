import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../presentation/account_controllers.dart';

/// The only surfaces that ever touch a provider SDK.
///
/// Same shape as `checkout/data/stripe_sheet.dart`, for the same reason: the
/// controller depends on a function, not on Google's or Apple's SDK, which is
/// what lets both sign-in paths be tested without a real account or a device.
///
/// Each returns `null` when the user backed out. A cancellation is not a
/// failure and must not paint an error — the lesson the checkout sheet already
/// paid for (§7.2, difference #4).
///
/// Neither uses Firebase. The backend validates the provider's own ID token
/// directly, so there is nothing in between.

/// Google. [serverClientId] is the backend's OAuth **web** client ID, and it
/// is not optional on Android: without it the SDK returns an account with no
/// `idToken` at all, and with the wrong one the backend rejects a token that
/// looks perfectly valid. It comes from the brand's configuration, so two
/// clients can sign in against two different Google projects.
Future<String?> requestGoogleIdToken({required String serverClientId}) async {
  final google = GoogleSignIn.instance;
  if (!google.supportsAuthenticate()) {
    debugPrint('[auth] google: platform has no interactive sign-in');
    return null;
  }
  try {
    // Idempotent, and cheap enough to call per attempt rather than holding
    // initialisation state that a hot restart would leave stale.
    await google.initialize(serverClientId: serverClientId);
    final account = await google.authenticate();
    final token = account.authentication.idToken;
    if (token == null || token.isEmpty) {
      // Almost always a configuration fault, not a user one: a serverClientId
      // that is not a web client, or an Android signing certificate that is
      // not registered in the Google Cloud project.
      debugPrint('[auth] google: signed in but no idToken — check serverClientId and SHA-1');
      return null;
    }
    return token;
  } on GoogleSignInException catch (e) {
    // Logged BEFORE the cancellation check, not after. A misconfigured OAuth
    // client and a user who changed their mind look identical on screen, and
    // this line is the only place the difference is visible at all.
    debugPrint('[auth] google: code=${e.code} description=${e.description}');
    if (e.code == GoogleSignInExceptionCode.canceled &&
        !googleFailureLooksLikeConfiguration(e.description)) {
      return null;
    }
    rethrow;
  }
}

/// Whether a `canceled` really means the CONFIGURATION is wrong.
///
/// Play Services does not distinguish the two. An Android OAuth client whose
/// package name and SHA-1 are not registered in the Google project comes back
/// as [GoogleSignInExceptionCode.canceled] with `[16] Account reauth failed.`
/// — the same code a user gets for dismissing the sheet. Observed on a real
/// device against both brands' projects; logcat shows the truth underneath
/// (`UNREGISTERED_ON_API_CONSOLE`, "This android application is not
/// registered to use OAuth2.0") while the app was told the user backed out.
///
/// The result was the worst kind of bug: tapping the button did nothing at
/// all, with no error, because a cancellation must never paint one (§7.2).
///
/// So the description is matched, and ONLY for signatures known to mean a
/// broken client. Anything unrecognised — including a null description — is
/// still treated as a genuine cancellation, because turning a user's change
/// of mind into a red error is the regression this must not cause.
///
/// ponytail: vendor string matching, and it is as brittle as it looks. The
/// day google_sign_in reports a distinct code for this, delete the whole
/// function and switch on the code instead.
bool googleFailureLooksLikeConfiguration(String? description) {
  final d = (description ?? '').toLowerCase();
  if (d.isEmpty) return false;
  return d.contains('reauth failed') ||
      d.contains('unregistered') ||
      d.contains('not registered') ||
      d.contains('developer_error');
}

/// Apple. iOS only in this app — the button is not built on Android, so the
/// Android/web `webAuthenticationOptions` path is deliberately not wired: it
/// needs a service ID and a return URL nobody has set up.
Future<String?> requestAppleIdToken() async {
  try {
    final credential = await SignInWithApple.getAppleIDCredential(
      // Email and name come back ONLY on the very first authorization for an
      // account, and are not needed here: the backend reads the identity
      // token. Asked for anyway so the server can populate a profile if it
      // wants to, because there is no second chance to ask.
      scopes: const [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
    );
    final token = credential.identityToken;
    if (token == null || token.isEmpty) {
      debugPrint('[auth] apple: authorized but no identityToken');
      return null;
    }
    return token;
  } on SignInWithAppleAuthorizationException catch (e) {
    if (e.code == AuthorizationErrorCode.canceled) return null;
    debugPrint('[auth] apple failed: ${e.code} ${e.message}');
    rethrow;
  }
}

/// Bound to the providers the account module declares, so `main_common` wires
/// the real SDKs in one place and a test can pass a function.
const RequestGoogleIdToken kRequestGoogleIdToken = requestGoogleIdToken;
const RequestAppleIdToken kRequestAppleIdToken = requestAppleIdToken;
