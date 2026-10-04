/// The Assets tab: one processor per drop zone, each turning a dropped file
/// into what it becomes, or into the reason it is refused.
///
/// A slot writes only the file dropped on it, the brand.json field naming it,
/// and for a pack image its credits row. The icon set derived from the mark
/// is written only by "Regenerate assets" (see [regenerateIcons]).
library;

import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:transasim_mobile/core/brand/brand_config.dart' show kPackImageRegions;

import 'generate.dart';
import 'icons.dart';
import 'video.dart';

/// What a preview shows and an Apply writes. Problems at level `error` block
/// the Apply.
class Plan {
  final text = <FileChange>[];
  final binary = <BinaryChange>[];
  final errors = <Map<String, String>>[];
  final warnings = <Map<String, String>>[];
  final notes = <String>[];

  /// Paths the preview shows as images, keyed by path, as data URIs.
  final previews = <String, String>{};

  void error(String field, String reason) => errors.add({'field': field, 'reason': reason});
  void warn(String field, String reason) => warnings.add({'field': field, 'reason': reason});

  List<String> get changedPaths => [
        for (final c in text) if (c.changed) c.path,
        for (final c in binary) if (c.changed) c.path,
      ];

  Map<String, Object?> toJson() => {
        'errors': errors,
        'warnings': warnings,
        'notes': notes,
        'changes': [
          for (final c in text)
            if (c.changed)
              {'path': c.path, 'isNew': c.before == null, 'diff': unifiedDiff(c.before, c.after)},
        ],
        'files': [
          for (final c in binary)
            if (c.changed)
              {
                'path': c.path,
                'isNew': c.before == null,
                'bytes': c.after.length,
                'preview': previews[c.path],
              },
        ],
        // The adaptive icon before masking and the themed layer, for the
        // circle / squircle / square preview with the safe circle on top.
        if (previews['viewport'] != null)
          'masks': {'viewport': previews['viewport'], 'monochrome': previews['monochrome']},
      };
}

/// The slot ids a brand shows: the fixed ones, every region, and each country
/// override it already has.
List<String> slotIds(Map<String, dynamic> brand) => [
      ...slots.keys,
      for (final r in kPackImageRegions) 'pack:$r',
      for (final k in ((_at(brand, 'visuals.packImages') as Map?) ?? const {}).keys)
        if (!kPackImageRegions.contains(k)) 'pack:$k',
    ];

/// What the Assets tab lists for [slug]: each slot's current file, the icon
/// set as it is on disk, and whether ffmpeg is there to strip audio.
Future<Map<String, Object?>> assetState(String root, String slug) async {
  final brand = jsonDecode(File('$root/brands/$slug/brand.json').readAsStringSync())
      as Map<String, dynamic>;
  Map<String, Object?> file(String path) {
    final f = File('$root/$path');
    return {'path': path, 'exists': f.existsSync(), 'bytes': f.existsSync() ? f.lengthSync() : 0};
  }

  return {
    'launch': templateValues(slug, brand, const {})['launchColour'],
    'ffmpeg': await hasFfmpeg(),
    'ffmpegHint': ffmpegInstallHint,
    'generatedIcons': File('$root/${monochromePath(slug)}').existsSync(),
    'slots': [
      for (final id in slotIds(brand))
        if (_at(brand, slotTarget(id)!.$1) case final name?)
          {'slot': id, 'field': slotTarget(id)!.$1, 'name': name, ...file('brands/$slug/assets/$name')}
        else
          {'slot': id, 'field': slotTarget(id)!.$1, 'name': null, 'exists': false},
    ],
    'icons': [for (final p in iconPaths(slug)) file(p)],
  };
}

/// The only files the raw route will serve for [slug].
Set<String> servablePaths(String root, String slug) {
  final brand = jsonDecode(File('$root/brands/$slug/brand.json').readAsStringSync())
      as Map<String, dynamic>;
  return {
    for (final id in slotIds(brand))
      if (_at(brand, slotTarget(id)!.$1) case final String name) 'brands/$slug/assets/$name',
    ...iconPaths(slug),
  };
}

String dataUri(List<int> bytes, String mime) => 'data:$mime;base64,${base64Encode(bytes)}';

/// A preview no bigger than [max] px, so a 2832 px photo is not sent whole.
String thumbnail(img.Image image, {int max = 480}) {
  final small = image.width > max || image.height > max
      ? img.copyResize(image, width: image.width >= image.height ? max : null,
          height: image.height > image.width ? max : null)
      : image;
  return dataUri(img.encodePng(small), 'image/png');
}

/// The drop zones, by id: the brand.json field each fills and the file name
/// Studio gives a new file. `pack:<key>` is a region or an ISO3 override.
const slots = {
  'mark': ('logo.mark', 'logo-mark.png'),
  'full': ('logo.full', 'logo-full.png'),
  'fullInverse': ('logo.fullInverse', 'logo-full-inverse.png'),
  'intro': ('logo.intro', 'logo-intro.mp4'),
  'card': ('mobile.cardBackground', 'card-background.jpg'),
};

