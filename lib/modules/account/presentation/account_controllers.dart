/// Widget -> controller -> repository. No widget touches a repository.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/brand/brand_config.dart';
import '../../../core/brand/brand_providers.dart';
import '../../../core/network/network_providers.dart';
import '../../../core/result/result.dart';
import '../../../core/session/session.dart';
import '../data/account_repository_impl.dart';
import '../domain/account.dart';

final accountRepositoryProvider = Provider<AccountRepository>(
  (ref) => AccountRepositoryImpl(ref.watch(apiClientProvider)),
);

final countriesProvider =
    FutureProvider<List<CountryRef>>((ref) => ref.watch(accountRepositoryProvider).countries());

/// Scoped to the session, not to the app.
///
/// Watching the token is what makes that true: without it this resolves once
/// and keeps serving the first user who signed in on this device — their name
/// and their email address — to whoever signs in next.
final profileProvider = FutureProvider<Profile>((ref) {
  ref.watch(bearerTokenProvider);
  return ref.watch(accountRepositoryProvider).profile();
});

/// How the socle renders one configured registration field.
///
/// ARCHITECTURE-MOBILE.md §2.9: the config chooses WHICH of a closed set to show
/// and in what order; the socle owns the label, the widget and the validation
/// for each. That boundary is what keeps `registration.fields` a list rather
/// than a form-builder language.
enum FieldKind { text, email, password, phone, postal, date, country }

class FieldSpec {
  final String id;
  final String labelKey;
  final FieldKind kind;

  /// Server-side optional. Only `phoneNum` is, among the visible fields.
  final bool optional;

  const FieldSpec(this.id, this.labelKey, this.kind, {this.optional = false});
}

const Map<String, FieldSpec> kFieldSpecs = <String, FieldSpec>{
  'email': FieldSpec('email', 'account.field.email', FieldKind.email),
  'password': FieldSpec('password', 'account.field.password', FieldKind.password),
  'firstName': FieldSpec('firstName', 'account.field.firstName', FieldKind.text),
  'lastName': FieldSpec('lastName', 'account.field.lastName', FieldKind.text),
  'dateOfBirth': FieldSpec('dateOfBirth', 'account.field.dateOfBirth', FieldKind.date),
  'address': FieldSpec('address', 'account.field.address', FieldKind.text),
  'zipCode': FieldSpec('zipCode', 'account.field.zipCode', FieldKind.postal),
  'city': FieldSpec('city', 'account.field.city', FieldKind.text),
  'country': FieldSpec('country', 'account.field.country', FieldKind.country),
  'phoneNum': FieldSpec('phoneNum', 'account.field.phoneNum', FieldKind.phone, optional: true),
};

/// The fields this brand shows, in its configured order.
///
/// `.select` rather than a bare watch: this rebuilds when the FIELD LIST
/// changes, which in practice is never after startup. Watching the whole
/// config would rebuild every form on any config change at all.
final registrationFieldsProvider = Provider<List<FieldSpec>>((ref) {
  final ids = ref.watch(brandConfigProvider.select((b) => b.mobile.registrationFields));
  return ids.map((id) => kFieldSpecs[id]).whereType<FieldSpec>().toList();
});

/// The pages the form is split into, each already resolved to specs.
///
/// A brand that declares no steps gets ONE page holding every field — which is
/// exactly the single-form behaviour every config had before steps existed, so
/// the screen has one code path rather than two.
final registrationStepsProvider = Provider<List<RegistrationPage>>((ref) {
  final specs = ref.watch(registrationFieldsProvider);
  final steps = ref.watch(brandConfigProvider.select((b) => b.mobile.registrationSteps));
  if (steps.isEmpty) {
    return [RegistrationPage(titleKey: 'account.registerTitle', fields: specs)];
  }
  final byId = {for (final s in specs) s.id: s};
  return [
    for (final step in steps)
      RegistrationPage(
        titleKey: step.titleKey,
        fields: step.fields.map((id) => byId[id]).whereType<FieldSpec>().toList(),
      ),
  ];
});

/// One page of the wizard.
class RegistrationPage {
  final String titleKey;
  final List<FieldSpec> fields;

  const RegistrationPage({required this.titleKey, required this.fields});
}

/// Validation mirrored from the deployed `SubscriberModel`, so a user is told
/// before a round trip rather than after one. The server stays the authority.
String? validateField(FieldSpec spec, String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return spec.optional ? null : 'account.error.required';

  switch (spec.kind) {
    case FieldKind.email:
      final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(trimmed);
      return ok ? null : 'account.error.email';
    case FieldKind.password:
      if (trimmed.length < kPasswordMinLength) return 'account.error.passwordShort';
      if (!kPasswordPattern.hasMatch(trimmed)) return 'account.error.passwordWeak';
      return null;
    default:
      return null;
  }
}

/// Sign-in, registration and verification share one shape.
sealed class AuthState {
  const AuthState();
}

final class AuthIdle extends AuthState {
  const AuthIdle();
}

