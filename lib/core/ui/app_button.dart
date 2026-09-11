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

  /// A light button on a dark ground, as Welcome's sheet needs. Fully round.
  onDark,

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
      AppButtonTone.onDark => (t.card, t.primary),
      AppButtonTone.danger => (t.surface, t.danger),
    };
    final outlined = tone == AppButtonTone.danger;

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
class AppInlineLink extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            prompt,
            style: AppType.body.copyWith(color: onDark ? t.onPrimaryMuted : t.inkMuted),
            textAlign: TextAlign.end,
          ),
        ),
        AppLinkButton(label: action, onPressed: onPressed, onDark: onDark),
      ],
    );
  }
}
