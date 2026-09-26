import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/brand/brand_providers.dart';
import '../../../core/i18n/locales.dart';
import '../../../core/session/session.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_button.dart';
import '../../../core/ui/app_card.dart';
import '../../../core/ui/app_skeleton.dart';
import '../../../core/ui/partner_card.dart';
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
            const SizedBox(height: Gap.lg),
            const PartnerCard(),
            if (signedIn) ...[
              const SizedBox(height: Gap.xl),
              AppButton(
                label: l10n.t('account.signOut'),
                icon: Icons.logout,
                tone: AppButtonTone.danger,
                onPressed: () => signOut(ref),
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
      // The identity block's own shape while it loads, so the page does not
      // reflow the moment the name arrives.
      loading: () => const AppSkeleton(
        child: Column(
          children: [
            AppSkeletonBox(height: 80, width: 80, circle: true),
            SizedBox(height: Gap.md),
            AppSkeletonBox(height: 24, width: 180),
            SizedBox(height: Gap.sm),
            AppSkeletonBox(height: 16, width: 140),
          ],
        ),
      ),
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
      data: (p) => _IdentityCard(
        child: Column(
          children: [
            _RingedAvatar(
              child: Text(p.initials, style: AppType.heading.copyWith(color: t.primary)),
            ),
            const SizedBox(height: Gap.md),
            Text(p.displayName, style: AppType.title.copyWith(color: t.primary)),
            Text(p.email, style: AppType.body.copyWith(color: t.inkMuted)),
          ],
        ),
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
    return _IdentityCard(
      child: Column(
        children: [
          _RingedAvatar(child: Icon(Icons.person_outline, size: 36, color: t.primary)),
          const SizedBox(height: Gap.md),
          Text(l10n.t('account.signedOutTitle'),
              style: AppType.heading.copyWith(color: t.primary)),
          const SizedBox(height: Gap.sm),
          Text(l10n.t('account.signedOutBody'),
              style: AppType.body.copyWith(color: t.inkMuted), textAlign: TextAlign.center),
          const SizedBox(height: Gap.lg),
          AppButton(
            label: l10n.t('account.signIn'),
            onPressed: () => context.pushNamed('welcome'),
          ),
        ],
      ),
    );
  }
}

/// The soft mint-to-cream card both identity states sit in, so a signed-out
/// visitor sees the same polish a signed-in one does rather than a bare
/// column on the page ground.
class _IdentityCard extends StatelessWidget {
  final Widget child;
  const _IdentityCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [t.accent, t.surface],
        ),
        borderRadius: BorderRadius.circular(Radii.card),
        boxShadow: Shadows.card,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Gap.xxl, horizontal: Gap.lg),
        child: child,
      ),
    );
  }
}

/// The 80px avatar disc, lifted off the identity card's gradient by a white
/// ring — otherwise a mint circle on a mint-to-cream card has no edge.
class _RingedAvatar extends StatelessWidget {
  final Widget child;
  const _RingedAvatar({required this.child});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: t.card,
        boxShadow: Shadows.field,
      ),
      child: CircleAvatar(radius: 40, backgroundColor: t.accent, child: child),
    );
  }
}

/// A row icon inside its own tinted tile, replacing a bare glyph with the
/// same icon-badge language Store and Pack details use (AppFeatureCard,
/// DestinationTile) — one visual grammar for "here's an icon", everywhere.
class _IconBadge extends StatelessWidget {
  final IconData icon;
  const _IconBadge(this.icon);

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: t.accent, borderRadius: BorderRadius.circular(Radii.chip)),
      child: Icon(icon, size: 19, color: t.primary),
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
          child: AppEyebrow(ref.watch(l10nProvider).t(titleKey)),
        ),
        // The shadow stays on the DecoratedBox; the FILL moved to a Material.
        //
        // A ListTile paints its ink on the nearest Material ancestor, so a
        // coloured box between the two swallows every splash — the framework
        // asserts exactly that, four times per build of this screen, and the
        // rows looked dead to the touch. Giving the decoration no colour keeps
        // the design's two-layer shadow (Material's `elevation` draws a
        // different one) while the Material underneath provides both the card
        // colour and a surface for the ink.
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.control),
            boxShadow: Shadows.card,
          ),
          child: Material(
            color: t.card,
            borderRadius: BorderRadius.circular(Radii.control),
            clipBehavior: Clip.antiAlias,
            child: Column(children: children),
          ),
        ),
      ],
    );
  }
}

class _LanguageRow extends ConsumerWidget {
  const _LanguageRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locales = ref.watch(brandConfigProvider.select((b) => b.locales));
    final current = ref.watch(languageProvider);
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);

    return ListTile(
      leading: const _IconBadge(Icons.language),
      title: Text(l10n.t('common.language'), style: AppType.body),
      subtitle: Text(kLanguageEndonyms[current] ?? current, style: AppType.caption),
      trailing: Icon(Icons.chevron_right, color: t.inkMuted),
      onTap: () => showModalBottomSheet<void>(
        context: context,
        backgroundColor: t.card,
        // Without this a sheet is capped at 9/16 of the screen, and seven
        // 56px rows plus the gesture-navigation inset do not fit: Sabily's
        // picker overflowed by 6.7px, clipping Shqip at the bottom. The cap is
        // the whole bug — the Column is already mainAxisSize.min and asks for
        // no more than its rows need.
        isScrollControlled: true,
        builder: (_) => SafeArea(
          // And when the rows genuinely exceed the screen — a brand serving
          // more languages, or a phone at the largest font scale — they scroll
          // instead of overflowing. An overflow here is invisible in release,
          // so the fix has to be structural rather than a bigger cap.
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Only the languages THIS brand serves. The socle's list is not
                // the authority (§2.5).
                for (final code in locales)
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
      ),
    );
  }
}

class _SupportAndLegal extends ConsumerWidget {
  const _SupportAndLegal();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final support = ref.watch(brandConfigProvider.select((b) => b.support.email));
    final terms = ref.watch(brandConfigProvider.select((b) => b.legal.termsUrl));
    final privacy = ref.watch(brandConfigProvider.select((b) => b.legal.privacyUrl));
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
          leading: const _IconBadge(Icons.support_agent),
          title: Text(l10n.t('support.contact'), style: AppType.body),
          subtitle: Text(support, style: AppType.caption),
          onTap: () => open('mailto:$support'),
        ),
        Divider(height: 1, color: t.hairline),
        ListTile(
          leading: const _IconBadge(Icons.description_outlined),
          title: Text(l10n.t('legal.terms'), style: AppType.body),
          trailing: Icon(Icons.open_in_new, size: 16, color: t.inkMuted),
          onTap: () => open(terms),
        ),
        Divider(height: 1, color: t.hairline),
        ListTile(
          leading: const _IconBadge(Icons.privacy_tip_outlined),
          title: Text(l10n.t('legal.privacy'), style: AppType.body),
          trailing: Icon(Icons.open_in_new, size: 16, color: t.inkMuted),
          onTap: () => open(privacy),
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
