/// Welcome, sign-in, registration, verification and password reset.
///
/// Layout follows the Sabily-branded Figma frames — `Welcome` (63:533),
/// `Log In` (52:519), `Sign Up` (52:369), `Verification` (63:157) and
/// `Forgot Password` (63:427) — with colours resolved through the brand tokens
/// rather than the literals those frames carry.
///
/// Not built, and not by omission: the Google and Apple buttons the old app
/// shipped. `/api/google-auth`, `/apple-auth`, `/google-register` and
/// `/apple-register` return ZERO occurrences across the deployed backend's 891
/// classes (`ANALYSE-EXISTANT.md` §7.7). Those buttons called routes that do
/// not exist. A button that cannot work is worse than an absent one, so they
/// return when the endpoints do — backend request B6.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/brand/brand_config.dart';
import '../../../core/brand/brand_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/account.dart';
import 'account_controllers.dart';


/// The brand mark over a short welcome, then one way in.
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = ref.watch(brandConfigProvider);
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);

    return Scaffold(
      backgroundColor: t.surface,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(Gap.xl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        brand.assetPath(brand.logo.mark),
                        height: 112,
                        width: 112,
                        errorBuilder: (_, _, _) =>
                            Icon(Icons.sim_card, size: 96, color: t.primary),
                      ),
                      const SizedBox(height: Gap.xl),
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
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(Gap.xl),
              decoration: BoxDecoration(
                color: t.primary,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(Radii.card),
                  topRight: Radius.circular(Radii.card),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.t('account.welcomeTitle'),
                    style: AppType.title.copyWith(color: t.onPrimary),
                  ),
                  const SizedBox(height: Gap.lg),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => context.pushNamed('signIn'),
                      icon: const Icon(Icons.mail_outline, size: 18),
                      label: Text(l10n.t('account.continueWithEmail')),
                    ),
                  ),
                  const SizedBox(height: Gap.md),
                  TextButton(
                    onPressed: () => context.pushNamed('register'),
                    child: Text(
                      l10n.t('account.noAccount'),
                      style: AppType.label.copyWith(color: t.onPrimary),
                    ),
                  ),
                  const SizedBox(height: Gap.sm),
                  Text(
                    l10n.t('account.legalNotice'),
                    style: AppType.caption.copyWith(color: t.onPrimary.withValues(alpha: 0.75)),
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

/// A card-on-surface form, shared by sign-in, verification and reset.
class _FormCard extends ConsumerWidget {
  final String titleKey;
  final String subtitleKey;
  final List<Widget> children;

  const _FormCard({
    required this.titleKey,
    required this.subtitleKey,
    required this.children,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);

    return Scaffold(
      backgroundColor: t.surface,
      appBar: AppBar(backgroundColor: t.surface),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Gap.lg),
          children: [
            Container(
              padding: const EdgeInsets.all(Gap.xl),
              decoration: BoxDecoration(
                color: t.card,
                borderRadius: BorderRadius.circular(Radii.card),
                border: Border.all(color: t.hairline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.t(titleKey),
                    style: AppType.title.copyWith(color: t.primary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: Gap.sm),
                  Text(
                    l10n.t(subtitleKey),
                    style: AppType.body.copyWith(color: t.inkMuted),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: Gap.xl),
                  ...children,
                ],
              ),
            ),
          ],
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
      padding: const EdgeInsets.only(bottom: Gap.md),
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
                style: AppType.label.copyWith(color: t.danger, letterSpacing: 0),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(l10nProvider);
    final state = ref.watch(authControllerProvider);

    ref.listen(authControllerProvider, (_, next) {
      if (next is AuthDone && context.mounted) context.goNamed('store');
    });

    return _FormCard(
      titleKey: 'account.signInTitle',
      subtitleKey: 'account.signInSubtitle',
      children: [
        Form(
          key: _form,
          child: Column(
            children: [
              AuthError(state: state),
              _Field(
                spec: kFieldSpecs['email']!,
                controller: _email,
                onChanged: (_) {},
              ),
              const SizedBox(height: Gap.lg),
              _Field(
                spec: kFieldSpecs['password']!,
                controller: _password,
                onChanged: (_) {},
                // Signing in must not reject a password that predates the
                // current rules — only registration enforces their shape.
                validateShape: false,
              ),
              const SizedBox(height: Gap.md),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: () => context.pushNamed('forgotPassword'),
                  child: Text(l10n.t('account.forgotPassword')),
                ),
              ),
              const SizedBox(height: Gap.sm),
              FilledButton(
                onPressed: state is AuthBusy
                    ? null
                    : () {
                        if (_form.currentState?.validate() != true) return;
                        ref
                            .read(authControllerProvider.notifier)
                            .signIn(_email.text, _password.text);
                      },
                child: state is AuthBusy
                    ? const SizedBox(
                        height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(l10n.t('account.signIn')),
              ),
              const SizedBox(height: Gap.md),
              TextButton(
                onPressed: () => context.pushNamed('register'),
                child: Text(l10n.t('account.noAccount')),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One configured field. The socle owns the widget and the validation; the
/// brand config only chose that this field appears, and where.
class _Field extends ConsumerWidget {
  final FieldSpec spec;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final bool validateShape;

  const _Field({
    required this.spec,
    required this.controller,
    required this.onChanged,
    this.validateShape = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);

    return TextFormField(
      controller: controller,
      onChanged: onChanged,
      obscureText: spec.kind == FieldKind.password,
      keyboardType: switch (spec.kind) {
        FieldKind.email => TextInputType.emailAddress,
        FieldKind.phone => TextInputType.phone,
        FieldKind.postal => TextInputType.text,
        _ => TextInputType.text,
      },
      autofillHints: switch (spec.kind) {
        FieldKind.email => const [AutofillHints.email],
        FieldKind.password => const [AutofillHints.password],
        FieldKind.phone => const [AutofillHints.telephoneNumber],
        _ => null,
      },
      style: AppType.body,
      decoration: InputDecoration(
        labelText: l10n.t(spec.labelKey) + (spec.optional ? ' · ${l10n.t('account.optional')}' : ''),
        labelStyle: AppType.label.copyWith(color: t.inkMuted),
        filled: true,
        fillColor: t.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.chip),
          borderSide: BorderSide(color: t.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.chip),
          borderSide: BorderSide(color: t.hairline),
        ),
      ),
      validator: (v) {
        final value = v ?? '';
        if (!validateShape) {
          return value.trim().isEmpty ? l10n.t('account.error.required') : null;
        }
        final key = validateField(spec, value);
        return key == null ? null : l10n.t(key, vars: {'min': '$kPasswordMinLength'});
      },
    );
  }
}

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _email = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _sent = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(l10nProvider);
    final state = ref.watch(authControllerProvider);

    return _FormCard(
      titleKey: 'account.resetTitle',
      subtitleKey: _sent ? 'account.resetSent' : 'account.resetSubtitle',
      children: [
        if (!_sent)
          Form(
            key: _form,
            child: Column(
              children: [
                AuthError(state: state),
                _Field(
                  spec: kFieldSpecs['email']!,
                  controller: _email,
                  onChanged: (_) {},
                ),
                const SizedBox(height: Gap.lg),
                FilledButton(
                  onPressed: state is AuthBusy
                      ? null
                      : () async {
                          if (_form.currentState?.validate() != true) return;
                          final ok = await ref
                              .read(authControllerProvider.notifier)
                              .requestPasswordReset(_email.text);
                          if (ok && mounted) setState(() => _sent = true);
                        },
                  child: Text(l10n.t('account.sendResetLink')),
                ),
              ],
            ),
          )
        else
          FilledButton(
            onPressed: () => context.pop(),
            child: Text(l10n.t('common.close')),
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
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);
    final state = ref.watch(authControllerProvider);

    ref.listen(authControllerProvider, (_, next) {
      if (next is AuthDone && context.mounted) context.goNamed('store');
    });

    return _FormCard(
      titleKey: 'account.verifyTitle',
      subtitleKey: 'account.verifySubtitle',
      children: [
        AuthError(state: state),
        Text(widget.email, style: AppType.bodyStrong.copyWith(color: t.primary)),
        const SizedBox(height: Gap.lg),
        TextField(
          controller: _code,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: AppType.title.copyWith(color: t.primary, letterSpacing: 8),
          decoration: InputDecoration(
            filled: true,
            fillColor: t.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Radii.chip),
              borderSide: BorderSide(color: t.hairline),
            ),
          ),
        ),
        const SizedBox(height: Gap.lg),
        FilledButton(
          onPressed: state is AuthBusy
              ? null
              : () => ref
                  .read(authControllerProvider.notifier)
                  .verify(email: widget.email, code: _code.text),
          child: Text(l10n.t('account.verify')),
        ),
        const SizedBox(height: Gap.sm),
        TextButton(
          onPressed: () =>
              ref.read(authControllerProvider.notifier).resendCode(widget.email),
          child: Text(l10n.t('account.resendCode')),
        ),
      ],
    );
  }
}

/// The registration form, built from `registration.fields`.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final Map<String, TextEditingController> _controllers = {};

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(String id) =>
      _controllers.putIfAbsent(id, TextEditingController.new);

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);
    final fields = ref.watch(registrationFieldsProvider);
    final state = ref.watch(authControllerProvider);
    final draft = ref.watch(registrationDraftProvider);

    ref.listen(authControllerProvider, (_, next) {
      if (next is AuthAwaitingCode && context.mounted) {
        context.pushNamed('verify', queryParameters: {'email': next.email});
      }
    });

    return Scaffold(
      backgroundColor: t.surface,
      appBar: AppBar(title: Text(l10n.t('account.registerTitle'))),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(Gap.lg),
            children: [
              Text(l10n.t('account.registerSubtitle'),
                  style: AppType.body.copyWith(color: t.inkMuted)),
              const SizedBox(height: Gap.lg),
              AuthError(state: state),
              for (final spec in fields) ...[
                switch (spec.kind) {
                  FieldKind.date => _DateField(spec: spec, value: draft.dateOfBirth),
                  FieldKind.country => _CountryField(spec: spec, value: draft.country),
                  _ => _Field(
                      spec: spec,
                      controller: _controllerFor(spec.id),
                      onChanged: (v) =>
                          ref.read(registrationDraftProvider.notifier).set(spec.id, v),
                    ),
                },
                const SizedBox(height: Gap.lg),
              ],
              const SizedBox(height: Gap.sm),
              FilledButton(
                onPressed: state is AuthBusy ? null : _submit,
                child: state is AuthBusy
                    ? const SizedBox(
                        height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(l10n.t('account.createAccount')),
              ),
              const SizedBox(height: Gap.md),
              Text(
                l10n.t('account.legalNotice'),
                style: AppType.caption,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _submit() {
    if (_form.currentState?.validate() != true) return;
    final draft = ref.read(registrationDraftProvider);
    final fields = ref.read(registrationFieldsProvider);

    // Date and country are not TextFormFields, so they validate here.
    final needsDate = fields.any((f) => f.kind == FieldKind.date);
    final needsCountry = fields.any((f) => f.kind == FieldKind.country);
    if ((needsDate && draft.dateOfBirth == null) || (needsCountry && draft.country == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ref.read(l10nProvider).t('account.error.required'))),
      );
      return;
    }
    ref.read(authControllerProvider.notifier).register(draft);
  }
}

class _DateField extends ConsumerWidget {
  final FieldSpec spec;
  final DateTime? value;

  const _DateField({required this.spec, required this.value});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);

    return InkWell(
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime(now.year - 25),
          firstDate: DateTime(now.year - 120),
          lastDate: now,
        );
        if (picked != null) {
          ref.read(registrationDraftProvider.notifier).setDate(picked);
        }
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: l10n.t(spec.labelKey),
          labelStyle: AppType.label.copyWith(color: t.inkMuted),
          filled: true,
          fillColor: t.card,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(Radii.chip),
            borderSide: BorderSide(color: t.hairline),
          ),
        ),
        child: Text(
          value == null ? l10n.t('account.choose') : RegistrationDraft.formatDate(value!),
          style: AppType.body.copyWith(color: value == null ? t.inkMuted : t.ink),
        ),
      ),
    );
  }
}

class _CountryField extends ConsumerWidget {
  final FieldSpec spec;
  final CountryRef? value;

  const _CountryField({required this.spec, required this.value});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);
    final countries = ref.watch(countriesProvider);

    return countries.when(
      loading: () => const LinearProgressIndicator(),
      error: (_, _) => Text(l10n.t('error.network_unavailable'),
          style: AppType.label.copyWith(color: t.danger)),
      data: (list) => DropdownButtonFormField<CountryRef>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: l10n.t(spec.labelKey),
          labelStyle: AppType.label.copyWith(color: t.inkMuted),
          filled: true,
          fillColor: t.card,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(Radii.chip),
            borderSide: BorderSide(color: t.hairline),
          ),
        ),
        items: [
          for (final c in list)
            DropdownMenuItem(value: c, child: Text(c.name, style: AppType.body)),
        ],
        onChanged: (c) {
          if (c != null) ref.read(registrationDraftProvider.notifier).setCountry(c);
        },
      ),
    );
  }
}
