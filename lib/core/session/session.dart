/// Session storage and lifetime. ARCHITECTURE-MOBILE.md §10.2.
///
/// This file exists because of R11, which was the worst non-money finding in
/// `ANALYSE-EXISTANT.md`:
///
///   - the JWT lived in `SharedPreferences` — an unencrypted XML file on
///     Android, a plist inside unencrypted iCloud backups on iOS;
///   - the user's PASSWORD was written to disk in plaintext at registration
///     (`pending_password`) and `clearAuthData()` did not remove it, so it
///     survived logout;
///   - there were TWO copies of the token in two storage layers, and a normal
///     logout cleared only one. The copy the HTTP client actually read survived,
///     so a signed-out user's requests kept carrying a valid bearer token;
///   - `isLoggedIn()` checked a boolean flag and a non-empty string. The token's
///     `exp` was never decoded, so an expired session read as signed in until
///     the first 401 ejected the user — possibly mid-checkout.
///
/// Every one of those is a test in `test/core/session_test.dart`. Read that file
/// alongside this one; the guarantees are meant to be provable, not promised.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../perf/perf_log.dart';

/// An authenticated session. There is exactly one field that is persisted —
/// the token — and it is never accompanied by a password.
class Session {
  final String token;

  /// Decoded from the JWT's `exp`. Null when the token carries no expiry.
  final DateTime? expiresAt;

  /// The JWT `sub`. Convenience only; the server remains the authority.
  final String? subject;

  const Session({required this.token, this.expiresAt, this.subject});

  bool isExpired({DateTime? now}) {
    final exp = expiresAt;
    if (exp == null) return false;
    return !exp.isAfter(now ?? DateTime.now().toUtc());
  }

  /// Expiring within [window] — used to avoid starting a checkout on a token
  /// that will die halfway through it.
  bool expiresWithin(Duration window, {DateTime? now}) {
    final exp = expiresAt;
    if (exp == null) return false;
    return exp.isBefore((now ?? DateTime.now().toUtc()).add(window));
  }

  /// Parse a JWT without verifying it. Verification is the server's job; this
  /// only reads the claims the client needs to behave sensibly.
  ///
  /// A token whose payload cannot be decoded still yields a Session — it is the
  /// server that decides whether a token is good. What this must never do is
  /// throw and take the app down at launch.
  static Session fromToken(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return Session(token: token);
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      ) as Map<String, dynamic>;

      final exp = payload['exp'];
      return Session(
        token: token,
        expiresAt: exp is num
            ? DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000, isUtc: true)
            : null,
        subject: payload['sub']?.toString(),
      );
    } catch (_) {
      return Session(token: token);
    }
  }
}

/// The ONE place a session is persisted.
///
/// Keychain on iOS; AES-GCM under a KeyStore-held key on Android. There is no
/// second layer and no `SharedPreferences` fallback: the old app's two-layer
/// split is precisely what let a logged-out user keep a live token.
class SessionStore {
  static const _tokenKey = 'session.token';

  final FlutterSecureStorage _storage;

  SessionStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              // v11 encrypts by default (AES-GCM with a KeyStore-held key), so
              // there is no opt-in flag to forget. On iOS the item is pinned to
              // this device and unavailable before first unlock, which keeps it
              // out of iCloud backups — the old app's token sat in a plist that
              // backups DID include.
              aOptions: AndroidOptions(),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  Future<Session?> read() async {
    final token = await _storage.read(key: _tokenKey);
    if (token == null || token.isEmpty) return null;
    return Session.fromToken(token);
  }

  Future<void> write(Session session) =>
      _storage.write(key: _tokenKey, value: session.token);

  /// Removes everything this socle stores. One key, one call — there is nothing
  /// else to forget, which is the point.
  Future<void> clear() => _storage.delete(key: _tokenKey);
}

final sessionStoreProvider = Provider<SessionStore>((ref) => SessionStore());

/// The session, as the rest of the app sees it.
///
/// `null` means signed out. An EXPIRED token also resolves to null: an expired
/// session is a signed-out session, decided here rather than discovered when a
/// request comes back 401.
class SessionController extends AsyncNotifier<Session?> {
  @override
  Future<Session?> build() async {
    final stored = await perfTime('session.restore (secure storage)', ref.read(sessionStoreProvider).read);
    if (stored == null) return null;
    if (stored.isExpired()) {
      // Do not keep a token we already know is dead.
      await ref.read(sessionStoreProvider).clear();
      return null;
    }
    return stored;
  }

  /// Called on a successful authentication.
  ///
  /// ⚠️ Takes a token and nothing else, deliberately. There is no overload that
  /// accepts a password, because no call site should be able to persist one.
  Future<void> signIn(String token) async {
    final session = Session.fromToken(token);
    await ref.read(sessionStoreProvider).write(session);
    state = AsyncValue<Session?>.data(session);
  }

  /// Clears local state. There is no server-side logout endpoint in this API,
  /// so the token remains valid until it expires — which is a reason to keep
  /// lifetimes short, and a backend request, not something the client can fix.
  Future<void> signOut() async {
    await ref.read(sessionStoreProvider).clear();
    state = const AsyncValue<Session?>.data(null);
  }

  /// The interceptor calls this on a 401. Same effect as signing out, named
  /// separately so telemetry can tell the two apart.
  Future<void> onUnauthorized() => signOut();
}

final sessionProvider =
    AsyncNotifierProvider<SessionController, Session?>(SessionController.new);

/// The bearer token for the network layer, or null.
///
/// Reads through the session rather than the store, so an expired token is
/// never attached to a request.
final bearerTokenProvider = Provider<String?>((ref) {
  final session = ref.watch(sessionProvider).value;
  if (session == null || session.isExpired()) return null;
  return session.token;
});

final isSignedInProvider = Provider<bool>((ref) => ref.watch(bearerTokenProvider) != null);