/// The brand.json field and file name for [slot], or null for an unknown one.
(String, String)? slotTarget(String slot) {
  if (slots[slot] case final s?) return s;
  if (!slot.startsWith('pack:')) return null;
  final key = slot.substring(5);
  if (!kPackImageRegions.contains(key) && !RegExp(r'^[A-Z]{3}$').hasMatch(key)) return null;
  return ('visuals.packImages.$key', 'pack-${key.toLowerCase()}.jpg');
}

Object? _at(Map json, String path) =>
    path.split('.').fold<Object?>(json, (n, k) => n is Map ? n[k] : null);

void _setAt(Map<String, dynamic> json, String path, Object value) {
  final keys = path.split('.');
  var node = json;
  for (final k in keys.take(keys.length - 1)) {
    node = (node[k] ??= <String, dynamic>{}) as Map<String, dynamic>;
  }
  node[keys.last] = value;
}

/// What dropping [bytes] on [slot] of [slug] would do.
Future<Plan> assetPlan(String root, String slug, String slot, List<int> bytes,
    {bool strip = false, Map<String, String> credit = const {}}) async {
  final plan = Plan();
  final target = slotTarget(slot);
  if (target == null) {
    plan.error(slot, 'not a drop zone Studio knows');
    return plan;
  }
  final (field, defaultName) = target;
  final brand = jsonDecode(File('$root/brands/$slug/brand.json').readAsStringSync())
      as Map<String, dynamic>;
  // An existing card background keeps its name; everything else uses Studio's.
  final name = slot == 'card' ? (_at(brand, field) as String? ?? defaultName) : defaultName;
  final path = 'brands/$slug/assets/$name';

  List<int>? out;
  if (slot == 'intro') {
    out = await _intro(plan, bytes, strip);
  } else {
    final image = tryDecode(bytes);
    if (image == null) {
      plan.error(field, 'not an image Studio can read: drop a PNG or JPEG');
      return plan;
    }
    out = switch (slot) {
      'mark' => _mark(plan, image, bytes),
      'full' || 'fullInverse' => _lockup(plan, field, image, bytes),
      'card' => _card(image),
      _ => _pack(plan, field, image, credit),
    };
    if (out != null) plan.previews[path] = thumbnail(tryDecode(out)!);
  }
  if (out == null) return plan;

  final change = BinaryChange(path, readBytes(root, path), out);
  plan.binary.add(change);
  final updated = jsonDecode(jsonEncode(brand)) as Map<String, dynamic>;
  _setAt(updated, field, name);
  plan.text.addAll(generate(root, slug, updated).where((c) => c.changed));
  if (slot.startsWith('pack:') && plan.errors.isEmpty) {
    plan.text.add(_creditsRow(root, slug, name, slot.substring(5), credit));
  }
  if (slot == 'mark' && change.changed && File('$root/${appIconPath(slug)}').existsSync()) {
    plan.notes.add('The launcher and app icons still show the previous mark until you press '
        'Regenerate assets for this brand.');
  }
  return plan;
}

List<int>? _mark(Plan plan, img.Image image, List<int> bytes) {
  final side = image.width > image.height ? image.width : image.height;
  if ((image.width - image.height).abs() > side * 0.1) {
    plan.error('logo.mark', '${image.width}×${image.height} is not square: a mark becomes an icon');
    return null;
  }
  if (side < 192) {
    plan.error('logo.mark', '$side px is too small: at least 192 px, ideally 432 px or more');
    return null;
  }
  if (side > 4096) {
    plan.error('logo.mark', '$side px is larger than Studio handles: export it at 2048 px or less');
    return null;
  }
  if (side < 432) plan.warn('logo.mark', '$side px will be scaled up to the 432 px brand mark');
  return _isPng(bytes) ? bytes : img.encodePng(image);
}

List<int>? _lockup(Plan plan, String field, img.Image image, List<int> bytes) {
  if (image.width > 2048) {
    plan.error(field, '${image.width} px wide: export it at 2048 px or less');
    return null;
  }
  return _isPng(bytes) ? bytes : img.encodePng(image);
}

List<int> _card(img.Image image) {
  final sized = image.width > 2832 ? img.copyResize(image, width: 2832) : image;
  return img.encodeJpg(sized, quality: 85);
}

/// 1200×675 (the 128 dp card header at 16:9), centre-cropped. Refused without
/// a source and a licence: every bundled photo has a recorded right to be.
List<int>? _pack(Plan plan, String field, img.Image image, Map<String, String> credit) {
  for (final k in ['source', 'licence']) {
    if ((credit[k] ?? '').trim().isEmpty) {
      plan.error(field, 'a pack image needs its $k before it can be saved');
    }
  }
  final targetRatio = 16 / 9;
  final (w, h) = image.width / image.height > targetRatio
      ? ((image.height * targetRatio).round(), image.height)
      : (image.width, (image.width / targetRatio).round());
  final cropped = img.copyCrop(image,
      x: (image.width - w) ~/ 2, y: (image.height - h) ~/ 2, width: w, height: h);
  if (w < 1200) plan.warn(field, '$w px wide after cropping to 16:9: it will be scaled up to 1200');
  final out = img.encodeJpg(
      img.copyResize(cropped, width: 1200, height: 675, interpolation: img.Interpolation.cubic),
      quality: 80);
  return plan.errors.isEmpty ? out : null;
}

