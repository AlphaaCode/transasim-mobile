/// The native icon set, generated from a brand's logo mark.
///
/// Written for a new brand, or when "Regenerate assets" is pressed for an
/// existing one, never otherwise: a published brand's hand-made icons stay
/// until someone asks. Pixel rules, not byte equality, are what
/// test/studio/icon_rules_test.dart checks.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'generate.dart';

/// brand_mark.png's size. Above it, Google's account picker crashed on
/// Sabily's 1473 px icon ("Canvas: trying to draw too large bitmap").
const markSize = 432;

/// brand_launcher_foreground.xml insets brand_mark by 28% on each side, so
/// the mark fills 44% of the adaptive icon's 108 dp layer.
const markShareOfLayer = 1 - 2 * 0.28;

/// The adaptive icon's safe zone, a 66 dp circle on the 108 dp layer, as a
/// radius in brand_mark's own pixels: 33/108 × 432/0.44 = 300 px. Every
/// opaque pixel of brand_mark must lie within it to survive every mask.
const safeRadius = 33 / 108 * markSize / markShareOfLayer;

/// Masks show the central 72 dp of the 108 dp layer; in that view the mark
/// spans 66% and the safe circle 91.7%.
const markShareOfViewport = markShareOfLayer * 108 / 72;

const _densities = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4};

String _res(String slug, String path) => 'android/app/src/$slug/res/$path';
String appIconPath(String slug) =>
    'ios/Runner/Brands/Brand-$slug.xcassets/AppIcon.appiconset/AppIcon-1024.png';
String monochromePath(String slug) => _res(slug, 'drawable/brand_launcher_monochrome.png');

/// Every file of the icon set, in the order [iconSet] writes them.
List<String> iconPaths(String slug) => [
      _res(slug, 'drawable/brand_mark.png'),
      monochromePath(slug),
      for (final d in _densities.keys) ...[
        _res(slug, 'mipmap-$d/ic_launcher.png'),
        _res(slug, 'drawable-$d/ic_notification.png'),
      ],
      appIconPath(slug),
    ];

/// Every icon file for [slug] from [markBytes], on [launchHex] (the colour the
/// adaptive icon's background layer already uses). Throws [FormatException]
/// for an image that cannot be used, with the reason.
List<BinaryChange> iconSet(String root, String slug, List<int> markBytes, String launchHex) {
  final icons = renderIcons(markBytes, launchHex);
  return [
    for (final MapEntry(key: path, value: image) in {
      _res(slug, 'drawable/brand_mark.png'): icons.mark,
      monochromePath(slug): icons.monochrome,
      for (final MapEntry(key: d, value: k) in _densities.entries) ...{
        _res(slug, 'mipmap-$d/ic_launcher.png'): _flat(icons, launchHex, (48 * k).round(), 4),
        _res(slug, 'drawable-$d/ic_notification.png'): _notification(icons, (24 * k).round()),
      },
      appIconPath(slug): _flat(icons, launchHex, 1024, 3),
    }.entries)
      BinaryChange(path, readBytes(root, path), img.encodePng(image)),
  ];
}

class Icons {
  Icons(this.mark, this.silhouette, this.monochrome);

  /// brand_mark.png: the logo fitted inside the safe circle, transparent around.
  final img.Image mark;

  /// The same fit as [mark], as white plus alpha: the shape a tint fills.
  final img.Image silhouette;

  /// The themed-icon layer: [silhouette] where the foreground puts the mark.
  final img.Image monochrome;

  /// The adaptive icon as a launcher shows it before masking: the central
  /// 72 dp, background colour under the foreground, [size] px square.
  img.Image viewport(String launchHex, int size) => _flat(this, launchHex, size, 4);
}

/// A dropped file decoded, or null. The decoders throw on some malformed
/// input instead of returning null; for Studio both mean "not an image".
img.Image? tryDecode(List<int> bytes) {
  try {
    return img.decodeImage(Uint8List.fromList(bytes));
  } catch (_) {
    return null;
  }
}

Icons renderIcons(List<int> markBytes, String launchHex) {
  final decoded = tryDecode(markBytes);
  if (decoded == null) throw const FormatException('not an image Studio can read (PNG or JPEG)');
  final src = decoded.convert(numChannels: 4);
  final fit = _fit(src);
  final mark = _place(src, fit, markSize, 1);
  final silhouette = _place(_silhouette(src), fit, markSize, 1);
  final monochrome = _place(silhouette, (x: 0, y: 0, w: markSize, h: markSize, scale: 1.0),
      markSize, markShareOfLayer);
  return Icons(mark, silhouette, monochrome);
}

typedef _Fit = ({int x, int y, int w, int h, double scale});

/// The opaque part of [src], and the scale that puts it inside a [markSize]
/// square with every opaque pixel within [safeRadius] of the centre.
_Fit _fit(img.Image src) {
  var x0 = src.width, y0 = src.height, x1 = -1, y1 = -1;
  for (final p in src) {
    if (p.a > 8) {
      x0 = math.min(x0, p.x);
      y0 = math.min(y0, p.y);
      x1 = math.max(x1, p.x);
      y1 = math.max(y1, p.y);
    }
  }
  if (x1 < 0) throw const FormatException('the logo is fully transparent');
  final w = x1 - x0 + 1, h = y1 - y0 + 1;
  final cx = x0 + w / 2, cy = y0 + h / 2;
  var r = 0.0;
  for (final p in src) {
    if (p.a > 8) r = math.max(r, math.sqrt(math.pow(p.x + .5 - cx, 2) + math.pow(p.y + .5 - cy, 2)));
  }
  // A few pixels of margin: resampling blurs the edge outwards.
  final scale = [markSize / w, markSize / h, (safeRadius - 4) / r].reduce(math.min);
  return (x: x0, y: y0, w: w, h: h, scale: scale);
}

