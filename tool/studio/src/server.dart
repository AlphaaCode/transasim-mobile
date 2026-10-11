/// Studio's local server: the tabs' API and the page's static files.
///
/// Loopback only, and it never commits or pushes: Apply writes the generated
/// files and stops there (docs/STUDIO-SPEC.md §10). Requests are served
/// concurrently, so a streaming log blocks nothing; every write goes through
/// one lock, and jobs through the runner's one-at-a-time queue.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:transasim_mobile/core/brand/brand_config.dart';

import '../../gen_brand_flavors.dart' show brandSlugs;
import 'assets.dart';
import 'backend.dart';
import 'distinct.dart';
import 'doctor.dart';
import 'fix_bundle.dart';
import 'generate.dart';
import 'guides.dart';
import 'incidents.dart';
import 'jobs.dart';
import 'new_brand.dart';
import 'probes.dart';
import 'redact.dart';
import 'runner.dart';
import 'signing.dart';

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
  '/integrations.js': ('tool/studio/web/integrations.js', 'text/javascript; charset=utf-8'),
  '/logs.js': ('tool/studio/web/logs.js', 'text/javascript; charset=utf-8'),
  '/doctor.js': ('tool/studio/web/doctor.js', 'text/javascript; charset=utf-8'),
  '/backend.js': ('tool/studio/web/backend.js', 'text/javascript; charset=utf-8'),
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
  final runner = Runner(
    logsDir: '$root/.studio/logs',
    redact: Redactor.forRepo(root),
    incidents: loadIncidents(root),
  );
  await for (final req in server) {
    unawaited(_handle(req, root, port, runner));
  }
}

/// Every write to the repo runs here, one after another.
Future<void> _writes = Future.value();
Future<void> _serial(Future<void> Function() write) {
  final run = _writes.then((_) => write());
  _writes = run.catchError((_) {});
  return run;
}

