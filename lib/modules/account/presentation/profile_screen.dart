import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/brand/brand_providers.dart';
import '../../../core/i18n/locales.dart';
import '../../../core/session/session.dart';
import '../../../core/theme/app_theme.dart';
import 'account_controllers.dart';

/// The Profile tab. Follows `Profile Settings - Sabily (Mobile)` (52:801).
///
/// It is also where the language picker lives, which is where it belongs: the
/// old app gave language its own bottom-tab, and the redesign folds it into
/// Profile.
///
/// Legal texts open the brand's URLs in a browser rather than a bundled PDF.
/// The old app shipped ONE set of PDFs for every client
/// (`ANALYSE-EXISTANT.md` §4.7), so a legal update meant a store submission and
/// every brand got the same document.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);
    final signedIn = ref.watch(isSignedInProvider);

    return Scaffold(
      backgroundColor: t.surface,
      appBar: AppBar(title: Text(l10n.t('nav.profile'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Gap.lg),
          children: [
            if (signedIn) const _Identity() else const _SignedOut(),
            const SizedBox(height: Gap.xl),
            _Section(titleKey: 'profile.preferences', children: const [_LanguageRow()]),
            const SizedBox(height: Gap.lg),
            const _SupportAndLegal(),
            if (signedIn) ...[
              const SizedBox(height: Gap.xl),
              OutlinedButton.icon(
                onPressed: () => signOut(ref),
                icon: Icon(Icons.logout, color: t.danger, size: 18),
                label: Text(
                  l10n.t('account.signOut'),
                  style: AppType.label.copyWith(color: t.danger),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: t.hairline),
                  padding: const EdgeInsets.symmetric(vertical: Gap.lg),
                  shape:
                      RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.control)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Identity extends ConsumerWidget {
  const _Identity();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTokens.of(context);
    final l10n = ref.watch(l10nProvider);
    final profile = ref.watch(profileProvider);

    return profile.when(
      loading: () => const Center(child: Padding(
        padding: EdgeInsets.all(Gap.xl),
        child: CircularProgressIndicator(),
      )),
      error: (_, _) => Center(
        child: Column(
          children: [
            Text(l10n.t('error.network_unavailable'),
                style: AppType.body.copyWith(color: t.inkMuted), textAlign: TextAlign.center),
            const SizedBox(height: Gap.md),
            TextButton(
              onPressed: () => ref.invalidate(profileProvider),
              child: Text(l10n.t('common.retry')),
            ),
          ],
        ),
      ),
      data: (p) => Column(
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: t.accent,
            child: Text(p.initials, style: AppType.title.copyWith(color: t.primary)),
          ),
          const SizedBox(height: Gap.md),
          Text(p.displayName, style: AppType.hero.copyWith(color: t.primary)),
          Text(p.email, style: AppType.body.copyWith(color: t.inkMuted)),
        ],
      ),
    );
  }
}

class _SignedOut extends ConsumerWidget {
  const _SignedOut();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);
    return Column(
      children: [
        CircleAvatar(
          radius: 40,
          backgroundColor: t.accent,
          child: Icon(Icons.person_outline, size: 36, color: t.primary),
        ),
        const SizedBox(height: Gap.md),
        Text(l10n.t('account.signedOutTitle'),
            style: AppType.heading.copyWith(color: t.primary)),
        const SizedBox(height: Gap.sm),
        Text(l10n.t('account.signedOutBody'),
            style: AppType.body.copyWith(color: t.inkMuted), textAlign: TextAlign.center),
        const SizedBox(height: Gap.lg),
        FilledButton(
          onPressed: () => context.pushNamed('welcome'),
          child: Text(l10n.t('account.signIn')),
        ),
      ],
    );
  }
}

class _Section extends ConsumerWidget {
  final String titleKey;
  final List<Widget> children;

  const _Section({required this.titleKey, required this.children});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: Gap.sm, left: Gap.xs),
          child: Text(
            ref.watch(l10nProvider).t(titleKey).toUpperCase(),
            style: AppType.captionStrong.copyWith(color: t.inkMuted),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(Radii.card),
            border: Border.all(color: t.hairline),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _LanguageRow extends ConsumerWidget {
  const _LanguageRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = ref.watch(brandConfigProvider);
    final current = ref.watch(languageProvider);
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);

    return ListTile(
      leading: Icon(Icons.language, color: t.primary),
      title: Text(l10n.t('common.language'), style: AppType.body),
      subtitle: Text(kLanguageEndonyms[current] ?? current, style: AppType.caption),
      trailing: Icon(Icons.chevron_right, color: t.inkMuted),
      onTap: () => showModalBottomSheet<void>(
        context: context,
        backgroundColor: t.card,
        builder: (_) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Only the languages THIS brand serves. The socle's list is not
              // the authority (§2.5).
              for (final code in brand.locales)
                ListTile(
                  title: Text(kLanguageEndonyms[code] ?? code, style: AppType.body),
                  trailing: code == current ? Icon(Icons.check, color: t.primary) : null,
                  onTap: () {
                    ref.read(languageProvider.notifier).set(code);
                    Navigator.of(context).pop();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SupportAndLegal extends ConsumerWidget {
  const _SupportAndLegal();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = ref.watch(brandConfigProvider);
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);

    Future<void> open(String url) async {
      final uri = Uri.tryParse(url);
      if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
    }

    return _Section(
      titleKey: 'profile.support',
      children: [
        ListTile(
          leading: Icon(Icons.support_agent, color: t.primary),
          title: Text(l10n.t('support.contact'), style: AppType.body),
          subtitle: Text(brand.support.email, style: AppType.caption),
          onTap: () => open('mailto:${brand.support.email}'),
        ),
        Divider(height: 1, color: t.hairline),
        ListTile(
          leading: Icon(Icons.description_outlined, color: t.primary),
          title: Text(l10n.t('legal.terms'), style: AppType.body),
          trailing: Icon(Icons.open_in_new, size: 16, color: t.inkMuted),
          onTap: () => open(brand.legal.termsUrl),
        ),
        Divider(height: 1, color: t.hairline),
        ListTile(
          leading: Icon(Icons.privacy_tip_outlined, color: t.primary),
          title: Text(l10n.t('legal.privacy'), style: AppType.body),
          trailing: Icon(Icons.open_in_new, size: 16, color: t.inkMuted),
          onTap: () => open(brand.legal.privacyUrl),
        ),
        Divider(height: 1, color: t.hairline),
        Padding(
          padding: const EdgeInsets.all(Gap.lg),
          child: Text(
            l10n.t('legal.publishedBy'),
            style: AppType.caption,
          ),
        ),
      ],
    );
  }
}
