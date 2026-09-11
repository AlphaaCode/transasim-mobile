/// The socle's one HTTP client.
///
/// It lives in core, not in whichever module happened to need it first: the
/// catalogue built it originally, and account importing it from there would
/// have been a module-to-module dependency (rule L2). Anything two modules both
/// need belongs in core, reached through a contract.
///
/// The bearer token is read through [bearerTokenProvider] on every request
/// rather than captured once, so signing out stops the very next call — the old
/// app kept a second copy of the token that logout never cleared, and a
/// signed-out user's requests carried it until it expired.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../brand/brand_providers.dart';
import '../session/session.dart';
import 'api_client.dart';


final apiClientProvider = Provider<ApiClient>((ref) {
  final brand = ref.watch(brandConfigProvider);
  return ApiClient(
    baseUrl: brand.mobile.apiBaseUrl,
    token: () => ref.read(bearerTokenProvider),
    language: () => ref.read(languageProvider),
  );
});
