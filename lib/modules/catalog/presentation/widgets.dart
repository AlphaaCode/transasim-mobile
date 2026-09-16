/// Shared catalogue pieces. Every value is a token or comes from the domain —
/// no colour literal, no inline font size (CI checks C2).
library;

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/brand/brand_providers.dart';
import '../../../core/i18n/country_names.dart';
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
///
/// Layers, as 63:53 stacks them: a 5% primary wash, the art, a 40% primary
/// darkening overlay, then a frosted 48x64 badge carrying the SIM glyph. The
/// two blurs (1px on the art, 6px under the badge) are applied only when there
/// is a photograph to blur: over the flat stand-in they change nothing a person
/// can see, and a backdrop filter in a scrolling list costs a layer per card.
class PackMedia extends StatelessWidget {
  final Pack pack;
  final String? popularLabel;

  /// A bundled regional photo, used when the backend gives this pack none.
  final String? fallbackAsset;

  /// 128 in a pack card (63:88); taller as a screen's hero (66:210).
  final double height;
  final BorderRadius borderRadius;

  const PackMedia({
    super.key,
    required this.pack,
    this.popularLabel,
    this.fallbackAsset,
    this.height = 128,
    this.borderRadius = const BorderRadius.all(Radius.circular(Radii.media)),
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final s = ShopTokens.of(context);
    final url = pack.coverImageUrl;
    final asset = fallbackAsset;
    // Decoded at the size it is drawn at, not the size it was stored at.
    final cacheWidth =
        (MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context)).round();
    final hasPhoto = url != null || asset != null;

    return SizedBox(
      height: height,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: s.fill.withValues(alpha: 0.05)),
            if (url != null)
              ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 1, sigmaY: 1),
                child: Image.network(
                url,
                fit: BoxFit.cover,
                // A 2000px hero scaled into a 160dp band costs ~16MB of image
                // cache per pack without cacheWidth, and the cache evicts the
                // ones still on screen to make room.
                cacheWidth: cacheWidth,
                // Keeps the previous frame while a new one decodes instead of
                // flashing back to the placeholder on every rebuild.
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => _Wash(s: s),
                ),
              )
            else if (asset != null)
              ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 1, sigmaY: 1),
                child: Image.asset(
                  asset,
                  fit: BoxFit.cover,
                  cacheWidth: cacheWidth,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => _Wash(s: s),
                ),
              )
            else
              _Wash(s: s),
            Container(color: s.fill.withValues(alpha: 0.40)),
            Center(child: _GlassBadge(frosted: hasPhoto)),
            if (pack.isPopular && popularLabel != null)
              PositionedDirectional(
                top: Gap.md,
                end: Gap.md,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 2),
                  decoration: BoxDecoration(
                    color: t.cta,
                    borderRadius: BorderRadius.circular(Radii.pill),
                    boxShadow: Shadows.badge,
                  ),
                  // Badge text uses the premium token — which is what the design
                  // does too, rather than inventing a sixth colour.
                  child: Text(
                    popularLabel!.toUpperCase(),
                    style: AppType.captionStrong.copyWith(color: t.premiumAccent, letterSpacing: 0),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 48x64, radius 8, white at 20% behind a 40% white edge, lifted by the card
/// shadow; the SIM glyph is 20x25 inside it (63:90).
class _GlassBadge extends StatelessWidget {
  final bool frosted;
  const _GlassBadge({required this.frosted});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final radius = BorderRadius.circular(Radii.chip);
    final badge = Container(
      width: 48,
      height: 64,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: t.onPrimary.withValues(alpha: 0.20),
        borderRadius: radius,
        border: Border.all(color: t.onPrimary.withValues(alpha: 0.40)),
      ),
      // Material's sim_card glyph occupies 16x20 of its 24 grid, so 30 draws
      // it at the frame's 20x25.
      child: SizedBox(
        width: 20,
        height: 25,
        child: OverflowBox(
          maxWidth: 30,
          maxHeight: 30,
          child: Icon(Icons.sim_card, size: 30, color: t.onPrimary),
        ),
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: radius, boxShadow: Shadows.card),
      child: frosted
          ? ClipRRect(
              borderRadius: radius,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                child: badge,
              ),
            )
          : badge,
    );
  }
}

class _Wash extends StatelessWidget {
  final ShopTokens s;
  const _Wash({required this.s});

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [s.fill, s.fillEnd],
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
        // 63:101: a 16.67 x 18.67 box whose glyph sits 2px down. Material's
        // glyphs fill 20 of their 24 grid, so a 20px icon draws them at 16.67.
        SizedBox(
          width: 50 / 3,
          height: 56 / 3,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: -5 / 3,
                top: 2 - 5 / 3,
                child: Icon(icon, size: 20, color: ShopTokens.of(context).fill),
              ),
            ],
          ),
        ),
        const SizedBox(width: Gap.sm),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(value, style: AppType.specValue.copyWith(color: t.primary)),
            Text(label, style: AppType.label.copyWith(color: t.inkFaint)),
          ],
        ),
      ],
    );
  }
}

/// The dark rounded price pill from the design.
class PricePill extends ConsumerWidget {
  final Money price;
  const PricePill({super.key, required this.price});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTokens.of(context);
    final s = ShopTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.xs),
      decoration: BoxDecoration(
        color: s.priceBadge,
        borderRadius: BorderRadius.circular(Radii.pill),
        boxShadow: Shadows.badge,
        // A white tag on a white card needs its edge drawn.
        border: s.priceBadge == t.card ? Border.all(color: t.fieldBorder) : null,
      ),
      child: Text(
        price.format(ref.watch(languageProvider)),
        style: AppType.priceTag.copyWith(color: s.onPriceBadge),
      ),
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
                    Text(
                      countryName(destination.code, l10n.language, fallback: destination.name),
                      style: AppType.bodyStrong.copyWith(color: t.primary),
                    ),
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
                    Text(
                      cheapest.format(l10n.language),
                      style: AppType.bodyStrong.copyWith(color: ShopTokens.of(context).display),
                    ),
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
