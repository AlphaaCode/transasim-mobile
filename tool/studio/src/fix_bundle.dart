/// The Fix Bundle (docs/STUDIO-SPEC.md §8): one Markdown message holding
/// everything Claude needs about a failed job, under 8,000 characters and
/// redacted. The log tail gives way first when it does not fit.
library;

import 'dart:convert';
import 'dart:io';

import 'backend.dart' show backendSummary;
import 'doctor.dart';
import 'guides.dart' show missingData;
import 'incidents.dart' show loadIncidents;
import 'redact.dart';
import 'runner.dart';

const fixBundleCap = 8000;
const _tailLines = 150;
const _lineCap = 300;

/// The page's own rule for a red line (logs.js): "0 errors" is not one,
/// and a flutter test progress line is one only when flutter marks it [E]
/// (the others carry test names such as "…names itself in the error").
final _looksLikeError = RegExp(r'(^|\s)E/|\berror\b|exception|failure|\bfailed\b|\bfatal\b', caseSensitive: false);
final _testProgress = RegExp(r'^\d\d:\d\d \+\d+');
bool _isError(String l) => _testProgress.hasMatch(l) ? l.trimRight().endsWith('[E]') : _looksLikeError.hasMatch(l);

String _clip(String l) => l.length <= _lineCap ? l : '${l.substring(0, _lineCap)}…';

String fixBundle({
  required Job job,
  required String version,
  required Map<String, String> tools,
  required String gitHash,
  required List<String> dirty,
  required String brandJson,
  required List<String> missing,
  required Redactor redact,
  String? backend,
  int cap = fixBundleCap,
}) {
  final lines = job.lines;
  final errorAt = job.matched.isNotEmpty
      ? lines.indexOf(job.matched.first.line)
      : lines.indexWhere(_isError);
  final seconds = job.started == null || job.finished == null
      ? '?'
      : (job.finished!.difference(job.started!).inMilliseconds / 1000).toStringAsFixed(1);
  final head = [
    '## Studio Fix Bundle: ${job.slug} · ${job.name} ${job.state}',
    '- Version: $version · git $gitHash${dirty.isEmpty ? ', clean' : ' + ${dirty.length} changed: ${dirty.take(8).join(', ')}'}',
    for (final c in job.steps) '- Command: `${c.display}`',
    '- Exit ${job.exitCode ?? '-'} after $seconds s',
    '- Tools: ${[for (final e in tools.entries) '${e.key} ${e.value}'].join(', ')}',
    '- Full log: ${job.logPath}',
    '',
    '### Matched incidents',
    if (job.matched.isEmpty) 'None matched: this may be a new incident.',
    for (final m in job.matched) ...[
      '- **${m.incident.id}**: ${m.incident.title}',
      '  Cause: ${m.incident.cause}',
      '  Fix: ${m.incident.fix}',
      if (m.incident.autofix case final a?) '  Autofix offered (not run): ${a['label']}',
    ],
    if (errorAt >= 0) ...[
      '',
      '### First error (line ${errorAt + 1})',
      '```',
      for (final l in lines.skip(errorAt).take(12)) _clip(l),
      '```',
    ],
  ].join('\n');
  final foot = [
    if (backend != null) ...['', backend],
    '',
    '### brand.json',
    '```json',
    brandJson,
    '```',
    '',
    '### Missing data',
    if (missing.isEmpty) 'None.',
    for (final m in missing) '- $m',
  ].join('\n');

  // The tail takes what is left, kept from the end.
  final tail = <String>[];
  var room = cap - head.length - foot.length - 80;
  for (final l in lines.reversed.take(_tailLines)) {
    final c = _clip(l);
    if (room - c.length - 1 < 0) break;
    room -= c.length + 1;
    tail.insert(0, c);
  }
  final text = redact([
    head,
    '',
    '### Last ${tail.length} lines',
    '```',
    ...tail,
    '```',
    foot,
  ].join('\n'));
  return text.length <= cap ? text : '${text.substring(0, cap - 16)}\n[…truncated]';
}

/// Gathers this machine's side of the bundle for [job].
Future<String> fixBundleFor(String root, Job job, Redactor redact) async {
  Future<String> out(String exe, List<String> args) async {
    try {
      // Not trimmed: git status's first column is a meaningful space.
      return '${(await Process.run(exe, args, workingDirectory: root)).stdout}';
    } on ProcessException {
      return '';
    }
  }

  final flutter = flutterRoot();
  final versions = flutter == null
      ? const {}
      : jsonDecode(File('$flutter/bin/cache/flutter.version.json').readAsStringSync()) as Map;
  final java = await Process.run(javaExecutable(), ['-version']).then((r) => '${r.stderr}', onError: (_) => '');
  final brandFile = File('$root/brands/${job.slug}/brand.json');
  final studioFile = File('$root/brands/${job.slug}/studio.json');
  final brand = brandFile.existsSync() ? jsonDecode(brandFile.readAsStringSync()) as Map<String, dynamic> : null;
  final studio =
      studioFile.existsSync() ? jsonDecode(studioFile.readAsStringSync()) as Map<String, dynamic> : <String, dynamic>{};
  final status = await out('git', ['status', '--porcelain']);
  return fixBundle(
    job: job,
    version: RegExp(r'^version:\s*(\S+)', multiLine: true)
            .firstMatch(File('$root/pubspec.yaml').readAsStringSync())?[1] ??
        '?',
    tools: {
      'Flutter': '${versions['frameworkVersion'] ?? '?'}',
      'Dart': Platform.version.split(' ').first,
      'JDK': '${javaMajor(java) ?? '?'}',
      'OS': '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    },
    gitHash: (await out('git', ['rev-parse', '--short', 'HEAD'])).trim(),
    dirty: [for (final l in const LineSplitter().convert(status)) if (l.length > 3) l.substring(3)],
    brandJson: brand == null ? '(no brand.json: ${job.slug} is not a brand)' : jsonEncode(brand),
    missing: brand == null
        ? const []
        : [for (final m in missingData(root, job.slug, brand, studio)) '${m['label']}: ${m['reason']}'],
    redact: redact,
    backend: brand == null ? null : backendSummary(root, job.slug, items: loadIncidents(root), now: DateTime.now().toUtc()),
  );
}
