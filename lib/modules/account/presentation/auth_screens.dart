/// Welcome, sign-in, registration, verification and password reset.
///
/// Layout follows the Sabily-branded Figma frames — `Welcome` (63:533),
/// `Log In` (52:519), `Sign Up` (52:369), `Verification` (63:157) and
/// `Forgot Password` (63:427) — with every colour resolved through the brand
/// tokens rather than the literals those frames carry. Where the frames
/// disagree with each other, `lib/core/ui/` holds the single resolution and
/// this file does not restate it.
///
/// Google and Apple are built, as of 23/09/2026 — see [SocialSignInButtons].
/// They were withheld until then, and the reason is worth keeping: the old
/// app's buttons called `/api/google-auth`, `/apple-auth`, `/google-register`
/// and `/apple-register`, which return ZERO occurrences across the deployed
/// backend's 891 classes (`ANALYSE-EXISTANT.md` §7.7). Backend request B6 was
/// answered with new routes — `POST /v1/auth/google` and `/v1/auth/apple` —
/// and those are what the app calls. The legacy four still respond and are
/// still not used.
///
/// Also not built: the three-step wizard `Sign Up` (52:369) actually draws.
/// See [RegisterScreen].
library;

import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/brand/brand_config.dart';
import '../../../core/brand/brand_providers.dart';
import '../../../core/i18n/country_names.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/session/session.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_button.dart';
import '../../../core/ui/app_card.dart';
import '../../../core/ui/app_text_field.dart';
import '../domain/account.dart';
import 'account_controllers.dart';

