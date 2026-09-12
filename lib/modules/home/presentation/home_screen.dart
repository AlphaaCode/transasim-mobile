/// Home. The first screen, and the only one in this app with no Figma frame
/// behind it — see the header note in `HomeModule`.
///
/// The ordering decision, stated so it can be argued with: "Scan your voucher"
/// is the hero, above the fold, at call-to-action weight. Sabily's customers
/// are Hajj and Umrah pilgrims, and they commonly arrive holding an
/// agency-issued voucher already paid for. For that person, redeeming is a more
/// likely first action than browsing a catalogue — so the catalogue is one tap
/// away rather than in front of them.
///
/// Everything here is the component layer built for auth, checkout and eSIM.
/// Nothing on this screen invents a style.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/brand/brand_providers.dart';
import '../../../core/session/session.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_button.dart';
import '../../../core/ui/app_card.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);
    final logo = ref.watch(brandConfigProvider.select((b) => b.logo.mark));
    final assetPath = ref.watch(brandConfigProvider.select((b) => b.assetPath));

    return Scaffold(
      body: AppScreenGradient(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, Gap.xxl),
            children: [
              Row(
                children: [
                  Image.asset(
                    assetPath(logo),
                    height: 40,
                    width: 40,
                    errorBuilder: (_, _, _) => Icon(Icons.sim_card, color: t.primary),
                  ),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Text(
                      l10n.t('startup.welcome'),
                      style: AppType.heading.copyWith(color: t.primary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Gap.xl),

              // THE hero. First thing on the screen, and the heaviest thing on
              // it — the call-to-action pair, because for this customer base
              // redeeming a voucher IS the purchase.
              const _VoucherHero(),

              const SizedBox(height: Gap.xl),
              Text(l10n.t('home.orBrowse'),
                  style: AppType.label.copyWith(color: t.inkMuted)),
              const SizedBox(height: Gap.md),
              _Shortcut(
                icon: Icons.storefront_outlined,
                titleKey: 'nav.store',
                bodyKey: 'catalog.subtitle',
                onTap: () => context.goNamed('store'),
              ),
              const SizedBox(height: Gap.md),
              _Shortcut(
                icon: Icons.sim_card_outlined,
                titleKey: 'nav.esims',
                bodyKey: 'home.esimsBody',
                onTap: () => context.goNamed('esims'),
              ),
              if (!ref.watch(isSignedInProvider)) ...[
                const SizedBox(height: Gap.xl),
                AppInlineLink(
                  prompt: l10n.t('account.noAccountPrompt'),
                  action: l10n.t('account.signIn'),
                  onPressed: () => context.pushNamed('welcome'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _VoucherHero extends ConsumerWidget {
  const _VoucherHero();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);

    return AppCard(
      glow: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 48,
                width: 48,
                decoration: BoxDecoration(
                  color: t.accent,
                  borderRadius: BorderRadius.circular(Radii.chip),
                ),
                child: Icon(Icons.qr_code_scanner, color: t.primary),
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Text(l10n.t('home.voucherTitle'),
                    style: AppType.hero.copyWith(color: t.primary)),
              ),
            ],
          ),
          const SizedBox(height: Gap.md),
          Text(l10n.t('home.voucherBody'),
              style: AppType.body.copyWith(color: t.inkMuted)),
          const SizedBox(height: Gap.xl),
          AppButton(
            label: l10n.t('home.scanVoucher'),
            icon: Icons.qr_code_scanner,
            tone: AppButtonTone.cta,
            onPressed: () => context.pushNamed('voucher'),
          ),
          const SizedBox(height: Gap.xs),
          // Typing is a way in, not a recovery. Offered here, at the same
          // moment as the camera, for the same reason the eSIM screen shows the
          // copyable code beside the QR rather than after it fails: some
          // printed slips will never scan.
          Center(
            child: AppLinkButton(
              label: l10n.t('home.enterCode'),
              onPressed: () => context.pushNamed('voucher'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Shortcut extends ConsumerWidget {
  final IconData icon;
  final String titleKey;
  final String bodyKey;
  final VoidCallback onTap;

  const _Shortcut({
    required this.icon,
    required this.titleKey,
    required this.bodyKey,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);

    return Material(
      color: t.card,
      borderRadius: BorderRadius.circular(Radii.control),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.control),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Gap.lg),
          child: Row(
            children: [
              Icon(icon, color: t.primary, size: 20),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.t(titleKey), style: AppType.bodyStrong.copyWith(color: t.ink)),
                    Text(l10n.t(bodyKey),
                        style: AppType.caption.copyWith(color: t.inkMuted),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: t.inkMuted),
            ],
          ),
        ),
      ),
    );
  }
}
