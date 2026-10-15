import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/studio/src/backend.dart';
import '../../tool/studio/src/incidents.dart';
import 'unconfigured.dart';

/// The backend items and their gate (docs/STUDIO-SPEC.md §9, §16.7), read
/// from the real 2026-10-11 reports (in their v1 form) and from probes.
void main() {
  final items = loadIncidents();
  final servers = loadServers();
  final now = DateTime.utc(2026, 10, 11, 13, 40);
  Map<String, Object?> fixture(String name) =>
      (jsonDecode(File('test/studio/fixtures/backend/$name.json').readAsStringSync()) as Map).cast();
  Map<String, dynamic> brand(String slug) =>
      jsonDecode(File('brands/$slug/brand.json').readAsStringSync()) as Map<String, dynamic>;

  Map<String, dynamic> acornBackend() => {
        'features': {'payments': false, 'vouchers': false},
        'clientDomains': ['odysseysim.com'],
        'migrationPath': 'SQL files applied by deploy.sh',
        'dev': {
          'server': 'dev', 'name': 'acorn-backend', 'domain': 'acorn.transasim.com',
          'apiBaseUrl': 'https://acorn.transasim.com/api', 'port': 9074, 'dir': '/apps/acorn-backend',
          'db': 'acorn_prod', 'jar': 'acorn-backend.jar', 'restartMethod': 'scripts', 'shellUser': 'root',
        },
        'activeEnv': 'dev',
      };
  final probes = <String, Object?>{
    'at': now.toIso8601String(),
    'dns': {'addresses': ['169.58.35.140']},
    'tls': {'daysLeft': 58},
    'packs': {'status': 200, 'count': 1045, 'ttfbMs': 180},
    'authApple': {'status': 400},
    'mgmtHttps': {'status': 403},
    'mgmtHttp': {'status': 301},
    'appConfig': {'status': 200},
  };
  final reference = (fixture('sabily-dev')['schema'] as Map).cast<String, Object?>();

  List<ItemResult> evaluate({
    String slug = 'acorn',
    String env = 'dev',
    Map<String, dynamic>? backend,
    Map<String, Object?>? report,
    bool stale = false,
    Map<String, Object?>? probesNow,
    bool noProbes = false,
    Map<String, Object?>? schemaReference,
    Map<String, dynamic>? brandJson,
    Map<String, Map<String, dynamic>> others = const {},
  }) {
    final b = backend ?? acornBackend();
    final r = report ?? fixture('acorn-dev');
    return evaluateBackend(
      BackendView(
        slug: slug,
        env: env,
        brand: brandJson ?? unconfiguredBrand(),
        studio: {'backend': b},
        server: servers[(b[env] as Map)['server']]!,
        report: stale ? null : r,
        reportStale: stale,
        serverReport: stale ? null : r,
        probes: noProbes ? null : (probesNow ?? probes),
        reference: schemaReference ?? reference,
        others: others,
        iosFlavor: true,
        now: now,
      ),
      items,
    );
  }

  Map<String, String> statuses(List<ItemResult> rs) => {for (final r in rs) r.id: r.status};

  test('every backend item has an evaluator, and every evaluator an item', () {
    final envItems = {for (final i in items.values) if (i.env != null) i.id};
    expect(backendEvaluators.keys.toSet(), envItems);
    expect(backendEvaluators.keys.first, 'be-box', reason: 'the runbook starts on the right box');
  });

  test("Acorn on DEV today reads as STUDIO-SPEC §16.12 predicts", () {
    final s = statuses(evaluate());
    expect(s, containsPair('be-anon', 'na'));
    expect(s, containsPair('be-stripe-test', 'na'));
    expect(s, containsPair('be-dev-purchase', 'na'));
    expect(s, containsPair('be-social-google', 'na'));
    for (final id in ['be-box', 'be-port', 'be-layout', 'be-db', 'be-seed', 'be-start', 'be-transatel', 'be-dns',
        'be-nginx', 'be-tls', 'be-mgmt-private', 'be-packs', 'be-jwt', 'be-mail', 'be-config', 'srv-certbot']) {
      expect(s[id], 'pass', reason: id);
    }
    for (final id in ['mail-shared-account', 'transatel-production-on-dev']) {
      expect(s[id], 'accepted', reason: id);
    }
    for (final id in ['be-survives-reboot', 'be-unshared', 'ddl-auto-cannot-alter', 'be-social-apple', 'srv-ports',
        'srv-pg-private', 'srv-no-http-backend', 'srv-world-readable', 'srv-no-prod-secrets', 'srv-backups']) {
      expect(s[id], 'warn', reason: id);
    }
    expect(s['be-schema-drift'], 'fail');
  });

  test('gate test is held only by what blocks: the schema, today', () {
    final rs = evaluate();
    expect(blockers(rs, 'test').map((r) => r.id), ['be-schema-drift']);
    final drift = rs.firstWhere((r) => r.id == 'be-schema-drift').reason;
    expect(drift, allOf(contains('app_config'), contains('subscriber'), contains('12 CHECK')));
  });

  test('a CHECK accepted with a reason stops counting; a column difference never does', () {
    final accepted = acornBackend()
      ..['schemaAccepted'] = {
        for (final c in (reference['checks'] as Map).keys) '$c': 'Liquibase schema: the app enforces the enum',
      };
    final drift = evaluate(backend: accepted).firstWhere((r) => r.id == 'be-schema-drift');
    expect(drift.status, 'fail');
    expect(drift.reason, isNot(contains('CHECK')));
    final same = fixture('acorn-dev')..['schema'] = reference;
    expect(statuses(evaluate(backend: accepted, report: same))['be-schema-drift'], 'pass');
    final noPath = acornBackend()..remove('migrationPath');
    expect(evaluate(backend: noPath, report: same).firstWhere((r) => r.id == 'be-schema-drift').reason,
        contains('migration path'));
  });

  test('without a schema reference the drift is unknown, and says how to get one', () {
    final r = evaluate(schemaReference: const {}).firstWhere((r) => r.id == 'be-schema-drift');
    expect(r.status, 'unknown');
    expect(r.reason, contains('Use as schema reference'));
    final old = evaluate(schemaReference: const {'outdated': true}).firstWhere((r) => r.id == 'be-schema-drift');
    expect(old.status, 'unknown');
    expect(old.reason, allOf(contains('older checker'), contains('Use as schema reference')));
    // Nor are hashes from two checker versions compared.
    final v1 = evaluate(report: fixture('acorn-dev')..['schema_version'] = 1).firstWhere((r) => r.id == 'be-schema-drift');
    expect(v1.status, 'unknown');
    expect(v1.reason, contains('older checker'));
  });

  test('a declared feature turns its items on', () {
    final vouchers = acornBackend()..['features'] = {'payments': false, 'vouchers': true};
    expect(statuses(evaluate(backend: vouchers))['be-anon'], 'pass');
    final undeclared = acornBackend()..remove('features');
    final r = evaluate(backend: undeclared).firstWhere((r) => r.id == 'be-anon');
    expect(r.status, 'unknown');
    expect(r.reason, contains('declare'));
    expect(blockers(evaluate(backend: undeclared), 'test').map((r) => r.id), contains('be-anon'));
  });

  test('payments on DEV want a test key, test mode and a working Stripe account', () {
    final pay = acornBackend()..['features'] = {'payments': true, 'vouchers': false};
    var r = evaluate(backend: pay).firstWhere((r) => r.id == 'be-stripe-test');
    expect(r.status, 'fail');
    expect(r.reason, contains('pending'));
    (pay['dev'] as Map)['stripePublishableKeyTest'] = 'pk_test_${'a' * 30}';
    final testMode = fixture('acorn-dev')
      ..['stripe_key_mode'] = 'test'
      ..['stripe_account_ok'] = true
      ..['stripe_charges_enabled'] = true;
    expect(statuses(evaluate(backend: pay, report: testMode))['be-stripe-test'], 'pass');
    final live = fixture('acorn-dev')..['stripe_key_mode'] = 'live';
    expect(evaluate(backend: pay, report: live).firstWhere((r) => r.id == 'be-stripe-test').reason, contains('live'));
  });

  test("a brand's production box is never evaluated as its DEV, so no item proposes a test key there", () {
    final esimple = {
      'features': {'payments': true, 'vouchers': true},
      'dev': {...(acornBackend()['dev'] as Map), 'name': 'esimple-backend', 'port': 9073},
    };
    expect(
        () => evaluate(slug: 'esimple', backend: esimple, report: fixture('esimple-dev'), brandJson: brand('esimple')),
        throwsA(isA<ArgumentError>().having((e) => '${e.message}', 'message', contains('production'))));
  });

  test("a cloned backend's leftovers fail the items that own them", () {
    // eSimple's real report, read as if it were a new brand's DEV backend.
    final demo = acornBackend();
    (demo['dev'] as Map)
      ..['name'] = 'esimple-backend'
      ..['dir'] = '/apps/esimple-backend'
      ..['jar'] = 'esimple-backend.jar'
      ..['port'] = 9073;
    final rs = evaluate(slug: 'acorn', backend: demo, report: fixture('esimple-dev'));
    final s = statuses(rs);
    expect(s['be-config'], 'fail');
    expect(rs.firstWhere((r) => r.id == 'be-config').reason,
        allOf(contains('jhipster.mail.base-url'), contains('SFTP')));
    expect(s['be-mail'], 'fail');
    expect(rs.firstWhere((r) => r.id == 'be-layout').reason, contains('conf'));
  });

  test("Sabily's DEV backend: the template JWT secret blocks, and systemd is its restart method", () {
    final sabily = {
      'features': {'payments': true, 'vouchers': true},
      'dev': {
        'server': 'dev', 'name': 'sabily', 'domain': 'sabily.transasim.com',
        'apiBaseUrl': 'https://sabily.transasim.com/api', 'port': 9060, 'dir': '/apps/sabily', 'db': 'sabily',
        'jar': 'sabily.jar', 'restartMethod': 'systemd', 'shellUser': 'root',
        'stripePublishableKeyTest': 'pk_test_${'b' * 30}',
      },
    };
    final rs = evaluate(slug: 'sabily', backend: sabily, report: fixture('sabily-dev'), brandJson: brand('sabily'));
    final s = statuses(rs);
    expect(s['be-jwt'], 'fail');
    expect(blockers(rs, 'test').map((r) => r.id), contains('be-jwt'));
    expect(s['be-survives-reboot'], 'pass');
    expect(s['be-layout'], 'pass');
    final scripts = {...sabily, 'dev': {...sabily['dev'] as Map, 'restartMethod': 'scripts'}};
    expect(evaluate(slug: 'sabily', backend: scripts, report: fixture('sabily-dev'), brandJson: brand('sabily'))
        .firstWhere((r) => r.id == 'be-layout').reason, contains('systemd'));
  });

  test('no report, a stale one, or no probes: the items say so, and they block', () {
    final none = evaluateBackend(
        BackendView(slug: 'acorn', env: 'dev', brand: unconfiguredBrand(), studio: {'backend': acornBackend()},
            server: servers['dev']!, probes: probes, reference: reference, iosFlavor: true, now: now),
        items);
    expect(statuses(none)['be-start'], 'unknown');
    expect(statuses(evaluate(stale: true))['be-start'], 'stale');
    expect(blockers(evaluate(stale: true), 'test').map((r) => r.id), contains('be-start'));
    final s = statuses(evaluate(noProbes: true));
    expect(s['be-dns'], 'unknown');
    expect(s['be-tls'], 'unknown');
    expect(s['be-start'], 'pass', reason: 'report items do not need probes');
  });

  test('probes decide what only they can see', () {
    final bad = {
      ...probes,
      'dns': {'addresses': ['1.2.3.4']},
      'tls': {'daysLeft': 10},
      'packs': {'status': 200, 'count': 0},
      'mgmtHttp': {'status': 200},
      'authApple': {'status': 404},
    };
    final s = statuses(evaluate(probesNow: bad));
    for (final id in ['be-dns', 'be-tls', 'be-packs', 'be-mgmt-private']) {
      expect(s[id], 'fail', reason: id);
    }
    expect(s['be-social-apple'], 'warn', reason: 'it warns on DEV (§14.5)');
  });

  test('on PROD the same items gate release, and the split ones block', () {
    final prod = acornBackend()..['prod'] = {...(acornBackend()['dev'] as Map), 'server': 'dev'};
    final rs = evaluate(env: 'prod', backend: prod);
    final unshared = rs.firstWhere((r) => r.id == 'be-unshared');
    expect(unshared.gate, 'release');
    expect(unshared.severity, 'block');
    expect(unshared.status, 'fail');
    expect(rs.any((r) => r.id == 'be-stripe-test'), isFalse, reason: 'a DEV-only item');
    expect(rs.firstWhere((r) => r.id == 'srv-ports').severity, 'block');
  });

  test('a legacy brand reads its items for information: nothing blocks, nothing asks to be declared', () {
    final sabily = {
      'dev': {
        'server': 'dev', 'name': 'sabily', 'domain': 'sabily.transasim.com',
        'apiBaseUrl': 'https://sabily.transasim.com/api', 'port': 9060, 'dir': '/apps/sabily', 'db': 'sabily',
        'jar': 'sabily.jar', 'restartMethod': 'systemd', 'shellUser': 'root',
      },
    };
    final rs = evaluateBackend(
      BackendView(
        slug: 'sabily', env: 'dev', brand: brand('sabily'), studio: {'backendGate': 'legacy', 'backend': sabily},
        server: servers['dev']!, report: fixture('sabily-dev.real'), serverReport: fixture('sabily-dev.real'),
        reference: reference, iosFlavor: true, now: DateTime.utc(2026, 10, 11, 19),
      ),
      items,
    );
    expect(statuses(rs)['be-jwt'], 'fail', reason: 'still shown as it is');
    for (final gate in ['test', 'release']) {
      expect(blockers(rs, gate), isEmpty, reason: gate);
    }
    expect(rs.every((r) => r.severity == 'info'), isTrue);
    expect(rs.where((r) => r.reason.contains('declare')), isEmpty);
    // Undeclared, its features are read from the app: a live key takes payments; every brand offers vouchers.
    expect(statuses(rs)['be-stripe-test'], isNot('na'));
    expect(statuses(rs)['be-anon'], 'pass');
  });

  test("the first real run's version 1 hashes: 19 tables apart, which version 2 no longer compares", () {
    // Version 1 counted timestamp(6) apart from timestamp: Acorn then differed from
    // Sabily in 19 tables, 17 of them by that spelling alone (column diff, 2026-10-11).
    final realReference = (fixture('sabily-dev.real')['schema'] as Map).cast<String, Object?>();
    final asIfCurrent = fixture('acorn-dev.real')..['schema_version'] = reportSchemaVersion;
    final drift = evaluate(report: asIfCurrent, schemaReference: realReference)
        .firstWhere((r) => r.id == 'be-schema-drift');
    expect(drift.reason, allOf(contains('app_config'), contains('15 more'), contains('12 CHECK')));
    expect(evaluate(report: fixture('acorn-dev.real'), schemaReference: realReference)
        .firstWhere((r) => r.id == 'be-schema-drift').status, 'unknown');
  });

  group('PROD (G2)', () {
    Map<String, dynamic> prodBackend() => acornBackend()
      ..['prod'] = {
        'server': 'prod-esimple', 'name': 'acorn-backend', 'domain': 'acorn-api.transasim.com',
        'apiBaseUrl': 'https://acorn-api.transasim.com/api', 'port': 9074, 'dir': '/apps/acorn-backend',
        'db': 'acorn_prod', 'jar': 'acorn-backend.jar', 'restartMethod': 'systemd', 'shellUser': 'hostadmin',
      }
      ..['phase2'] = {'at': '2026-10-11T20:11:01Z', 'jarSha256': '48e036897da443d8', 'backendCommit': '54dd318'};
    final prodProbes = {...probes, 'dns': {'addresses': ['80.241.216.126']}};
    const manual = ['bp-fresh', 'bp-testdata', 'bp-backup', 'bp-rotated'];
    List<ItemResult> prodEval({Map<String, dynamic>? backend, Map<String, Object?>? report, Map<String, dynamic>? checklist}) {
      final r = report ?? fixture('acorn-prod');
      return evaluateBackend(
        BackendView(
          slug: 'acorn', env: 'prod', brand: unconfiguredBrand(),
          studio: {'backend': backend ?? prodBackend(), 'checklist': ?checklist},
          server: servers['prod-esimple']!, report: r, serverReport: r, probes: prodProbes,
          reference: (fixture('acorn-prod')['schema'] as Map).cast<String, Object?>(), iosFlavor: true, now: now,
        ),
        items,
      );
    }

    test('on a clean PROD box, Go prod waits only on what a person ticks', () {
      final rs = prodEval();
      expect(blockers(rs, 'release').map((r) => r.id), unorderedEquals(manual));
      final s = statuses(rs);
      for (final id in ['bp-same-jar', 'bp-nopending', 'bp-ledger', 'be-dns', 'srv-backups']) {
        expect(s[id], 'pass', reason: id);
      }
      expect(s['bp-live-stripe'], 'na', reason: 'payments are off');
      expect(s.containsKey('be-stripe-test'), isFalse, reason: 'a DEV-only item');
      final ticked = prodEval(checklist: {for (final id in manual) id: {'note': 'done', 'at': '2026-10-12'}});
      expect(blockers(ticked, 'release'), isEmpty);
      expect(blockers(ticked, 'submit').map((r) => r.id), ['reviewer-account'],
          reason: 'the first real purchase is n/a without payments');
    });

    test('PROD runs the jar DEV tested, or Go prod waits', () {
      final other = fixture('acorn-prod')..['jar_sha256_16'] = '0000000000000000';
      expect(prodEval(report: other).firstWhere((r) => r.id == 'bp-same-jar').reason,
          allOf(contains('0000000000000000'), contains('48e036897da443d8')));
      final noPhase2 = prodBackend()..remove('phase2');
      expect(prodEval(backend: noPhase2).firstWhere((r) => r.id == 'bp-same-jar').reason, contains('Go phase 2'));
    });

    test('every SQL run by hand on DEV must be ticked applied on PROD', () {
      final ledger = prodBackend()
        ..['schemaLedger'] = [
          {'id': 'widen-acorn-columns', 'what': 'app_config and subscriber varchar(255)', 'devAt': '2026-10-11'},
        ];
      final open = prodEval(backend: ledger).firstWhere((r) => r.id == 'bp-ledger');
      expect(open.status, 'fail');
      expect(open.reason, contains('app_config and subscriber varchar(255)'));
      (ledger['schemaLedger'] as List).first['prodAt'] = '2026-10-12';
      expect(statuses(prodEval(backend: ledger))['bp-ledger'], 'pass');
    });

    test("a PROD box's server items block, where a DEV box's only warn", () {
      final messy = fixture('acorn-prod')..['server'] = fixture('acorn-dev')['server'];
      final rs = prodEval(report: messy);
      expect(blockers(rs, 'release').map((r) => r.id), containsAll(['srv-world-readable', 'srv-backups']));
    });
  });

  test('another brand on the same box may not hold the same port', () {
    final other = {
      'backend': {'dev': {...(acornBackend()['dev'] as Map), 'name': 'other-backend', 'dir': '/apps/other', 'db': 'other'}},
    };
    final r = evaluate(others: {'demo': other}).firstWhere((r) => r.id == 'be-port');
    expect(r.status, 'fail');
    expect(r.reason, contains('demo'));
  });
}