Future<void> _handle(HttpRequest req, String root, int port, Runner runner) async {
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
          'apply' => await _serial(() => applyPlan(root, plan, accepted(b), send)),
          _ => await send(404, {'error': 'no such route'}),
        };

    // New brand: /api/new/preview|apply.
    if (parts.length == 3 && parts[0] == 'api' && parts[1] == 'new' && req.method == 'POST') {
      final b = await body();
      final form = (b['form'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
      return await previewOrApply(parts[2], newBrandPlan(root, form, bytes(b, 'logo')), b);
    }
    if (parts.length >= 2 && parts[0] == 'api' && const {'jobs', 'logs', 'doctor', 'incidents', 'servers', 'classify'}.contains(parts[1])) {
      return await _tools(req, root, parts, runner, send, body);
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

    // Integrations: the guides, filled for the brand's pending values; a check
    // for one pasted value; the previewed Apply of brand.json and studio.json.
    if (req.method == 'POST' && parts.length >= 4 && parts[3] == 'guides') {
      final b = await body();
      final brand = (b['brand'] as Map?)?.cast<String, dynamic>() ?? _readBrand(root, slug);
      final studio = (b['studio'] as Map?)?.cast<String, dynamic>() ?? readStudio(root, slug);
      final guides = loadGuides(root);
      if (parts.length == 4) {
        final values = placeholders(slug, brand, studio);
        return await send(200, {
          'guides': [
            for (final g in guides.values)
              {
                ...resolveGuide(g, slug, brand, studio),
                'current': g.field == null ? null : readField(g.field!, brand, studio),
                'confirmed': (studio['checklist'] as Map?)?[g.checklistItem],
                'requiresNow': {for (final k in g.requires) k: values[k]},
              },
          ],
          'missing': missingData(root, slug, brand, studio),
        });
      }
      if (parts.length == 6 && parts[5] == 'check' && guides[parts[4]] != null) {
        final v = checkPaste(guides[parts[4]]!, '${b['value'] ?? ''}',
            brand: brand, studio: studio, others: otherBrands(root, slug));
        return await send(200, {'value': v.value, 'errors': v.errors, 'derived': v.derived});
      }
    }
    if (req.method == 'POST' && parts.length == 5 && parts[3] == 'integrations') {
      final b = await body();
      if (b['brand'] is! Map || b['studio'] is! Map) {
        return await send(400, {'error': 'expected the pending brand and studio'});
      }
      final plan = integrationsPlan(root, slug, (b['brand'] as Map).cast<String, dynamic>(),
          (b['studio'] as Map).cast<String, dynamic>());
      return await previewOrApply(parts[4], plan, b);
    }
    if (parts.length >= 4 && parts[3] == 'backend') {
      return await _backend(req, root, slug, parts.sublist(4), runner, send, body, previewOrApply);
    }
    if (req.method == 'POST' && parts.length == 4 && parts[3] == 'upload-sha1') {
      try {
        return await send(200, {'sha1': await uploadKeySha1(root, slug)});
      } on StateError catch (e) {
        return await send(200, {'error': e.message});
      }
    }

    // The Brand tab.
    if (parts.length == 4 && req.method == 'POST') {
      final b = await body();
      if (parts[3] == 'preview') {
        return await send(200, check(root, slug, b));
      }
      if (parts[3] == 'apply' && b['brand'] is Map) {
        return await _serial(() => _apply(root, slug, b['brand'] as Map<String, dynamic>, accepted(b), send));
      }
    }
    return await send(404, {'error': 'no such route'});
  } on FormatException catch (e) {
    return await send(400, {'error': 'not JSON: ${e.message}'});
  } catch (e) {
    return await send(500, {'error': '$e'});
  }
}

/// Jobs, logs, Doctor and the incident list.
Future<void> _tools(HttpRequest req, String root, List<String> parts, Runner runner,
    Future<void> Function(int, Object) send, Future<Map<String, dynamic>> Function() body) async {
  final res = req.response;
  final get = req.method == 'GET';
  switch (parts.sublist(1)) {
    case ['incidents'] when get:
      return await send(200, [for (final i in loadIncidents(root).values) i.toJson()]);
    case ['classify'] when req.method == 'POST':
      // A server log pasted in: redacted, matched against the incident list, never stored.
      final text = runner.redact('${(await body())['text'] ?? ''}');
      return await send(200, [
        for (final m in classify(text, loadIncidents(root).values))
          {...m.incident.toJson(), 'line': m.line},
      ]);
    case ['servers'] when get:
      return await send(200, [for (final s in loadServers(root).values) s.toJson()]);
    case ['doctor'] when get:
      return await send(200, {
        'checks': [for (final c in await runDoctor(root)) c.toJson()],
        'machine': readMachine(root),
      });
    case ['jobs'] when get:
      return await send(200, {
        'jobs': [for (final j in runner.jobs.toList().reversed) j.toJson()],
        'names': jobNames,
      });
    case ['jobs'] when req.method == 'POST':
      final b = await body();
      final name = '${b['job']}';
      final slug = '${b['slug'] ?? 'studio'}';
      if (slug != 'studio' && !brandSlugs(root).contains(slug)) {
        return await send(404, {'error': 'no brand "$slug"'});
      }
      final refused = switch (name) {
        'build-dev' => buildDevRefusal(root, slug),
        'launch-dev' => launchRefusal(root, slug),
        _ => null,
      };
      if (refused != null) return await send(409, {'error': refused});
      final steps = jobNames.containsKey(name) ? jobSteps(root, name, slug: slug) : null;
      if (steps == null) return await send(400, {'error': 'no job "$name" to run here'});
      return await send(200, runner.enqueue(slug, name, steps).toJson());
    case ['jobs', final id, ...final rest] when runner[id] != null:
      final job = runner[id]!;
      switch (rest) {
        case [] when get:
          return await send(200, job.toJson());
        case ['cancel'] when req.method == 'POST':
          await runner.cancel(id);
          return await send(200, job.toJson());
        case ['bundle'] when get:
          return await send(200, {'text': await fixBundleFor(root, job, runner.redact)});
        case ['stream'] when get:
          // Server-sent events: the lines so far, the new ones as they come,
          // then the job's end state.
          res
            ..bufferOutput = false
            ..headers.set('content-type', 'text/event-stream; charset=utf-8')
            ..headers.set('cache-control', 'no-store');
          final done = Completer<void>();
          void line(String l) => res.write('data: $l\n\n');
          for (final l in job.lines.toList()) {
            line(l);
          }
          final sub = job.live.listen(line, onDone: done.complete);
          if (job.state != 'queued' && job.state != 'running') {
            await sub.cancel();
          } else {
            await done.future;
          }
          res.write('event: end\ndata: ${jsonEncode(job.toJson())}\n\n');
          return await res.close();
      }
    case ['logs'] when get:
      final dir = Directory('$root/.studio/logs');
      final logs = dir.existsSync()
          ? (dir.listSync().whereType<File>().where((f) => f.path.endsWith('.log')).toList()
            ..sort((a, b) => b.path.compareTo(a.path)))
          : <File>[];
      return await send(200, [
        for (final f in logs.take(100))
          {'name': f.uri.pathSegments.last, 'bytes': f.lengthSync(), 'modified': f.lastModifiedSync().toIso8601String()},
      ]);
    case ['logs', final name] when get:
      final f = File('$root/.studio/logs/$name');
      if (!RegExp(r'^[\w.-]+\.log$').hasMatch(name) || !f.existsSync()) {
        return await send(404, {'error': 'no log "$name"'});
      }
      return await send(200, {'name': name, 'text': runner.redact(f.readAsStringSync())});
  }
  return await send(404, {'error': 'no such route'});
}

/// The newest probes per brand and env, kept for this session only.
final _probes = <String, Map<String, Object?>>{};

/// The Backend tab (docs/STUDIO-SPEC.md §16): its state, a pasted report,
/// the probes, the previewed Apply of its fields, Go phase 2, and the schema
/// reference. Nothing here reaches a server but the brand's public endpoints.
Future<void> _backend(HttpRequest req, String root, String slug, List<String> rest, Runner runner,
    Future<void> Function(int, Object) send, Future<Map<String, dynamic>> Function() body,
    Future<void> Function(String, Plan, Map) previewOrApply) async {
  final items = loadIncidents(root);
  final now = DateTime.now().toUtc();
  String envOf(Object? e) => e == 'prod' ? 'prod' : 'dev';
  Future<void> state(String env) =>
      send(200, backendState(root, slug, env, items: items, probes: _probes['$slug/$env'], now: now));
  if (req.method == 'GET' && rest.isEmpty) return state(envOf(req.uri.queryParameters['env']));
  if (req.method == 'GET' && rest.length == 1 && rest.single == 'runbook') {
    return send(200, {'text': backendRunbook(root, slug, envOf(req.uri.queryParameters['env']), items: items)});
  }
  if (req.method != 'POST') return send(404, {'error': 'no such route'});
  final b = await body();
  final env = envOf(b['env']);
  final cfg = ((readStudio(root, slug)['backend'] as Map?)?[env] as Map?) ?? const {};
  switch (rest) {
    case ['report']:
      final server = loadServers(root)[cfg['server']];
      if (server == null) return send(400, {'error': 'Enter the ${env.toUpperCase()} backend and Apply it first.'});
      if (env == 'dev' && server.prodFor.contains(slug)) {
        return send(422, {'refused': "${server.id} runs $slug's production: it is never $slug's DEV."});
      }
      final v = checkReport('${b['text'] ?? ''}',
          server: server, backend: '${cfg['name']}', now: now, redact: runner.redact);
      if (v.refused != null) return send(422, {'refused': v.refused});
      storeReport(root, slug: slug, env: env, server: server, report: v.report!);
      return state(env);
    case ['probe']:
      if (cfg['domain'] == null || cfg['apiBaseUrl'] == null) {
        return send(400, {'error': 'Enter the ${env.toUpperCase()} domain and API base URL, and Apply them first.'});
      }
      final brand = _readBrand(root, slug);
      _probes['$slug/$env'] = await runProbes(
        domain: '${cfg['domain']}',
        apiBaseUrl: '${cfg['apiBaseUrl']}',
        google: '${(brand['mobile'] as Map?)?['googleServerClientId'] ?? ''}'.isNotEmpty,
        ios: File('$root/ios/Flutter/$slug.xcconfig').existsSync(),
      );
      return state(env);
    case [final action] when action == 'preview' || action == 'apply':
      final plan = backendPlan(root, slug, ((b['backend'] as Map?) ?? const {}).cast(),
          ticks: ((b['ticks'] as Map?) ?? const {}).cast(), items: items, now: now);
      return previewOrApply(action, plan, b);
    case ['phase2', final action]:
      return previewOrApply(
          action, phase2Plan(root, slug, '${b['commit'] ?? ''}', items: items, probes: _probes['$slug/dev'], now: now), b);
    case ['reference', final action]:
      return previewOrApply(action, referencePlan(root, slug, now: now), b);
    case ['goprod', final action]:
      final plan = goProdPlan(root, slug,
          stripeKeyLive: b['stripeKeyLive'] as String?, items: items, probes: _probes['$slug/prod'], now: now);
      return previewOrApply(action, plan, b);
  }
  return send(404, {'error': 'no such route'});
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
