/// The theme is DERIVED from [BrandConfig]. It is never written.
///
/// ARCHITECTURE-MOBILE.md §2.2 / brief §5.7. This file is the ONLY place in
/// `lib/` allowed to contain a colour literal, and CI check C2 enforces that
/// (`tool/check_layers.dart`). The old app accumulated 894 colour decisions
/// across 39 files, all frozen at compile time — centralised, but unchangeable
/// without a store submission (`ANALYSE-EXISTANT.md` §4.4).
///
/// Third-party SDKs do not read [ThemeData]. Stripe's PaymentSheet, WebViews
/// and system notifications must be handed values explicitly from [AppTokens],
/// as data — the old app hardcoded `#015552` into the Stripe sheet, matching
/// nothing in its own theme.
library;

import 'package:flutter/material.dart';

import '../brand/brand_config.dart';


/// Semantic colours and structural greys are SOCLE decisions, not brand
/// decisions, so they live here and not in `brand.json` (§2.3).
///
/// They become configurable the day a client asks — not before. The hygiene
/// rule applies to design tokens too: nothing enters the config unless code
/// reads it and a client has a reason to change it.
abstract final class _Socle {
  static const danger = Color(0xFFB3261E);
  static const success = Color(0xFF2E7D32);
  static const warning = Color(0xFFED6C02);

  static const ink = Color(0xFF1B1C1B);

  /// #3f4948 — read off both Sabily auth frames, where it carries subtext,
  /// field labels and footer copy. A neutral, so it is socle-owned.
  static const inkMuted = Color(0xFF3F4948);
  static const card = Color(0xFFFFFFFF);
  static const onPrimary = Color(0xFFFFFFFF);

  /// Premium register: deliberately cream-and-gold, detached from the brand
  /// palette. A brand that writes nothing gets exactly this (§2.3).
  static const premiumSurface = Color(0xFFFFF9E8);
  static const premiumAccent = Color(0xFF735C00);
  static const premiumText = Color(0xFF1E1C09);

  /// A QR code is read by a camera, not by a person, and ISO/IEC 18004 wants
  /// maximum luminance contrast. Tinting one to the brand is how a code ends
  /// up rejected by a scanner that was working a moment ago — so these two are
  /// deliberately NOT derived from the palette, and deliberately not
  /// configurable. The only brand-neutral values in the file, on purpose.
  static const qrForeground = Color(0xFF000000);
  static const qrBackground = Color(0xFFFFFFFF);
}

