/// Studio's local server: the Brand tab's API and the page's static files.
///
/// One request at a time, loopback only, and it never commits or pushes:
/// Apply writes the generated files and stops there (docs/STUDIO-SPEC.md §10).
library;

import 'dart:convert';
import 'dart:io';

import 'package:transasim_mobile/core/brand/brand_config.dart';

import '../../gen_brand_flavors.dart' show brandSlugs;
import 'assets.dart';
import 'distinct.dart';
import 'generate.dart';
import 'new_brand.dart';

const studioPort = 4777;

/// Whether a request may be served at all.
///
/// Binding to loopback keeps other machines out, not other web pages: any tab
/// in the browser can send requests to 127.0.0.1. The Host check defeats DNS
/// rebinding (the page's own domain would be the Host), and the custom header
/// required on every POST makes the browser demand a CORS preflight that this
/// server never grants, so no other page can trigger a write.
bool trusted(String method, String? host, String? studioHeader, {int port = studioPort}) =>
    (host == '127.0.0.1:$port' || host == 'localhost:$port') &&
    (method == 'GET' || studioHeader == '1');

final _slugPattern = RegExp(r'^[a-z][a-z0-9]*$');

/// Everything the page loads, by URL: a fixed list, so no request can name a
/// file. The fonts are the app's own, which keeps Studio offline.
const _static = {
  '/': ('tool/studio/web/index.html', 'text/html; charset=utf-8'),
  '/app.js': ('tool/studio/web/app.js', 'text/javascript; charset=utf-8'),
  '/assets.js': ('tool/studio/web/assets.js', 'text/javascript; charset=utf-8'),
  '/wizard.js': ('tool/studio/web/wizard.js', 'text/javascript; charset=utf-8'),
  '/studio.css': ('tool/studio/web/studio.css', 'text/css; charset=utf-8'),
  '/fonts/IBMPlexSans-Regular.ttf': ('assets/fonts/IBMPlexSans-Regular.ttf', 'font/ttf'),
  '/fonts/IBMPlexSans-Medium.ttf': ('assets/fonts/IBMPlexSans-Medium.ttf', 'font/ttf'),
  '/fonts/IBMPlexSans-SemiBold.ttf': ('assets/fonts/IBMPlexSans-SemiBold.ttf', 'font/ttf'),
  '/fonts/BeVietnamPro-Bold.ttf': ('assets/fonts/BeVietnamPro-Bold.ttf', 'font/ttf'),
};

Future<void> serve(String root, {int port = studioPort, bool open = true}) async {
  final HttpServer server;
  try {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  } on SocketException {
    stderr.writeln('Port $port is taken: is Studio already running? Open http://127.0.0.1:$port');
    exit(1);
  }
  final url = 'http://127.0.0.1:$port';
  stdout.writeln('Studio on $url  (Ctrl+C to stop)');
  if (open) {
    if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', url]);
    } else {
      await Process.run(Platform.isMacOS ? 'open' : 'xdg-open', [url]);
    }
  }
  // Sequential on purpose: one job at a time (§3).
  await for (final req in server) {
    await _handle(req, root, port);
  }
}

