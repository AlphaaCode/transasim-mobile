/// Studio's generators: every text file a brand needs that follows from its
/// brand.json and studio.json, computed and never written here.
///
/// [generate] returns [FileChange]s; the server shows them as diffs and writes
/// them only on Apply. Templates live in tool/studio/templates/, mirroring the
/// paths they produce: `{slug}` in a path, `{{key}}` in a body. Adding a
/// generated file means adding a template. Images are Phase 1b.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../../gen_brand_flavors.dart' show brandSlugs, withBrandFlavors;

const templatesDir = 'tool/studio/templates';

/// One file as it is on disk ([before], null when absent) and as Studio would
/// write it ([after]). [path] is repo-relative with forward slashes.
class FileChange {
  FileChange(this.path, this.before, this.after);

  final String path;
  final String? before;
  final String after;

  bool get changed => before != after;
}

/// The same, for a file that is not text: an image or a video.
class BinaryChange {
  BinaryChange(this.path, this.before, this.after);

  final String path;
  final List<int>? before;
  final List<int> after;

  bool get changed {
    final b = before;
    if (b == null || b.length != after.length) return true;
    for (var i = 0; i < b.length; i++) {
      if (b[i] != after[i]) return true;
    }
    return false;
  }
}

List<int>? readBytes(String root, String path) {
  final f = File('$root/$path');
  return f.existsSync() ? f.readAsBytesSync() : null;
}

/// brand.json exactly as the committed files are formatted, so a save from
/// Studio changes only the values that were edited.
String encodeBrand(Map<String, dynamic> brand) =>
    '${const JsonEncoder.withIndent('  ').convert(brand)}\n';

Map<String, dynamic> readStudio(String root, String slug) {
  final f = File('$root/brands/$slug/studio.json');
  return f.existsSync() ? jsonDecode(f.readAsStringSync()) as Map<String, dynamic> : {};
}

/// Every file Studio owns for [slug], as [brand] would make it.
///
/// The themed-icon XML (mipmap-anydpi-v33) names the generated monochrome
/// layer, so it belongs to the icon set: it is emitted only when that set
/// exists on disk or is being written ([withIcons]). A brand whose icons were
/// made by hand keeps exactly the files it has.
List<FileChange> generate(String root, String slug, Map<String, dynamic> brand,
    {bool withIcons = false, Map<String, dynamic>? studio}) {
  String? read(String path) {
    final f = File('$root/$path');
    return f.existsSync() ? f.readAsStringSync() : null;
  }

  final hasIcons = withIcons ||
      File('$root/android/app/src/$slug/res/drawable/brand_launcher_monochrome.png').existsSync();
  final values = templateValues(slug, brand, studio ?? readStudio(root, slug));
  final base = '${Directory('$root/$templatesDir').absolute.path.replaceAll(r'\', '/')}/';
  final changes = <FileChange>[
    FileChange('brands/$slug/brand.json', read('brands/$slug/brand.json'), encodeBrand(brand)),
    for (final t in Directory(base).listSync(recursive: true).whereType<File>())
      if (t.path.endsWith('.tmpl') && (hasIcons || !t.path.contains('mipmap-anydpi-v33')))
        _render(t, base, slug, values, read),
  ];
  final pubspec = read('pubspec.yaml')!;
  final slugs = {...brandSlugs(root), slug}.toList()..sort();
  changes.add(FileChange('pubspec.yaml', pubspec, withBrandFlavors(pubspec, slugs)));
  return changes..sort((a, b) => a.path.compareTo(b.path));
}

