/// The app's buttons. Every tappable action in `lib/modules/` is one of these.
///
/// Built once, here, because the Sabily frames do not agree with themselves:
/// Log In draws its submit 48px tall at radius 8, Sign Up draws the same
/// control 56px tall at radius 12, and Welcome draws a white pill. Styling each
/// screen to its own frame would ship three buttons that are almost the same,
/// which is how the old app reached 894 colour decisions across 39 files.
///
/// One resolution, applied everywhere: 56/12 for a filled action, because at
/// 48/8 the submit is the same size and shape as the field above it and stops
/// reading as the end of the form.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Which role the button plays. Not which colour it is — a brand supplies the
/// colours and only the roles are fixed.
enum AppButtonTone {
  /// The brand's primary, with [AppTokens.onPrimary] on it. Account actions:
  /// sign in, create account, verify.
  primary,

  /// The brand's call-to-action pair. Commerce only — buy, pay, top up.
  /// Sabily's is yellow; another brand's need not be.
  cta,

  /// The shop's secondary action (top-up): [ShopTokens.cta]. The brand's CTA
  /// unless its `theme.shop` says otherwise — eSimple's shop buttons are navy.
  shop,

  /// A button that leads to paying: [ShopTokens.buy]. The brand's primary
  /// unless its `theme.shop` gives commerce its own colour.
  buy,

  /// A light button on a dark ground, as Welcome's sheet needs. Fully round.
  onDark,

  /// Outlined, neutral ink: "Continue with Google", "Continue with Apple".
  /// A second and third filled button beside the form's own submit would make
  /// three equal calls to action out of one decision.
  social,

  /// Outlined, in the danger colour. Signing out and anything else a user
  /// should not hit by reflex — filled would give it the weight of the action
  /// the screen actually wants.
  danger,
}

class AppButton extends StatelessWidget {
  final String label;

  /// `null` disables the button, which is also how a form says "not yet valid".
  final VoidCallback? onPressed;

  final AppButtonTone tone;

  /// Leading icon, at the design's 20px.
  final IconData? icon;

  /// Trailing icon. Sign Up's "Continue to Security" carries an arrow.
  final IconData? trailingIcon;

  /// Swaps the label for a spinner and ignores taps. The label still occupies
  /// its width, so the button does not resize mid-request.
  final bool busy;

  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.tone = AppButtonTone.primary,
    this.icon,
    this.trailingIcon,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final enabled = onPressed != null && !busy;

    final (Color fill, Color ink) = switch (tone) {
      AppButtonTone.primary => (t.primary, t.onPrimary),
      AppButtonTone.cta => (t.cta, t.ctaText),
      AppButtonTone.shop => (ShopTokens.of(context).cta, ShopTokens.of(context).ctaText),
      AppButtonTone.buy => (ShopTokens.of(context).buy, ShopTokens.of(context).onBuy),
      AppButtonTone.onDark => (t.card, t.primary),
      AppButtonTone.social => (t.card, t.ink),
      AppButtonTone.danger => (t.surface, t.danger),
    };
    final outlined = tone == AppButtonTone.danger || tone == AppButtonTone.social;

    final radius = tone == AppButtonTone.onDark
        ? BorderRadius.circular(Radii.pill)
        : BorderRadius.circular(Radii.control);

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Opacity(
        // Disabled is dimmed rather than recoloured, so a brand's CTA stays
        // recognisably its own colour while it is unavailable.
        opacity: enabled ? 1 : 0.45,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: !enabled || outlined
                ? Shadows.none
                : tone == AppButtonTone.onDark
                    ? Shadows.field
                    : Shadows.control,
          ),
          // `shape` only, never `shape` AND `borderRadius`: Material asserts
          // on both being set, and passing the pair crashed the outlined tone
          // at runtime while every other tone rendered fine.
          child: Material(
            color: fill,
            shape: RoundedRectangleBorder(
              borderRadius: radius,
              side: outlined ? BorderSide(color: t.hairline) : BorderSide.none,
            ),
            child: InkWell(
              onTap: enabled ? onPressed : null,
              borderRadius: radius,
              child: SizedBox(
                height: kAppButtonHeight,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Gap.xl),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null && !busy) ...[
                          Icon(icon, size: 20, color: ink),
                          const SizedBox(width: Gap.md),
                        ],
                        Flexible(
                          child: busy
                              ? SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: ink),
                                )
                              : Text(
                                  label,
                                  style: AppType.labelStrong.copyWith(color: ink),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                ),
                        ),
                        if (trailingIcon != null && !busy) ...[
                          const SizedBox(width: Gap.sm),
                          Icon(trailingIcon, size: 16, color: ink),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 56, from Sign Up's primary action. Exported so a screen can reserve the
/// space without guessing it.
const double kAppButtonHeight = 56;

/// A button that reads as text: "Forgot password?", "Sign up", "Resend code".
///
/// Padded out to a 48px tap target even though the text is 20px tall — the
/// design draws these as bare text, and bare text at 14px is not tappable.
class AppLinkButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  /// Set on a dark ground, where the brand's primary would disappear.
  final bool onDark;

  const AppLinkButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.onDark = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
        tapTargetSize: MaterialTapTargetSize.padded,
        foregroundColor: onDark ? t.card : t.primary,
        textStyle: AppType.labelStrong,
      ),
      child: Text(label, style: AppType.labelStrong),
    );
  }
}

