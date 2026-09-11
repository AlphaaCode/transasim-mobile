import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/brand/brand_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_text_field.dart';
import 'catalog_controllers.dart';
import 'widgets.dart';

/// The Store tab: every destination with a purchasable pack.
///
/// Follows `eSIM Catalog - Sabily (Mobile).png` and `Regional Packs - Sabily
/// (Mobile).png` for structure — a title block, a search field, then the list.
class StoreScreen extends ConsumerWidget {
  const StoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);
    final async = ref.watch(catalogControllerProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('nav.store'))),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => StateMessage(
            icon: Icons.error_outline,
            title: l10n.t('error.generic'),
            actionLabel: l10n.t('common.retry'),
            onAction: () => ref.read(catalogControllerProvider.notifier).refresh(),
          ),
          data: (state) => switch (state) {
            CatalogLoading() => const Center(child: CircularProgressIndicator()),
            CatalogFailed(:final error) => StateMessage(
                icon: Icons.cloud_off,
                // Typed error -> dictionary key. Never a raw exception string.
                title: l10n.t('error.${error.code}', vars: const {}),
                actionLabel: l10n.t('common.retry'),
                onAction: () => ref.read(catalogControllerProvider.notifier).refresh(),
              ),
            CatalogReady() => _Loaded(state: state),
          },
        ),
      ),
      backgroundColor: t.surface,
    );
  }
}

class _Loaded extends ConsumerWidget {
  final CatalogReady state;
  const _Loaded({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);

    return RefreshIndicator(
      onRefresh: () => ref.read(catalogControllerProvider.notifier).refresh(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, Gap.xxl),
        children: [
          Text(l10n.t('catalog.title'), style: AppType.title.copyWith(color: t.primary)),
          const SizedBox(height: Gap.xs),
          Text(l10n.t('catalog.subtitle'), style: AppType.body.copyWith(color: t.inkMuted)),
          const SizedBox(height: Gap.lg),
          AppSearchField(
            hint: l10n.t('catalog.searchHint'),
            onChanged: ref.read(catalogControllerProvider.notifier).search,
          ),
          const SizedBox(height: Gap.lg),
          if (state.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Gap.xxl),
              child: StateMessage(
                icon: Icons.search_off,
                title: l10n.t('catalog.emptyTitle'),
                body: l10n.t('catalog.emptyBody'),
              ),
            )
          else
            for (final destination in state.visible)
              DestinationTile(
                destination: destination,
                onTap: () => context.pushNamed(
                  'destination',
                  pathParameters: {'code': destination.code},
                ),
              ),
        ],
      ),
    );
  }
}