Future<List<int>?> _intro(Plan plan, List<int> bytes, bool strip) async {
  var info = readMp4(bytes);
  if (!info.isMp4 || !info.hasVideo) {
    plan.error('logo.intro', 'not an MP4 with a video track');
    return null;
  }
  if (info.hasAudio) {
    if (!strip) {
      plan.error('logo.intro',
          'it has an audio track, even a silent one stops the intro from playing: strip it');
      plan.notes.add(await hasFfmpeg()
          ? 'strip-available'
          : 'ffmpeg is not installed, so Studio cannot strip the audio. $ffmpegInstallHint.');
      return null;
    }
    bytes = await stripAudio(bytes);
    info = readMp4(bytes);
    plan.notes.add('Audio track removed with ffmpeg (stream copy: the video is unchanged).');
  }
  final mb = bytes.length / 1048576;
  final s = info.seconds;
  if (mb > 6) plan.error('logo.intro', '${mb.toStringAsFixed(1)} MB: it must start within 1.5 s, keep it under 3 MB');
  if (mb > 3 && mb <= 6) plan.warn('logo.intro', '${mb.toStringAsFixed(1)} MB is heavy for a cold start');
  if (s == null) plan.warn('logo.intro', 'its duration could not be read');
  if (s != null && s > 8) plan.error('logo.intro', '${s.toStringAsFixed(1)} s is too long for an intro');
  if (s != null && s > 5 && s <= 8) plan.warn('logo.intro', '${s.toStringAsFixed(1)} s is longer than the shipped intros (4–5 s)');
  plan.notes.add('MP4, ${info.handlers.join(', ')} tracks, ${s?.toStringAsFixed(2) ?? '?'} s, ${mb.toStringAsFixed(2)} MB.');
  return plan.errors.isEmpty ? bytes : null;
}

bool _isPng(List<int> b) => b.length > 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E;

const _creditsHeader = '''# Pack header images

Bundled stand-ins for the photo a pack card shows until the backend supplies
one per pack (`visuals.packImages` in `brand.json`): one per image region, plus
per-country overrides. Resized to 1200x675 for the 128 dp card header. Each row
was entered in Studio, with its source and licence, when the image was added.

| File | Used for | Source | Licence | Photographer |
|---|---|---|---|---|
''';

/// PACK-IMAGES-CREDITS.md with [file]'s row added, or replaced if it had one.
FileChange _creditsRow(String root, String slug, String file, String usedFor, Map<String, String> c) {
  final path = 'brands/$slug/assets/PACK-IMAGES-CREDITS.md';
  final before = File('$root/$path').existsSync() ? File('$root/$path').readAsStringSync() : null;
  String cell(String? v) => (v ?? '').trim().isEmpty ? '—' : v!.trim().replaceAll('|', '/');
  final row = '| `$file` | $usedFor | ${cell(c['source'])} | ${cell(c['licence'])} | ${cell(c['author'])} |';
  final lines = (before ?? _creditsHeader).trimRight().split('\n')
    ..removeWhere((l) => l.startsWith('| `$file` |'));
  return FileChange(path, before, '${[...lines, row].join('\n')}\n');
}

/// "Regenerate assets": the whole icon set from the brand's current mark,
/// plus the themed-icon XML that names it.
Plan regenerateIcons(String root, String slug) {
  final plan = Plan();
  final brand = jsonDecode(File('$root/brands/$slug/brand.json').readAsStringSync())
      as Map<String, dynamic>;
  final mark = File('$root/brands/$slug/assets/${_at(brand, 'logo.mark')}');
  if (!mark.existsSync()) {
    plan.error('logo.mark', 'no mark to generate from: drop one on the Assets tab first');
    return plan;
  }
  addIcons(plan, root, slug, mark.readAsBytesSync(), templateValues(slug, brand, const {})['launchColour']!);
  plan.text.addAll(generate(root, slug, brand, withIcons: true).where((c) => c.changed));
  return plan;
}

/// The icon set into [plan], with a preview of each and of the masked icon.
void addIcons(Plan plan, String root, String slug, List<int> mark, String launchHex) {
  try {
    final icons = renderIcons(mark, launchHex);
    plan.binary.addAll(iconSet(root, slug, mark, launchHex));
    for (final c in plan.binary) {
      if (c.path.endsWith('.png')) plan.previews[c.path] = thumbnail(tryDecode(c.after)!, max: 256);
    }
    plan.previews['viewport'] = dataUri(img.encodePng(icons.viewport(launchHex, 288)), 'image/png');
    plan.previews['monochrome'] = dataUri(img.encodePng(icons.monochrome), 'image/png');
  } on FormatException catch (e) {
    plan.error('logo.mark', e.message);
  }
}