/// The resolved token set handed to widgets and to third-party SDKs.
///
/// Widgets read tokens; they never compute a colour.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  // Brand roles (§2.2)
  final Color primary;
  final Color accent;
  final Color surface;
  final Color cta;
  final Color ctaText;

  // Socle-owned
  final Color danger;
  final Color success;
  final Color warning;
  final Color ink;
  final Color inkMuted;
  final Color hairline;
  final Color card;
  final Color onPrimary;

  /// Outline of a control sitting on [card]. [hairline] is blended into the
  /// cream ground and is the wrong value on white — the design draws inputs
  /// with a distinctly cooler, darker edge than it draws dividers.
  final Color fieldBorder;

  /// Placeholder and other text that must recede without becoming unreadable.
  final Color inkFaint;

  /// Text on the [primary] ground that is deliberately secondary — the legal
  /// line under Welcome's call to action.
  final Color onPrimaryMuted;

  /// An unselected filter chip: the brand ground, one step recessed. The
  /// template draws #f0edec on a near-white page; a literal grey would look
  /// dirty on cream, so it is the same ink-into-ground move, on this brand's
  /// own ground.
  final Color chipSurface;

  /// Fixed black-on-white. See `_Socle.qrForeground`.
  final Color qrForeground;
  final Color qrBackground;

  // Premium: brand override if present, socle default otherwise
  final Color premiumSurface;
  final Color premiumAccent;
  final Color premiumText;

  const AppTokens({
    required this.primary,
    required this.accent,
    required this.surface,
    required this.cta,
    required this.ctaText,
    required this.danger,
    required this.success,
    required this.warning,
    required this.ink,
    required this.inkMuted,
    required this.hairline,
    required this.card,
    required this.onPrimary,
    required this.fieldBorder,
    required this.inkFaint,
    required this.onPrimaryMuted,
    required this.chipSurface,
    required this.qrForeground,
    required this.qrBackground,
    required this.premiumSurface,
    required this.premiumAccent,
    required this.premiumText,
  });

  factory AppTokens.from(BrandConfig brand) => AppTokens(
        primary: brand.colors.primary,
        accent: brand.colors.accent,
        surface: brand.colors.surface,
        cta: brand.colors.cta,
        ctaText: brand.colors.ctaText,
        danger: _Socle.danger,
        success: _Socle.success,
        warning: _Socle.warning,
        ink: _Socle.ink,
        inkMuted: _Socle.inkMuted,
        // Derived, not fixed. The design's card border is a cream-tinted
        // hairline because the surface is cream; a fixed grey would look wrong
        // the day a client arrives with a cool palette. Blending the anchor
        // colour into the brand's own surface follows the brand automatically.
        hairline: Color.alphaBlend(
          brand.colors.primary.withValues(alpha: 0.14),
          brand.colors.surface,
        ),
        card: _Socle.card,
        onPrimary: _Socle.onPrimary,
        // Figma draws this #bfc9c7. Written as a literal it would be a fifth
        // hand-picked value in a file that already disagrees with itself; the
        // same anchor-into-ground blend that produces [hairline], taken onto
        // white instead of cream, lands within a shade of it and follows a
        // client whose palette is nothing like this one.
        fieldBorder: Color.alphaBlend(
          brand.colors.primary.withValues(alpha: 0.25),
          _Socle.card,
        ),
        inkFaint: Color.lerp(_Socle.inkMuted, _Socle.card, 0.22)!,
        // Figma draws this #90d2ce — a fifth teal, and the same problem as the
        // #004d40 the mapping in §2.2 already settled. Derived from the accent
        // over the primary ground instead, so it cannot carry one client's hue
        // into another client's build.
        onPrimaryMuted: Color.alphaBlend(
          brand.colors.accent.withValues(alpha: 0.82),
          brand.colors.primary,
        ),
        chipSurface: Color.alphaBlend(
          _Socle.inkMuted.withValues(alpha: 0.06),
          brand.colors.surface,
        ),
        qrForeground: _Socle.qrForeground,
        qrBackground: _Socle.qrBackground,
        premiumSurface: brand.theme.premiumSurface ?? _Socle.premiumSurface,
        premiumAccent: brand.theme.premiumAccent ?? _Socle.premiumAccent,
        premiumText: brand.theme.premiumText ?? _Socle.premiumText,
      );

  static AppTokens of(BuildContext context) => Theme.of(context).extension<AppTokens>()!;

  /// The auth ground: accent at the top falling to the brand surface.
  ///
  /// Figma runs #d2f5ec -> #fff9e8. The second stop is NOT this brand's
  /// surface (#f9f2d3) — it is a lighter cream the file introduced on its own,
  /// the same class of drift as the #004d40 heading. Both ends are read from
  /// the config here, so the gradient is the brand's two creams and not
  /// Sabily's.
  LinearGradient get screenGradient => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[accent, surface],
      );

  /// The upward shadow under a sheet that rises from the bottom of the screen.
  /// Tinted with the brand's own primary rather than neutral black.
  List<BoxShadow> get sheetShadow => <BoxShadow>[
        BoxShadow(
          color: primary.withValues(alpha: 0.15),
          blurRadius: 15,
          offset: const Offset(0, -8),
        ),
      ];

  @override
  AppTokens copyWith({Color? primary, Color? accent, Color? surface, Color? cta, Color? ctaText}) =>
      AppTokens(
        primary: primary ?? this.primary,
        accent: accent ?? this.accent,
        surface: surface ?? this.surface,
        cta: cta ?? this.cta,
        ctaText: ctaText ?? this.ctaText,
        danger: danger,
        success: success,
        warning: warning,
        ink: ink,
        inkMuted: inkMuted,
        hairline: hairline,
        card: card,
        onPrimary: onPrimary,
        fieldBorder: fieldBorder,
        inkFaint: inkFaint,
        onPrimaryMuted: onPrimaryMuted,
        chipSurface: chipSurface,
        qrForeground: qrForeground,
        qrBackground: qrBackground,
        premiumSurface: premiumSurface,
        premiumAccent: premiumAccent,
        premiumText: premiumText,
      );

  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) return this;
    return AppTokens(
      primary: Color.lerp(primary, other.primary, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      cta: Color.lerp(cta, other.cta, t)!,
      ctaText: Color.lerp(ctaText, other.ctaText, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      inkMuted: Color.lerp(inkMuted, other.inkMuted, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      card: Color.lerp(card, other.card, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      fieldBorder: Color.lerp(fieldBorder, other.fieldBorder, t)!,
      inkFaint: Color.lerp(inkFaint, other.inkFaint, t)!,
      onPrimaryMuted: Color.lerp(onPrimaryMuted, other.onPrimaryMuted, t)!,
      chipSurface: Color.lerp(chipSurface, other.chipSurface, t)!,
      // Not lerped: a QR mid-transition between two greys is a QR that does
      // not scan.
      qrForeground: qrForeground,
      qrBackground: qrBackground,
      premiumSurface: Color.lerp(premiumSurface, other.premiumSurface, t)!,
      premiumAccent: Color.lerp(premiumAccent, other.premiumAccent, t)!,
      premiumText: Color.lerp(premiumText, other.premiumText, t)!,
    );
  }
}

/// 4pt spacing scale. The old app had no scale — inline literals whose
/// distribution was ~85% compatible with 4/8pt, so layouts port without a
/// fight (`ANALYSE-EXISTANT.md` §4.5 note).
/// Corner radii, from the same frames: cards 24, media and buttons 16,
/// small chips 8, pills fully round.
abstract final class Radii {
  static const double card = 24;
  static const double media = 16;
  static const double control = 16;
  static const double chip = 8;
  static const double pill = 9999;

  /// The bottom sheet on Welcome. Top corners only.
  static const double sheet = 40;
}

/// Elevation, as the design draws it. Two-layer shadows, so the near layer
/// gives the edge and the far layer gives the lift.
///
/// They live here because a `Colors.*` reference outside this file is a CI
/// violation (check C2) — which is the right outcome: a shadow is a design
/// token, not something a widget invents.
abstract final class Shadows {
  /// A raised card. 0 10px 15px -3px / 0 4px 6px -4px, both black at 10%.
  static final List<BoxShadow> card = <BoxShadow>[
    BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 15, spreadRadius: -3,
        offset: const Offset(0, 10)),
    BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 6, spreadRadius: -4,
        offset: const Offset(0, 4)),
  ];

  /// A primary control. 0 4px 6px -1px / 0 2px 4px -2px.
  static final List<BoxShadow> control = <BoxShadow>[
    BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 6, spreadRadius: -1,
        offset: const Offset(0, 4)),
    BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4, spreadRadius: -2,
        offset: const Offset(0, 2)),
  ];

  /// An input. Barely there: 0 1px 2px at 5%.
  static final List<BoxShadow> field = <BoxShadow>[
    BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 2, offset: const Offset(0, 1)),
  ];

  static const List<BoxShadow> none = <BoxShadow>[];
}

