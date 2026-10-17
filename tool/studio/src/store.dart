/// The store kit (docs/PLATFORM-PLAN.md §9, slice S): the Play listing's
/// graphics and phone screenshots, made from the brand's own files and kept in
/// `dist/<slug>/store/` (gitignored, like a release). Nothing here uploads.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

import 'assets.dart' show thumbnail;
import 'generate.dart' show templateValues;
import 'icons.dart';

String storeDir(String slug) => 'dist/$slug/store';
const playIconFile = 'play-icon-512.png';
const featureGraphicFile = 'feature-graphic-1024x500.png';

/// What a capture asks the emulator for: 9:16 at 1080 px, the size Play's
/// promotion wants, and inside its 2:1 limit (a Pixel 6's 1080×2400 is not).
const shotWidth = 1080, shotHeight = 1920;

Map<String, dynamic> _brand(String root, String slug) =>
    jsonDecode(File('$root/brands/$slug/brand.json').readAsStringSync()) as Map<String, dynamic>;

Map _map(Object? v) => v is Map ? v : const {};

List<int> _asset(String root, String slug, Object? name, String field) {
  final f = File('$root/brands/$slug/assets/$name');
  if (name is! String || !f.existsSync()) throw FormatException('$field: no file to make it from');
  return f.readAsBytesSync();
}

int _rgb(String hex) => int.parse(hex.substring(1), radix: 16);

