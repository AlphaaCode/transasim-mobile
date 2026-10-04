/// Studio's local server: the Brand tab's API and the page's static files.
///
/// One request at a time, loopback only, and it never commits or pushes:
/// Apply writes the generated files and stops there (docs/STUDIO-SPEC.md §10).
library;

import 'dart:convert';
import 'dart:io';

import 'package:transasim_mobile/core/brand/brand_config.dart';

import '../../gen_brand_flavors.dart' show brandSlugs;
import 'generate.dart';

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
    if (parts.length == 4 && req.method == 'POST') {
      final body = jsonDecode(await utf8.decoder.bind(req).join());
      if (parts[3] == 'preview' && body is Map<String, dynamic>) {
        return await send(200, check(root, slug, body));
      }
      if (parts[3] == 'apply' && body is Map<String, dynamic> && body['brand'] is Map) {
        final accepted = {...(body['acceptDirty'] as List? ?? const []).whereType<String>()};
        return await _apply(root, slug, body['brand'] as Map<String, dynamic>, accepted, send);
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

/// What the Brand tab shows for [brand]: the app's own validation, the frozen
/// ids it would change, and the diff of every file Studio would write.
Map<String, Object?> check(String root, String slug, Map<String, dynamic> brand) {
  final v = BrandConfig.parse(brand, expectedSlug: slug);
  return {
    'errors': [for (final e in v.errors) {'field': e.field, 'reason': e.reason}],
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
