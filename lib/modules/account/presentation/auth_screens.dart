/// Welcome, sign-in, registration, verification and password reset.
///
/// Layout follows the Sabily-branded Figma frames — `Welcome` (63:533),
/// `Log In` (52:519), `Sign Up` (52:369), `Verification` (63:157) and
/// `Forgot Password` (63:427) — with every colour resolved through the brand
/// tokens rather than the literals those frames carry. Where the frames
/// disagree with each other, `lib/core/ui/` holds the single resolution and
/// this file does not restate it.
///
/// Not built, and not by omission: the Google and Apple buttons the old app
/// shipped. `/api/google-auth`, `/apple-auth`, `/google-register` and
/// `/apple-register` return ZERO occurrences across the deployed backend's 891
/// classes (`ANALYSE-EXISTANT.md` §7.7). Those buttons called routes that do
/// not exist. A button that cannot work is worse than an absent one, so they
/// return when the endpoints do — backend request B6.
///
/// Also not built: the three-step wizard `Sign Up` (52:369) actually draws.
/// See [RegisterScreen].
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/brand/brand_config.dart';
import '../../../core/brand/brand_providers.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_button.dart';
import '../../../core/ui/app_card.dart';
import '../../../core/ui/app_text_field.dart';
import '../domain/account.dart';
import 'account_controllers.dart';

/// The brand mark in its glass badge over a gradient, then one way in.
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = ref.watch(brandConfigProvider);
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);

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
                            brand.assetPath(brand.logo.mark),
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
  const AppBackButton({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    // Navigator rather than go_router: this is a plain visual control, and
    // asking the router whether it can pop makes it unmountable anywhere a
    // router is not in scope — a widget test, a preview, a sheet.
    if (!Navigator.of(context).canPop()) return const SizedBox(height: 40);
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
            onTap: () => Navigator.of(context).maybePop(),
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

    return _AuthScaffold(
      titleKey: 'account.resetTitle',
      subtitleKey: _sent ? 'account.resetSent' : 'account.resetSubtitle',
      children: [
        if (!_sent)
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
                  label: l10n.t('account.sendResetLink'),
                  busy: state is AuthBusy,
                  onPressed: () async {
                    if (_form.currentState?.validate() != true) return;
                    final ok = await ref
                        .read(authControllerProvider.notifier)
                        .requestPasswordReset(_email.text);
                    if (ok && mounted) setState(() => _sent = true);
                  },
                ),
              ],
            ),
          )
        else
          AppButton(label: l10n.t('common.close'), onPressed: () => context.pop()),
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

/// The registration form, built from `registration.fields`.
///
/// ⚠️ Figma draws this as a THREE-STEP WIZARD (52:369): a three-dot progress
/// indicator, four fields on step one, and a "Continue to Security" button.
/// This is one scrolling form over all ten configured fields instead.
///
/// That is a flagged divergence, not an oversight. How many fields exist, and
/// in what order, is decided by `registration.fields` against the deployed
/// `SubscriberModel` — so a wizard has to cut a list whose length is
/// configuration. Splitting it is a real improvement worth making; it needs the
/// step boundaries to come from `brand.json`, which is a change to the config
/// contract and therefore a decision rather than a refactor.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final Map<String, TextEditingController> _controllers = {};

  /// Fields the design sets side by side when the config places them together.
  /// Figma pairs the two name fields and nothing else, so neither does this.
  static const Set<String> _paired = {'firstName', 'lastName'};

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

    ref.listen(authControllerProvider, (_, next) {
      if (next is AuthAwaitingCode && context.mounted) {
        context.pushNamed('verify', queryParameters: {'email': next.email});
      }
    });

    return Scaffold(
      body: AppScreenGradient(
        child: SafeArea(
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, Gap.xxl),
              children: [
                const AppBackButton(),
                const SizedBox(height: Gap.xl),
                Text(
                  l10n.t('account.registerTitle'),
                  style: AppType.hero.copyWith(color: t.primary),
                ),
                const SizedBox(height: Gap.sm),
                Text(
                  l10n.t('account.registerSubtitle'),
                  style: AppType.body.copyWith(color: t.inkMuted),
                ),
                const SizedBox(height: Gap.xxl),
                AuthError(state: state),
                ..._rows(fields),
                const SizedBox(height: Gap.lg),
                AppButton(
                  label: l10n.t('account.createAccount'),
                  busy: state is AuthBusy,
                  onPressed: _submit,
                ),
                const SizedBox(height: Gap.lg),
                Text(
                  l10n.t('account.legalNotice'),
                  style: AppType.label.copyWith(color: t.inkMuted),
                  textAlign: TextAlign.center,
                ),
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
      ),
    );
  }

  /// Lays the configured fields out, pairing the two name fields into one row
  /// when the config happens to place them next to each other.
  List<Widget> _rows(List<FieldSpec> fields) {
    final out = <Widget>[];
    for (var i = 0; i < fields.length; i++) {
      final spec = fields[i];
      final next = i + 1 < fields.length ? fields[i + 1] : null;

      if (next != null && _paired.contains(spec.id) && _paired.contains(next.id)) {
        out
          ..add(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _field(spec)),
                const SizedBox(width: Gap.lg),
                Expanded(child: _field(next)),
              ],
            ),
          )
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

  void _submit() {
    // Date and country validate through their own FormFields now, so one call
    // covers every field. The previous version checked those two separately and
    // reported the failure in a snackbar, which never said which field.
    if (_form.currentState?.validate() != true) return;
    ref.read(authControllerProvider.notifier).register(ref.read(registrationDraftProvider));
  }
}

/// One configured text field. The socle owns the widget, the keyboard and the
/// validation; the brand config only chose that this field appears, and where.
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
      format: (c) => c.name,
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
                  final shown = _query.isEmpty
                      ? list
                      : list.where((c) => c.name.toLowerCase().contains(_query)).toList();
                  return ListView.builder(
                    controller: scrollController,
                    itemCount: shown.length,
                    itemBuilder: (_, i) => ListTile(
                      title: Text(shown[i].name, style: AppType.body.copyWith(color: t.ink)),
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
