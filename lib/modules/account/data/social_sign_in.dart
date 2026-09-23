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
    if (e.code == GoogleSignInExceptionCode.canceled) return null;
    debugPrint('[auth] google failed: ${e.code} ${e.description}');
    rethrow;
  }
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