FileChange _render(File template, String base, String slug, Map<String, String> values,
    String? Function(String) read) {
  final full = template.absolute.path.replaceAll(r'\', '/');
  final path = full
      .substring(base.length, full.length - '.tmpl'.length)
      .replaceAll('{slug}', slug);
  final body = template.readAsStringSync().replaceAllMapped(
        RegExp(r'\{\{(\w+)\}\}'),
        (m) => values[m[1]] ?? (throw StateError('${template.path}: unknown placeholder ${m[0]}')),
      );
  return FileChange(path, read(path), body);
}

/// The `{{key}}` values, derived from the brand. Tolerant of a half-edited
/// brand: the preview still renders, and BrandConfig's errors block Apply.
Map<String, String> templateValues(
    String slug, Map<String, dynamic> brand, Map<String, dynamic> studio) {
  String s(Object? v) => v is String ? v : '';
  Map<String, dynamic> m(Object? v) => v is Map<String, dynamic> ? v : const {};
  final mobile = m(brand['mobile']);
  final logo = m(brand['logo']);

  // logo.introBackground ?? colors.surface: the rule the wiring test checks.
  final launch = s(logo['introBackground'] ?? m(brand['colors'])['surface']).toLowerCase();

  // logo.iconBackground decouples the LAUNCHER ICON from the launch window.
  // One resource served both until eSimple wanted a navy icon and a black
  // entry. Absent - which is every other brand - and the two stay one colour,
  // so their generated files do not move by a byte.
  final icon = s(logo['iconBackground']).toLowerCase();
  final hasIconBg = RegExp(r'^#[0-9a-f]{6}$').hasMatch(icon);
  final isHex = RegExp(r'^#[0-9a-f]{6}$').hasMatch(launch);
  String channel(int at) => isHex ? '0x${launch.substring(at, at + 2).toUpperCase()}' : '0x??';

  const suffix = '.apps.googleusercontent.com';
  final iosClient = s(mobile['googleIosClientId']);
  return {
    'slug': slug,
    'name': s(brand['name']),
    'displayName': s(mobile['displayName']),
    'bundleIdentifier': s(mobile['bundleIdentifier']),
    'appleTeamId': s(studio['appleTeamId']),
    'launchColour': launch,
    // The whole line, or nothing at all: the template engine substitutes and
    // does not branch, so "emit only when set" lives here.
    'iconBackgroundLine':
        hasIconBg ? '\n    <color name="brand_icon_background">$icon</color>' : '',
    'iconBackgroundRef':
        hasIconBg ? '@color/brand_icon_background' : '@color/brand_splash_background',
    'launchRed': channel(1),
    'launchGreen': channel(3),
    'launchBlue': channel(5),
    'googleServerClientId': s(mobile['googleServerClientId']),
    'googleIosClientId': iosClient,
    'googleReversedClientId': iosClient.endsWith(suffix)
        ? 'com.googleusercontent.apps.${iosClient.substring(0, iosClient.length - suffix.length)}'
        : '',
  };
}

/// The published store ids [brand] would change, field -> reason. studio.json's
/// `published` block freezes them: a new id is a new store listing that
/// orphans every install (ARCHITECTURE-MOBILE.md §3.3).
Map<String, String> frozenViolations(Map<String, dynamic> brand, Map<String, dynamic> studio) {
  final published = studio['published'];
  if (published is! Map) return const {};
  final mobile = brand['mobile'] is Map ? brand['mobile'] as Map : const {};
  return {
    for (final e in published.entries)
      if (mobile[e.key] != e.value)
        'mobile.${e.key}': 'published as "${e.value}": frozen, a new id is a new store listing',
  };
}

/// A unified diff of [before] (null: new file) and [after], with [context]
/// unchanged lines around each change.
// ponytail: O(n·m) LCS table; fine for files of a few hundred lines, use
// Myers' algorithm if Studio ever diffs something large.
String unifiedDiff(String? before, String after, {int context = 3}) {
  final a = before == null ? const <String>[] : before.split('\n');
  final b = after.split('\n');
  final lcs = List.generate(a.length + 1, (_) => List<int>.filled(b.length + 1, 0));
  for (var i = a.length - 1; i >= 0; i--) {
    for (var j = b.length - 1; j >= 0; j--) {
      lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : math.max(lcs[i + 1][j], lcs[i][j + 1]);
    }
  }
  // Each op: the marker, the line, and its 1-based line numbers in a and b.
  final ops = <(String, String, int, int)>[];
  var i = 0, j = 0;
  while (i < a.length || j < b.length) {
    if (i < a.length && j < b.length && a[i] == b[j]) {
      ops.add((' ', a[i], ++i, ++j));
    } else if (j == b.length || (i < a.length && lcs[i + 1][j] >= lcs[i][j + 1])) {
      ops.add(('-', a[i], ++i, j));
    } else {
      ops.add(('+', b[j], i, ++j));
    }
  }
  // Changes closer than 2·context unchanged lines share one hunk.
  final changed = [for (var x = 0; x < ops.length; x++) if (ops[x].$1 != ' ') x];
  final out = StringBuffer();
  var g = 0;
  while (g < changed.length) {
    var last = g;
    while (last + 1 < changed.length && changed[last + 1] - changed[last] <= 2 * context + 1) {
      last++;
    }
    final hunk = ops.sublist(
        math.max(0, changed[g] - context), math.min(ops.length, changed[last] + context + 1));
    final aLines = hunk.where((o) => o.$1 != '+').length;
    final bLines = hunk.where((o) => o.$1 != '-').length;
    final aStart = hunk.firstWhere((o) => o.$1 != '+', orElse: () => hunk.first).$3;
    final bStart = hunk.firstWhere((o) => o.$1 != '-', orElse: () => hunk.first).$4;
    out.writeln('@@ -${aLines == 0 ? 0 : aStart},$aLines +${bLines == 0 ? 0 : bStart},$bLines @@');
    for (final o in hunk) {
      out.writeln('${o.$1}${o.$2}');
    }
    g = last + 1;
  }
  return out.toString();
}
