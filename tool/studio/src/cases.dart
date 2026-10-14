/// The case store (Slice D1, docs/STUDIO-SPEC.md §18): what was wrong, why,
/// and what fixed it, kept so the next failure that looks the same can show
/// the nearest earlier ones. A case is one yaml file. Two copies are written
/// together, only ever through a previewed Apply:
///
/// - `.studio/cases/<id>.yaml`, private (gitignored), with the job and the log
///   it came from;
/// - `tool/studio/cases/<id>.yaml`, committed, secret-free, without them.
///
/// Nothing here reads a server, runs a model or replays a diff.
library;

import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

import 'assets.dart';
import 'generate.dart';
import 'incidents.dart';
import 'redact.dart';

const casesDir = 'tool/studio/cases';
const privateCasesDir = '.studio/cases';

const _maxText = 1500;
const _maxDiff = 30000;
final _idPattern = RegExp(r'^[a-z0-9][a-z0-9-]{0,79}$');
final _slugPattern = RegExp(r'^[a-z][a-z0-9]*$');

/// A path a case may name: inside the repository, relative, and not one of the
/// files Studio never touches (keys, keystores, git's own files).
String? badCasePath(String path) {
  final p = path.trim();
  if (p.isEmpty) return 'is empty';
  if (p.contains('\u0000')) return 'holds a NUL byte';
  if (p.startsWith('/') || p.startsWith(r'\') || RegExp(r'^[A-Za-z]:').hasMatch(p) || p.startsWith('~')) {
    return 'is not relative to the repository';
  }
  if (p.contains(r'\')) return 'uses a backslash';
  final parts = p.split('/');
  if (parts.contains('..')) return 'leaves the repository (..)';
  if (parts.contains('.git')) return 'is inside .git';
  final name = parts.last.toLowerCase();
  if (name.endsWith('key.properties') || name.endsWith('.jks') || name.endsWith('.keystore') ||
      name == '.env' || name.startsWith('.env.')) {
    return 'is a key or secret file';
  }
  return null;
}

/// The file paths a unified diff names, from its `diff --git`, `---` and `+++` lines.
List<String> diffPaths(String diff) {
  final out = <String>{};
  for (final line in diff.split('\n')) {
    final m = RegExp(r'^diff --git a/(.+?) b/(.+)$').firstMatch(line);
    if (m != null) {
      out
        ..add(m[1]!)
        ..add(m[2]!);
      continue;
    }
    final h = RegExp(r'^(?:---|\+\+\+) (?:[ab]/)?(.+?)(?:\t.*)?$').firstMatch(line);
    if (h != null && h[1] != '/dev/null') out.add(h[1]!);
  }
  return out.toList();
}

/// What is wrong with [c] as (field, reason); empty when it may be stored.
/// A secret-shaped value refuses the whole case, naming the field and never
/// the value.
List<(String, String)> caseProblems(Map<String, dynamic> c, Redactor redact, {Iterable<String>? incidentIds}) {
  final out = <(String, String)>[];
  void bad(String f, String why) => out.add((f, why));
  String s(String k) => c[k] is String ? c[k] as String : '';
  List<String> list(String k) => c[k] is List ? [for (final e in c[k] as List) '$e'] : const [];

  if (!_idPattern.hasMatch(s('id'))) bad('id', 'lowercase letters, digits and hyphens, at most 80');
  final incident = s('incident');
  if (incident.isNotEmpty && incidentIds != null && !incidentIds.contains(incident)) {
    bad('incident', 'no incident "$incident" in the incident list');
  }
  if (s('symptom').trim().isEmpty) bad('symptom', 'what was seen: required');
  for (final k in const ['symptom', 'cause']) {
    if (s(k).length > _maxText) bad(k, 'at most $_maxText characters');
  }
  if (s('diff').length > _maxDiff) bad('diff', 'at most $_maxDiff characters: a case is a small fix');
  if (s('solvedBy').length > 100) bad('solvedBy', 'at most 100 characters');
  if (!RegExp(r'^\d{4}-\d\d-\d\d$').hasMatch(s('date'))) bad('date', 'a date, 2026-10-14');
  for (final b in list('brands')) {
    if (b != 'all' && !_slugPattern.hasMatch(b)) bad('brands', '"$b" is not a brand folder name');
  }
  final tests = list('tests');
  if (tests.length > 20) bad('tests', 'at most 20');

  // Paths: the diff's, and any test that is written as one.
  for (final p in diffPaths(s('diff'))) {
    if (badCasePath(p) case final why?) bad('diff', 'names "$p", which $why');
  }
  for (final (i, t) in tests.indexed) {
    if (t.length > 200) bad('tests[$i]', 'at most 200 characters');
    final looksLikePath = (t.contains('/') || t.endsWith('.dart')) && !t.contains(' ');
    if (looksLikePath) {
      if (badCasePath(t) case final why?) bad('tests[$i]', '"$t" $why');
    }
  }

  // Secrets last: a case that holds one is refused whole, never edited.
  void scan(String field, String text) {
    final kinds = redact.found(text).where((k) => k != 'an e-mail address').toList();
    if (kinds.isNotEmpty) {
      bad(field, 'holds a value shaped like a secret (${kinds.join(', ')}): the whole case is refused and nothing is kept');
    }
  }

  for (final k in const ['id', 'incident', 'symptom', 'cause', 'diff', 'solvedBy', 'date']) {
    scan(k, s(k));
  }
  for (final (i, t) in tests.indexed) {
    scan('tests[$i]', t);
  }
  for (final (i, b) in list('brands').indexed) {
    scan('brands[$i]', b);
  }
  return out;
}

/// [c] with every string through the redactor (an e-mail address becomes
/// `[email]`, as in every log), and only the fields a case has.
Map<String, dynamic> redactedCase(Map<String, dynamic> c, Redactor redact, {bool private = false}) {
  String s(String k) => redact('${c[k] ?? ''}'.replaceAll('\r', ''));
  List<String> list(String k) => [for (final e in (c[k] as List? ?? const [])) redact('$e')];
  return {
    'id': s('id'),
    'incident': s('incident'),
    'symptom': s('symptom'),
    'cause': s('cause'),
    'diff': s('diff'),
    'tests': list('tests'),
    'solvedBy': s('solvedBy'),
    'brands': list('brands'),
    'date': s('date'),
    // Only the private copy says which job and log it came from.
    if (private && c['job'] != null) 'job': redact('${c['job']}'),
    if (private && c['log'] != null) 'log': redact('${c['log']}'),
  };
}

/// The yaml text of a case. Strings are written as double-quoted scalars (JSON
/// escapes are valid yaml); a diff is a literal block so it can be read and
/// reviewed in a commit.
String caseYaml(Map<String, dynamic> c) {
  final b = StringBuffer();
  void scalar(String k, Object? v) => b.writeln('$k: ${jsonEncode(v)}');
  for (final k in const ['id', 'incident']) {
    scalar(k, c[k] ?? '');
  }
  scalar('symptom', c['symptom'] ?? '');
  scalar('cause', c['cause'] ?? '');
  final diff = '${c['diff'] ?? ''}';
  if (diff.isEmpty) {
    b.writeln('diff: ""');
  } else {
    // `|2` fixes the indent at two, so a first line that starts with spaces survives.
    b.writeln(diff.endsWith('\n') ? 'diff: |2' : 'diff: |2-');
    for (final line in (diff.endsWith('\n') ? diff.substring(0, diff.length - 1) : diff).split('\n')) {
      b.writeln(line.isEmpty ? '' : '  $line');
    }
  }
  b.writeln('tests: ${jsonEncode(c['tests'] ?? const [])}');
  scalar('solvedBy', c['solvedBy'] ?? '');
  b.writeln('brands: ${jsonEncode(c['brands'] ?? const [])}');
  scalar('date', c['date'] ?? '');
  for (final k in const ['job', 'log']) {
    if (c[k] != null) scalar(k, c[k]);
  }
  return b.toString();
}

Map<String, dynamic>? parseCase(String text) {
  try {
    final y = loadYaml(text);
    if (y is! YamlMap) return null;
    return {
      for (final e in y.entries)
        '${e.key}': e.value is YamlList ? [for (final x in e.value as YamlList) '$x'] : e.value,
    };
  } on YamlException {
    return null;
  }
}

/// Every case, the private copy winning over the committed one with the same id.
List<Map<String, dynamic>> loadCases(String root) {
  final byId = <String, Map<String, dynamic>>{};
  for (final dir in [casesDir, privateCasesDir]) {
    final d = Directory('$root/$dir');
    if (!d.existsSync()) continue;
    for (final f in d.listSync().whereType<File>().where((f) => f.path.endsWith('.yaml'))) {
      if (parseCase(f.readAsStringSync()) case final c? when c['id'] != null) byId['${c['id']}'] = c;
    }
  }
  return byId.values.toList()..sort((a, b) => '${a['id']}'.compareTo('${b['id']}'));
}

String? _read(String root, String path) {
  final f = File('$root/$path');
  return f.existsSync() ? f.readAsStringSync() : null;
}

/// The previewed change that stores [cases]. A case that fails
/// [caseProblems] is an error when [strict] (a single save), and is skipped
/// with a warning otherwise (the seed, where one refused commit must not
/// block the rest). Nothing is written here.
Plan casesPlan(String root, List<Map<String, dynamic>> cases, {required Redactor redact, bool strict = true, Iterable<String>? incidentIds}) {
  final plan = Plan();
  final ids = <String>{};
  for (final c in cases) {
    final id = '${c['id']}';
    final problems = caseProblems(c, redact, incidentIds: incidentIds);
    if (!ids.add(id)) problems.add(('id', 'two cases with the id "$id"'));
    if (problems.isNotEmpty) {
      for (final (field, why) in problems) {
        strict ? plan.error('case $id: $field', why) : plan.warn('skipped $id: $field', why);
      }
      continue;
    }
    for (final (dir, private) in [(casesDir, false), (privateCasesDir, true)]) {
      final path = '$dir/$id.yaml';
      plan.text.add(FileChange(path, _read(root, path), caseYaml(redactedCase(c, redact, private: private))));
    }
  }
  return plan;
}

// ---- retrieval --------------------------------------------------------------

const _stop = {
  'the', 'and', 'for', 'with', 'that', 'this', 'from', 'was', 'not', 'are', 'has', 'have', 'but', 'you', 'its', 'into', 'when',
};

/// The words of [text] that say something: lower-case, at least three characters.
Set<String> tokens(String text) => {
      for (final w in text.toLowerCase().split(RegExp(r'[^a-z0-9_]+')))
        if (w.length >= 3 && !_stop.contains(w)) w,
    };

/// [cases] nearest to a failure first: a case for one of [incidentIds] ranks
/// above any other, then by how many words of [symptom] it shares; a case that
/// shares nothing is left out. No model: a count of shared words.
List<({Map<String, dynamic> found, int score, String why})> rankCases(
    List<Map<String, dynamic>> cases, {Iterable<String> incidentIds = const [], String symptom = '', int limit = 5}) {
  final want = tokens(symptom);
  final ranked = <({Map<String, dynamic> found, int score, String why})>[];
  for (final c in cases) {
    final sameIncident = '${c['incident'] ?? ''}'.isNotEmpty && incidentIds.contains(c['incident']);
    final shared = tokens('${c['symptom'] ?? ''}').intersection(want);
    final score = (sameIncident ? 1000 : 0) + shared.length;
    if (score == 0) continue;
    ranked.add((
      found: c,
      score: score,
      why: [if (sameIncident) 'same incident', if (shared.isNotEmpty) '${shared.length} shared words'].join(', '),
    ));
  }
  // Newest first among equals, so the ordering is the same on every run.
  ranked.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    return byScore != 0 ? byScore : '${b.found['date']}${b.found['id']}'.compareTo('${a.found['date']}${a.found['id']}');
  });
  return ranked.take(limit).toList();
}

// ---- seed -------------------------------------------------------------------

/// Cases from what the repository already knows: one per incident signature,
/// and one per commit whose subject starts with "fix". A dry run: it returns
/// candidates and writes nothing. [gitLog] and [gitShow] are for tests.
List<Map<String, dynamic>> seedCandidates(
  String root, {
  required Map<String, Incident> incidents,
  required DateTime now,
  String Function(List<String> args)? git,
  int maxCommits = 200,
}) {
  String run(List<String> args) {
    if (git != null) return git(args);
    final r = Process.runSync('git', args, workingDirectory: root);
    return r.exitCode == 0 ? '${r.stdout}' : '';
  }

  final today = now.toUtc().toIso8601String().substring(0, 10);
  final out = <Map<String, dynamic>>[];
  for (final i in incidents.values.where((i) => i.kind == 'signature' && i.matchExamples.isNotEmpty)) {
    out.add({
      'id': 'seed-${i.id}',
      'incident': i.id,
      'symptom': i.matchExamples.first,
      'cause': i.cause,
      'diff': '',
      'tests': const <String>[],
      'solvedBy': 'incident list',
      'brands': i.brands,
      'date': i.date.length >= 10 ? i.date.substring(0, 10) : today,
    });
  }
  // %x1f / %x1e keep a subject with any punctuation in one piece.
  final log = run(['log', '-n', '$maxCommits', '--pretty=format:%H%x1f%s%x1f%aI%x1e']);
  for (final rec in log.split('\x1e')) {
    final f = rec.trim().split('\x1f');
    if (f.length < 3 || !RegExp(r'^fix', caseSensitive: false).hasMatch(f[1])) continue;
    final diff = run(['show', '--format=', '--patch', '--no-color', f[0]]).replaceAll('\r', '');
    final files = diffPaths(diff);
    out.add({
      'id': 'fix-${f[0].substring(0, 7)}',
      'incident': '',
      'symptom': f[1],
      'cause': '',
      'diff': diff,
      'tests': [for (final p in files) if (p.startsWith('test/')) p],
      'solvedBy': 'commit ${f[0].substring(0, 7)}',
      'brands': const ['all'],
      'date': f[2].length >= 10 ? f[2].substring(0, 10) : today,
    });
  }
  return out;
}
