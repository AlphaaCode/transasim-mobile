/// The test record (Slice C1, docs/STUDIO-SPEC.md §6.2): a Pass, a Fail or a
/// Skip that Alpha records for a brand after trying it by hand, kept in
/// `brands/<slug>/studio.json` `tests`. Whether a brand is *Tested* is worked
/// out from it each time and never stored: the newest record counts, and only
/// while the commit and the brand still are the ones it was recorded for.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'assets.dart';
import 'generate.dart';
import 'redact.dart';

const testResults = ['pass', 'fail', 'skip'];
const _keep = 20;

/// Fingerprint of the brand as the app sees it: brand.json and studio.json
/// without `tests`, so recording a result does not undo itself.
String brandHash(String root, String slug) {
  final brandFile = File('$root/brands/$slug/brand.json');
  final brand = brandFile.existsSync() ? jsonDecode(brandFile.readAsStringSync()) : null;
  final studio = {...readStudio(root, slug)}..remove('tests');
  return sha256.convert(utf8.encode(jsonEncode([brand, studio]))).toString().substring(0, 16);
}

String? _git(String root, List<String> args) {
  final r = Process.runSync('git', args, workingDirectory: root);
  return r.exitCode == 0 ? '${r.stdout}'.trim() : null;
}

/// The commit the working tree is on, or null outside a repository.
String? headCommit(String root) => _git(root, ['rev-parse', 'HEAD']);

/// Whether anything but [slug]'s own studio.json differs between [from] and
/// HEAD. That file is where the record itself is committed, so committing the
/// record must not undo it; any other change is new code to try.
bool codeChangedSince(String root, String slug, String from) {
  final r = Process.runSync(
      'git', ['diff', '--quiet', from, 'HEAD', '--', '.', ':(exclude)brands/$slug/studio.json'],
      workingDirectory: root);
  return r.exitCode != 0;
}

/// Files git shows as changed or untracked, other than [slug]'s studio.json.
List<String> changedBesidesRecord(String root, String slug) {
  final r = Process.runSync('git', ['status', '--porcelain'], workingDirectory: root);
  if (r.exitCode != 0) return const ['(git failed)'];
  return [
    for (final line in '${r.stdout}'.split('\n'))
      if (line.length > 3 && line.substring(3).trim() != 'brands/$slug/studio.json') line.substring(3).trim(),
  ];
}

/// Where a brand stands: [status] is untested, stale, failed, passed or skipped.
class TestState {
  const TestState(this.status, this.detail, {this.record});
  final String status;
  final String detail;
  final Map<String, dynamic>? record;

  /// Pass and Skip let a release through; Skip is a recorded result like any other.
  bool get unlocks => status == 'passed' || status == 'skipped';

  Map<String, Object?> toJson() => {'status': status, 'detail': detail, 'unlocks': unlocks, 'record': record};
}

/// The state of [slug] now.
TestState testState(String root, String slug) {
  final tests = (readStudio(root, slug)['tests'] as List? ?? const []).whereType<Map>().toList();
  if (tests.isEmpty) return const TestState('untested', 'no result recorded for this brand');
  final last = tests.last.cast<String, dynamic>();
  final head = headCommit(root);
  final at = '${last['at'] ?? ''}';
  if ('${last['brandHash']}' != brandHash(root, slug)) {
    return TestState('stale', 'the brand changed since the result recorded $at', record: last);
  }
  if (head == null || '${last['gitHash']}'.isEmpty) {
    return TestState('stale', 'the commit cannot be compared', record: last);
  }
  if ('${last['gitHash']}' != head && codeChangedSince(root, slug, '${last['gitHash']}')) {
    return TestState('stale', 'there are new commits since the result recorded $at', record: last);
  }
  return switch (last['result']) {
    'pass' => TestState('passed', 'Pass recorded $at', record: last),
    'skip' => TestState('skipped', 'Skip recorded $at', record: last),
    _ => TestState('failed', 'Fail recorded $at: record a Pass or a Skip after fixing it', record: last),
  };
}

/// The refusal a release gets for [state], or null when it may go.
String? testRefusal(TestState state) => state.unlocks
    ? null
    : 'not tested: ${state.detail}. Record a result in Build ("Tested on device/emulator": Pass, or Skip) for this commit first';

/// The studio.json change that records [result] for [slug] at the current
/// commit. A previewed Apply only: nothing is written here.
Plan testRecordPlan(String root, String slug, String result, String note, {required DateTime now}) {
  final plan = Plan();
  final text = note.trim();
  if (!testResults.contains(result)) plan.error('result', 'pass, fail or skip');
  if (text.length > 300) plan.error('note', 'at most 300 characters');
  if (Redactor.forRepo(root).found(text).isNotEmpty) {
    plan.error('note', 'looks like a secret; a note never holds one');
  }
  final head = headCommit(root);
  if (head == null) plan.error('commit', 'this is not a git repository, so there is no commit to record');
  final others = changedBesidesRecord(root, slug);
  if (others.isNotEmpty) {
    plan.error('tree', 'commit first: the result is for a commit, and these files have changes: ${others.take(5).join(', ')}');
  }
  if (plan.errors.isNotEmpty || head == null) return plan;

  final studio = readStudio(root, slug);
  final tests = [...(studio['tests'] as List? ?? const [])];
  tests.add({
    'result': result,
    'at': now.toUtc().toIso8601String(),
    'gitHash': head,
    'brandHash': brandHash(root, slug),
    if (text.isNotEmpty) 'note': text,
  });
  studio['tests'] = tests.length > _keep ? tests.sublist(tests.length - _keep) : tests;
  final file = File('$root/brands/$slug/studio.json');
  plan.text.add(FileChange('brands/$slug/studio.json', file.existsSync() ? file.readAsStringSync() : null,
      '${const JsonEncoder.withIndent('  ').convert(studio)}\n'));
  plan.notes.add('Records "$result" for commit ${head.substring(0, 7)}. It is a change to studio.json: '
      'commit it, and the release still counts it.');
  return plan;
}
