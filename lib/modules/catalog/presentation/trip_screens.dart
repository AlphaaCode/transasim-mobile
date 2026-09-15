/// A trip through several countries: pick them, see the packs that cover them.
///
/// No design source — like Home and the onboarding tour, this is built from the
/// component layer (search field, filter chips, cards, the fixed buy bar of the
/// pack detail screen) and is for Yazid to review.
///
/// Flow: Store -> "Plusieurs pays ?" -> pick countries -> ranked coverages ->
/// a pack's detail. The matching is [matchCoverage], over the catalogue already
/// in memory: no request, nothing to wait for.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/brand/brand_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_button.dart';
import '../../../core/ui/app_text_field.dart';
import '../domain/destination_search.dart';
import '../domain/catalog.dart';
import '../domain/coverage_match.dart';
import 'catalog_controllers.dart';
import 'destination_screen.dart';
import 'widgets.dart';

/// Every purchasable pack once, from the catalogue already loaded.
final allPacksProvider = FutureProvider<List<Pack>>((ref) async {
  final destinations = await ref.watch(catalogRepositoryProvider).destinations();
  final byId = <int, Pack>{
    for (final d in destinations)
      for (final p in d.packs) p.id: p,
  };
  return byId.values.toList();
});

/// Keyed by the chosen codes, sorted and comma-joined.
final tripMatchProvider = FutureProvider.family<CoverageMatch, String>((ref, key) async {
  final packs = await ref.watch(allPacksProvider.future);
  return matchCoverage(packs, key.split(',').where((c) => c.isNotEmpty).toSet());
});

const _minCountries = 2;

class TripPickerScreen extends ConsumerStatefulWidget {
  const TripPickerScreen({super.key});

  @override
  ConsumerState<TripPickerScreen> createState() => _TripPickerScreenState();
}

class _TripPickerScreenState extends ConsumerState<TripPickerScreen> {
  /// In the order chosen, so the chips read the way the trip was planned.
  final _chosen = <String>{};
  String _query = '';

  void _toggle(String code) =>
      setState(() => _chosen.contains(code) ? _chosen.remove(code) : _chosen.add(code));

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);
    final names = ref.watch(countryNamesProvider).value;

    final countries = names == null
        ? const <MapEntry<String, String>>[]
        : searchDestinations(
            names.entries.toList()..sort((a, b) => a.value.compareTo(b.value)),
            _query,
            code: (e) => e.key,
            name: (e) => e.value,
          );

    return Scaffold(
      backgroundColor: t.surface,
      bottomNavigationBar: _BottomBar(
        child: AppButton(
          label: l10n.t('trip.find', vars: {'count': '${_chosen.length}'}),
          icon: Icons.travel_explore,
          onPressed: _chosen.length < _minCountries
              ? null
              : () => context.pushNamed(
                    'tripResults',
                    queryParameters: {'c': _chosen.join(',')},
                  ),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(title: l10n.t('trip.title')),
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.t('trip.pickHint'), style: AppType.body.copyWith(color: t.inkMuted)),
                const SizedBox(height: Gap.md),
                AppSearchField(
                  hint: l10n.t('catalog.searchHint'),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ],
            ),
          ),
          // What is chosen, always in view; a tap takes one back out.
          if (_chosen.isNotEmpty && names != null)
            AppChipRow(
              padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.md),
              children: [
                for (final code in _chosen)
                  AppFilterChip(
                    label: '${names[code] ?? code}  ✕',
                    selected: true,
                    onTap: () => _toggle(code),
                  ),
              ],
            ),
          Expanded(
            child: names == null
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: Gap.lg),
                    itemCount: countries.length,
                    itemBuilder: (context, i) {
                      final MapEntry(key: code, value: name) = countries[i];
                      final on = _chosen.contains(code);
                      return InkWell(
                        onTap: () => _toggle(code),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.md),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(name, style: AppType.body.copyWith(color: t.ink)),
                              ),
                              Icon(
                                on ? Icons.check_circle : Icons.radio_button_unchecked,
                                color: on ? t.primary : t.inkFaint,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class TripResultsScreen extends ConsumerWidget {
  final List<String> codes;
  const TripResultsScreen({super.key, required this.codes});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);
    final key = ([...codes]..sort()).join(',');
    final match = ref.watch(tripMatchProvider(key));
    final names = ref.watch(countryNamesProvider).value ?? const <String, String>{};
    final count = codes.length;

    return Scaffold(
      backgroundColor: t.surface,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(title: l10n.t('trip.resultsTitle', vars: {'count': '$count'})),
          Expanded(
            child: match.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => StateMessage(icon: Icons.cloud_off, title: l10n.t('error.generic')),
              data: (m) => ListView(
                padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.xxl),
                children: [
                  Text(
                    codes.map((c) => names[c] ?? c).join(' · '),
                    style: AppType.bodyStrong.copyWith(color: t.primary),
                  ),
                  const SizedBox(height: Gap.md),
                  if (m.options.isEmpty)
                    StateMessage(icon: Icons.search_off, title: l10n.t('trip.nothing'))
                  else if (m.complete)
                    Text(
                      l10n.t('trip.allCovered', vars: {'count': '$count'}),
                      style: AppType.body.copyWith(color: t.inkMuted),
                    )
                  else
                    _Notice(
                      title: l10n.t('trip.noneCovers', vars: {'count': '$count'}),
                      body: l10n.t('trip.closest'),
                    ),
                  const SizedBox(height: Gap.lg),
                  for (var i = 0; i < m.options.length; i++) ...[
                    _OptionCard(
                      option: m.options[i],
                      chosenCount: count,
                      best: m.complete && i == 0,
                      names: names,
                    ),
                    const SizedBox(height: Gap.lg),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionCard extends ConsumerStatefulWidget {
  final CoverageOption option;
  final int chosenCount;
  final bool best;
  final Map<String, String> names;

  const _OptionCard({
    required this.option,
    required this.chosenCount,
    required this.best,
    required this.names,
  });

  @override
  ConsumerState<_OptionCard> createState() => _OptionCardState();
}

class _OptionCardState extends ConsumerState<_OptionCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);
    final language = ref.watch(languageProvider);
    final o = widget.option;
    final n = widget.chosenCount;

    final headline = !o.coversAll
        ? l10n.t('trip.coversPartial', vars: {'covered': '${o.covered.length}', 'count': '$n'})
        : o.extra == 0
            ? l10n.t('trip.coversExactly', vars: {'count': '$n'})
            : o.extra == 1
                ? l10n.t('trip.coversPlusOne', vars: {'count': '$n'})
                : l10n.t('trip.coversPlus', vars: {'count': '$n', 'extra': '${o.extra}'});
    final from = o.from!.format(language);
    final packs = _expanded ? o.packs : o.packs.take(1).toList();

    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(Radii.control),
        border: Border.all(color: widget.best ? t.primary : t.cardBorder),
        boxShadow: t.packShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.best) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 2),
              decoration: BoxDecoration(
                color: t.cta,
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
              child: Text(
                l10n.t('trip.bestMatch').toUpperCase(),
                style: AppType.captionStrong.copyWith(color: t.premiumAccent, letterSpacing: 0),
              ),
            ),
            const SizedBox(height: Gap.sm),
          ],
          Text(headline, style: AppType.cardTitle.copyWith(color: t.primary)),
          if (!o.coversAll) ...[
            const SizedBox(height: Gap.xs),
            Text(
              l10n.t('trip.missing', vars: {
                'names': o.missing.map((c) => widget.names[c] ?? c).join(', '),
              }),
              style: AppType.labelStrong.copyWith(color: t.danger),
            ),
          ],
          const SizedBox(height: Gap.xs),
          Text(
            o.packs.length == 1
                ? l10n.t('trip.onePack', vars: {'price': from})
                : l10n.t('trip.packsFrom', vars: {'packs': '${o.packs.length}', 'price': from}),
            style: AppType.body.copyWith(color: t.inkMuted),
          ),
          const SizedBox(height: Gap.md),
          for (final pack in packs) _PackRow(pack: pack, destinationCode: o.covered.first),
          if (o.packs.length > 1)
            AppLinkButton(
              label: _expanded
                  ? l10n.t('trip.hidePacks')
                  : l10n.t('trip.showPacks', vars: {'count': '${o.packs.length}'}),
              onPressed: () => setState(() => _expanded = !_expanded),
            ),
        ],
      ),
    );
  }
}

