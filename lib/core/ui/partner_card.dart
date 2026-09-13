import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../brand/brand_providers.dart';
import '../theme/app_theme.dart';
import 'app_card.dart';

/// Become a Partner. Opens the brand's partner page: the application form
/// lives on the website (52:639), so the app does not duplicate it. Absent
/// when the brand has no partner programme.
class PartnerCard extends ConsumerWidget {
  const PartnerCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref.watch(brandConfigProvider.select((b) => b.support.partnerUrl));
    if (url == null) return const SizedBox.shrink();
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);

    return AppFeatureCard(
      icon: Icons.handshake,
      title: l10n.t('partner.title'),
      body: l10n.t('partner.body'),
      trailing: Icon(Icons.open_in_new, size: 16, color: t.inkMuted),
      onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
    );
  }
}
