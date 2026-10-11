/// The one incident list (docs/STUDIO-SPEC.md §8): every failure this repo
/// has met, as data in `tool/studio/incidents/<id>.yaml`. Log classification
/// reads `match`, the release checklist reads `kind: checklist`, and a case
/// in the case store points at an `id`. There is no second list: a new
/// incident becomes a file here the same day.
library;

import 'dart:io';

import 'package:yaml/yaml.dart';

const incidentsDir = 'tool/studio/incidents';

/// The jobs an incident may offer as its fix: a button the user presses,
/// never a command written in YAML.
const autofixJobs = {'gradle-stop', 'sdk-install'};

/// Where an env-aware item (§9, §16) is evaluated, and what it may depend on.
const itemEnvs = {'dev', 'prod', 'both', 'server'};
const itemConditions = {'payments', 'vouchers', 'google', 'ios', 'provisions', 'clientDomains'};

class Incident {
  Incident({
    required this.id,
    required this.title,
    required this.kind,
    required this.match,
    required this.cause,
    required this.fix,
    required this.autofix,
    required this.where,
    required this.evidence,
    required this.brands,
    required this.date,
    required this.gate,
    required this.source,
    required this.matchExamples,
    required this.missExamples,
    this.env,
    this.when = const [],
    this.severity = const {'dev': 'block', 'prod': 'block'},
    this.acceptedRisk,
  });

  final String id, title, cause, fix, evidence, date;

  /// signature (found in logs), check (a static or artifact check) or
  /// checklist (a manual gate).
  final String kind;

  /// test, release or submit: what waits on it; none for a plain signature.
  final String gate;
  final List<RegExp> match;

  /// `{job, label}`, the job one of [autofixJobs]; null when the fix is manual.
  final Map<String, String>? autofix;
  final List<String> where, brands, matchExamples, missExamples;

  /// For a line the app itself prints: the file that prints it and the text.
  final (String, String)? source;

  /// For an item of the backend phase: dev, prod, both or server; null otherwise.
  final String? env;

  /// The conditions under which the item applies (all of them); n/a otherwise.
  final List<String> when;

  /// block or warn, per env.
  final Map<String, String> severity;

  /// The reason a known risk is accepted: the item then reads accepted.
  final String? acceptedRisk;

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'kind': kind,
        'match': [for (final r in match) r.pattern],
        'cause': cause,
        'fix': fix,
        'autofix': autofix,
        'where': where,
        'evidence': evidence,
        'brands': brands,
        'date': date,
        'gate': gate,
        if (env != null) ...{'env': env, 'when': when, 'severity': severity, 'acceptedRisk': acceptedRisk},
      };
}

Map<String, Incident> loadIncidents([String root = '.']) {
  final files = Directory('$root/$incidentsDir').listSync().whereType<File>()
      .where((f) => f.path.endsWith('.yaml')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return {
    for (final f in files)
      if (_parse(f) case final i) i.id: i,
  };
}

Incident _parse(File f) {
  final name = f.uri.pathSegments.last;
  Never bad(String why) => throw FormatException('$incidentsDir/$name: $why');
  final y = loadYaml(f.readAsStringSync());
  if (y is! YamlMap) bad('not a YAML map');
  String str(String k) {
    final v = y[k];
    if (v == null || '$v'.isEmpty) bad('"$k" must be a non-empty string');
    return '$v';
  }

  List<String> strings(Object? v) => [for (final s in (v as List? ?? const [])) '$s'];

  final id = str('id');
  if ('$id.yaml' != name) bad('id "$id" must equal the file name');
  final kind = str('kind');
  if (!const {'signature', 'check', 'checklist'}.contains(kind)) bad('kind must be signature, check or checklist');
  final gate = str('gate');
  if (!const {'none', 'test', 'release', 'submit'}.contains(gate)) bad('gate must be none, test, release or submit');
  final match = [
    for (final p in strings(y['match']))
      () {
        try {
          return RegExp(p, caseSensitive: false);
        } on FormatException catch (e) {
          bad('regex "$p" does not compile: ${e.message}');
        }
      }(),
  ];
  final examples = y['examples'] as YamlMap?;
  if (kind == 'signature' && match.isEmpty) bad('a signature needs match regexes');
  if (match.isNotEmpty && (strings(examples?['match']).isEmpty || strings(examples?['miss']).isEmpty)) {
    bad('match regexes need examples of both kinds (examples: {match, miss})');
  }
  final env = y['env'] as String?;
  if (env != null && !itemEnvs.contains(env)) bad('env must be one of ${itemEnvs.join(', ')}');
  if (env != null && kind == 'signature') bad('an item with an env is a check or a checklist, not a signature');
  final when = strings(y['when']);
  for (final c in when) {
    if (!itemConditions.contains(c)) bad('when "$c" is not one of ${itemConditions.join(', ')}');
  }
  final sev = y['severity'];
  final severity = switch (sev) {
    null => const {'dev': 'block', 'prod': 'block'},
    String s => {'dev': s, 'prod': s},
    YamlMap m => {'dev': '${m['dev'] ?? 'block'}', 'prod': '${m['prod'] ?? 'block'}'},
    _ => bad('severity must be block, warn, or {dev: ..., prod: ...}'),
  };
  if (severity.values.any((s) => s != 'block' && s != 'warn')) bad('severity must be block or warn');
  final autofix = y['autofix'] as YamlMap?;
  if (autofix != null && !autofixJobs.contains(autofix['job'])) {
    bad('autofix job "${autofix['job']}" is not one of ${autofixJobs.join(', ')}');
  }
  final source = y['source'] as YamlMap?;
  return Incident(
    id: id,
    title: str('title'),
    kind: kind,
    match: match,
    cause: str('cause'),
    fix: str('fix'),
    autofix: autofix == null ? null : {'job': '${autofix['job']}', 'label': '${autofix['label']}'},
    where: strings(y['where']),
    evidence: str('evidence'),
    brands: strings(y['brands']),
    date: str('date'),
    gate: gate,
    source: source == null ? null : ('${source['file']}', '${source['text']}'),
    matchExamples: strings(examples?['match']),
    missExamples: strings(examples?['miss']),
    env: env,
    when: when,
    severity: severity,
    acceptedRisk: y['acceptedRisk'] as String?,
  );
}

/// The incidents [log] shows, each with the first line that matched, in
/// the order the log first shows them.
List<({Incident incident, String line})> classify(String log, Iterable<Incident> incidents) {
  final found = <String, ({Incident incident, String line})>{};
  for (final line in log.split('\n')) {
    for (final i in incidents) {
      if (!found.containsKey(i.id) && i.match.any((r) => r.hasMatch(line))) {
        found[i.id] = (incident: i, line: line.trimRight());
      }
    }
  }
  return found.values.toList();
}