/// One pack inside an option; opens its detail, which has the buy button.
class _PackRow extends ConsumerWidget {
  final Pack pack;
  final String destinationCode;
  const _PackRow({required this.pack, required this.destinationCode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);
    final validity = pack.validity.isKnown ? ' · ${packValidityLabel(l10n, pack.validity)}' : '';

    return InkWell(
      borderRadius: BorderRadius.circular(Radii.chip),
      onTap: () => context.pushNamed(
        'pack',
        pathParameters: {'code': destinationCode, 'id': '${pack.id}'},
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: Gap.md),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: t.cardBorder))),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(pack.name, style: AppType.bodyStrong.copyWith(color: t.ink)),
                  Text(
                    '${packDataLabel(l10n, pack.data)}$validity',
                    style: AppType.caption.copyWith(color: t.inkMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Gap.md),
            Text(
              pack.price!.format(ref.watch(languageProvider)),
              style: AppType.labelStrong.copyWith(color: t.primary),
            ),
            Icon(Icons.chevron_right, color: t.inkMuted),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final String title;
  final String body;
  const _Notice({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: t.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(Radii.chip),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: t.warning, size: 20),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppType.labelStrong.copyWith(color: t.ink)),
                Text(body, style: AppType.label.copyWith(color: t.inkMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String title;
  const _Header({required this.title});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.sm, Gap.xs, Gap.lg, Gap.sm),
        child: Row(
          children: [
            BackPill(
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              color: t.primary,
              onTap: () => context.pop(),
            ),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: Text(title,
                  style: AppType.heading.copyWith(color: t.primary),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}

/// The fixed foot bar the pack detail screen uses (66:202).
class _BottomBar extends StatelessWidget {
  final Widget child;
  const _BottomBar({required this.child});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Container(
      decoration: BoxDecoration(
        color: t.card,
        border: Border(top: BorderSide(color: t.hairline)),
        boxShadow: Shadows.bottomBar,
      ),
      padding: const EdgeInsets.fromLTRB(Gap.lg, 17, Gap.lg, Gap.lg),
      child: SafeArea(top: false, child: child),
    );
  }
}
