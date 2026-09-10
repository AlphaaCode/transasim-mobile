import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/brand/brand_providers.dart';
import '../../../core/theme/app_theme.dart';

/// Deliberately empty. See `wallet_module.dart`.
class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('nav.wallet'))),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(Gap.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.account_balance_wallet_outlined, size: 64, color: t.accent),
              const SizedBox(height: Gap.lg),
              Text(l10n.t('wallet.comingSoon'), style: AppType.title),
              const SizedBox(height: Gap.sm),
              Text(
                l10n.t('wallet.comingSoonBody'),
                style: AppType.body.copyWith(color: t.inkMuted),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