final class AuthBusy extends AuthState {
  const AuthBusy();
}

final class AuthFailed extends AuthState {
  /// A dictionary key, never a server string.
  final String messageKey;
  const AuthFailed(this.messageKey);
}

/// Registration succeeded; the server has emailed a code.
final class AuthAwaitingCode extends AuthState {
  final String email;
  const AuthAwaitingCode(this.email);
}

/// A session now exists. Emitted only after the token is stored.
final class AuthDone extends AuthState {
  const AuthDone();
}

/// The account is active but the server issued no token, so nobody is signed
/// in yet. The live backend's activation always ends here.
final class AuthActivated extends AuthState {
  const AuthActivated();
}

/// A new password is set. Nobody is signed in: the user signs in with it.
final class AuthPasswordReset extends AuthState {
  const AuthPasswordReset();
}

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthIdle();

  Future<void> signIn(String email, String password) async {
    state = const AuthBusy();
    try {
      final token = await ref.read(accountRepositoryProvider).signIn(
            email: email.trim(),
            password: password,
          );
      // The token goes straight to secure storage. The password is not kept,
      // not cached and not passed on — see core/session.
      await ref.read(sessionProvider.notifier).signIn(token);
      state = const AuthDone();
    } on AccountFailure catch (e) {
      state = AuthFailed(
        e.isBadCredentials ? 'account.error.badCredentials' : 'error.${e.error.code}',
      );
    }
  }

  Future<void> register(RegistrationDraft draft) async {
    state = const AuthBusy();
    try {
      await ref.read(accountRepositoryProvider).register(
            draft,
            language: ref.read(languageProvider),
          );
      state = AuthAwaitingCode(draft.email.trim());
    } on AccountFailure catch (e) {
      state = AuthFailed(
        e.isDuplicateAccount ? 'account.error.emailTaken' : 'error.${e.error.code}',
      );
    }
  }

  Future<void> verify({required String email, required String code}) async {
    state = const AuthBusy();
    try {
      final token = await ref.read(accountRepositoryProvider).verify(
            email: email,
            code: code.trim(),
          );
      if (token == null) {
        state = const AuthActivated();
        return;
      }
      await ref.read(sessionProvider.notifier).signIn(token);
      state = const AuthDone();
    } on AccountFailure catch (e) {
      state = AuthFailed(
        e.error is HttpFailure ? 'account.error.badCode' : 'error.${e.error.code}',
      );
    }
  }

  Future<void> resendCode(String email) async {
    try {
      await ref.read(accountRepositoryProvider).resendCode(email);
    } on AccountFailure {
      // Resend is best-effort: a failure here must not replace the screen the
      // user is working in with an error state.
    }
  }

  Future<bool> requestPasswordReset(String email) async {
    state = const AuthBusy();
    try {
      await ref.read(accountRepositoryProvider).requestPasswordReset(email.trim());
      // Idle, not Done: a reset code signs nobody in. AuthDone here is what
      // sent the user into the app from Forgot Password — Sign In, still
      // mounted underneath, heard "done" and navigated to the Store.
      state = const AuthIdle();
      return true;
    } on AccountFailure catch (e) {
      state = AuthFailed('error.${e.error.code}');
      return false;
    }
  }

  Future<bool> finishPasswordReset({required String code, required String newPassword}) async {
    state = const AuthBusy();
    try {
      await ref.read(accountRepositoryProvider).finishPasswordReset(
            code: code.trim(),
            newPassword: newPassword,
          );
      state = const AuthPasswordReset();
      return true;
    } on AccountFailure catch (e) {
      state = AuthFailed(
        e.isPasswordRejected
            ? 'account.error.passwordWeak'
            : e.isUnknownResetCode
                ? 'account.error.badCode'
                : 'error.${e.error.code}',
      );
      return false;
    }
  }

  void reset() => state = const AuthIdle();
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);

/// The draft being filled in. Held here so it survives a rebuild without the
/// screen owning the state.
class RegistrationDraftController extends Notifier<RegistrationDraft> {
  @override
  RegistrationDraft build() => const RegistrationDraft();

  void set(String fieldId, String value) {
    state = switch (fieldId) {
      'email' => state.copyWith(email: value),
      'password' => state.copyWith(password: value),
      'firstName' => state.copyWith(firstName: value),
      'lastName' => state.copyWith(lastName: value),
      'address' => state.copyWith(address: value),
      'zipCode' => state.copyWith(zipCode: value),
      'city' => state.copyWith(city: value),
      'phoneNum' => state.copyWith(phoneNum: value),
      _ => state,
    };
  }

  void setDate(DateTime value) => state = state.copyWith(dateOfBirth: value);

  void setCountry(CountryRef value) => state = state.copyWith(country: value);
}

final registrationDraftProvider =
    NotifierProvider<RegistrationDraftController, RegistrationDraft>(
        RegistrationDraftController.new);

/// Signing out is a core concern the account module simply triggers.
Future<void> signOut(WidgetRef ref) => ref.read(sessionProvider.notifier).signOut();