/// The brand mark in its glass badge over a gradient, then one way in.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  @override
  void initState() {
    super.initState();
    _clearStaleFailure(ref);
  }

  @override
  Widget build(BuildContext context) {
    // Only the logo matters here. A bare watch rebuilds the whole welcome
    // screen when any field of the config changes — including the remote
    // swap after first frame.
    final logo = ref.watch(brandConfigProvider.select((b) => b.logo.mark));
    final assetPath = ref.watch(brandConfigProvider.select((b) => b.assetPath));
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);
    final state = ref.watch(authControllerProvider);

    _enterAppOnSession(context, ref);

    return Scaffold(
      body: AppScreenGradient(
        child: Column(
          children: [
            Expanded(
              child: SafeArea(
                bottom: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(Gap.xl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppLogoBadge(
                          child: Image.asset(
                            assetPath(logo),
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) =>
                                Icon(Icons.sim_card, size: 72, color: t.primary),
                          ),
                        ),
                        const SizedBox(height: Gap.xxl),
                        Text(
                          l10n.t('startup.welcome'),
                          style: AppType.hero.copyWith(color: t.primary),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: Gap.sm),
                        Text(
                          l10n.t('startup.subtitle'),
                          style: AppType.body.copyWith(color: t.inkMuted),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            AppBottomSheetCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.t('account.welcomeTitle'),
                    style: AppType.hero.copyWith(color: t.onPrimary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: Gap.xxl),
                  AppButton(
                    label: l10n.t('account.continueWithEmail'),
                    icon: Icons.mail_outline,
                    tone: AppButtonTone.onDark,
                    onPressed: () => context.pushNamed('signIn'),
                  ),
                  const SocialSignInButtons(),
                  AuthError(state: state),
                  const SizedBox(height: Gap.sm),
                  AppLinkButton(
                    label: l10n.t('account.noAccount'),
                    onDark: true,
                    onPressed: () => context.pushNamed('register'),
                  ),
                  const SizedBox(height: Gap.sm),
                  Text(
                    l10n.t('account.legalNotice'),
                    style: AppType.label.copyWith(color: t.onPrimaryMuted),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The transactional screen shell: gradient ground, a back control, and one
/// glowing card. Shared by sign-in, verification and reset.
class _AuthScaffold extends ConsumerWidget {
  final String titleKey;
  final String subtitleKey;
  final List<Widget> children;

  const _AuthScaffold({required this.titleKey, required this.subtitleKey, required this.children});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);

    return Scaffold(
      body: AppScreenGradient(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(padding: EdgeInsets.all(Gap.lg), child: AppBackButton()),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.xxl),
                  children: [
                    AppCard(
                      glow: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            l10n.t(titleKey),
                            style: AppType.hero.copyWith(color: t.primary),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: Gap.sm),
                          Text(
                            l10n.t(subtitleKey),
                            style: AppType.body.copyWith(color: t.inkMuted),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: Gap.xxl),
                          ...children,
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A 40px round chip around the back arrow, as the header frames draw it.
///
/// Flips with the text direction on its own — `Icons.arrow_back` is
/// direction-aware, which is why the Arabic build already showed it on the
/// right.
class AppBackButton extends StatelessWidget {
  /// Overrides "pop the route". The wizard walks back a step instead, so a
  /// user one field from the end does not lose the whole form to a reflex.
  final VoidCallback? onTap;

  const AppBackButton({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    // Navigator rather than go_router: this is a plain visual control, and
    // asking the router whether it can pop makes it unmountable anywhere a
    // router is not in scope — a widget test, a preview, a sheet.
    if (onTap == null && !Navigator.of(context).canPop()) {
      return const SizedBox(height: 40, width: 40);
    }
    // Figma draws the chip cream on a cream header, which disappears entirely
    // once the ground is the accent end of the gradient. White with the same
    // soft lift every other control carries reads as a control at both ends.
    // Aligned here rather than at each call site: dropped straight into a
    // ListView it gets full-width constraints and centres itself, which is
    // exactly what happened on the registration screen.
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: DecoratedBox(
        decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: Shadows.field),
        child: Material(
          color: t.card,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap ?? () => Navigator.of(context).maybePop(),
            child: SizedBox(
              height: 40,
              width: 40,
              child: Icon(Icons.arrow_back, size: 18, color: t.primary),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows a typed failure, translated at the edge.
class AuthError extends ConsumerWidget {
  final AuthState state;
  const AuthError({super.key, required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state is! AuthFailed) return const SizedBox.shrink();
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.lg),
      child: Container(
        padding: const EdgeInsets.all(Gap.md),
        decoration: BoxDecoration(
          color: t.danger.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(Radii.chip),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: t.danger, size: 18),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: Text(
                l10n.t((state as AuthFailed).messageKey),
                style: AppType.labelStrong.copyWith(color: t.danger),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The app is entered when a session comes into existence — the one thing
/// only a verified credential can cause — and never on a controller state.
///
/// Keyed to a state before: every auth flow shares one controller, and a
/// password-reset "done" was heard by Sign In, still mounted underneath, which
/// navigated to the Store with nobody signed in.
void _enterAppOnSession(BuildContext context, WidgetRef ref) {
  ref.listen<bool>(isSignedInProvider, (was, now) {
    if (now && was != true && context.mounted) context.goNamed('store');
  });
}

/// A failure belongs to the screen that produced it. Every auth screen shares
/// one controller, so without this a wrong password on Sign In followed the
/// user into the registration wizard and sat above all three steps (seen
/// against the live backend). Deferred a microtask: a provider cannot be
/// written while the widget tree is being built.
void _clearStaleFailure(WidgetRef ref) => Future.microtask(() {
      if (ref.read(authControllerProvider) is AuthFailed) {
        ref.read(authControllerProvider.notifier).reset();
      }
    });

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _form = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _clearStaleFailure(ref);
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(l10nProvider);
    final state = ref.watch(authControllerProvider);

    _enterAppOnSession(context, ref);

    return _AuthScaffold(
      titleKey: 'account.signInTitle',
      subtitleKey: 'account.signInSubtitle',
      children: [
        Form(
          key: _form,
          child: Column(
            children: [
              AuthError(state: state),
              AppTextField(
                label: l10n.t('account.field.email'),
                icon: Icons.mail_outline,
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                validator: (v) => validateTranslated(l10n, kFieldSpecs['email']!, v),
              ),
              const SizedBox(height: Gap.lg),
              AppTextField(
                label: l10n.t('account.field.password'),
                icon: Icons.lock_outline,
                controller: _password,
                obscure: true,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                labelTrailing: AppLinkButton(
                  label: l10n.t('account.forgotPassword'),
                  onPressed: () => context.pushNamed('forgotPassword'),
                ),
                // Signing in must not reject a password that predates the
                // current rules — only registration enforces their shape.
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? l10n.t('account.error.required') : null,
              ),
              const SizedBox(height: Gap.xl),
              AppButton(
                label: l10n.t('account.signIn'),
                busy: state is AuthBusy,
                onPressed: () {
                  if (_form.currentState?.validate() != true) return;
                  ref.read(authControllerProvider.notifier).signIn(_email.text, _password.text);
                },
              ),
              const SizedBox(height: Gap.sm),
              AppInlineLink(
                prompt: l10n.t('account.noAccountPrompt'),
                action: l10n.t('account.createAccount'),
                onPressed: () => context.pushNamed('register'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// "Continue with Google" / "Continue with Apple", on the welcome screen under
/// the "Continue with email" button.
///
/// Each is offered only where it can actually work:
///
///  - **Google** needs the brand's `mobile.googleServerClientId`. Without it
///    the SDK cannot mint an ID token on Android at all, so the button would
///    be a guaranteed dead end;
///  - **Apple** is iOS-only here. `defaultTargetPlatform`, not `Platform`,
///    because a module may not import `dart:io` (rule L4) — and this is the
///    right check anyway.
///
/// Both end in the same session as the email form; see [AuthController].
class SocialSignInButtons extends ConsumerWidget {
  const SocialSignInButtons({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final busy = ref.watch(authControllerProvider) is AuthBusy;
    final google = ref.watch(googleSignInOfferedProvider);
    final apple = defaultTargetPlatform == TargetPlatform.iOS;
    if (!google && !apple) return const SizedBox.shrink();

    return Column(
      children: [
        const SizedBox(height: Gap.md),
        if (google)
          AppButton(
            label: l10n.t('account.continueWithGoogle'),
            tone: AppButtonTone.social,
            icon: Icons.account_circle_outlined,
            onPressed:
                busy ? null : () => ref.read(authControllerProvider.notifier).signInWithGoogle(),
          ),
        if (google && apple) const SizedBox(height: Gap.sm),
        if (apple)
          AppButton(
            label: l10n.t('account.continueWithApple'),
            tone: AppButtonTone.social,
            icon: Icons.apple,
            onPressed:
                busy ? null : () => ref.read(authControllerProvider.notifier).signInWithApple(),
          ),
      ],
    );
  }
}

/// Validation lives in the controller; this only translates the key it returns.
String? validateTranslated(L10n l10n, FieldSpec spec, String? value) {
  final key = validateField(spec, value ?? '');
  return key == null ? null : l10n.t(key, vars: {'min': '$kPasswordMinLength'});
}

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _email = TextEditingController();
  final _form = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _clearStaleFailure(ref);
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(l10nProvider);
    final state = ref.watch(authControllerProvider);

    return _AuthScaffold(
      titleKey: 'account.resetTitle',
      subtitleKey: 'account.resetSubtitle',
      children: [
        Form(
          key: _form,
          child: Column(
            children: [
              AuthError(state: state),
              AppTextField(
                label: l10n.t('account.field.email'),
                icon: Icons.mail_outline,
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                validator: (v) => validateTranslated(l10n, kFieldSpecs['email']!, v),
              ),
              const SizedBox(height: Gap.xl),
              AppButton(
                label: l10n.t('account.sendResetCode'),
                busy: state is AuthBusy,
                onPressed: () async {
                  if (_form.currentState?.validate() != true) return;
                  final ok = await ref
                      .read(authControllerProvider.notifier)
                      .requestPasswordReset(_email.text);
                  // Replaced, not pushed: once the code is set, popping the
                  // code step lands on Sign In, where the new password is used.
                  if (ok && context.mounted) {
                    context.pushReplacementNamed(
                      'resetPassword',
                      queryParameters: {'email': _email.text.trim()},
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The second half of a password reset, as `sabily.fr/<lang>/reinitialiser-mot-de-passe`
/// draws it: the code from the email and the new password on one screen.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  final String email;
  const ResetPasswordScreen({super.key, required this.email});

  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _form = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _clearStaleFailure(ref);
  }

  @override
  void dispose() {
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);
    final state = ref.watch(authControllerProvider);

    ref.listen(authControllerProvider, (_, next) {
      if (next is AuthPasswordReset && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ref.read(l10nProvider).t('account.passwordUpdated'))),
        );
        // Back to Sign In (Forgot Password replaced itself with this screen).
        if (context.canPop()) {
          context.pop();
        } else {
          context.goNamed('signIn');
        }
      }
    });

    return _AuthScaffold(
      titleKey: 'account.resetTitle',
      subtitleKey: 'account.resetSent',
      children: [
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AuthError(state: state),
              AppTextField(
                label: l10n.t('account.field.resetCode'),
                controller: _code,
                autofocus: true,
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? l10n.t('account.error.required') : null,
              ),
              const SizedBox(height: Gap.lg),
              AppTextField(
                label: l10n.t('account.field.newPassword'),
                icon: Icons.lock_outline,
                controller: _password,
                obscure: true,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.newPassword],
                validator: (v) => validateTranslated(l10n, kFieldSpecs['password']!, v),
              ),
              const SizedBox(height: Gap.sm),
              Text(
                l10n.t('account.passwordHint'),
                style: AppType.caption.copyWith(color: t.inkMuted),
              ),
              const SizedBox(height: Gap.xl),
              AppButton(
                label: l10n.t('account.resetSubmit'),
                busy: state is AuthBusy,
                onPressed: () {
                  if (_form.currentState?.validate() != true) return;
                  ref
                      .read(authControllerProvider.notifier)
                      .finishPasswordReset(code: _code.text, newPassword: _password.text);
                },
              ),
              const SizedBox(height: Gap.sm),
              Center(
                child: AppLinkButton(
                  label: l10n.t('account.resendResetCode'),
                  onPressed: () async {
                    final ok = await ref
                        .read(authControllerProvider.notifier)
                        .requestPasswordReset(widget.email);
                    if (ok && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.t('account.resetCodeSent'))),
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class VerifyScreen extends ConsumerStatefulWidget {
  final String email;
  const VerifyScreen({super.key, required this.email});

  @override
  ConsumerState<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends ConsumerState<VerifyScreen> {
  final _code = TextEditingController();

  @override
  void initState() {
    super.initState();
    _clearStaleFailure(ref);
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);
    final state = ref.watch(authControllerProvider);

    _enterAppOnSession(context, ref);
    ref.listen(authControllerProvider, (_, next) {
      // Active, but no token: the user signs in with the password they chose.
      if (next is AuthActivated && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ref.read(l10nProvider).t('account.activated'))),
        );
        context.goNamed('signIn');
      }
    });

    return _AuthScaffold(
      titleKey: 'account.verifyTitle',
      subtitleKey: 'account.verifySubtitle',
      children: [
        AuthError(state: state),
        Text(
          widget.email,
          style: AppType.bodyStrong.copyWith(color: t.primary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: Gap.xl),
        AppTextField(
          label: l10n.t('account.field.code'),
          controller: _code,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          autofocus: true,
        ),
        const SizedBox(height: Gap.xl),
        AppButton(
          label: l10n.t('account.verify'),
          busy: state is AuthBusy,
          onPressed: () => ref
              .read(authControllerProvider.notifier)
              .verify(email: widget.email, code: _code.text),
        ),
        const SizedBox(height: Gap.sm),
        Center(
          child: AppLinkButton(
            label: l10n.t('account.resendCode'),
            onPressed: () => ref.read(authControllerProvider.notifier).resendCode(widget.email),
          ),
        ),
      ],
    );
  }
}

/// Registration, as `Sign Up - Sabily (Mobile)` (52:369) draws it: a header
/// carrying the back control and a three-dot progress indicator, then one
/// step's worth of fields, then a button naming the step it leads to.
///
/// The split is CONFIGURATION, not layout. `registration.steps` groups fields
/// that `registration.fields` already declared; a brand that omits it gets one
/// page with everything on it, which is what every config did before steps
/// existed. Nothing here decides what is required — the deployed
/// `SubscriberModel` does, and it does not care how many screens the user
/// crossed to fill the form in.
///
/// ⚠️ Only STEP ONE exists in Figma. The file has no step-two or step-three
/// frame — `Sign Up - Sabily (Mobile)` is step one, and the only evidence for
/// what follows is its own button copy, "Continue to Security". Steps two and
/// three in `brands/sabily/brand.json` are therefore a reading of that one
/// signal, and they live in config precisely so correcting them is a config
/// push rather than a release.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  /// One key per page. Only the current page is mounted, so only its fields
  /// are validated — which is the point: "Continue to Security" checks the
  /// four fields above it, not the eleven the server will eventually want.
  final Map<int, GlobalKey<FormState>> _forms = {};
  final Map<String, TextEditingController> _controllers = {};

  int _step = 0;

  /// Fields the design sets side by side when the config places them together.
  /// Figma pairs the two name fields and nothing else, so neither does this.
  static const Set<String> _paired = {'firstName', 'lastName'};

  @override
  void initState() {
    super.initState();
    _clearStaleFailure(ref);
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(String id) =>
      _controllers.putIfAbsent(id, TextEditingController.new);

  GlobalKey<FormState> _formFor(int step) =>
      _forms.putIfAbsent(step, GlobalKey<FormState>.new);

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);
    final pages = ref.watch(registrationStepsProvider);
    // Only the busy/failed flag matters to this screen's chrome, so only that
    // is watched. Watching the whole state rebuilt the entire form — every
    // field, every controller — on each transition.
    final state = ref.watch(authControllerProvider);

    ref.listen(authControllerProvider, (_, next) {
      if (next is AuthAwaitingCode && context.mounted) {
        context.pushNamed('verify', queryParameters: {'email': next.email});
      }
    });

    final page = pages[_step.clamp(0, pages.length - 1)];
    final last = _step >= pages.length - 1;
    final multi = pages.length > 1;

    return Scaffold(
      body: AppScreenGradient(
        child: SafeArea(
          child: Column(
            children: [
              _Header(
                steps: pages.length,
                current: _step,
                onBack: _back,
              ),
              Expanded(
                child: Form(
                  key: _formFor(_step),
                  child: ListView(
                    // A new key per step so the scroll position resets and the
                    // previous page's fields are torn down rather than reused
                    // with different specs.
                    key: ValueKey(_step),
                    padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, Gap.xxl),
                    children: [
                      Text(
                        l10n.t(multi ? page.titleKey : 'account.registerTitle'),
                        style: AppType.hero.copyWith(color: t.primary),
                      ),
                      const SizedBox(height: Gap.sm),
                      Text(
                        multi
                            ? l10n.t('account.stepOf', vars: {
                                'current': '${_step + 1}',
                                'total': '${pages.length}',
                              })
                            : l10n.t('account.registerSubtitle'),
                        style: AppType.body.copyWith(color: t.inkMuted),
                      ),
                      const SizedBox(height: Gap.xxl),
                      AuthError(state: state),
                      ..._rows(page.fields),
                      const SizedBox(height: Gap.lg),
                      AppButton(
                        label: last
                            ? l10n.t('account.createAccount')
                            : l10n.t('account.continueTo',
                                vars: {'step': l10n.t(pages[_step + 1].titleKey)}),
                        trailingIcon: last ? null : Icons.arrow_forward,
                        busy: state is AuthBusy,
                        onPressed: last ? _submit : _next,
                      ),
                      if (last) ...[
                        const SizedBox(height: Gap.lg),
                        Text(
                          l10n.t('account.legalNotice'),
                          style: AppType.label.copyWith(color: t.inkMuted),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: Gap.sm),
                      AppInlineLink(
                        prompt: l10n.t('account.haveAccountPrompt'),
                        action: l10n.t('account.signIn'),
                        onPressed: () => context.pop(),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Lays a page's fields out, pairing the two name fields into one row when
  /// the config happens to place them next to each other.
  List<Widget> _rows(List<FieldSpec> fields) {
    final out = <Widget>[];
    for (var i = 0; i < fields.length; i++) {
      final spec = fields[i];
      final next = i + 1 < fields.length ? fields[i + 1] : null;

      if (next != null && _paired.contains(spec.id) && _paired.contains(next.id)) {
        out
          ..add(Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _field(spec)),
              const SizedBox(width: Gap.lg),
              Expanded(child: _field(next)),
            ],
          ))
          ..add(const SizedBox(height: Gap.lg));
        i++;
        continue;
      }
      out
        ..add(_field(spec))
        ..add(const SizedBox(height: Gap.lg));
    }
    return out;
  }

  Widget _field(FieldSpec spec) => switch (spec.kind) {
        FieldKind.date => _DateField(spec: spec),
        FieldKind.country => _CountryField(spec: spec),
        _ => _RegisterTextField(spec: spec, controller: _controllerFor(spec.id)),
      };

  /// Back leaves the screen only from the first step; otherwise it walks back
  /// through the form. A user one field from the end should not lose the lot
  /// to a reflex swipe.
  void _back() {
    if (_step == 0) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() => _step--);
  }

  void _next() {
    if (_formFor(_step).currentState?.validate() != true) return;
    setState(() => _step++);
  }

  void _submit() {
    if (_formFor(_step).currentState?.validate() != true) return;
    ref.read(authControllerProvider.notifier).register(ref.read(registrationDraftProvider));
  }
}

/// The 64px header from 52:370: back control, progress indicator, and a
/// matching spacer so the dots sit centred rather than pushed off by the
/// button's width.
class _Header extends ConsumerWidget {
  final int steps;
  final int current;
  final VoidCallback onBack;

  const _Header({required this.steps, required this.current, required this.onBack});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    return SizedBox(
      height: 64,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            AppBackButton(onTap: onBack),
            if (steps > 1)
              AppStepDots(
                count: steps,
                current: current,
                semanticLabel: l10n.t('account.stepOf', vars: {
                  'current': '${current + 1}',
                  'total': '$steps',
                }),
              ),
            const SizedBox(width: 40),
          ],
        ),
      ),
    );
  }
}

class _RegisterTextField extends ConsumerWidget {
  final FieldSpec spec;
  final TextEditingController controller;

  const _RegisterTextField({required this.spec, required this.controller});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);

    return AppTextField(
      label: l10n.t(spec.labelKey),
      note: spec.optional ? l10n.t('account.optional') : null,
      icon: switch (spec.kind) {
        FieldKind.email => Icons.mail_outline,
        FieldKind.password => Icons.lock_outline,
        FieldKind.phone => Icons.phone_outlined,
        _ => null,
      },
      controller: controller,
      obscure: spec.kind == FieldKind.password,
      keyboardType: switch (spec.kind) {
        FieldKind.email => TextInputType.emailAddress,
        FieldKind.phone => TextInputType.phone,
        _ => TextInputType.text,
      },
      autofillHints: switch (spec.kind) {
        FieldKind.email => const [AutofillHints.email],
        FieldKind.password => const [AutofillHints.newPassword],
        FieldKind.phone => const [AutofillHints.telephoneNumber],
        _ => null,
      },
      onChanged: (v) => ref.read(registrationDraftProvider.notifier).set(spec.id, v),
      validator: (v) => validateTranslated(l10n, spec, v),
    );
  }
}

class _DateField extends ConsumerWidget {
  final FieldSpec spec;
  const _DateField({required this.spec});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);

    return AppPickerField<DateTime>(
      label: l10n.t(spec.labelKey),
      placeholder: l10n.t('account.choose'),
      trailingIcon: Icons.calendar_today_outlined,
      value: ref.watch(registrationDraftProvider).dateOfBirth,
      format: RegistrationDraft.formatDate,
      onChanged: ref.read(registrationDraftProvider.notifier).setDate,
      validator: (v) => v == null ? l10n.t('account.error.required') : null,
      onPick: () {
        final now = DateTime.now();
        return showDatePicker(
          context: context,
          initialDate: ref.read(registrationDraftProvider).dateOfBirth ?? DateTime(now.year - 25),
          firstDate: DateTime(now.year - 120),
          lastDate: now,
        );
      },
    );
  }
}

class _CountryField extends ConsumerWidget {
  final FieldSpec spec;
  const _CountryField({required this.spec});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);

    return AppPickerField<CountryRef>(
      label: l10n.t(spec.labelKey),
      placeholder: l10n.t('account.choose'),
      value: ref.watch(registrationDraftProvider).country,
      format: (c) => countryName(c.code, l10n.language, fallback: c.name),
      onChanged: ref.read(registrationDraftProvider.notifier).setCountry,
      validator: (v) => v == null ? l10n.t('account.error.required') : null,
      // A searchable sheet, not a dropdown menu: the live list is every country
      // the platform sells in, and a Material menu makes the user scroll two
      // hundred rows with no way to type.
      onPick: () => showModalBottomSheet<CountryRef>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppTokens.of(context).card,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.control)),
        ),
        builder: (_) => const _CountrySheet(),
      ),
    );
  }
}

class _CountrySheet extends ConsumerStatefulWidget {
  const _CountrySheet();

  @override
  ConsumerState<_CountrySheet> createState() => _CountrySheetState();
}

class _CountrySheetState extends ConsumerState<_CountrySheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);
    final countries = ref.watch(countriesProvider);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      builder: (_, scrollController) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(Gap.lg),
              child: AppTextField(
                label: l10n.t('account.searchCountry'),
                icon: Icons.search,
                autofocus: true,
                onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              ),
            ),
            Expanded(
              child: countries.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => Center(
                  child: Text(
                    l10n.t('error.network_unavailable'),
                    style: AppType.body.copyWith(color: t.inkMuted),
                  ),
                ),
                data: (list) {
                  // Shown, ordered and searched in the interface language; the
                  // backend's English name still matches a search.
                  String label(CountryRef c) => countryName(c.code, l10n.language, fallback: c.name);
                  final shown = [
                    for (final c in list)
                      if (_query.isEmpty ||
                          label(c).toLowerCase().contains(_query) ||
                          c.name.toLowerCase().contains(_query))
                        c,
                  ]..sort((a, b) => compareCountryNames(label(a), label(b)));
                  return ListView.builder(
                    controller: scrollController,
                    itemCount: shown.length,
                    itemBuilder: (_, i) => ListTile(
                      title: Text(label(shown[i]), style: AppType.body.copyWith(color: t.ink)),
                      onTap: () => Navigator.of(context).pop(shown[i]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