/// [src]'s fitted part, scaled by [share] of the fit, centred on a
/// transparent [canvas]-px square.
img.Image _place(img.Image src, _Fit fit, int canvas, double share) {
  final part = img.copyCrop(src, x: fit.x, y: fit.y, width: fit.w, height: fit.h);
  final w = math.max(1, (fit.w * fit.scale * share).round());
  final h = math.max(1, (fit.h * fit.scale * share).round());
  final sized = img.copyResize(part, width: w, height: h, interpolation: img.Interpolation.cubic);
  final out = img.Image(width: canvas, height: canvas, numChannels: 4);
  return img.compositeImage(out, sized,
      dstX: (canvas - w) ~/ 2, dstY: (canvas - h) ~/ 2, blend: img.BlendMode.direct);
}

/// White wherever the logo's shape is, transparent elsewhere: what a themed
/// icon tints.
///
/// 1. The shape is the logo's own alpha, or for a logo with no transparency,
///    every pixel far enough from the corner colour.
/// 2. A tile logo (eSimple's white "eSIM" on a gradient) would then be a blank
///    tile, so the shape's pixels are split by brightness (Otsu) and, when the
///    two groups are clearly apart, the smaller one is knocked out.
// ponytail: the corner colour stands for the background, and "clearly apart"
// is a fixed 80/255 gap; a logo that defeats both needs a hand-made monochrome
// PNG dropped over the generated one.
img.Image _silhouette(img.Image src) {
  final total = src.width * src.height;
  final transparent = src.where((p) => p.a < 250).length > total ~/ 100;
  final corners = [
    src.getPixel(0, 0),
    src.getPixel(src.width - 1, 0),
    src.getPixel(0, src.height - 1),
    src.getPixel(src.width - 1, src.height - 1),
  ];
  num avg(num Function(img.Pixel) channel) => corners.map(channel).reduce((a, b) => a + b) / 4;
  final (r, g, b) = (avg((p) => p.r), avg((p) => p.g), avg((p) => p.b));
  int lum(img.Pixel p) => (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round().clamp(0, 255);

  final shape = List<int>.filled(total, 0);
  final histogram = List<int>.filled(256, 0);
  for (final p in src) {
    final num a = transparent
        ? p.a
        : ((math.sqrt(math.pow(p.r - r, 2) + math.pow(p.g - g, 2) + math.pow(p.b - b, 2)) - 24) * 4)
            .clamp(0, 255);
    shape[p.y * src.width + p.x] = a.round();
    if (a > 128) histogram[lum(p)]++;
  }

  // Otsu: the brightness threshold that best separates the shape in two.
  final n = histogram.reduce((a, b) => a + b);
  final sum = [for (var i = 0; i < 256; i++) i * histogram[i]].reduce((a, b) => a + b);
  var best = -1.0, cut = 0, darkN = 0, darkSum = 0;
  for (var t = 0, w = 0, s = 0; t < 255; t++) {
    w += histogram[t];
    s += t * histogram[t];
    if (w == 0 || w == n) continue;
    final between = w * (n - w) * math.pow(s / w - (sum - s) / (n - w), 2);
    if (between > best) (best, cut, darkN, darkSum) = (between.toDouble(), t, w, s);
  }
  final lightN = n - darkN;
  final apart = darkN > 0 && lightN > 0 && (sum - darkSum) / lightN - darkSum / darkN > 80;
  final knockLight = lightN < darkN;
  final knockOut = apart && math.min(darkN, lightN) > n * 0.03;

  final out = img.Image(width: src.width, height: src.height, numChannels: 4);
  for (final p in src) {
    final minority = knockLight ? lum(p) > cut : lum(p) <= cut;
    final a = knockOut && minority ? 0 : shape[p.y * src.width + p.x];
    out.setPixelRgba(p.x, p.y, 255, 255, 255, a);
  }
  return out;
}

img.Color _rgb(String hex) {
  final v = int.parse(hex.substring(1), radix: 16);
  return img.ColorRgb8(v >> 16 & 0xFF, v >> 8 & 0xFF, v & 0xFF);
}

/// A launcher icon as a pre-adaptive launcher or iOS shows it: the
/// background colour, the mark at its adaptive size, no transparency.
img.Image _flat(Icons icons, String launchHex, int size, int channels) {
  final out = img.Image(width: size, height: size, numChannels: channels);
  img.fill(out, color: _rgb(launchHex));
  final s = (size * markShareOfViewport).round();
  final mark = img.copyResize(icons.mark, width: s, height: s, interpolation: img.Interpolation.cubic);
  return img.compositeImage(out, mark, dstX: (size - s) ~/ 2, dstY: (size - s) ~/ 2);
}

/// Android's status-bar icon: white on transparent, the system tints it.
img.Image _notification(Icons icons, int size) =>
    img.copyResize(icons.silhouette, width: size, height: size, interpolation: img.Interpolation.cubic);
