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
  static const inkMuted = Color(0xFF5A625F);
  static const hairline = Color(0xFFDBE0DE);
  static const card = Color(0xFFFFFFFF);
  static const onPrimary = Color(0xFFFFFFFF);

  /// Premium register: deliberately cream-and-gold, detached from the brand
  /// palette. A brand that writes nothing gets exactly this (§2.3).
  static const premiumSurface = Color(0xFFFFF9E8);
  static const premiumAccent = Color(0xFF735C00);
  static const premiumText = Color(0xFF1E1C09);
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
        hairline: _Socle.hairline,
        card: _Socle.card,
        onPrimary: _Socle.onPrimary,
        premiumSurface: brand.theme.premiumSurface ?? _Socle.premiumSurface,
        premiumAccent: brand.theme.premiumAccent ?? _Socle.premiumAccent,
        premiumText: brand.theme.premiumText ?? _Socle.premiumText,
      );

  static AppTokens of(BuildContext context) => Theme.of(context).extension<AppTokens>()!;

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
      premiumSurface: Color.lerp(premiumSurface, other.premiumSurface, t)!,
      premiumAccent: Color.lerp(premiumAccent, other.premiumAccent, t)!,
      premiumText: Color.lerp(premiumText, other.premiumText, t)!,
    );
  }
}

/// 4pt spacing scale. The old app had no scale — inline literals whose
/// distribution was ~85% compatible with 4/8pt, so layouts port without a
/// fight (`ANALYSE-EXISTANT.md` §4.5 note).
abstract final class Gap {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Named text styles. There is no inline `fontSize:` anywhere else in `lib/`.
///
/// The old app had ZERO named styles and 288 inline literals across 14 distinct
/// sizes (`ANALYSE-EXISTANT.md` §4.5). Nothing to migrate — so the scale is
/// built once, here, and used by name.
abstract final class AppType {
  /// Latin/Cyrillic/Greek coverage.
  static const String family = 'NotoSans';

  /// Arabic coverage. Declared as a fallback family so a single style renders
  /// French and Arabic without the widget knowing which it is.
  ///
  /// ARCHITECTURE-MOBILE.md §12.6 recorded that NO Arabic-capable typeface was
  /// specified anywhere — the old app named bare 'Roboto' and relied on
  /// per-platform fallback, which differs between Android and iOS. Bundling
  /// both families removes that variance and keeps the app correct offline.
  static const List<String> fallback = <String>['NotoSansArabic'];

  static const TextStyle _base = TextStyle(fontFamily: family, fontFamilyFallback: fallback);

  static final TextStyle display =
      _base.copyWith(fontSize: 32, height: 1.25, fontWeight: FontWeight.w700);
  static final TextStyle title =
      _base.copyWith(fontSize: 24, height: 1.30, fontWeight: FontWeight.w700);
  static final TextStyle heading =
      _base.copyWith(fontSize: 18, height: 1.35, fontWeight: FontWeight.w600);
  static final TextStyle body = _base.copyWith(fontSize: 16, height: 1.50);
  static final TextStyle bodyStrong =
      _base.copyWith(fontSize: 16, height: 1.50, fontWeight: FontWeight.w600);
  static final TextStyle label =
      _base.copyWith(fontSize: 14, height: 1.40, fontWeight: FontWeight.w500);
  static final TextStyle caption =
      _base.copyWith(fontSize: 12, height: 1.35, color: _Socle.inkMuted);
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
