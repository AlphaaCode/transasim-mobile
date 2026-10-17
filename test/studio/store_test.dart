import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../../tool/studio/src/icons.dart' show tryDecode;
import '../../tool/studio/src/jobs.dart';
import '../../tool/studio/src/store.dart';

/// The store kit (docs/PLATFORM-PLAN.md §9, slice S): Play's own rules for the
/// listing's images, and the graphics made from a real brand's files.
void main() {
  Map<String, dynamic> brand(String slug) =>
      jsonDecode(File('brands/$slug/brand.json').readAsStringSync()) as Map<String, dynamic>;
  int rgbOf(img.Pixel p) => (p.r.toInt() << 16) | (p.g.toInt() << 8) | p.b.toInt();
  int hex(String h) => int.parse(h.substring(1), radix: 16);

  test('a phone screenshot: Play refuses past 2:1, under 320 px, over 3840 px, with alpha or over 8 MB', () {
    expect(checkShot(1080, 1920).problems, isEmpty);
    expect(checkShot(1080, 1920).promotable, isTrue, reason: '9:16 at 1080 px is the size promotion asks for');
    expect(checkShot(1920, 1080).promotable, isTrue);
    expect(checkShot(1080, 2160).problems, isEmpty, reason: 'exactly 2:1 is allowed');
    expect(checkShot(1080, 2160).promotable, isFalse, reason: 'allowed, but not 9:16');
    expect(checkShot(1080, 2400).problems.single, contains('2.22:1'));
    expect(checkShot(200, 300).problems.single, contains('at least 320 px'));
    expect(checkShot(2160, 3900).problems.single, contains('at most 3840 px'));
    expect(checkShot(1080, 1920, alpha: true).problems.single, contains('alpha'));
    expect(checkShot(1080, 1920, bytes: 9 * 1024 * 1024).problems.single, contains('8 MB'));
  });

  test("the screenshots Play refused for Acorn on 2026-10-16 read as refused, and why", () {
    final shots = Directory('brands/acorn/assets/phone').listSync().whereType<File>().toList();
    expect(shots, isNotEmpty);
    for (final f in shots) {
      final image = tryDecode(f.readAsBytesSync())!;
      final c = checkShot(image.width, image.height);
      expect(c.problems, [contains('taller than 2:1')], reason: f.path);
      expect(c.promotable, isFalse, reason: '${image.width} px wide is under 1080');
    }
  });

  test("the Play icon is Acorn's launcher at 512: its mark on the launcher's background", () {
    final icon = tryDecode(playIcon('.', 'acorn'))!;
    expect((icon.width, icon.height), (512, 512));
    expect(rgbOf(icon.getPixel(0, 0)), hex(iconBackground('acorn', brand('acorn'))));
    expect(icon.getPixel(0, 0).a, 255, reason: 'Play rounds the corners itself: the square stays opaque');
  });

  test("the feature graphic: 1024×500, no alpha, Acorn's lockup centred on its surface colour", () {
    final g = tryDecode(featureGraphic('.', 'acorn'))!;
    expect((g.width, g.height, g.numChannels), (1024, 500, 3));
    final surface = hex('${brand('acorn')['colors']['surface']}');
    for (final (x, y) in [(0, 0), (1023, 0), (0, 499), (1023, 499), (100, 250), (923, 250)]) {
      expect(rgbOf(g.getPixel(x, y)), surface, reason: 'the margin at ($x, $y) is the surface colour');
    }
    // Coordinates, not pixels: the image package's iterator reuses one Pixel object.
    final inked = [for (final p in g) if (rgbOf(p) != surface) (p.x, p.y)];
    expect(inked, isNotEmpty, reason: 'the lockup is drawn');
    final xs = inked.map((p) => p.$1), ys = inked.map((p) => p.$2);
    final (left, right) = (xs.reduce((a, b) => a < b ? a : b), xs.reduce((a, b) => a > b ? a : b));
    final (top, bottom) = (ys.reduce((a, b) => a < b ? a : b), ys.reduce((a, b) => a > b ? a : b));
    expect(((left + right) / 2 - 512).abs(), lessThan(3), reason: 'centred across');
    expect(((top + bottom) / 2 - 250).abs(), lessThan(3), reason: 'centred down');
    expect(bottom - top, lessThanOrEqualTo(280), reason: 'clear of the edges Play may crop');
  });

  test("a lockup that would vanish on the surface moves to the primary colour: Sabily's white logo", () {
    // Sabily's logo.full is white: on its cream surface it would not be seen.
    final g = tryDecode(featureGraphic('.', 'sabily'))!;
    expect(rgbOf(g.getPixel(0, 0)), hex('${brand('sabily')['colors']['primary']}'));
    expect(rgbOf(g.getPixel(0, 0)), isNot(hex('${brand('sabily')['colors']['surface']}')));
  });

  test("a lockup with no transparency sits on its own background: eSimple's white box", () {
    final g = tryDecode(featureGraphic('.', 'esimple'))!;
    final lockup = tryDecode(File('brands/esimple/assets/${brand('esimple')['logo']['full']}').readAsBytesSync())!;
    expect(rgbOf(g.getPixel(0, 0)), rgbOf(lockup.getPixel(0, 0)), reason: 'its edges would show on any other colour');
  });

  test('a capture is kept as Play takes it: no alpha, numbered in order', () {
    final root = Directory.systemTemp.createTempSync('store');
    addTearDown(() => root.deleteSync(recursive: true));
    final screen = img.Image(width: 1080, height: 1920, numChannels: 4);
    img.fill(screen, color: img.ColorRgba8(30, 60, 90, 255));
    final png = img.encodePng(screen);
    expect(saveShot(root.path, 'acorn', png), 'phone-01.png');
    expect(saveShot(root.path, 'acorn', png), 'phone-02.png');
    final kept = tryDecode(File('${root.path}/dist/acorn/store/phone/phone-01.png').readAsBytesSync())!;
    expect((kept.width, kept.height, kept.numChannels), (1080, 1920, 3));
    final listed = shots(root.path, 'acorn');
    expect([for (final s in listed) s['file']], ['phone-01.png', 'phone-02.png']);
    expect(listed.first['problems'], isEmpty);
    expect(listed.first['promotable'], isTrue);
    expect(() => saveShot(root.path, 'acorn', utf8.encode('not a png')), throwsFormatException);
  });

  test('capture mode sets the emulator to 1080×1920 with a clean status bar, and undoes both; never a phone', () {
    final root = Directory.systemTemp.createTempSync('store');
    addTearDown(() => root.deleteSync(recursive: true));
    File('${root.path}/.studio/machine.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode({'sdkRoot': '/sdk', 'avd': 'test'}));
    List<String> lines(String job) => [for (final s in jobSteps(root.path, job, slug: 'acorn')!) s.args.join(' ')];
    final on = lines('store-capture-on');
    expect(on.first, '-e shell wm size 1080x1920');
    expect(on, contains(allOf(contains('com.android.systemui.demo'), contains('command enter'))));
    final off = lines('store-capture-off');
    expect(off, contains(allOf(contains('com.android.systemui.demo'), contains('command exit'))));
    expect(off.last, '-e shell wm size reset');
    expect([...on, ...off].every((l) => l.startsWith('-e ')), isTrue, reason: 'adb -e: the emulator, never a phone plugged in');
    expect(jobSteps(Directory.systemTemp.path, 'store-capture-on', slug: 'acorn'), isNull,
        reason: 'no adb before Doctor has found the SDK');
  });
}
