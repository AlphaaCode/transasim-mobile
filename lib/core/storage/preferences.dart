import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Overridden at startup with the real instance.
///
/// In core because more than one module keeps small device-local state here
/// (checkout's pending order, the onboarding tour), and a module may not import
/// another module (rule L2).
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPreferencesProvider must be overridden'),
);
