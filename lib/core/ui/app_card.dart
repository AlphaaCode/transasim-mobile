/// Surfaces: the ground a screen sits on, and the card that floats on it.
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The auth ground — the brand's accent falling to its surface.
///
/// Welcome draws this gradient; Log In and Sign Up draw a flat cream. Applied
/// to all three, because the flat version is what the gradient looks like when
/// nobody got round to it, and a gradient is free.
class AppScreenGradient extends StatelessWidget {
  final Widget child;

  const AppScreenGradient({super.key, required this.child});

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(gradient: AppTokens.of(context).screenGradient),
    child: child,
  );
}

/// A white card with the design's two-layer lift.
///
/// [glow] adds the pair of ambient blooms Log In carries behind its content: a
/// mint one out of the top-right corner, a call-to-action one out of the
/// bottom-left. They are the single easiest detail to lose on a
/// re-implementation, because nothing in the colour tokens implies them.
///
/// Figma draws them as two 128px circles under a 20px layer blur. They are
/// painted here as radial gradients instead: identical to the eye, and it
/// avoids an `ImageFilter` — which forces a `saveLayer` on every frame of a
/// screen that scrolls and animates a keyboard in and out.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool glow;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Gap.xl),
    this.glow = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final radius = BorderRadius.circular(Radii.control);

    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: radius, boxShadow: Shadows.float(t.primary)),
      child: ClipRRect(
        borderRadius: radius,
        child: ColoredBox(
          color: t.card,
          child: Stack(
            children: [
              if (glow) ...[
                _Bloom(color: t.accent, opacity: 0.5, alignment: Alignment.topRight),
                _Bloom(color: t.cta, opacity: 0.2, alignment: Alignment.bottomLeft),
              ],
              Padding(padding: padding, child: child),
            ],
          ),
        ),
      ),
    );
  }
}

/// One 256px bloom anchored to a corner, half of it clipped away by the card —
/// which is what a blurred 128px circle sitting on the corner looks like.
class _Bloom extends StatelessWidget {
  final Color color;
  final double opacity;
  final AlignmentGeometry alignment;

  const _Bloom({required this.color, required this.opacity, required this.alignment});

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: Align(
      alignment: alignment,
      child: IgnorePointer(
        child: Container(
          height: 256,
          width: 256,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: <Color>[
                color.withValues(alpha: opacity),
                color.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// The dark sheet that rises from the bottom of Welcome: the brand's primary,
/// rounded at the top only, lifted by an upward shadow in the brand's own hue.
class AppBottomSheetCard extends StatelessWidget {
  final Widget child;

  const AppBottomSheetCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: t.primary,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(Radii.sheet)),
        boxShadow: t.sheetShadow,
      ),
      child: SafeArea(
        top: false,
        child: Padding(padding: const EdgeInsets.all(Gap.xxl), child: child),
      ),
    );
  }
}

/// The round, translucent badge Welcome sets its logo inside — accent at 20%
/// behind a hairline of the same hue, lifted off the gradient.
///
/// Not the logo on the background: the badge is what makes the mark read as
/// placed rather than pasted, and it is brand-agnostic because both the fill
/// and the border come from the accent role.
class AppLogoBadge extends StatelessWidget {
  final Widget child;
  final double size;

  const AppLogoBadge({super.key, required this.child, this.size = 192});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Container(
      height: size,
      width: size,
      // 63:536: the mark fills the circle edge to edge, inside the 1px border
      // and nothing else. This was 20% padding which, on top of the asset's own
      // transparent margin, left the disc at half the badge's width.
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: t.accent.withValues(alpha: 0.2),
        border: Border.all(color: t.accent.withValues(alpha: 0.35)),
        // Not Shadows.card: two 10% layers under a circle on a pale gradient
        // read as a grey ring, not a lift.
        boxShadow: Shadows.field,
      ),
      child: ClipOval(child: SizedBox.expand(child: child)),
    );
  }
}

/// The three-dot step indicator from `Sign Up - Sabily (Mobile)` (52:374).
///
/// Figma's exact geometry: every dot 6px tall and pill-shaped, the active one
/// 24px wide and the rest 8px, 4px apart. Colours resolved through the brand —
/// the frame draws the active dot #004d40, which is the fourth teal §2.2
/// already arbitrated, and the track #eae3c4, which is what [AppTokens
/// .hairline] already is: a structural line on the cream ground.
class AppStepDots extends StatelessWidget {
  final int count;
  final int current;