/// A sentence with one tappable word at the end — "Don't have an account?
/// Sign up". One widget because the design uses the shape four times and each
/// half is a different family: prose in Noto Sans, the link in IBM Plex Sans.
///
/// ONE text block, not a [Row] of two widgets. It was a Row, and a Row can only
/// break BETWEEN its children: on a 360dp phone in French, "Pas encore de
/// compte ?" did not fit beside "Créer le compte", so the prompt wrapped inside
/// its own [Flexible] and the footer read
///
/// ```
///       Pas encore de
///   compte ?  Créer le compte
/// ```
///
/// As one paragraph it breaks where a sentence breaks, and at these widths it
/// does not break at all.
///
/// The cost, recorded rather than hidden: the tappable area is now the action
/// span's own box, around 20px tall, instead of [AppLinkButton]'s padded 48px.
/// Standalone links — "Forgot password?", "Resend code" — still use that button
/// and keep the full target.
class AppInlineLink extends StatefulWidget {
  final String prompt;
  final String action;
  final VoidCallback onPressed;
  final bool onDark;

  const AppInlineLink({
    super.key,
    required this.prompt,
    required this.action,
    required this.onPressed,
    this.onDark = false,
  });

  @override
  State<AppInlineLink> createState() => _AppInlineLinkState();
}

class _AppInlineLinkState extends State<AppInlineLink> {
  /// A field, and disposed: a recogniser built inside `build` leaks one per
  /// rebuild, and this widget rebuilds on every keystroke in the form above it.
  late final TapGestureRecognizer _tap = TapGestureRecognizer()
    ..onTap = () => widget.onPressed();

  @override
  void dispose() {
    _tap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Padding(
      // A comfortable strip around a target that is now text-sized.
      padding: const EdgeInsets.symmetric(vertical: Gap.sm),
      child: Text.rich(
        TextSpan(
          // 14, matching the link beside it rather than the 16 of body prose:
          // at 16 the French sentence is wider than the 280dp this footer gets
          // inside the sign-in card on a 360dp phone, and no amount of
          // re-flowing fixes a line that does not fit.
          style: AppType.prose.copyWith(color: widget.onDark ? t.onPrimaryMuted : t.inkMuted),
          children: [
            TextSpan(text: '${widget.prompt} '),
            TextSpan(
              text: widget.action,
              style: AppType.labelStrong.copyWith(color: widget.onDark ? t.card : t.primary),
              recognizer: _tap,
            ),
          ],
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

/// A filter chip, as White-Label Store Template's Filter Section (66:54) draws
/// it: a pill, the primary fill when selected, the recessed ground with a field
/// border when not.
class AppFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const AppFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final shape = StadiumBorder(
      side: selected ? BorderSide.none : BorderSide(color: t.fieldBorder),
    );

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        // The active chip is the shop's fill: its only filled control.
        color: selected ? ShopTokens.of(context).fill : t.chipSurface,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: Padding(
            // 16 x 9; the unselected 1px border is painted inside the same
            // outer size, as the template does (17 x 9 there, border included).
            padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: 9),
            child: Text(
              label,
              style: AppType.chip.copyWith(
                color: selected ? ShopTokens.of(context).onFill : t.inkMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A horizontally scrolling row of chips, 12 apart (66:54).
class AppChipRow extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  const AppChipRow({super.key, required this.children, this.padding = EdgeInsets.zero});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: padding,
        child: Row(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: Gap.md),
              children[i],
            ],
          ],
        ),
      );
}
