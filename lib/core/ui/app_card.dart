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
      decoration: BoxDecoration(borderRadius: radius, boxShadow: Shadows.card),
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
        child: Padding(
          padding: const EdgeInsets.all(Gap.xxl),
          child: child,
        ),
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
      padding: EdgeInsets.all(size * 0.2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: t.accent.withValues(alpha: 0.2),
        border: Border.all(color: t.accent.withValues(alpha: 0.35)),
        // Not Shadows.card: two 10% layers under a circle on a pale gradient
        // read as a grey ring, not a lift.
        boxShadow: Shadows.field,
      ),
      child: child,
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
