import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transasim_mobile/core/brand/brand_config.dart';
import 'package:transasim_mobile/core/theme/app_theme.dart';

/// The status bar's icons over each brand's real colours. On 2026-10-17
/// Acorn's destination page showed dark icons on its dark blue header, because
/// nothing in the app set them.
void main() {
  // WCAG contrast of white and of black icons on [c].
  double onWhite(Color c) => 1.05 / (c.computeLuminance() + 0.05);
  double onBlack(Color c) => (c.computeLuminance() + 0.05) / 0.05;

  for (final slug in ['sabily', 'esimple', 'acorn']) {
    test(slug, () {
      final json = jsonDecode(File('brands/$slug/brand.json').readAsStringSync());
      final r = BrandConfig.parse(json as Map<String, dynamic>, expectedSlug: slug);
      if (r.errors.isNotEmpty) throw StateError(r.describe(slug));
      final theme = buildTheme(r.config as BrandConfig);
      final surface = theme.extension<AppTokens>()!.surface;
      final fill = theme.extension<ShopTokens>()!.fill;

      expect(statusBarOver(surface).statusBarIconBrightness, Brightness.dark, reason: 'the light app');
      expect(statusBarOver(fill).statusBarIconBrightness,
          onWhite(fill) >= onBlack(fill) ? Brightness.light : Brightness.dark,
          reason: 'the destination header');
      if (slug == 'acorn') expect(statusBarOver(fill).statusBarIconBrightness, Brightness.light);
    });
  }
}