Future<void> _handle(HttpRequest req, String root, int port) async {
  final res = req.response;
  Future<void> send(int status, Object body) async {
    res
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await res.close();
  }

  try {
    if (!trusted(req.method, req.headers.value('host'), req.headers.value('x-studio'),
        port: port)) {
      return await send(403, {'error': 'refused: Studio only answers its own page'});
    }
    final path = req.uri.path;
    final asset = _static[path];
    if (asset != null && req.method == 'GET') {
      res.headers.set('content-type', asset.$2);
      res.headers.set('cache-control', 'no-store');
      res.add(File('$root/${asset.$1}').readAsBytesSync());
      return await res.close();
    }

    final parts = path.split('/').where((p) => p.isNotEmpty).toList();
    Future<Map<String, dynamic>> body() async {
      final b = jsonDecode(await utf8.decoder.bind(req).join());
      if (b is! Map<String, dynamic>) throw const FormatException('expected a JSON object');
      return b;
    }

    Set<String> accepted(Map b) => {...(b['acceptDirty'] as List? ?? const []).whereType<String>()};
    List<int>? bytes(Map b, String key) => b[key] is String ? base64Decode(b[key] as String) : null;
    Future<void> previewOrApply(String action, Plan plan, Map b) async => switch (action) {
          'preview' => await send(200, plan.toJson()),
          'apply' => await applyPlan(root, plan, accepted(b), send),
          _ => await send(404, {'error': 'no such route'}),
        };

    // New brand: /api/new/preview|apply.
    if (parts.length == 3 && parts[0] == 'api' && parts[1] == 'new' && req.method == 'POST') {
      final b = await body();
      final form = (b['form'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
      return await previewOrApply(parts[2], newBrandPlan(root, form, bytes(b, 'logo')), b);
    }
    if (parts.length < 2 || parts[0] != 'api' || parts[1] != 'brands') {
      return await send(404, {'error': 'no such route'});
    }
    final slugs = brandSlugs(root);
    if (parts.length == 2 && req.method == 'GET') {
      return await send(200, [
        for (final slug in slugs) {'slug': slug, 'name': _readBrand(root, slug)['name']},
      ]);
    }
    final slug = parts[2];
    if (!_slugPattern.hasMatch(slug) || !slugs.contains(slug)) {
      return await send(404, {'error': 'no brand "$slug"'});
    }

    if (parts.length == 3 && req.method == 'GET') {
      final brand = _readBrand(root, slug);
      return await send(200, {
        'brand': brand,
        'studio': readStudio(root, slug),
        ...check(root, slug, brand),
      });
    }
    // The Assets tab: its state, the files it shows, and one drop zone or the
    // icon set at a time.
    if (parts.length == 4 && parts[3] == 'assets' && req.method == 'GET') {
      return await send(200, await assetState(root, slug));
    }
    if (parts.length == 4 && parts[3] == 'raw' && req.method == 'GET') {
      // Only the files the Assets tab lists, so no request can name another.
      final file = req.uri.queryParameters['path'] ?? '';
      if (!servablePaths(root, slug).contains(file) || !File('$root/$file').existsSync()) {
        return await send(404, {'error': 'not a file of $slug'});
      }
      final ext = file.split('.').last;
      res.headers.set('content-type',
          {'png': 'image/png', 'jpg': 'image/jpeg', 'mp4': 'video/mp4'}[ext] ?? 'application/octet-stream');
      res.headers.set('cache-control', 'no-store');
      res.add(File('$root/$file').readAsBytesSync());
      return await res.close();
    }
    if (parts.length == 5 && req.method == 'POST' && parts[3] == 'icons') {
      final b = await body();
      return await previewOrApply(parts[4], regenerateIcons(root, slug), b);
    }
    if (parts.length == 5 && req.method == 'POST' && parts[3] == 'assets') {
      final b = await body();
      final plan = await assetPlan(root, slug, b['slot'] as String? ?? '', bytes(b, 'data') ?? const [],
          strip: b['strip'] == true,
          credit: {for (final e in (b['credit'] as Map? ?? const {}).entries) '${e.key}': '${e.value}'});
      return await previewOrApply(parts[4], plan, b);
    }

    // The Brand tab.
    if (parts.length == 4 && req.method == 'POST') {
      final b = await body();
      if (parts[3] == 'preview') {
        return await send(200, check(root, slug, b));
      }
      if (parts[3] == 'apply' && b['brand'] is Map) {
        return await _apply(root, slug, b['brand'] as Map<String, dynamic>, accepted(b), send);
      }
    }
    return await send(404, {'error': 'no such route'});
  } on FormatException catch (e) {
    return await send(400, {'error': 'not JSON: ${e.message}'});
  } catch (e) {
    return await send(500, {'error': '$e'});
  }
}

Map<String, dynamic> _readBrand(String root, String slug) =>
    jsonDecode(File('$root/brands/$slug/brand.json').readAsStringSync()) as Map<String, dynamic>;

/// What the Brand tab shows for [brand]: the app's own validation, values it
/// would share with another brand, the frozen ids it would change, and the
/// diff of every file Studio would write.
Map<String, Object?> check(String root, String slug, Map<String, dynamic> brand) {
  final v = BrandConfig.parse(brand, expectedSlug: slug);
  final others = {
    for (final s in brandSlugs(root))
      if (s != slug) s: _readBrand(root, s),
  };
  return {
    'errors': [
      for (final e in v.errors) {'field': e.field, 'reason': e.reason},
      for (final e in clashes(brand, others).entries) {'field': e.key, 'reason': e.value},
    ],
    'warnings': [for (final w in v.warnings) {'field': w.field, 'reason': w.reason}],
    'frozen': [
      for (final e in frozenViolations(brand, readStudio(root, slug)).entries)
        {'field': e.key, 'reason': e.value},
    ],
    'changes': [
      for (final c in generate(root, slug, brand))
        if (c.changed)
          {'path': c.path, 'isNew': c.before == null, 'diff': unifiedDiff(c.before, c.after)},
    ],
  };
}

Future<void> _apply(String root, String slug, Map<String, dynamic> brand, Set<String> accepted,
    Future<void> Function(int, Object) send) async {
  final result = check(root, slug, brand);
  if ((result['errors'] as List).isNotEmpty || (result['frozen'] as List).isNotEmpty) {
    return await send(422, {...result, 'refused': 'fix the errors and frozen ids first'});
  }
  // Paths come from the generators, never from the request.
  final changes = generate(root, slug, brand).where((c) => c.changed).toList();
  final dirty = (await dirtyPaths(root, [for (final c in changes) c.path]))
      .where((p) => !accepted.contains(p))
      .toList();
  if (dirty.isNotEmpty) {
    return await send(409, {
      'dirty': dirty,
      'refused': 'these files have changes not committed; overwrite them only on purpose',
    });
  }
  for (final c in changes) {
    final f = File('$root/${c.path}');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(c.after);
  }
  return await send(200, {'written': [for (final c in changes) c.path]});
}

/// Writes [plan] under the same rules as the Brand tab's Apply: refused on an
/// error, and a file git shows as changed is overwritten only when the
/// request names it in acceptDirty. Paths come from the plan, never the
/// request.
Future<void> applyPlan(String root, Plan plan, Set<String> accepted,
    Future<void> Function(int, Object) send) async {
  if (plan.errors.isNotEmpty) {
    return await send(422, {...plan.toJson(), 'refused': 'fix the errors first'});
  }
  final paths = plan.changedPaths;
  final dirty =
      (await dirtyPaths(root, paths)).where((p) => !accepted.contains(p)).toList();
  if (dirty.isNotEmpty) {
    return await send(409, {
      'dirty': dirty,
      'refused': 'these files have changes not committed; overwrite them only on purpose',
    });
  }
  for (final c in plan.text.where((c) => c.changed)) {
    File('$root/${c.path}')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(c.after);
  }
  for (final c in plan.binary.where((c) => c.changed)) {
    File('$root/${c.path}')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(c.after);
  }
  return await send(200, {'written': paths});
}

/// Which of [paths] git reports as modified or untracked.
Future<List<String>> dirtyPaths(String root, List<String> paths) async {
  if (paths.isEmpty) return const [];
  final r = await Process.run('git', ['status', '--porcelain', '--', ...paths],
      workingDirectory: root);
  if (r.exitCode != 0) throw StateError('git status failed: ${r.stderr}');
  return [
    for (final line in (r.stdout as String).split('\n'))
      if (line.length > 3) line.substring(3).trim(),
  ];
}