abstract final class Gap {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Named text styles. There is no inline `fontSize:` anywhere else in `lib/`,
/// and CI check C2b enforces that.
///
/// The old app had ZERO named styles and 288 inline literals across 14 distinct
/// sizes (`ANALYSE-EXISTANT.md` §4.5).
///
/// THREE FAMILIES, BY ROLE — this is a deliberate system in the Sabily frames,
/// not three batches of mockups drifting apart:
///
///   Be Vietnam Pro  headlines only. Nothing under 20px uses it.
///   IBM Plex Sans   UI chrome: field labels, buttons, links, legal text.
///   Noto Sans       prose: subtitles, body copy, placeholders.
///
/// ARCHITECTURE-MOBILE.md §5.7 previously collapsed all three to Noto Sans on
/// the grounds that only Noto pairs with an Arabic face. That reasoning was
/// wrong: `fontFamilyFallback` resolves PER GLYPH, so an Arabic string inside a
/// Be Vietnam Pro style renders in Noto Sans Arabic while the Latin around it
/// renders in Be Vietnam Pro. Every style below therefore carries the fallback,
/// and the design's hierarchy survives in all seven languages.
abstract final class AppType {
  /// Headline family. Latin only — Arabic falls through to [fallback].
  static const String displayFamily = 'BeVietnamPro';

  /// UI chrome family. Latin only — Arabic falls through to [fallback].
  static const String uiFamily = 'IBMPlexSans';

  /// Prose family, and the app-wide default.
  static const String family = 'NotoSans';

  /// Arabic coverage for all three.
  ///
  /// ARCHITECTURE-MOBILE.md §12.6 recorded that NO Arabic-capable typeface was
  /// specified anywhere — the old app named bare 'Roboto' and relied on
  /// per-platform fallback, which differs between Android and iOS. Bundling the
  /// family removes that variance and keeps the app correct offline.
  static const List<String> fallback = <String>['NotoSansArabic'];

  static const TextStyle _display =
      TextStyle(fontFamily: displayFamily, fontFamilyFallback: fallback);
  static const TextStyle _ui = TextStyle(fontFamily: uiFamily, fontFamilyFallback: fallback);
  static const TextStyle _body = TextStyle(fontFamily: family, fontFamilyFallback: fallback);

  // Sizes, weights, line heights and tracking are the computed values read
  // from the Sabily-branded frames, not invented.

  /// 32/40 — the largest thing on a screen.
  static final TextStyle display =
      _display.copyWith(fontSize: 32, height: 40 / 32, fontWeight: FontWeight.w700);

