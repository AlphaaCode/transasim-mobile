import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/studio/src/backend.dart';
import '../../tool/studio/src/redact.dart';

/// The checker's report (docs/STUDIO-SPEC.md §16.6): what Studio accepts from
/// a paste, and what it refuses without storing a byte. The fixtures are the
/// real 2026-10-11 run (check_output.v0.jsonl) and its v1 form, derived from it.
void main() {
  final servers = loadServers();
  final dev = servers['dev']!;
  final redact = Redactor(const ['a-known-keystore-pw']);
  Map<String, dynamic> fixture(String name) =>
      jsonDecode(File('test/studio/fixtures/backend/$name.json').readAsStringSync()) as Map<String, dynamic>;
  final generated = DateTime.utc(2026, 10, 11, 12, 40);
  final soon = generated.add(const Duration(hours: 1));

  String? refusal(Object report, {DateTime? now, Server? server, String backend = 'acorn-backend'}) =>
      checkReport(report is String ? report : jsonEncode(report),
              server: server ?? dev, backend: backend, now: now ?? soon, redact: redact)
          .refused;

  test('the registry names each box, its Postgres port, and which brands it runs in production', () {
    expect(dev.expectedHostname, 'vmi3448057');
    expect(dev.pgPort, 6478);
    expect(dev.prodFor, ['esimple']);
    expect(servers['prod-esimple']!.sshPort, 52145);
    expect(servers['retired']!.role, 'retired');
  });

  test('a report from the right box, fresh and complete, is accepted', () {
    for (final (name, backend) in [('acorn-dev', 'acorn-backend'), ('esimple-dev', 'esimple-backend'), ('sabily-dev', 'sabily')]) {
      final v = checkReport(jsonEncode(fixture(name)), server: dev, backend: backend, now: soon, redact: redact);
      expect(v.refused, isNull, reason: name);
      expect(v.report!['hostname'], 'vmi3448057');
    }
  });

  test('the first real run (schema version 1, 2026-10-11) passes every rule but the version', () {
    // Its timestamp hashes count timestamp(6) apart from timestamp: version 2 does not.
    final at = DateTime.utc(2026, 10, 11, 19);
    for (final (name, backend) in [('acorn-dev.real', 'acorn-backend'), ('sabily-dev.real', 'sabily')]) {
      final text = File('test/studio/fixtures/backend/$name.json').readAsStringSync();
      expect(checkReport(text, server: dev, backend: backend, now: at, redact: redact).refused,
          contains('unknown schema_version (1)'), reason: name);
      final v2 = (jsonDecode(text) as Map)..['schema_version'] = 2;
      expect(checkReport(jsonEncode(v2), server: dev, backend: backend, now: at, redact: redact).refused, isNull,
          reason: '$name: every other field still fits');
    }
  });

  test("another brand's report from the same box is refused: the backend must be the brand's own", () {
    // Both backends run on vmi3448057, so the box alone cannot tell them apart.
    final r = refusal(fixture('sabily-dev'));
    expect(r, allOf(contains('WRONG BACKEND'), contains('sabily'), contains('acorn-backend')));
  });

  test('a report from another box is refused as WRONG BOX', () {
    final r = refusal(fixture('acorn-dev')..['hostname'] = 'vmi3247176');
    expect(r, allOf(contains('WRONG BOX'), contains('vmi3247176'), contains('vmi3448057')));
    expect(refusal(fixture('acorn-dev'), server: servers['prod-esimple']), contains('WRONG BOX'));
  });

  test('the real 2026-10-11 output (version 0) is refused: unknown schema_version', () {
    final lines = File('test/studio/fixtures/backend/check_output.v0.jsonl').readAsLinesSync();
    expect(lines, hasLength(3));
    for (final line in lines) {
      expect(refusal(line), contains('unknown schema_version'));
    }
    expect(refusal(fixture('acorn-dev')..['schema_version'] = 3), contains('unknown schema_version'));
  });

  test('anything shaped like a secret refuses the whole report, and the message never repeats it', () {
    final smuggled = {
      'a Stripe secret key': 'sk_${'live'}_${'4' * 30}',
      'a JWT': 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ4In0.c2lnbmF0dXJl',
      'a PEM key': '-----BEGIN PRIVATE KEY-----\nAAAA\n-----END PRIVATE KEY-----',
      'an e-mail address': 'info@sabily.fr',
      'a known password': 'a-known-keystore-pw',
      'a webhook secret': 'whsec_${'a' * 20}',
    };
    for (final MapEntry(key: what, value: secret) in smuggled.entries) {
      final report = fixture('acorn-dev');
      (report['config_values'] as Map)['spc_name'] = secret;
      final r = refusal(report);
      expect(r, contains('secret'), reason: what);
      expect(r, isNot(contains(secret)), reason: what);
    }
  });

  test("the checker's own refusal is shown as such", () {
    expect(refusal({'hostname': 'vmi3448057', 'error': 'output withheld: secret-like marker detected'}),
        contains('withheld'));
  });

  test('a report older than 24 h, or from the future, is refused', () {
    expect(refusal(fixture('acorn-dev'), now: generated.add(const Duration(hours: 25))),
        allOf(contains('stale'), contains('24 h')));
    expect(refusal(fixture('acorn-dev'), now: generated.subtract(const Duration(minutes: 10))),
        contains('future'));
  });

  test('a missing, unknown or mistyped field refuses the report and says which', () {
    expect(refusal(fixture('acorn-dev')..remove('cert_days_left')), contains('cert_days_left'));
    expect(refusal(fixture('acorn-dev')..['notes'] = 'free text'), contains('notes'));
    expect(refusal(fixture('acorn-dev')..['port_listening'] = 'yes'), contains('port_listening'));
    final nested = fixture('acorn-dev');
    (nested['server'] as Map).remove('backups_scheduled');
    expect(refusal(nested), contains('server.backups_scheduled'));
    final long = fixture('acorn-dev');
    (long['config_values'] as Map)['spc_name'] = 'x' * 201;
    expect(refusal(long), contains('config_values.spc_name'));
    final hash = fixture('acorn-dev');
    ((hash['schema'] as Map)['tables'] as Map)['agency'] = 'not a hash';
    expect(refusal(hash), contains('schema'));
    expect(refusal('not json at all'), contains('JSON'));
    expect(refusal('[1, 2]'), contains('JSON object'));
  });

  test('an accepted report is stored under .studio, and goes stale after 24 h', () {
    final root = Directory.systemTemp.createTempSync('reports');
    addTearDown(() => root.deleteSync(recursive: true));
    final report =
        checkReport(jsonEncode(fixture('acorn-dev')), server: dev, backend: 'acorn-backend', now: soon, redact: redact).report!;
    storeReport(root.path, slug: 'acorn', env: 'dev', server: dev, report: report);
    expect(Directory('${root.path}/.studio/reports/acorn').listSync(), hasLength(1));

    final fresh = latestReport(root.path, 'acorn', 'dev', now: soon)!;
    expect(fresh.fresh, isTrue);
    expect(fresh.report['slug'], 'acorn-backend');
    expect(latestReport(root.path, 'acorn', 'dev', now: generated.add(const Duration(hours: 25)))!.fresh, isFalse);
    expect(latestReport(root.path, 'acorn', 'prod', now: soon), isNull);
    expect(latestServerReport(root.path, 'dev', now: soon)!.report['slug'], 'acorn-backend');

    // A report filed under the wrong brand before Studio checked the backend
    // (2026-10-11) is ignored, even when it is the newest.
    final misfiled = {...fixture('sabily-dev'), 'generated_at': '2026-10-11T13:00:00Z'};
    storeReport(root.path, slug: 'acorn', env: 'dev', server: dev, report: misfiled);
    expect(latestReport(root.path, 'acorn', 'dev', now: soon)!.report['slug'], 'sabily');
    expect(latestReport(root.path, 'acorn', 'dev', backend: 'acorn-backend', now: soon)!.report['slug'], 'acorn-backend');
  });

  test('every field the checker prints is one Studio reads, and the other way round', () {
    final script = File('$backendScriptsDir/spc-backend-check.sh').readAsStringSync();
    final printed = {
      for (final m in RegExp(r'out\["(\w+)"\]').allMatches(script)) m[1]!,
      // The database fields start as null in one loop.
      for (final m in RegExp(r'"(\w+)"').allMatches(RegExp(r'for k in \(([^)]*)\):').firstMatch(script)![1]!)) m[1]!,
    };
    expect(printed, reportFields.keys.toSet());
    for (final MapEntry(key: field, value: spec) in reportFields.entries) {
      if (spec is Map) {
        for (final key in spec.keys) {
          expect(script, contains('"$key"'), reason: '$field.$key');
        }
      }
    }
    // No field name could trip the checker's own secret-marker guard.
    final marker = RegExp(r'sk_|pk_|eyJ|BEGIN|password', caseSensitive: false);
    expect(reportFields.keys.where(marker.hasMatch), isEmpty);
  });
}
