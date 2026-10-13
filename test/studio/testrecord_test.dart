@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/studio/src/server.dart' show applyPlan;
import '../../tool/studio/src/testrecord.dart';

/// Slice C1: the test record, on a throwaway git repository so commits and
/// edits are real.
void main() {
  late Directory repo;
  final now = DateTime.utc(2026, 10, 13, 9);

  String git(List<String> args) {
    final r = Process.runSync('git', args, workingDirectory: repo.path);
    expect(r.exitCode, 0, reason: 'git ${args.join(' ')}: ${r.stderr}');
    return '${r.stdout}'.trim();
  }

  void write(String path, String text) => File('${repo.path}/$path')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(text);

  void commit(String message) {
    git(['add', '-A']);
    git(['commit', '-q', '-m', message]);
  }

  Map<String, dynamic> studioJson() => jsonDecode(File('${repo.path}/brands/demo/studio.json').readAsStringSync()) as Map<String, dynamic>;

  /// Records [result] through the plan and writes it as Apply does.
  Future<void> record(String result, {String note = ''}) async {
    final plan = testRecordPlan(repo.path, 'demo', result, note, now: now);
    expect(plan.errors, isEmpty, reason: '${plan.errors}');
    // The record is a studio.json change; recording twice before a commit overwrites it on purpose.
    await applyPlan(repo.path, plan, {'brands/demo/studio.json'}, (_, _) async {});
  }

  setUp(() {
    repo = Directory.systemTemp.createTempSync('testrecord');
    git(['init', '-q']);
    git(['config', 'user.email', 't@example.com']);
    git(['config', 'user.name', 'T']);
    write('brands/demo/brand.json', '{"slug": "demo", "name": "Demo"}\n');
    write('brands/demo/studio.json', '{"appleTeamId": "X"}\n');
    write('lib/app.dart', '// app\n');
    commit('first');
  });
  tearDown(() => repo.deleteSync(recursive: true));

  test('a brand with no result is untested, and the refusal says what to do', () {
    final s = testState(repo.path, 'demo');
    expect(s.status, 'untested');
    expect(s.unlocks, isFalse);
    expect(testRefusal(s), allOf(contains('not tested'), contains('Record a result in Build'), contains('Skip')));
  });

  test('nothing is written until Apply: the plan only describes the change', () {
    final before = File('${repo.path}/brands/demo/studio.json').readAsStringSync();
    final plan = testRecordPlan(repo.path, 'demo', 'pass', 'works on the emulator', now: now);
    expect(plan.errors, isEmpty);
    expect(plan.changedPaths, ['brands/demo/studio.json']);
    expect(File('${repo.path}/brands/demo/studio.json').readAsStringSync(), before);
    expect(testState(repo.path, 'demo').status, 'untested');
    expect(Process.runSync('git', ['status', '--porcelain'], workingDirectory: repo.path).stdout, '');
  });

  test('a recorded Pass reads back, with its commit, brand hash, time and note', () async {
    await record('pass', note: 'sign-in and the catalogue work');
    final s = testState(repo.path, 'demo');
    expect(s.status, 'passed');
    expect(s.unlocks, isTrue);
    expect(testRefusal(s), isNull);
    expect((studioJson()['tests'] as List).single, {
      'result': 'pass',
      'at': '2026-10-13T09:00:00.000Z',
      'gitHash': git(['rev-parse', 'HEAD']),
      'brandHash': brandHash(repo.path, 'demo'),
      'note': 'sign-in and the catalogue work',
    });
  });

  test('Skip unlocks, and is recorded as a skip', () async {
    await record('skip');
    expect(testState(repo.path, 'demo').status, 'skipped');
    expect(testState(repo.path, 'demo').unlocks, isTrue);
  });

  test('Fail does not unlock, and a later Pass does', () async {
    await record('fail', note: 'crashes on launch');
    final s = testState(repo.path, 'demo');
    expect(s.status, 'failed');
    expect(s.unlocks, isFalse);
    expect(testRefusal(s), contains('Fail recorded'));
    await record('pass');
    expect(testState(repo.path, 'demo').status, 'passed', reason: 'the newest record counts');
  });

  test('committing the record itself does not undo it', () async {
    await record('pass');
    commit('record the test');
    expect(testState(repo.path, 'demo').status, 'passed');
  });

  test('a brand edit resets it: the hash changes', () async {
    final h = brandHash(repo.path, 'demo');
    await record('pass');
    expect(brandHash(repo.path, 'demo'), h, reason: 'recording a result is not a brand edit');
    commit('record');
    write('brands/demo/brand.json', '{"slug": "demo", "name": "Demo 2"}\n');
    expect(brandHash(repo.path, 'demo'), isNot(h));
    commit('rename');
    final s = testState(repo.path, 'demo');
    expect(s.status, 'stale');
    expect(s.unlocks, isFalse);
    expect(s.detail, contains('brand changed'));
  });

  test('an edit to the rest of studio.json resets it too', () async {
    await record('pass');
    commit('record');
    final next = studioJson()..['appleTeamId'] = 'Y';
    write('brands/demo/studio.json', jsonEncode(next));
    expect(testState(repo.path, 'demo').status, 'stale');
  });

  test('a new commit that changes the code resets it', () async {
    await record('pass');
    commit('record');
    expect(testState(repo.path, 'demo').status, 'passed');
    write('lib/app.dart', '// app, changed\n');
    commit('change the app');
    final s = testState(repo.path, 'demo');
    expect(s.status, 'stale');
    expect(s.detail, contains('new commits'));
    expect(testRefusal(s), contains('Record a result in Build'));
  });

  test("a commit touching only another brand's folder keeps the state", () async {
    await record('pass');
    commit('record');
    write('brands/other/brand.json', '{}\n');
    write('brands/other/studio.json', '{"x": 1}\n');
    commit('other brand');
    expect(testState(repo.path, 'demo').status, 'passed');
  });

  test("a commit touching shared code, or this brand's own folder, resets it", () async {
    await record('pass');
    commit('record');
    write('brands/demo/assets/logo.png', 'png');
    commit('this brand asset');
    expect(testState(repo.path, 'demo').status, 'stale', reason: 'its own folder');
    await record('pass');
    commit('record again');
    expect(testState(repo.path, 'demo').status, 'passed');
    write('pubspec.yaml', 'name: x\n');
    commit('shared file');
    expect(testState(repo.path, 'demo').status, 'stale', reason: 'outside brands/');
  });

  test('the plan is refused with other uncommitted changes, a secret note, or a bad result', () {
    write('lib/app.dart', '// edited, not committed\n');
    expect(testRecordPlan(repo.path, 'demo', 'pass', '', now: now).errors.single['reason'], contains('commit first'));
    git(['checkout', '--', 'lib/app.dart']);
    expect(testRecordPlan(repo.path, 'demo', 'pass', 'key sk_live_51ABCDEFGHIJKLMNOP', now: now).errors.single['field'], 'note');
    expect(testRecordPlan(repo.path, 'demo', 'maybe', '', now: now).errors.single['field'], 'result');
    expect(testRecordPlan(repo.path, 'demo', 'pass', 'a day ' * 60, now: now).errors.single['field'], 'note');
  });

  test('only the newest 20 results are kept', () async {
    for (var i = 0; i < 22; i++) {
      await record(i.isEven ? 'pass' : 'fail', note: 'run $i');
      commit('record $i');
    }
    final tests = studioJson()['tests'] as List;
    expect(tests, hasLength(20));
    expect((tests.first as Map)['note'], 'run 2');
  });
}