  /// 28/36, -0.7 tracking — "Welcome Back", "Create Account",
  /// "Log in or sign up". The one headline size the auth flow uses.
  static final TextStyle hero = _display.copyWith(
      fontSize: 28, height: 36 / 28, fontWeight: FontWeight.w600, letterSpacing: -0.7);

  /// 24/32 — screen and section titles.
  static final TextStyle title =
      _display.copyWith(fontSize: 24, height: 32 / 24, fontWeight: FontWeight.w600);

  /// 20/25 — card titles.
  static final TextStyle heading =
      _display.copyWith(fontSize: 20, height: 25 / 20, fontWeight: FontWeight.w700);

  /// 18/27 — price pills.
  static final TextStyle subtitle = _body.copyWith(fontSize: 18, height: 27 / 18);

  /// 18/28 semibold — the pack name and the total on the checkout summary.
  static final TextStyle subtitleStrong =
      _body.copyWith(fontSize: 18, height: 28 / 18, fontWeight: FontWeight.w600);

  /// 16/24 — paragraph copy. "Sign in to continue your journey".
  static final TextStyle body = _body.copyWith(fontSize: 16, height: 24 / 16);
  static final TextStyle bodyStrong =
      _body.copyWith(fontSize: 16, height: 24 / 16, fontWeight: FontWeight.w600);

  /// 16 — what an empty input says. Prose, not chrome: the design sets
  /// placeholders in Noto Sans Regular at the value's own size, so the text
  /// does not jump family or size once the user types.
  static final TextStyle placeholder = _body.copyWith(fontSize: 16, height: 24 / 16);

  /// 14/20, +0.28 — field labels and legal text.
  static final TextStyle label = _ui.copyWith(
      fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500, letterSpacing: 0.28);

  /// 14/20, +0.28, semibold — button labels and links.
  static final TextStyle labelStrong = _ui.copyWith(
      fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600, letterSpacing: 0.28);

  static final TextStyle caption =
      _ui.copyWith(fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w500,
          color: _Socle.inkMuted);
  static final TextStyle captionStrong = _ui.copyWith(
      fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w600, letterSpacing: 0.24);

  /// 12/16, medium, +0.6 — filter chips (66:54). The template sets Inter; UI
  /// chrome in this socle is IBM Plex Sans, so the family maps and the metrics
  /// carry over.
  static final TextStyle chip = _ui.copyWith(
      fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w500, letterSpacing: 0.6);
}

/// Build the app theme from a brand configuration.
///
/// Dark mode is deliberately NOT produced. ARCHITECTURE-MOBILE.md §12.1
/// recommends it stay explicitly off for v1, for all clients: a half-done dark
/// mode costs more than an absent one, and the target palette is built on a
/// light cream ground. The app pins `themeMode: ThemeMode.light` so the OS
/// setting cannot half-apply one.
ThemeData buildTheme(BrandConfig brand) {
  final t = AppTokens.from(brand);

  final scheme = ColorScheme.fromSeed(
    seedColor: t.primary,
    brightness: Brightness.light,
  ).copyWith(
    primary: t.primary,
    onPrimary: t.onPrimary,
    secondary: t.accent,
    onSecondary: t.primary,
    surface: t.card,
    onSurface: t.ink,
    error: t.danger,
  );

  final textTheme = TextTheme(
    displayLarge: AppType.display,
    headlineMedium: AppType.title,
    titleMedium: AppType.heading,
    bodyLarge: AppType.body,
    bodyMedium: AppType.body,
    labelLarge: AppType.label,
    bodySmall: AppType.caption,
  ).apply(bodyColor: t.ink, displayColor: t.ink);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: t.surface,
    fontFamily: AppType.family,
    fontFamilyFallback: AppType.fallback,
    textTheme: textTheme,
    extensions: <ThemeExtension<dynamic>>[t],
    appBarTheme: AppBarTheme(
      backgroundColor: t.surface,
      foregroundColor: t.primary,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: AppType.heading.copyWith(color: t.primary),
    ),
    // The CTA role is a filled button with brand-specified text on it — never
    // "the primary colour with white text".
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: t.cta,
        foregroundColor: t.ctaText,
        textStyle: AppType.label,
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Gap.md)),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: t.primary,
        foregroundColor: t.onPrimary,
        textStyle: AppType.label,
        elevation: 0,
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Gap.md)),
      ),
    ),
    cardTheme: CardThemeData(
      color: t.card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Gap.lg),
        side: BorderSide(color: t.hairline),
      ),
    ),
    dividerTheme: DividerThemeData(color: t.hairline, space: 1, thickness: 1),
  );
}
