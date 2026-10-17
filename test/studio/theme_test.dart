import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

/// Studio's two themes (docs/PLATFORM-PLAN.md §11), read from studio.css itself:
/// every text colour readable on every surface in both, every input's edge
/// visible, and every colour a token, so a new rule cannot bring back a literal
/// that only works on one background.
void main() {
  final css = File('tool/studio/web/studio.css').readAsStringSync();
  const darkSelector = ':root';
  const lightSelector = ":root[data-theme='light']";

  (int, int) span(String selector) {
    final start = css.indexOf('$selector {');
    if (start == -1) throw StateError('studio.css has no "$selector {" block');
    return (start, css.indexOf('}', start) + 1);
  }

  Map<String, String> tokens(String selector) {
    final (start, end) = span(selector);
    return {
      for (final m in RegExp(r'--([\w-]+):\s*([^;]+);').allMatches(css.substring(start, end))) m[1]!: m[2]!.trim(),
    };
  }

  final colour = RegExp(r'^(#[0-9a-fA-F]{6}|rgba\([^)]*\))$');
  final dark = tokens(darkSelector);
  final lightOwn = tokens(lightSelector);
  final light = {...dark, ...lightOwn};

  /// [r, g, b, a], channels 0 to 255.
  List<double> rgba(Map<String, String> theme, String name) {
    final v = theme[name];
    expect(v, isNotNull, reason: '--$name is not defined');
    if (v!.startsWith('#')) {
      final n = int.parse(v.substring(1), radix: 16);
      return [(n >> 16) & 255, (n >> 8) & 255, n & 255, 1].map((x) => x.toDouble()).toList();
    }
    return v.substring(5, v.length - 1).split(',').map((s) => double.parse(s.trim())).toList();
  }

  List<double> over(List<double> top, List<double> under) =>
      [for (var i = 0; i < 3; i++) top[3] * top[i] + (1 - top[3]) * under[i], 1];

  double luminance(List<double> c) {
    double channel(double v) {
      final s = v.round() / 255;
      return s <= 0.03928 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
    }

    return 0.2126 * channel(c[0]) + 0.7152 * channel(c[1]) + 0.0722 * channel(c[2]);
  }

  double ratio(List<double> a, List<double> b) {
    final x = luminance(a), y = luminance(b);
    return (math.max(x, y) + .05) / (math.min(x, y) + .05);
  }

  for (final (name, theme) in [('dark', dark), ('light', light)]) {
    test('$name: every text colour reads at 4.5:1 on every surface', () {
      for (final ink in ['ink', 'ink-2', 'ink-3', 'accent', 'ok', 'warn', 'err']) {
        for (final ground in ['bg', 'panel', 'field', 'input-bg']) {
          expect(ratio(rgba(theme, ink), rgba(theme, ground)), greaterThanOrEqualTo(4.5), reason: '--$ink on --$ground');
        }
      }
      expect(ratio(rgba(theme, 'on-accent'), rgba(theme, 'accent')), greaterThanOrEqualTo(4.5),
          reason: 'the label of an Apply button');
      // Diff lines and log lines: their ink on their own tint, laid over the page and the panel.
      for (final (ink, tint) in [('add-ink', 'add-bg'), ('del-ink', 'del-bg'), ('err-ink', 'err-bg'), ('warn-ink', null)]) {
        for (final ground in ['bg', 'panel']) {
          final under = tint == null ? rgba(theme, ground) : over(rgba(theme, tint), rgba(theme, ground));
          expect(ratio(rgba(theme, ink), under), greaterThanOrEqualTo(4.5), reason: '--$ink on ${tint ?? ground} over --$ground');
        }
      }
    });

    test("$name: an input's edge shows at 3:1 against its fill (WCAG 1.4.11)", () {
      expect(ratio(rgba(theme, 'input-edge'), rgba(theme, 'input-bg')), greaterThanOrEqualTo(3));
    });
  }

  test('the light theme sets every colour the dark one does', () {
    final colours = dark.entries.where((e) => colour.hasMatch(e.value)).map((e) => e.key);
    expect(colours.where((k) => !lightOwn.containsKey(k)), isEmpty);
    expect(lightOwn.values.where((v) => !colour.hasMatch(v)), isEmpty, reason: 'a light token that is not a colour');
  });

  test('a colour is a token: no literal outside the two theme blocks', () {
    var rest = css;
    for (final selector in [lightSelector, darkSelector]) {
      final start = rest.indexOf('$selector {');
      rest = rest.replaceRange(start, rest.indexOf('}', start) + 1, '');
    }
    final literals = [for (final m in RegExp(r'#[0-9a-fA-F]{3,8}\b|rgba?\(').allMatches(rest)) m[0]];
    // Device previews, not Studio's own chrome: the themed-icon wallpaper and the
    // safe-zone guide look the same whatever Studio's theme.
    expect(literals, ['#3a4a5c', '#ff4fd8']);
  });
}
