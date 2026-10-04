import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../../tool/studio/src/icons.dart';

/// The rules every generated icon must meet, run on Sabily's real logo mark.
/// Not byte equality with the hand-made icons: pixels that obey the platform
/// rules are the contract, and a better resampler must not fail this test.
void main() {
  const sabilyLaunch = '#f9f2d3';
  final mark = File('brands/sabily/assets/logo-mark.png').readAsBytesSync();
  final set = {
    for (final c in iconSet('.', 'acme', mark, sabilyLaunch))
      c.path.split('/res/').last.split('/AppIcon.appiconset/').last: img.decodePng(
        Uint8List.fromList(c.after),
      )!,
  };

  double farthestOpaque(img.Image i) {
    var r = 0.0;
    final c = i.width / 2;
    for (final p in i) {
      if (p.a > 8) r = math.max(r, math.sqrt(math.pow(p.x + .5 - c, 2) + math.pow(p.y + .5 - c, 2)));
    }
    return r;
  }

  test('the safe radius is what the foreground XML makes it', () {
    // brand_launcher_foreground.xml: inset 28% → the mark fills 44% of 108 dp,
    // so the 66 dp safe circle is 33/108 × 432/0.44 = 300 px of brand_mark.
    expect(File('android/app/src/sabily/res/drawable/brand_launcher_foreground.xml').readAsStringSync(),
        contains('android:inset="28%"'));
    expect(safeRadius, closeTo(300, 1e-9));
  });

  test('brand_mark: at most 432 px, transparent around, inside the safe circle', () {
    final m = set['drawable/brand_mark.png']!;
    expect((m.width, m.height), (432, 432));
    expect(m.numChannels, 4);
    expect(m.getPixel(0, 0).a, 0, reason: 'a corner must be transparent');
    expect(farthestOpaque(m), lessThanOrEqualTo(safeRadius));
  });

  test('the monochrome layer is one colour, inside the safe zone, and not empty', () {
    final m = set['drawable/brand_launcher_monochrome.png']!;
    expect((m.width, m.height), (432, 432));
    var opaque = 0;
    for (final p in m) {
      if (p.a > 8) {
        opaque++;
        expect((p.r, p.g, p.b), (255, 255, 255));
      }
    }
    expect(opaque, greaterThan(1000));
    // On the 108 dp layer itself: 33/108 of 432 px.
    expect(farthestOpaque(m), lessThanOrEqualTo(33 / 108 * 432));
  });

  test('launcher mipmaps at every density, opaque squares', () {
    for (final (d, px) in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]) {
      final m = set['mipmap-$d/ic_launcher.png']!;
      expect((m.width, m.height), (px, px), reason: d);
      expect(m.getPixel(0, 0).a, 255, reason: '$d corner');
    }
  });

  test('notification icons: white on transparent, at every density', () {
    for (final (d, px) in [('mdpi', 24), ('hdpi', 36), ('xhdpi', 48), ('xxhdpi', 72), ('xxxhdpi', 96)]) {
      final m = set['drawable-$d/ic_notification.png']!;
      expect((m.width, m.height), (px, px), reason: d);
      expect(m.where((p) => p.a > 8 && (p.r, p.g, p.b) != (255, 255, 255)), isEmpty, reason: d);
      expect(m.where((p) => p.a > 8), isNotEmpty, reason: d);
    }
  });

  test('the iOS app icon: 1024 px and no alpha channel, as App Store Connect requires', () {
    final m = set['AppIcon-1024.png']!;
    expect((m.width, m.height), (1024, 1024));
    expect(m.numChannels, 3);
  });

  test('a logo with no transparency still gets a shape, not a blank square', () {
    // An opaque blue disc on white: the corner colour is the background.
    final square = img.Image(width: 300, height: 300, numChannels: 4);
    for (final p in square) {
      final inDisc = math.pow(p.x - 150, 2) + math.pow(p.y - 150, 2) < 100 * 100;
      inDisc ? p.setRgba(20, 60, 200, 255) : p.setRgba(255, 255, 255, 255);
    }
    final icons = renderIcons(img.encodePng(square), sabilyLaunch);
    expect(icons.monochrome.getPixel(216, 216).a, greaterThan(200), reason: 'the disc');
    expect(icons.monochrome.getPixel(216, 216 - 90).a, 0, reason: 'outside the disc');
  });

  test('a file that is not an image is refused with a reason', () {
    expect(() => renderIcons([1, 2, 3], sabilyLaunch), throwsFormatException);
  });
}
