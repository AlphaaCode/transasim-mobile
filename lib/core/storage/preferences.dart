import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../brand/brand_providers.dart';

/// Overridden at startup with the real instance.
///
/// In core because more than one module keeps small device-local state here
/// (checkout's pending order, the onboarding tour), and a module may not import
/// another module (rule L2).
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPreferencesProvider must be overridden'),
);

/// What the app this one replaces left in the same store. Store updates keep
/// app data, and both apps use SharedPreferences, so an updated phone still
/// holds the old app's keys (old Sabily app, `lib/services/auth_service.dart`
/// and `language_service.dart`).
///
/// Its session is not carried over: the token sat here in plain text beside
/// the password it came from (`pending_password`), and this app keeps a token
/// only in secure storage. So both are deleted, and an updated user is simply
/// signed out — their eSIMs and orders are on the server, behind sign-in. The
/// language they picked is kept.
///
/// Nearly free once done: `containsKey` reads the in-memory copy, so a phone
/// with nothing left to forget touches no platform channel.
Future<void> forgetLegacyApp(SharedPreferences prefs) async {
  const legacyLanguage = 'selected_language';
  const legacyCredentials = [
    'auth_token',
    'is_logged_in',
    'user_data',
    'pending_email',
    'pending_password',
  ];

  final language = prefs.get(legacyLanguage);
  if (language is String && !prefs.containsKey(LanguageController.storageKey)) {
    await prefs.setString(LanguageController.storageKey, language);
  }
  await Future.wait([
    for (final key in [legacyLanguage, ...legacyCredentials])
      if (prefs.containsKey(key)) prefs.remove(key),
  ]);
}
