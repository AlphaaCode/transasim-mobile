@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/studio/src/cases.dart';
import '../../tool/studio/src/fix_bundle.dart';
import '../../tool/studio/src/incidents.dart';
import '../../tool/studio/src/redact.dart';
import '../../tool/studio/src/runner.dart';
import '../../tool/studio/src/server.dart' show applyPlan;
import '../../tool/studio/src/solve.dart';

/// Slice D1: the case store, retrieval, the seed and Solve. Every secret
/// below is made up. The store is a temporary repository, so what is written
/// (and what is not) can be looked at.
void main() {
  late Directory repo;
  final redact = Redactor(const []);
  final now = DateTime.utc(2026, 10, 14, 9, 30, 15);

  Map<String, dynamic> aCase({String id = 'install-update-incompatible-20261014', String symptom = 'INSTALL_FAILED_UPDATE_INCOMPATIBLE: Existing package com.sabily.esim signatures do not match',
          String diff = '', List<String> tests = const ['uninstall-retry passed'], String incident = 'install-update-incompatible', String date = '2026-10-14'}) =>
      {
        'id': id,
        'incident': incident,
        'symptom': symptom,
        'cause': 'the emulator holds the app signed with another key',
        'diff': diff,
        'tests': tests,
        'solvedBy': 'autofix uninstall-retry',
        'brands': ['sabily'],
        'date': date,
        'job': '20261014-093000-sabily-build-dev',
        'log': '.studio/logs/20261014-093000-sabily-build-dev.log',
      };

  String git(List<String> args) {
    final r = Process.runSync('git', args, workingDirectory: repo.path);
    expect(r.exitCode, 0, reason: 'git ${args.join(' ')}: ${r.stderr}');
    return '${r.stdout}'.trim();
  }

  void commit(String file, String text, String message) {
    File('${repo.path}/$file')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(text);
    git(['add', '-A']);
    git(['commit', '-q', '-m', message]);
  }

  setUp(() {
    repo = Directory.systemTemp.createTempSync('cases');
    git(['init', '-q']);
    git(['config', 'user.email', 't@example.com']);
    git(['config', 'user.name', 'T']);
  });
  tearDown(() => repo.deleteSync(recursive: true));

  group('what a case may hold', () {
    test('a good case has no problems', () {
      expect(caseProblems(aCase(), redact, incidentIds: loadIncidents().keys), isEmpty);
    });

    // Each is built from pieces so this file carries no key-shaped literal.
    final secrets = {
      'a Stripe secret key': 'sk_${'live'}_51AbCdEfGhIjKlMnOp',
      'a bearer token': 'Authorization: Bearer abc123.def456',
      'a JWT': 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTYifQ.c2lnbmF0dXJlMTIzNDU',
      'a password': 'password=hunter2hunter2',
      'a signed URL': 'https://x.example/f.pdf?X-Amz-Signature=deadbeef1234',
      'a publishable key': 'pk_${'live'}_51AbCdEfGhIjKlMnOpQrStUv',
    };
    for (final MapEntry(key: kind, value: secret) in secrets.entries) {
      for (final field in ['symptom', 'cause', 'diff']) {
        test('$kind in $field refuses the whole case, naming the field and not the value', () {
          final c = aCase()..[field] = 'something went wrong near $secret here';
          final problems = caseProblems(c, redact);
          expect(problems.map((p) => p.$1), contains(field));
          for (final (_, why) in problems) {
            expect(why, isNot(contains(secret)));
            expect(why, isNot(contains(secret.split(' ').last)));
          }
          final plan = casesPlan(repo.path, [c], redact: redact);
          expect(plan.errors, isNotEmpty);
          expect(plan.changedPaths, isEmpty, reason: 'nothing of a refused case is kept, not even redacted');
        });
      }
    }

    test('a secret in a test line is refused too, by its index', () {
      final problems = caseProblems(aCase(tests: ['fine', 'with sk_${'live'}_51AbCdEfGhIjKlMnOp']), redact);
      expect(problems.map((p) => p.$1), ['tests[1]']);
    });

    test('an e-mail address is not a secret: it is masked', () {
      final c = aCase(symptom: 'sign-in for jane.doe@example.com failed');
      expect(caseProblems(c, redact), isEmpty);
      expect(redactedCase(c, redact)['symptom'], 'sign-in for [email] failed');
    });

    for (final path in ['../../etc/passwd', '/etc/hosts', r'C:\Windows\x.dll', 'a/../../b.txt', '.git/config', 'android/acorn-key.properties',
        'android/app/sabily-upload-key.jks', r'lib\x.dart', '~/x']) {
      test('a diff that touches "$path" is refused', () {
        final diff = 'diff --git a/$path b/$path\n--- a/$path\n+++ b/$path\n@@ -1 +1 @@\n-a\n+b\n';
        final problems = caseProblems(aCase(diff: diff), redact);
        expect(problems.map((p) => p.$1), contains('diff'), reason: path);
        expect(casesPlan(repo.path, [aCase(diff: diff)], redact: redact).changedPaths, isEmpty);
      });
    }

    test('a normal diff and a test path inside the repository pass', () {
      const diff = 'diff --git a/lib/core/x.dart b/lib/core/x.dart\n--- a/lib/core/x.dart\n+++ b/lib/core/x.dart\n@@ -1 +1 @@\n-a\n+b\n';
      expect(caseProblems(aCase(diff: diff, tests: ['test/core/x_test.dart']), redact), isEmpty);
      expect(caseProblems(aCase(tests: ['../outside_test.dart']), redact).map((p) => p.$1), ['tests[0]']);
    });

    test('an unknown incident, a bad id and an oversized diff are refused', () {
      expect(caseProblems(aCase(incident: 'no-such-incident'), redact, incidentIds: loadIncidents().keys).map((p) => p.$1), ['incident']);
      expect(caseProblems(aCase(id: 'Bad Id'), redact).map((p) => p.$1), ['id']);
      expect(caseProblems(aCase(diff: 'x' * 30001), redact).map((p) => p.$1), contains('diff'));
    });
  });

  group('storing, only through Apply', () {
    test('a plan writes nothing; Apply writes a private and a committed copy', () async {
      final plan = casesPlan(repo.path, [aCase()], redact: redact);
      expect(plan.errors, isEmpty);
      expect(Directory('${repo.path}/tool').existsSync() || Directory('${repo.path}/.studio').existsSync(), isFalse,
          reason: 'building the plan touches no file');
      expect(plan.changedPaths, [
        'tool/studio/cases/install-update-incompatible-20261014.yaml',
        '.studio/cases/install-update-incompatible-20261014.yaml',
      ]);
      await applyPlan(repo.path, plan, {}, (_, _) async {});
      final committed = File('${repo.path}/tool/studio/cases/install-update-incompatible-20261014.yaml').readAsStringSync();
      final private = File('${repo.path}/.studio/cases/install-update-incompatible-20261014.yaml').readAsStringSync();
      expect(committed, isNot(contains('job')), reason: 'the shared copy does not say which job or log it came from');
      expect(committed, isNot(contains('.studio/logs')));
      expect(private, allOf(contains('job:'), contains('log:')));
    });

    test('a case reads back exactly, diff included, whatever the diff holds', () async {
      const diff = 'diff --git a/lib/a.dart b/lib/a.dart\n--- a/lib/a.dart\n+++ b/lib/a.dart\n@@ -1,4 +1,4 @@\n'
          ' \tkeep: "quotes", # not a comment\n-  old line with trailing space \n+  new: line\n \n+    indented\n';
      final c = aCase(diff: diff, tests: ['test/a_test.dart', 'ran: all "green"']);
      await applyPlan(repo.path, casesPlan(repo.path, [c], redact: redact), {}, (_, _) async {});
      final back = loadCases(repo.path).single;
      expect(back['diff'], diff);
      expect(back['symptom'], c['symptom']);
      expect(back['tests'], ['test/a_test.dart', 'ran: all "green"']);
      expect(back['brands'], ['sabily']);
      expect(back['incident'], 'install-update-incompatible');
      expect(back['job'], isNotNull, reason: 'the private copy wins when both exist');
    });

    test('a diff without a final newline, and an empty one, survive', () async {
      await applyPlan(repo.path, casesPlan(repo.path, [aCase(id: 'a', diff: 'one\ntwo'), aCase(id: 'b', diff: '')], redact: redact), {}, (_, _) async {});
      final byId = {for (final c in loadCases(repo.path)) c['id']: c};
      expect(byId['a']!['diff'], 'one\ntwo');
      expect(byId['b']!['diff'], '');
    });

    test('every string is redacted on the way in', () {
      final plan = casesPlan(repo.path, [aCase(symptom: 'for jane.doe@example.com')], redact: redact);
      expect(plan.text.map((c) => c.after).join(), isNot(contains('jane.doe')));
      expect(plan.text.map((c) => c.after).join(), contains('[email]'));
    });
  });

  group('retrieval', () {
    final cases = [
      aCase(id: 'same-incident', symptom: 'something unrelated entirely', date: '2026-01-01'),
      aCase(id: 'overlap-two', incident: '', symptom: 'gradle daemon thrashing garbage collector', date: '2026-02-01'),
      aCase(id: 'overlap-one', incident: '', symptom: 'garbage in the heap', date: '2026-03-01'),
      aCase(id: 'nothing-shared', incident: '', symptom: 'emulator airplane mode', date: '2026-04-01'),
    ];

    test('the same incident ranks above any word overlap, then by shared words; nothing shared is left out', () {
      final r = rankCases(cases, incidentIds: ['install-update-incompatible'], symptom: 'Gradle daemon: garbage collector is thrashing');
      expect([for (final x in r) x.found['id']], ['same-incident', 'overlap-two', 'overlap-one']);
      expect(r.first.why, 'same incident');
      expect(r[1].why, '5 shared words');
    });

    test('without an incident it is the words alone, and a limit cuts the list', () {
      final r = rankCases(cases, symptom: 'garbage collector thrashing', limit: 1);
      expect([for (final x in r) x.found['id']], ['overlap-two']);
      expect(rankCases(cases, symptom: ''), isEmpty);
    });

    test('equal scores come out newest first, the same on every run', () {
      final twins = [aCase(id: 'old', incident: '', symptom: 'garbage', date: '2026-01-01'), aCase(id: 'new', incident: '', symptom: 'garbage', date: '2026-05-01')];
      for (var i = 0; i < 3; i++) {
        expect([for (final x in rankCases(twins, symptom: 'garbage')) x.found['id']], ['new', 'old']);
      }
    });
  });

  group('the seed', () {
    setUp(() {
      commit('lib/a.dart', 'a\n', 'feat: add a');
      commit('lib/a.dart', 'a\nb\n', 'fix: the a screen overflowed');
      commit('test/a_test.dart', 'test\n', 'Fix the b screen');
      commit('lib/keys.dart', 'const k = "sk_${'live'}_51AbCdEfGhIjKlMnOp";\n', 'fix: use the key');
      commit('lib/c.dart', 'c\n', 'chore: unrelated');
    });

    test('candidates: one per incident signature, one per "fix" commit; others are not', () {
      final incidents = loadIncidents();
      final c = seedCandidates(repo.path, incidents: incidents, now: now);
      final signatures = incidents.values.where((i) => i.kind == 'signature' && i.matchExamples.isNotEmpty).length;
      expect(c.where((x) => '${x['id']}'.startsWith('seed-')), hasLength(signatures));
      final fixes = c.where((x) => '${x['id']}'.startsWith('fix-')).toList();
      expect(fixes.map((x) => x['symptom']), unorderedEquals(['fix: the a screen overflowed', 'Fix the b screen', 'fix: use the key']));
      expect(fixes.firstWhere((x) => x['symptom'] == 'Fix the b screen')['tests'], ['test/a_test.dart']);
    });

    test('a dry run writes nothing; the commit holding a key is skipped with a warning, the rest are kept', () {
      final incidents = loadIncidents();
      final before = repo.listSync().map((e) => e.path).toSet();
      final plan = casesPlan(repo.path, seedCandidates(repo.path, incidents: incidents, now: now),
          redact: redact, strict: false, incidentIds: incidents.keys);
      expect(repo.listSync().map((e) => e.path).toSet(), before, reason: 'no file, no folder: nothing until Apply');
      expect(plan.errors, isEmpty);
      expect(plan.warnings.map((w) => w['field']).join(), contains('skipped fix-'));
      expect(plan.warnings.map((w) => w['reason']).join(), isNot(contains('51AbCdEf')));
      final stored = plan.text.map((c) => c.path).where((p) => p.startsWith('tool/studio/cases/')).toList();
      expect(stored.where((p) => p.contains('/fix-')), hasLength(2), reason: 'two fix commits are clean, one holds a key');
    });

    test('after Apply the seeded cases are found by retrieval', () async {
      final incidents = loadIncidents();
      final plan = casesPlan(repo.path, seedCandidates(repo.path, incidents: incidents, now: now),
          redact: redact, strict: false, incidentIds: incidents.keys);
      await applyPlan(repo.path, plan, {}, (_, _) async {});
      final r = rankCases(loadCases(repo.path), incidentIds: ['transatel-bad-sim'], symptom: 'activation refused');
      expect(r.first.found['id'], 'seed-transatel-bad-sim');
    });
  });

  group('Solve', () {
    final failure = Failure(
      jobId: 'job-1', slug: 'sabily', job: 'build-dev', symptom: 'INSTALL_FAILED_UPDATE_INCOMPATIBLE signatures do not match',
      incident: const FailedIncident(
        id: 'install-update-incompatible', title: 'signed with another key', cause: 'another key', line: 'INSTALL_FAILED_UPDATE_INCOMPATIBLE',
        autofix: {'job': 'uninstall-retry', 'label': 'Uninstall from the emulator and retry'},
      ),
    );

    test('the stages come in order: autofix, nearest cases, Fix Bundle', () {
      final stages = solveStages(failure, [aCase()], SolveBook());
      expect([for (final s in stages) s['stage']], ['autofix', 'cases', 'bundle']);
      expect(stages.first['job'], 'uninstall-retry');
      expect(((stages[1]['cases'] as List).single as Map)['id'], 'install-update-incompatible-20261014');
    });

    test('with no autofix it starts at the cases; with no case it still ends at the bundle', () {
      final plain = Failure(jobId: 'j', slug: 'sabily', job: 'build-dev', symptom: 'something odd');
      final stages = solveStages(plain, [aCase()], SolveBook());
      expect([for (final s in stages) s['stage']], ['cases', 'bundle']);
      expect(stages.first['cases'], isEmpty);
    });

    test('nothing is run: Solve only reads, and the autofix is a button the page shows', () {
      final book = SolveBook();
      solveStages(failure, [aCase()], book);
      expect(book.triedFor('job-1').autofixes, isEmpty, reason: 'only a press records an autofix');
      expect(book.proposals, isEmpty);
    });

    test('the Fix Bundle lists the cases and the autofix already tried', () async {
      final book = SolveBook()..autofixStarted('fix-job', 'uninstall-retry', failure);
      solveStages(failure, [aCase()], book);
      final lines = triedLines(book.triedFor('job-1'), [aCase()]);
      expect(lines, [
        '- autofix pressed: uninstall-retry',
        startsWith('- case install-update-incompatible-20261014 (autofix uninstall-retry, 2026-10-14): INSTALL_FAILED_UPDATE_INCOMPATIBLE'),
      ]);

      final dir = Directory.systemTemp.createTempSync('bundle');
      addTearDown(() => dir.deleteSync(recursive: true));
      final runner = Runner(logsDir: '${dir.path}/logs', redact: redact, incidents: loadIncidents());
      final dart = '${flutterRoot()}/bin/cache/dart-sdk/bin/dart${Platform.isWindows ? '.exe' : ''}';
      final script = File('${dir.path}/f.dart')..writeAsStringSync('import "dart:io"; void main() { print("E boom"); exit(1); }');
      final job = runner.enqueue('sabily', 'build-dev', [Step(dart, [script.path])]);
      await job.done;
      String bundle(List<String> tried) => fixBundle(
            job: job, version: '1.1.9+22', tools: const {}, gitHash: 'abc1234', dirty: const [], brandJson: '{}', missing: const [],
            redact: redact, tried: tried);
      expect(bundle(lines), allOf(contains('### Cases already tried'), contains('- autofix pressed: uninstall-retry'), contains('- case install-update-incompatible-20261014')));
      expect(bundle(const []), isNot(contains('Cases already tried')));
    });
  });

  group('saving a case when a fix worked', () {
    final failure = Failure(
      jobId: 'job-1', slug: 'sabily', job: 'build-dev', symptom: 's',
      incident: const FailedIncident(id: 'gradle-heap', title: 'heap', cause: 'R8 ran out of heap', line: 'java.lang.OutOfMemoryError: Java heap space', autofix: {'job': 'gradle-stop', 'label': 'Stop'}),
    );

    test('an autofix that passed, then the failed job passing again, proposes a case', () {
      final book = SolveBook()..autofixStarted('fix-1', 'gradle-stop', failure);
      expect(book.jobEnded(jobId: 'fix-1', slug: 'sabily', name: 'gradle-stop', passed: true, now: now), isNull, reason: 'not yet: the relaunch has not passed');
      expect(book.jobEnded(jobId: 'x', slug: 'esimple', name: 'build-dev', passed: true, now: now), isNull, reason: 'another brand');
      final c = book.jobEnded(jobId: 'job-2', slug: 'sabily', name: 'build-dev', passed: true, now: now)!;
      expect(c['incident'], 'gradle-heap');
      expect(c['solvedBy'], 'autofix gradle-stop');
      expect(c['tests'], ['gradle-stop passed, then build-dev passed again']);
      expect(c['symptom'], 'java.lang.OutOfMemoryError: Java heap space');
      expect(c['id'], 'gradle-heap-20261014-093015');
      expect(caseProblems(c, redact, incidentIds: loadIncidents().keys), isEmpty);
      expect(book.proposals, contains(c['id']));
      expect(book.jobEnded(jobId: 'job-3', slug: 'sabily', name: 'build-dev', passed: true, now: now), isNull, reason: 'proposed once');
    });

    test('uninstall-retry is its own relaunch: passing is enough', () {
      final book = SolveBook()..autofixStarted('fix-1', 'uninstall-retry', failure);
      expect(book.jobEnded(jobId: 'fix-1', slug: 'sabily', name: 'uninstall-retry', passed: true, now: now)!['solvedBy'], 'autofix uninstall-retry');
    });

    test('a failed autofix, or a failed relaunch, proposes nothing', () {
      final book = SolveBook()..autofixStarted('fix-1', 'gradle-stop', failure);
      expect(book.jobEnded(jobId: 'fix-1', slug: 'sabily', name: 'gradle-stop', passed: false, now: now), isNull);
      expect(book.jobEnded(jobId: 'job-2', slug: 'sabily', name: 'build-dev', passed: true, now: now), isNull);
      expect(book.proposals, isEmpty);
    });

    test('a proposal is stored only by Apply, and then is no longer a proposal', () async {
      final book = SolveBook()..autofixStarted('fix-1', 'uninstall-retry', failure);
      final c = book.jobEnded(jobId: 'fix-1', slug: 'sabily', name: 'uninstall-retry', passed: true, now: now)!;
      final plan = casesPlan(repo.path, [c], redact: redact, incidentIds: loadIncidents().keys);
      expect(plan.errors, isEmpty);
      expect(loadCases(repo.path), isEmpty, reason: 'proposed, not stored');
      await applyPlan(repo.path, plan, {}, (_, _) async {});
      expect(loadCases(repo.path).single['id'], c['id']);
    });
  });
}
