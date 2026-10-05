/// "Does my phone support eSIM?", as a sheet anyone can open.
///
/// In `core/ui/` because three modules show it — Home, Checkout and the eSIM
/// install card — and modules may not import each other (rule L2). Core
/// imports no module, so the dependency only ever points inward.
///
/// Static text, no network, no platform channel. The one optional action is
/// opening the dialer, and it is best effort: a phone that refuses is not an
/// error worth a message, because the sheet has already said what to type.
///
/// ⚠️ It must never block or discourage a purchase. It answers a question the
/// user already has; it does not gate anything, and nothing reads its result.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../brand/brand_providers.dart';
import '../theme/app_theme.dart';
import 'app_button.dart';

/// Opens the sheet. Returns when it is dismissed; the result is deliberately
/// nothing, because no caller may branch on it.
Future<void> showEsimHelpSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppTokens.of(context).card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.sheet)),
      ),
      builder: (_) => const EsimHelpSheet(),
    );

class EsimHelpSheet extends ConsumerWidget {
  const EsimHelpSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);

    return SafeArea(
      child: ConstrainedBox(
        // Tall enough to read, short enough that the page behind stays
        // visible — it is a help sheet, not a screen.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.t('esimHelp.title'),
                style: AppType.title.copyWith(color: t.primary),
              ),
              const SizedBox(height: Gap.md),
              Text(
                l10n.t('esimHelp.intro'),
                style: AppType.body.copyWith(color: t.inkMuted),
              ),
              const SizedBox(height: Gap.xl),
              _Section(
                icon: Icons.android,
                title: l10n.t('esimHelp.androidTitle'),
                body: l10n.t('esimHelp.android'),
              ),
              const SizedBox(height: Gap.lg),
              _Section(
                icon: Icons.phone_iphone,
                title: l10n.t('esimHelp.iphoneTitle'),
                body: l10n.t('esimHelp.iphone'),
              ),
              const SizedBox(height: Gap.lg),
              _Section(
                icon: Icons.lock_outline,
                title: l10n.t('esimHelp.carrierTitle'),
                body: l10n.t('esimHelp.carrier'),
              ),
              const SizedBox(height: Gap.xl),
              AppButton(
                label: l10n.t('esimHelp.dialer'),
                icon: Icons.dialpad,
                tone: AppButtonTone.onDark,
                onPressed: _openDialer,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Opens the dialer pre-filled with `*#06#`. The USER presses call — nothing
  /// here dials anything.
  ///
  /// Best effort by design: a device with no dialer, or one that refuses the
  /// intent, is not worth an error. The sheet has already written the code out
  /// in full, so the button is a shortcut and never the only way.
  static Future<void> _openDialer() async {
    try {
      // `#` has to be percent-encoded or it reads as a URI fragment and the
      // dialer receives `*` alone.
      await launchUrl(Uri.parse('tel:*%2306%23'));
    } catch (_) {
      // Silent on purpose.
    }
  }
}

class _Section extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _Section({required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 36,
          width: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: t.accent,
            borderRadius: BorderRadius.circular(Radii.chip),
          ),
          child: Icon(icon, size: 20, color: t.primary),
        ),
        const SizedBox(width: Gap.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppType.bodyStrong.copyWith(color: t.ink)),
              const SizedBox(height: Gap.xs),
              Text(body, style: AppType.body.copyWith(color: t.inkMuted)),
            ],
          ),
        ),
      ],
    );
  }
}

/// The small text link under a checkout summary, or anywhere a full card would
/// be too loud. Informational: it opens the sheet and nothing else.
class EsimHelpLink extends ConsumerWidget {
  const EsimHelpLink({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);

    return InkWell(
      onTap: () => showEsimHelpSheet(context),
      borderRadius: BorderRadius.circular(Radii.chip),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Gap.sm),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.help_outline, size: 16, color: t.primary),
            const SizedBox(width: Gap.xs),
            Flexible(
              child: Text(
                l10n.t('esimHelp.entry'),
                style: AppType.labelStrong.copyWith(color: t.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
