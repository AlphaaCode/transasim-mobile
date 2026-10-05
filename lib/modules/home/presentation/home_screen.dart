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
import '../../../core/onboarding/tour.dart';
import '../../../core/session/session.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_button.dart';
import '../../../core/ui/app_card.dart';
import '../../../core/ui/esim_help_sheet.dart';
import '../../../core/ui/app_coach_mark.dart';
import '../../../core/ui/partner_card.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _scanKey = GlobalKey(debugLabel: 'tour:scan');

  @override
  void initState() {
    super.initState();
    // After the first frame, so every target has a size to point at — and
    // after a beat, so the tour does not land on a screen still settling.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      final l10n = ref.read(l10nProvider);
      await runTour(context, ref, [
        (
          TourStep.scanVoucher,
          CoachMark(target: _scanKey, title: l10n.t('tour.scan.title'), body: l10n.t('tour.scan.body')),
        ),
        (
          TourStep.store,
          CoachMark(
            target: ref.read(navAnchorProvider('nav.store')),
            title: l10n.t('tour.store.title'),
            body: l10n.t('tour.store.body'),
          ),
        ),
        (
          TourStep.esims,
          CoachMark(
            target: ref.read(navAnchorProvider('nav.esims')),
            title: l10n.t('tour.esims.title'),
            body: l10n.t('tour.esims.body'),
          ),
        ),
      ]);
    });
  }

  @override
  Widget build(BuildContext context) {
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
              _VoucherHero(scanKey: _scanKey),

              const SizedBox(height: Gap.xl),
              AppEyebrow(l10n.t('home.orBrowse')),
              const SizedBox(height: Gap.md),
              AppFeatureCard(
                icon: Icons.storefront_outlined,
                title: l10n.t('nav.store'),
                body: l10n.t('catalog.subtitle'),
                tileColor: t.accent,
                trailing: Icon(Icons.chevron_right, color: t.inkMuted),
                onTap: () => context.goNamed('store'),
              ),
              const SizedBox(height: Gap.md),
              AppFeatureCard(
                icon: Icons.sim_card_outlined,
                title: l10n.t('nav.esims'),
                body: l10n.t('home.esimsBody'),
                // Gold, not mint: only the Store shortcut is mint. My eSIMs
                // and the partner card below share the warm treatment, which
                // is what separates "browse and buy" from "what you own".
                tileColor: t.premiumSurface,
                iconColor: t.premiumAccent,
                trailing: Icon(Icons.chevron_right, color: t.inkMuted),
                onTap: () => context.goNamed('esims'),
              ),
              const SizedBox(height: Gap.md),
              // Accent, never danger red: this answers a question, it does not
              // report a problem, and it must never read as a reason not to
              // buy. Nothing downstream branches on whether it was opened.
              AppFeatureCard(
                icon: Icons.help_outline,
                title: l10n.t('esimHelp.entry'),
                body: l10n.t('esimHelp.intro'),
                tileColor: t.accent,
                trailing: Icon(Icons.chevron_right, color: t.inkMuted),
                onTap: () => showEsimHelpSheet(context),
              ),
              const SizedBox(height: Gap.xl),
              const PartnerCard(),
              // A footer, not another item in the list: a hairline closes
              // the stack of cards first, so the sign-in prompt reads as the
              // end of the page rather than as a fifth thing to tap.
              if (!ref.watch(isSignedInProvider)) ...[
                const SizedBox(height: Gap.xxl),
                Divider(color: t.hairline, height: 1),
                const SizedBox(height: Gap.sm),
                Center(
                  child: AppInlineLink(
                    prompt: l10n.t('account.noAccountPrompt'),
                    action: l10n.t('account.signIn'),
                    onPressed: () => context.pushNamed('welcome'),
                  ),
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
  final GlobalKey scanKey;
  const _VoucherHero({required this.scanKey});

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
            key: scanKey,
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