double _luminance(int rgb) {
  double c(int v) {
    final s = v / 255;
    return s <= 0.03928 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * c(rgb >> 16 & 255) + 0.7152 * c(rgb >> 8 & 255) + 0.0722 * c(rgb & 255);
}

/// The colour the launcher draws the icon on: logo.iconBackground when the
/// brand sets one, else the launch colour (generate.dart's rule).
String iconBackground(String slug, Map<String, dynamic> brand) {
  final icon = '${_map(brand['logo'])['iconBackground'] ?? ''}'.toLowerCase();
  return RegExp(r'^#[0-9a-f]{6}$').hasMatch(icon) ? icon : templateValues(slug, brand, const {})['launchColour']!;
}

/// Play's 512 px icon: the launcher icon as a pre-adaptive launcher shows it,
/// square and opaque (Play rounds it). The same render as the launcher's.
List<int> playIcon(String root, String slug) {
  final brand = _brand(root, slug);
  final bg = iconBackground(slug, brand);
  return img.encodePng(renderIcons(_asset(root, slug, _map(brand['logo'])['mark'], 'logo.mark'), bg).viewport(bg, 512));
}

/// Play's feature graphic, 1024×500 with no alpha (Play takes JPEG or 24-bit
/// PNG): a lockup of the brand centred on one of its colours.
///
/// The pair is measured, not assumed from the field names: the surface colour
/// first, then the primary, each with `logo.full` then `logo.fullInverse`, and
/// the first pair where the lockup reaches 3:1 (WCAG's floor for graphics)
/// wins, else the best one. Sabily's `logo.full` is white, and on its cream
/// surface it would vanish. A lockup with no transparency brings its own
/// ground (eSimple's sits in a white box) and is laid on that colour.
// ponytail: logo on colour only, no tagline: the image package draws no TTF.
// A designed graphic dropped in dist/ replaces it until "Generate" is pressed again.
List<int> featureGraphic(String root, String slug) {
  final brand = _brand(root, slug);
  final logo = _map(brand['logo']);
  final colors = _map(brand['colors']);
  final lockups = [
    for (final field in ['full', 'fullInverse', if (logo['full'] == null) 'mark'])
      if (logo[field] != null) _decode(_asset(root, slug, logo[field], 'logo.$field'), field),
  ];
  if (lockups.isEmpty) throw const FormatException('logo.full: no file to make it from');
  for (final lockup in lockups) {
    if (lockup.where((p) => p.a < 250).length <= lockup.width * lockup.height ~/ 100) {
      final c = lockup.getPixel(0, 0);
      return _compose(lockup, c.r.toInt() << 16 | c.g.toInt() << 8 | c.b.toInt());
    }
  }
  ({img.Image lockup, int ground, double contrast})? best;
  for (final ground in [colors['surface'], colors['primary']].whereType<String>().map(_rgb)) {
    for (final lockup in lockups) {
      final a = _luminance(ground), b = _luminance(_meanColour(lockup));
      final contrast = (math.max(a, b) + .05) / (math.min(a, b) + .05);
      if (best == null || contrast > best.contrast && best.contrast < 3) best = (lockup: lockup, ground: ground, contrast: contrast);
    }
    if (best != null && best.contrast >= 3) break;
  }
  return _compose(best!.lockup, best.ground);
}

/// [src]'s visible part centred on a 1024×500 field of [ground], clear of the edges.
List<int> _compose(img.Image src, int ground) {
  final lockup = _opaquePart(src);
  final scale = math.min(1024 * 0.6 / lockup.width, 500 * 0.56 / lockup.height);
  final w = math.max(1, (lockup.width * scale).round()), h = math.max(1, (lockup.height * scale).round());
  final sized = img.copyResize(lockup, width: w, height: h, interpolation: img.Interpolation.cubic);
  final out = img.Image(width: 1024, height: 500, numChannels: 3);
  img.fill(out, color: img.ColorRgb8(ground >> 16 & 255, ground >> 8 & 255, ground & 255));
  return img.encodePng(img.compositeImage(out, sized, dstX: (1024 - w) ~/ 2, dstY: (500 - h) ~/ 2));
}

img.Image _decode(List<int> bytes, String field) =>
    tryDecode(bytes)?.convert(numChannels: 4) ??
    (throw FormatException('logo.$field: not an image Studio can read (PNG or JPEG)'));

/// The average colour of [image]'s solid pixels, as 0xRRGGBB.
int _meanColour(img.Image image) {
  var r = 0, g = 0, b = 0, n = 0;
  for (final p in image) {
    if (p.a > 128) {
      r += p.r.toInt();
      g += p.g.toInt();
      b += p.b.toInt();
      n++;
    }
  }
  return n == 0 ? 0 : (r ~/ n) << 16 | (g ~/ n) << 8 | b ~/ n;
}

/// [src] cropped to its visible pixels, so a lockup's transparent padding does
/// not shrink it or pull it off centre.
img.Image _opaquePart(img.Image src) {
  var x0 = src.width, y0 = src.height, x1 = -1, y1 = -1;
  for (final p in src) {
    if (p.a > 8) {
      x0 = math.min(x0, p.x);
      y0 = math.min(y0, p.y);
      x1 = math.max(x1, p.x);
      y1 = math.max(y1, p.y);
    }
  }
  if (x1 < 0) throw const FormatException('logo.full: the image is fully transparent');
  return img.copyCrop(src, x: x0, y: y0, width: x1 - x0 + 1, height: y1 - y0 + 1);
}

/// Why Play would refuse a phone screenshot of [width]×[height], and whether it
/// also meets the promotion size: 9:16 (or 16:9) with the short side at least
/// 1080 px.
({List<String> problems, bool promotable}) checkShot(int width, int height, {bool alpha = false, int bytes = 0}) {
  final short = math.min(width, height), long = math.max(width, height);
  final problems = [
    if (short < 320) 'the short side is $short px: Play wants at least 320 px',
    if (long > 3840) 'the long side is $long px: Play allows at most 3840 px',
    if (long > 2 * short) '$width×$height is taller than 2:1 (${(long / short).toStringAsFixed(2)}:1): Play refuses it',
    if (alpha) 'it has an alpha channel: Play takes JPEG or 24-bit PNG',
    if (bytes > 8 * 1024 * 1024) 'it is over 8 MB',
  ];
  return (problems: problems, promotable: problems.isEmpty && short >= 1080 && long * 9 == short * 16);
}

Directory _shots(String root, String slug) => Directory('$root/${storeDir(slug)}/phone');

/// The emulator's screen as PNG bytes, or null when adb does not send it within
/// 15 s (then it is killed, like every adb call Studio waits on). `-e`: the
/// emulator, never a phone plugged in.
Future<List<int>?> screencap(String adb) async {
  final Process p;
  try {
    p = await Process.start(adb, ['-e', 'exec-out', 'screencap', '-p']);
  } on ProcessException {
    return null;
  }
  unawaited(p.stdin.close().catchError((_) {}));
  unawaited(p.stderr.drain<void>().catchError((_) {}));
  final bytes = <int>[];
  try {
    await p.stdout.listen(bytes.addAll).asFuture<void>().timeout(const Duration(seconds: 15));
    return await p.exitCode.timeout(const Duration(seconds: 5)) == 0 && bytes.isNotEmpty ? bytes : null;
  } on TimeoutException {
    p.kill();
    return null;
  }
}

/// A capture from the emulator as Play takes it: decoded, alpha dropped, written
/// as the next phone-NN.png. Returns the file's name.
String saveShot(String root, String slug, List<int> png) {
  final image = tryDecode(png);
  if (image == null) throw const FormatException('the emulator did not send an image');
  final dir = _shots(root, slug)..createSync(recursive: true);
  var n = 1;
  String name() => 'phone-${'$n'.padLeft(2, '0')}.png';
  while (File('${dir.path}/${name()}').existsSync()) {
    n++;
  }
  File('${dir.path}/${name()}').writeAsBytesSync(img.encodePng(image.convert(numChannels: 3)));
  return name();
}

/// The screenshots in `dist/<slug>/store/phone`, in order, each checked.
List<Map<String, Object?>> shots(String root, String slug) {
  final dir = _shots(root, slug);
  if (!dir.existsSync()) return const [];
  final files = dir.listSync().whereType<File>().where((f) => RegExp(r'\.(png|jpe?g)$', caseSensitive: false).hasMatch(f.path)).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return [
    for (final f in files)
      () {
        final name = f.uri.pathSegments.last;
        final bytes = f.readAsBytesSync();
        final image = tryDecode(bytes);
        if (image == null) return {'file': name, 'problems': ['not an image Studio can read'], 'promotable': false};
        final c = checkShot(image.width, image.height,
            alpha: name.toLowerCase().endsWith('.png') && image.numChannels == 4, bytes: bytes.length);
        return {
          'file': name,
          'width': image.width,
          'height': image.height,
          'problems': c.problems,
          'promotable': c.promotable,
          'preview': thumbnail(image, max: 240),
        };
      }(),
  ];
}

/// Removes one screenshot from `dist/<slug>/store/phone`; [name] is a file name there, nothing else.
bool removeShot(String root, String slug, String name) {
  if (!RegExp(r'^[\w-]+\.(png|jpe?g)$', caseSensitive: false).hasMatch(name)) return false;
  final f = File('${_shots(root, slug).path}/$name');
  if (!f.existsSync()) return false;
  f.deleteSync();
  return true;
}

/// What the Store tab shows: each graphic as it would be made now, whether the
/// file in dist/ is that one, and the screenshots.
Map<String, Object?> storeState(String root, String slug) {
  final graphics = <Map<String, Object?>>[];
  for (final (file, label, make) in [
    (playIconFile, 'Play icon · 512×512', playIcon),
    (featureGraphicFile, 'Feature graphic · 1024×500', featureGraphic),
  ]) {
    final written = File('$root/${storeDir(slug)}/$file');
    try {
      final now = make(root, slug);
      graphics.add({
        'file': file,
        'label': label,
        'preview': thumbnail(tryDecode(now)!, max: 512),
        'written': written.existsSync(),
        'current': written.existsSync() && _same(written.readAsBytesSync(), now),
      });
    } on FormatException catch (e) {
      graphics.add({'file': file, 'label': label, 'error': e.message, 'written': written.existsSync()});
    }
  }
  return {'dir': storeDir(slug), 'graphics': graphics, 'shots': shots(root, slug), 'shotSize': '$shotWidth×$shotHeight'};
}

/// Writes both graphics into `dist/<slug>/store/`; returns their paths.
List<String> writeGraphics(String root, String slug) {
  Directory('$root/${storeDir(slug)}').createSync(recursive: true);
  return [
    for (final (file, make) in [(playIconFile, playIcon), (featureGraphicFile, featureGraphic)])
      (File('$root/${storeDir(slug)}/$file')..writeAsBytesSync(make(root, slug))).path.substring(root.length + 1),
  ];
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
