@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/studio/src/backend.dart';
import '../../tool/studio/src/fix_bundle.dart';
import '../../tool/studio/src/incidents.dart';
import '../../tool/studio/src/jobs.dart';
import '../../tool/studio/src/redact.dart';
import '../../tool/studio/src/runner.dart';

/// The Backend tab's writes, on a copy of the repo's text files: its fields,
/// Go phase 2, the schema reference, then the DEV build it unlocks and the
/// Fix Bundle's Backend section (docs/STUDIO-SPEC.md §16.9, §16.10).
void main() {
  late Directory root;
  late String r;
  final items = loadIncidents();
  final generated = DateTime.utc(2026, 10, 11, 12, 40);
  final now = generated.add(const Duration(minutes: 30));
  Map<String, Object?> fixture(String name) =>
      (jsonDecode(File('test/studio/fixtures/backend/$name.json').readAsStringSync()) as Map).cast();

  final acornDev = {
    'server': 'dev', 'name': 'acorn-backend', 'domain': 'acorn.transasim.com',
    'apiBaseUrl': 'https://acorn.transasim.com/api', 'port': 9074, 'dir': '/apps/acorn-backend',
    'db': 'acorn_prod', 'jar': 'acorn-backend.jar', 'restartMethod': 'scripts', 'shellUser': 'root',
  };
  Map<String, dynamic> acorn() => {
        'features': {'payments': false, 'vouchers': false},
        'clientDomains': ['odysseysim.com'],
        'migrationPath': 'SQL files applied by deploy.sh',
        'dev': {...acornDev},
      };
  final goodProbes = <String, Object?>{
    'at': now.toIso8601String(),
    'dns': {'addresses': ['169.58.35.140']},
    'tls': {'daysLeft': 58},
    'packs': {'status': 200, 'count': 1045, 'ttfbMs': 180},
    'authApple': {'status': 400},
    'mgmtHttps': {'status': 403},
    'mgmtHttp': {'status': 301},
    'appConfig': {'status': 200},
  };

  void copy(String from) {
    final src = FileSystemEntity.typeSync(from) == FileSystemEntityType.directory;
    if (!src) {
      File('$r/$from')
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(File(from).readAsBytesSync());
      return;
    }
    for (final f in Directory(from).listSync(recursive: true).whereType<File>()) {
      final rel = f.path.replaceAll(r'\', '/');
      if (rel.endsWith('.png') || rel.endsWith('.mp4') || rel.endsWith('.jpg')) continue;
      File('$r/$rel')
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(f.readAsBytesSync());
    }
  }

  void writeStudio(String slug, Map<String, dynamic> studio) =>
      File('$r/brands/$slug/studio.json').writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(studio)}\n');
  Map<String, dynamic> readStudioJson(String slug) =>
      jsonDecode(File('$r/brands/$slug/studio.json').readAsStringSync()) as Map<String, dynamic>;
  Map<String, dynamic> studioAfter(dynamic plan, String slug) {
    final change = (plan.text as List).firstWhere((c) => c.path == 'brands/$slug/studio.json');
    return jsonDecode(change.after as String) as Map<String, dynamic>;
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('backend-flow');
    r = root.path.replaceAll(r'\', '/');
    for (final p in ['brands', 'tool/studio/guides', 'tool/studio/templates', 'tool/studio/backend',
        'tool/studio/incidents', 'tool/studio/servers.yaml', 'pubspec.yaml', 'ios/Flutter', 'ios/Runner/Brands',
        'android/app/src', 'lib/flavors']) {
      copy(p);
    }
    // Each test starts from brands with no backend entered, whatever the repo holds.
    for (final slug in ['acorn', 'esimple', 'sabily']) {
      writeStudio(slug, readStudioJson(slug)..remove('backend'));
    }
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('the fields Apply writes studio.json only, and never the keys Go phase 2 owns', () {
    expect((studioAfter(backendPlan(r, 'acorn', {...acorn(), 'features': {}}, items: items, now: now), 'acorn')['backend']
            as Map)
        .containsKey('features'), isFalse, reason: 'an empty features block is not written');
    final edited = acorn()..['phase2'] = {'at': 'yesterday', 'jarSha256': 'forged', 'backendCommit': 'abc1234'};
    final plan = backendPlan(r, 'acorn', edited, items: items, now: now);
    expect(plan.errors, isEmpty);
    expect(plan.changedPaths, ['brands/acorn/studio.json']);
    final after = studioAfter(plan, 'acorn');
    expect((after['backend'] as Map).containsKey('phase2'), isFalse);
    expect((after['backend'] as Map)['dev'], acornDev);
    expect(after['appleTeamId'], 'DP7F8WQCJD', reason: 'the rest of studio.json is kept');
  });

  test('a manual backend item is ticked with a note and a time; nothing else is', () {
    final plan = backendPlan(r, 'acorn', acorn(),
        ticks: {'be-dev-purchase': {'note': 'card 4242, eSIM provisioned', 'evidence': 'order 81'}}, items: items, now: now);
    expect(plan.errors, isEmpty);
    expect((studioAfter(plan, 'acorn')['checklist'] as Map)['be-dev-purchase'],
        {'note': 'card 4242, eSIM provisioned', 'evidence': 'order 81', 'at': now.toIso8601String()});
    final wrong = backendPlan(r, 'acorn', acorn(), ticks: {'be-jwt': {'note': 'trust me'}}, items: items, now: now);
    expect(wrong.errors.map((e) => e['field']), contains('checklist.be-jwt'));
  });

  test('Go phase 2 stays shut until the report, the probes, the gate and the commit say yes', () {
    writeStudio('acorn', {...readStudioJson('acorn'), 'backend': acorn()});
    var plan = phase2Plan(r, 'acorn', 'nope', items: items, now: now);
    expect(plan.errors.map((e) => e['field']), containsAll(['report', 'probes', 'backendCommit']));

    final dev = loadServers(r)['dev']!;
    storeReport(r, slug: 'acorn', env: 'dev', server: dev, report: fixture('acorn-dev'));
    plan = phase2Plan(r, 'acorn', '54dd318', items: items, probes: goodProbes, now: now);
    expect(plan.errors.map((e) => e['field']), ['be-schema-drift'], reason: 'no reference yet');

    // With a reference the schema matches, the gate opens.
    File('$r/$referenceSchemaFile')
        .writeAsStringSync(jsonEncode({'schemaVersion': reportSchemaVersion, 'schema': fixture('acorn-dev')['schema']}));
    plan = phase2Plan(r, 'acorn', '54dd318', items: items, probes: goodProbes, now: now);
    expect(plan.errors, isEmpty);
    expect((studioAfter(plan, 'acorn')['backend'] as Map)['phase2'],
        {'at': now.toIso8601String(), 'jarSha256': '48e036897da443d8', 'backendCommit': '54dd318'});

    final old = {...goodProbes, 'at': generated.subtract(const Duration(hours: 2)).toIso8601String()};
    expect(phase2Plan(r, 'acorn', '54dd318', items: items, probes: old, now: now).errors.map((e) => e['field']),
        contains('probes'));
  });

  test("only Sabily's fresh DEV report becomes the schema reference", () {
    expect(referencePlan(r, 'acorn', now: now).errors, isNotEmpty);
    expect(referencePlan(r, 'sabily', now: now).errors.map((e) => e['field']), contains('report'));
    storeReport(r, slug: 'sabily', env: 'dev', server: loadServers(r)['dev']!, report: fixture('sabily-dev'));
    final plan = referencePlan(r, 'sabily', now: now);
    expect(plan.errors, isEmpty);
    expect(plan.changedPaths, [referenceSchemaFile]);
    final written = jsonDecode(plan.text.single.after) as Map;
    expect(written['schema'], fixture('sabily-dev')['schema']);
    expect(written['schemaVersion'], reportSchemaVersion);
    // One written by the version-1 checker reads as outdated, not as a reference.
    File('$r/$referenceSchemaFile').writeAsStringSync(jsonEncode({'schema': written['schema']}));
    expect(readReference(r), {'outdated': true});
    expect(written['generatedAt'], '2026-10-11T12:40:00Z');
  });

  test('a DEV build waits for Go phase 2, and carries the DEV URL and, with payments, the test key', () {
    writeStudio('acorn', {...readStudioJson('acorn'), 'backend': acorn()});
    expect(buildDevRefusal(r, 'acorn'), contains('Go phase 2'));
    expect(jobSteps(r, 'build-dev', slug: 'acorn'), isNull);
    expect(buildDevRefusal(r, 'studio'), isNotNull);

    final passed = {...acorn(), 'phase2': {'at': 'x', 'jarSha256': '48e036897da443d8', 'backendCommit': '54dd318'}};
    writeStudio('acorn', {...readStudioJson('acorn'), 'backend': passed});
    expect(buildDevRefusal(r, 'acorn'), isNull);
    final args = jobSteps(r, 'build-dev', slug: 'acorn')!.single.args;
    expect(args, containsAllInOrder(['build', 'apk', '--profile', '--flavor', 'acorn', '-t', 'lib/flavors/main_acorn.dart']));
    expect(args, contains('--dart-define=API_BASE_URL=https://acorn.transasim.com/api'));
    expect(args.where((a) => a.contains('STRIPE')), isEmpty, reason: 'payments are off');
    expect(args, isNot(contains('--release')));

    passed['features'] = {'payments': true, 'vouchers': false};
    writeStudio('acorn', {...readStudioJson('acorn'), 'backend': passed});
    expect(buildDevRefusal(r, 'acorn'), contains('pk_test_'));
    (passed['dev'] as Map)['stripePublishableKeyTest'] = 'pk_test_${'a' * 30}';
    writeStudio('acorn', {...readStudioJson('acorn'), 'backend': passed});
    expect(jobSteps(r, 'build-dev', slug: 'acorn')!.single.args, contains('--dart-define=STRIPE_PUBLISHABLE_KEY=pk_test_${'a' * 30}'));
  });

  test('Build for test (DEV) does it all: build, stop Gradle, start the emulator, install, open', () {
    writeStudio('acorn', {
      ...readStudioJson('acorn'),
      'backend': {...acorn(), 'phase2': {'at': 'x', 'jarSha256': '48e036897da443d8', 'backendCommit': '54dd318'}},
    });
    File('$r/.studio/machine.json')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(jsonEncode({'sdkRoot': '$r/sdk', 'avd': 'sabily_test', 'gpu': 'angle_indirect'}));
    final lines = [
      for (final s in jobSteps(r, 'build-dev', slug: 'acorn')!) '${s.executable.split(RegExp(r'[\\/]')).last} ${s.args.join(' ')}',
    ];
    expect(lines[0], contains('build apk --profile --flavor acorn'));
    expect(lines[1], contains('--stop'), reason: 'Gradle stops after the build, before the emulator takes the memory');
    expect(lines[2], contains('-avd sabily_test'));
    expect(lines, contains(contains('install -r ${devApk(r, 'acorn')}')));
    expect(lines.last, contains('monkey -p com.transasim.acorn'));
  });

  test('the tab lists every CHECK difference still to accept, and accepting them clears the list', () {
    writeStudio('acorn', {...readStudioJson('acorn'), 'backend': acorn()});
    storeReport(r, slug: 'acorn', env: 'dev', server: loadServers(r)['dev']!, report: fixture('acorn-dev'));
    File('$r/$referenceSchemaFile')
        .writeAsStringSync(jsonEncode({'schemaVersion': reportSchemaVersion, 'schema': fixture('sabily-dev')['schema']}));
    final checks = backendState(r, 'acorn', 'dev', items: items, now: now)['schemaChecks'] as List;
    expect(checks, hasLength(12), reason: 'all of them, not the first four the reason names');
    expect(checks, contains('payment.payment_method_check'));
    writeStudio('acorn', {
      ...readStudioJson('acorn'),
      'backend': {...acorn(), 'schemaAccepted': {for (final c in checks) '$c': 'the backend enum sets the value'}},
    });
    expect(backendState(r, 'acorn', 'dev', items: items, now: now)['schemaChecks'], isEmpty);
  });

  test('Launch on emulator: stop Gradle, start the AVD Doctor found, wait for boot, install, open', () {
    expect(launchRefusal(r, 'acorn'), contains('Doctor'), reason: 'no machine.json yet');
    File('$r/.studio/machine.json')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(jsonEncode({'sdkRoot': '$r/sdk', 'avd': 'sabily_test', 'gpu': 'angle_indirect'}));
    expect(launchRefusal(r, 'acorn'), contains('Build for test (DEV)'), reason: 'no APK yet');
    File(devApk(r, 'acorn'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('apk');
    expect(launchRefusal(r, 'acorn'), isNull);

    final steps = jobSteps(r, 'launch-dev', slug: 'acorn')!;
    final lines = [for (final s in steps) '${s.executable.split(RegExp(r'[\\/]')).last} ${s.args.join(' ')}'];
    expect(lines.first, contains('--stop'), reason: 'Gradle and the emulator never share the memory');
    expect(lines[1], allOf(contains('-avd sabily_test'), contains('-gpu angle_indirect'), contains('-no-snapshot-save')));
    expect(steps[1].detached, isTrue, reason: 'the job must not wait for the emulator to close');
    expect(lines[2], allOf(contains('-e wait-for-device'), contains('sys.boot_completed')));
    expect(lines[3], contains('airplane-mode disable'), reason: 'the app must reach the DEV backend');
    expect(lines[4], contains('-e install -r ${devApk(r, 'acorn')}'));
    expect(lines[5], contains('monkey -p com.transasim.acorn'));
    expect(steps, hasLength(6), reason: 'no emulator answers here, so one is started');
  });

  test('a legacy brand has no Go phase 2, and builds for DEV without one', () {
    writeStudio('sabily', {
      ...readStudioJson('sabily'),
      'backendGate': 'legacy',
      'backend': {
        'dev': {
          'server': 'dev', 'name': 'sabily', 'domain': 'sabily.transasim.com',
          'apiBaseUrl': 'https://sabily.transasim.com/api', 'port': 9060, 'dir': '/apps/sabily', 'db': 'sabily',
          'jar': 'sabily.jar', 'restartMethod': 'systemd', 'shellUser': 'root',
        },
      },
    });
    expect(phase2Plan(r, 'sabily', '54dd318', items: items, now: now).errors.map((e) => e['reason']),
        contains(contains('legacy')));
    expect(buildDevRefusal(r, 'sabily'), isNull);
    final args = jobSteps(r, 'build-dev', slug: 'sabily')!.single.args;
    expect(args, contains('--dart-define=API_BASE_URL=https://sabily.transasim.com/api'));
    expect(args.where((a) => a.contains('STRIPE')), isEmpty, reason: 'no test key recorded: none passed, none asked');
    expect(backendSummary(r, 'sabily', items: items, now: now), contains('legacy'));
  });

  test("the Fix Bundle's Backend section names the report and what fails, under the cap", () async {
    writeStudio('acorn', {...readStudioJson('acorn'), 'backend': acorn()});
    storeReport(r, slug: 'acorn', env: 'dev', server: loadServers(r)['dev']!, report: fixture('acorn-dev'));
    final section = backendSummary(r, 'acorn', items: items, now: now)!;
    expect(section, allOf(contains('### Backend (DEV)'), contains('vmi3448057'), contains('be-schema-drift'),
        contains('48e036897da443d8')));
    expect(backendSummary(r, 'sabily', items: items, now: now), isNull, reason: 'no backend entered');

    final runner = Runner(logsDir: '$r/logs', redact: Redactor(const []), incidents: items);
    final dart = '${flutterRoot()}/bin/cache/dart-sdk/bin/dart${Platform.isWindows ? '.exe' : ''}';
    final job = runner.enqueue('acorn', 'build-dev', [Step(dart, ['--version'])]);
    await job.done;
    final bundle = fixBundle(
      job: job, version: '1.1.9+22', tools: const {'OS': 'test'}, gitHash: 'abc', dirty: const [],
      brandJson: '{}', missing: const [], redact: Redactor(const []), backend: section,
    );
    expect(bundle.length, lessThanOrEqualTo(fixBundleCap));
    expect(bundle, contains('### Backend (DEV)'));
  });
}
