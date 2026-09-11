/// Shared catalogue pieces. Every value is a token or comes from the domain —
/// no colour literal, no inline font size (CI checks C2).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/brand/brand_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_button.dart';
import '../domain/catalog.dart';


/// The pack card's media band.
///
/// The design shows a photograph behind a dark scrim with a SIM glyph on top.
/// There is no photograph to show: the old app built one by string-concatenating
/// a client's WordPress host into the data model, which is exactly the coupling
/// this socle exists to remove (`ANALYSE-EXISTANT.md` §4.6).
///
/// So the scrim and the glyph ARE the treatment until `coverImageUrl` arrives
/// from the backend, at which point it slots in behind them unchanged.
class PackMedia extends StatelessWidget {
  final Pack pack;
  final String? popularLabel;

  const PackMedia({super.key, required this.pack, this.popularLabel});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final url = pack.coverImageUrl;

    return SizedBox(
      height: 128,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.media),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (url != null)
              Image.network(
                url,
                fit: BoxFit.cover,
                // Decoded at the size it is drawn at, not the size it was
                // uploaded at. A 2000px hero scaled into a 160dp band costs
                // ~16MB of image cache per pack without this, and the cache
                // evicts the ones still on screen to make room.
                cacheWidth: (MediaQuery.sizeOf(context).width *
                        MediaQuery.devicePixelRatioOf(context))
                    .round(),
                // Keeps the previous frame while a new one decodes instead of
                // flashing back to the placeholder on every rebuild.
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => _Wash(t: t),
              )
            else
              _Wash(t: t),
            Container(color: t.primary.withValues(alpha: 0.40)),
            Center(
              child: Container(
                width: 48,
                height: 64,
                decoration: BoxDecoration(
                  color: t.onPrimary.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(Radii.chip),
                  border: Border.all(color: t.onPrimary.withValues(alpha: 0.40)),
                ),
                child: Icon(Icons.sim_card_outlined, color: t.onPrimary, size: 24),
              ),
            ),
            if (pack.isPopular && popularLabel != null)
              PositionedDirectional(
                top: Gap.md,
                end: Gap.md,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 2),
                  decoration: BoxDecoration(
                    color: t.cta,
                    borderRadius: BorderRadius.circular(Radii.pill),
                  ),
                  // Badge text uses the premium token — which is what the design
                  // does too, rather than inventing a sixth colour.
                  child: Text(
                    popularLabel!.toUpperCase(),
                    style: AppType.captionStrong.copyWith(color: t.premiumAccent),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Wash extends StatelessWidget {
  final AppTokens t;
  const _Wash({required this.t});

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [t.primary, t.accent],
          ),
        ),
      );
}

/// A value with its label beneath — "10 GB / Data", "7 days / Validity".
class SpecItem extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const SpecItem({super.key, required this.icon, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: t.primary),
        const SizedBox(width: Gap.sm),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(value, style: AppType.body.copyWith(color: t.primary)),
            Text(label, style: AppType.label.copyWith(color: t.inkMuted)),
          ],
        ),
      ],
    );
  }
}

/// The dark rounded price pill from the design.
class PricePill extends StatelessWidget {
  final Money price;
  const PricePill({super.key, required this.price});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.xs),
      decoration: BoxDecoration(
        color: t.primary,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Text(price.format(), style: AppType.subtitle.copyWith(color: t.onPrimary)),
    );
  }
}

/// A destination row in the store list.
class DestinationTile extends ConsumerWidget {
  final Destination destination;
  final VoidCallback onTap;

  const DestinationTile({super.key, required this.destination, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTokens.of(context);
    final l10n = ref.watch(l10nProvider);
    final cheapest = destination.cheapestPrice;

    return Card(
      margin: const EdgeInsets.only(bottom: Gap.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.card),
        child: Padding(
          padding: const EdgeInsets.all(Gap.lg),
          child: Row(
            children: [
              // No third-party flag CDN. The old app pulled every flag from
              // flagcdn.com — an uncontrolled runtime dependency in a commercial
              // funnel (§4.6). A country code on a brand-tinted disc needs no
              // network at all.
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: t.accent,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  destination.code,
                  style: AppType.labelStrong.copyWith(color: t.primary),
                ),
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(destination.name, style: AppType.bodyStrong.copyWith(color: t.primary)),
                    Text(
                      l10n.t('catalog.packCount', vars: {'count': '${destination.packs.length}'}),
                      style: AppType.caption,
                    ),
                  ],
                ),
              ),
              if (cheapest != null) ...[
                const SizedBox(width: Gap.sm),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(l10n.t('catalog.from'), style: AppType.caption),
                    Text(cheapest.format(), style: AppType.bodyStrong.copyWith(color: t.primary)),
                  ],
                ),
              ],
              const SizedBox(width: Gap.xs),
              Icon(Icons.chevron_right, color: t.inkMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Loading, empty and error states, shared so every catalogue screen shows the
/// same thing. The old app had none of these — 29 screens each re-implemented
/// the pattern, which is how two tabs of one screen ended up with inverted
/// colour thresholds.
class StateMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? body;
  final String? actionLabel;
  final VoidCallback? onAction;

  const StateMessage({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Gap.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: t.inkMuted),
            const SizedBox(height: Gap.lg),
            Text(title, style: AppType.heading.copyWith(color: t.primary), textAlign: TextAlign.center),
            if (body != null) ...[
              const SizedBox(height: Gap.sm),
              Text(body!, style: AppType.body.copyWith(color: t.inkMuted), textAlign: TextAlign.center),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: Gap.lg),
              AppButton(label: actionLabel!, onPressed: onAction),
            ],
          ],
        ),
      ),
    );
  }
}
