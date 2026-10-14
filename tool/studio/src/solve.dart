/// "Solve" on a failed job (Slice D1, docs/STUDIO-SPEC.md §18): the autofix if
/// there is one, then the nearest cases, then the Fix Bundle, always in that
/// order. Nothing runs by itself: the autofix is a button, the cases are shown,
/// and what was tried goes into the bundle. When an autofix is followed by the
/// same job passing, a case is *proposed*, and stored only through Apply.
library;

import 'cases.dart';

/// What Solve needs to know about a failed job.
class Failure {
  const Failure({required this.jobId, required this.slug, required this.job, required this.symptom, this.incident});

  final String jobId, slug;

  /// The job's name (build-dev, launch-dev…).
  final String job;

  /// The lines that say what went wrong, already redacted.
  final String symptom;

  /// The incident it matched first, if any: its id, title, cause, the line, and its autofix.
  final FailedIncident? incident;
}

class FailedIncident {
  const FailedIncident({required this.id, required this.title, required this.cause, required this.line, this.autofix});

  final String id, title, cause, line;

  /// `{job, label}`, or null.
  final Map<String, String>? autofix;
}

/// What was done about one failed job so far.
class Tried {
  final autofixes = <String>[];
  final cases = <String>[];

  bool get isEmpty => autofixes.isEmpty && cases.isEmpty;
}

class SolveBook {
  final _tried = <String, Tried>{};
  final _autofixOf = <String, Failure>{};
  final _awaiting = <String, ({Failure failure, String autofix})>{};

  /// Case proposals by id, until they are stored or the page is closed.
  final proposals = <String, Map<String, dynamic>>{};

  Tried triedFor(String failedJobId) => _tried.putIfAbsent(failedJobId, Tried.new);

  /// The user pressed [autofix] (job [autofixJobId]) for [failure].
  void autofixStarted(String autofixJobId, String autofix, Failure failure) {
    triedFor(failure.jobId).autofixes.add(autofix);
    _autofixOf[autofixJobId] = failure;
  }

  /// A job ended. Returns the case proposed by it, if it completes a fix: an
  /// autofix that is itself the relaunch passed, or the failed job passed
  /// again after its autofix.
  Map<String, dynamic>? jobEnded({required String jobId, required String slug, required String name, required bool passed, required DateTime now}) {
    if (!passed) return null;
    final fix = _autofixOf[jobId];
    if (fix != null) {
      // uninstall-retry installs and opens the app again: it is its own relaunch.
      if (name == 'uninstall-retry') return _propose(fix, name, '$name passed', now);
      _awaiting['${fix.slug}/${fix.job}'] = (failure: fix, autofix: name);
      return null;
    }
    final waiting = _awaiting.remove('$slug/$name');
    return waiting == null ? null : _propose(waiting.failure, waiting.autofix, '${waiting.autofix} passed, then $name passed again', now);
  }

  Map<String, dynamic>? _propose(Failure f, String autofix, String evidence, DateTime now) {
    final incident = f.incident;
    if (incident == null) return null; // nothing known to say it was
    final stamp = now.toUtc().toIso8601String().replaceAll(RegExp(r'[-:T]'), '').substring(0, 14);
    final id = '${incident.id}-${stamp.substring(0, 8)}-${stamp.substring(8)}';
    return proposals[id] = {
      'id': id,
      'incident': incident.id,
      'symptom': incident.line,
      'cause': incident.cause,
      'diff': '',
      'tests': [evidence],
      'solvedBy': 'autofix $autofix',
      'brands': [f.slug],
      'date': now.toUtc().toIso8601String().substring(0, 10),
      'job': f.jobId,
    };
  }
}

/// The three stages of Solve for [failure], in order. The cases stage records
/// what it showed in [book], which the Fix Bundle then lists as already tried.
List<Map<String, Object?>> solveStages(Failure failure, List<Map<String, dynamic>> cases, SolveBook book, {int show = 3}) {
  final autofix = failure.incident?.autofix;
  final ranked = rankCases(cases,
      incidentIds: [if (failure.incident != null) failure.incident!.id], symptom: failure.symptom, limit: show);
  final tried = book.triedFor(failure.jobId);
  for (final r in ranked) {
    if (!tried.cases.contains('${r.found['id']}')) tried.cases.add('${r.found['id']}');
  }
  return [
    if (autofix != null)
      {'stage': 'autofix', 'job': autofix['job'], 'label': autofix['label'], 'incident': failure.incident!.id},
    {
      'stage': 'cases',
      'cases': [
        for (final r in ranked)
          {
            'id': r.found['id'],
            'why': r.why,
            'incident': r.found['incident'],
            'symptom': r.found['symptom'],
            'cause': r.found['cause'],
            'diff': r.found['diff'],
            'solvedBy': r.found['solvedBy'],
            'date': r.found['date'],
          },
      ],
    },
    {'stage': 'bundle'},
  ];
}

/// The lines the Fix Bundle prints for what was already tried, so Claude does
/// not propose it again.
List<String> triedLines(Tried tried, List<Map<String, dynamic>> cases) {
  String clip(String s) => s.length <= 120 ? s : '${s.substring(0, 120)}…';
  return [
    for (final a in tried.autofixes) '- autofix pressed: $a',
    for (final id in tried.cases)
      if (cases.where((c) => c['id'] == id).firstOrNull case final c?)
        '- case $id (${c['solvedBy']}, ${c['date']}): ${clip('${c['symptom']}')}${'${c['cause']}'.isEmpty ? '' : ' → ${clip('${c['cause']}')}'}',
  ];
}