  /// Read out for screen readers, which cannot see a row of dots.
  final String semanticLabel;

  const AppStepDots({
    super.key,
    required this.count,
    required this.current,
    required this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Semantics(
      label: semanticLabel,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < count; i++) ...[
            if (i > 0) const SizedBox(width: Gap.xs),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              height: 6,
              width: i == current ? 24 : 8,
              decoration: BoxDecoration(
                color: i == current ? t.primary : t.hairline,
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A value card, as Become a Partner (52:656) draws it: white, 12 radius, 24
/// padding, a soft teal lift; a 48px tile with an 8 radius holding the glyph;
/// a 20/28 heading over a 14/20 supporting line.
class AppFeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback? onTap;
  final Widget? trailing;

  /// The tile's ground. 52:639 alternates accent and surface.
  final Color? tileColor;

  /// The glyph on that tile. Defaults to the brand's primary; a gold tile
  /// takes the gold accent, so the pair reads as one warm treatment rather
  /// than a teal icon stranded on cream.
  final Color? iconColor;

  /// Replaces the white card ground. One card on a screen can take
  /// [AppTokens.accentGradient] to stop reading as another row in the list —
  /// Store's multi-country entry does, because it is the one card there that
  /// is an offer rather than a destination.
  final Gradient? gradient;

  const AppFeatureCard({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.onTap,
    this.trailing,
    this.tileColor,
    this.iconColor,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final radius = BorderRadius.circular(Radii.tile);

    return AppPressable(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          // Floating, not merely lifted: the redesign separates every card
          // from the cream page by height alone, with no outline anywhere.
          boxShadow: Shadows.float(t.primary),
          gradient: gradient,
          // The gradient is painted by this box, so the Material above it has
          // to be see-through rather than white — `transparency`, not a
          // transparent colour literal, which C2 would reject.
          color: gradient == null ? t.card : null,
        ),
        child: Material(
          type: gradient == null ? MaterialType.canvas : MaterialType.transparency,
          color: gradient == null ? t.card : null,
          borderRadius: gradient == null ? radius : null,
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(Gap.xl),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: tileColor ?? t.surface,
                      borderRadius: BorderRadius.circular(Radii.chip),
                    ),
                    child: Icon(icon, color: iconColor ?? t.primary, size: 24),
                  ),
                  const SizedBox(width: Gap.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: AppType.cardTitle.copyWith(color: t.primary)),
                        const SizedBox(height: Gap.xs),
                        Text(body, style: AppType.prose.copyWith(color: t.inkMuted)),
                      ],
                    ),
                  ),
                  if (trailing != null) ...[const SizedBox(width: Gap.sm), trailing!],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A section label: small, upper case, widely tracked — PREFERENCES,
/// ALL DESTINATIONS, GOOD TO KNOW, VALIDITY.
///
/// One widget because the shape was written out four times in four screens
/// with three different letter-spacings, which is how a heading starts
/// meaning something slightly different on each page. Upper-casing happens
/// here rather than in the string files so translators are never asked to
/// shout: Turkish and Greek do not upper-case the way `toUpperCase` does in
/// every locale, and the day that matters it is one method to fix, not seven
/// language maps.
class AppEyebrow extends StatelessWidget {
  final String label;

  const AppEyebrow(this.label, {super.key});

  @override
  Widget build(BuildContext context) => Text(
    label.toUpperCase(),
    style: AppType.captionStrong.copyWith(
      color: AppTokens.of(context).inkMuted,
      letterSpacing: 0.88,
    ),
  );
}

/// Scales its child down a touch while it is held.
///
/// The cards in this app are tappable surfaces, and a tappable surface that
/// does not move under the finger reads as a picture of a card. Material's
/// ink splash alone does not carry on a white card over cream — the ripple
/// is almost invisible against it.
///
/// 0.97 and 110ms: enough to feel, short enough that a scrolling list does
/// not appear to wobble. The press is cancelled on drag, so starting a
/// scroll from on top of a card does not shrink it.
class AppPressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  const AppPressable({super.key, required this.child, required this.onTap});

  @override
  State<AppPressable> createState() => _AppPressableState();
}

class _AppPressableState extends State<AppPressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null) return widget.child;
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
