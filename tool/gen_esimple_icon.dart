/// Regenerates eSimple's launcher icon from the new mark.
///
/// ```
/// dart run tool/gen_esimple_icon.dart <mark.png>
/// ```
///
/// Deliberately NOT Studio's "Regenerate assets": that would rewrite
/// `brand.json`'s `logo.mark` and the in-app logos too, and only the launcher
/// and store icons are changing. It calls the SAME [renderIcons] Studio calls,
/// so the safe-zone rules in `test/studio/icon_rules_test.dart` apply unchanged.
///
/// ⚠️ It writes FOUR files, not Studio's full [iconPaths] set. This repo ships
/// one pre-API-26 raster (`mipmap-xxxhdpi`) and the adaptive icon, and no
/// per-density notification icons or monochrome layer — Sabily and Acorn are
/// the same shape. Writing the full set gave eSimple a
/// `brand_launcher_monochrome.png`, which switched on the themed-icon branch in
/// `generate.dart` and made Studio demand a `mipmap-anydpi-v33/ic_launcher.xml`
/// that no brand has, failing `golden_master_test`. Adding the themed layer is
/// a change worth making for all three brands at once, not a side effect of a
/// logo swap.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'studio/src/icons.dart';

/// eSimple's launch colour, from `logo.introBackground` — the same value
/// `brand_splash_background` holds and the adaptive icon's background layer
/// draws. Navy was considered and declined; black keeps the icon and the
/// splash the same colour, which is why they share one resource.
const _launchHex = '#000000';

const _mark = 'android/app/src/esimple/res/drawable/brand_mark.png';
const _launcher = 'android/app/src/esimple/res/mipmap-xxxhdpi/ic_launcher.png';
const _appIcon =
    'ios/Runner/Brands/Brand-esimple.xcassets/AppIcon.appiconset/AppIcon-1024.png';
const _play = 'dist/esimple-play-icon-512.png';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/gen_esimple_icon.dart <mark.png>');
    exit(2);
  }
  final icons = renderIcons(File(args.first).readAsBytesSync(), _launchHex);

  // `viewport` is the adaptive icon as a launcher composes it before masking:
  // the background colour under the mark at its real share. 4 channels for
  // Android and the Play listing, 3 for iOS, which rejects an alpha channel.
  _write(_mark, img.encodePng(icons.mark));
  _write(_launcher, img.encodePng(icons.viewport(_launchHex, 192)));
  _write(_appIcon, img.encodePng(_opaque(icons.viewport(_launchHex, 1024))));
  // Play rounds the listing icon itself, so this one keeps square corners.
  _write(_play, img.encodePng(icons.viewport(_launchHex, 512)));
}

/// The same pixels with the alpha channel dropped. Apple rejects an App Store
/// icon that has one, even when it is fully opaque.
img.Image _opaque(img.Image src) {
  final out = img.Image(width: src.width, height: src.height, numChannels: 3);
  for (final p in src) {
    out.setPixelRgb(p.x, p.y, p.r, p.g, p.b);
  }
  return out;
}

void _write(String path, List<int> bytes) {
  final file = File(path)..parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes);
  final decoded = img.decodePng(Uint8List.fromList(bytes))!;
  stdout.writeln('wrote $path  ${decoded.width}x${decoded.height} '
      '${decoded.numChannels}ch  ${(bytes.length / 1024).toStringAsFixed(1)} KB');
}
