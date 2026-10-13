/// Studio's job runner (docs/STUDIO-SPEC.md §3, §8): one job at a time,
/// first in first out, each line redacted before it is kept, streamed or
/// written to `.studio/logs/<time>-<slug>-<step>.log`. A failed job is
/// classified against the incident list.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'incidents.dart';
import 'redact.dart';

/// One command of a job. [display] is what the log shows instead of the
/// full executable path.
class Step {
  Step(this.executable, this.args, {this.workingDirectory, String? display, this.detached = false, this.lateArgs})
      : display = display ?? [executable.split(RegExp(r'[\\/]')).last, ...args].join(' ');

  final String executable;
  final List<String> args;
  final String? workingDirectory;
  final String display;

  /// Started and left running (the emulator): the job goes on at once, and
  /// Cancel does not stop it.
  final bool detached;

  /// Arguments found out when the step starts, added after [args] (logcat
  /// needs the app's pid, which exists only once the app runs). It may throw
  /// a [StateError]: its message is logged and the step fails.
  final Future<List<String>> Function()? lateArgs;
}

class Job {
  Job._(this.id, this.slug, this.name, this.steps, this.logPath);

  final String id, slug, name, logPath;
  final List<Step> steps;

  /// queued, running, passed, failed or cancelled.
  String state = 'queued';
  int? exitCode;
  DateTime? started, finished;

  /// Every line so far, already redacted.
  // ponytail: the whole log stays in memory for the session; keep a tail
  // here and read the file if a job ever logs more than a build does.
  final lines = <String>[];
  List<({Incident incident, String line})> matched = const [];

  /// A job with no natural end (logcat) keeps only its last [tail] lines in
  /// memory and at most [logCapBytes] in its file, and matches each line
  /// against the incident list as it arrives rather than once at the end.
  int? tail;
  int _logBytes = 0;

  /// The lines from now on, as they arrive.
  Stream<String> get live => _live.stream;
  Future<void> get done => _done.future;

  final _live = StreamController<String>.broadcast();
  final _done = Completer<void>();
  Process? _process;
  bool _cancelled = false;

  Map<String, Object?> toJson() => {
        'id': id,
        'slug': slug,
        'name': name,
        'state': state,
        'exitCode': exitCode,
        'started': started?.toIso8601String(),
        'finished': finished?.toIso8601String(),
        'ms': started == null ? null : (finished ?? DateTime.now()).difference(started!).inMilliseconds,
        'commands': [for (final s in steps) s.display],
        'log': logPath,
        'lines': lines.length,
        'matched': [
          for (final m in matched) {...m.incident.toJson(), 'line': m.line},
        ],
      };
}

/// The most a never-ending job writes to its log file.
const logCapBytes = 10 * 1024 * 1024;

class Runner {
  Runner({required this.logsDir, required this.redact, required this.incidents});

  final String logsDir;
  final Redactor redact;
  final Map<String, Incident> incidents;

  final _jobs = <String, Job>{};
  final _queue = <Job>[];
  bool _busy = false;

  Iterable<Job> get jobs => _jobs.values;
  Job? operator [](String id) => _jobs[id];

  /// [tail]: see [Job.tail].
  Job enqueue(String slug, String name, List<Step> steps, {int? tail}) {
    final t = DateTime.now();
    String two(int n) => '$n'.padLeft(2, '0');
    final stamp = '${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}${two(t.second)}'
        '-${'${t.millisecond}'.padLeft(3, '0')}';
    var id = '$stamp-$slug-$name';
    for (var n = 2; _jobs.containsKey(id); n++) {
      id = '$stamp-$slug-$name-$n';
    }
    final job = Job._(id, slug, name, steps, '$logsDir/$id.log')..tail = tail;
    _jobs[id] = job;
    _queue.add(job);
    _pump();
    return job;
  }

  /// A queued job is dropped; a running one is stopped with every process it
  /// started (Gradle and Flutter both spawn children a plain kill leaves).
  Future<void> cancel(String id) async {
    final job = _jobs[id];
    if (job == null || job._done.isCompleted) return;
    job._cancelled = true;
    if (_queue.remove(job)) {
      job.state = 'cancelled';
      job.finished = DateTime.now();
      await job._live.close();
      job._done.complete();
    } else if (job._process case final p?) {
      await killTree(p.pid);
    }
  }

  Future<void> _pump() async {
    if (_busy || _queue.isEmpty) return;
    _busy = true;
    final job = _queue.removeAt(0);
    try {
      await _run(job);
    } finally {
      _busy = false;
      unawaited(_pump());
    }
  }

  Future<void> _run(Job job) async {
    job
      ..state = 'running'
      ..started = DateTime.now();
    final sink = (File(job.logPath)..createSync(recursive: true)).openWrite();
    void emit(String raw) {
      // Colour codes (the Android CLI, Gradle) would show as debris.
      final line = redact(raw.replaceAll(RegExp(r'\x1B\[[0-9;?]*[A-Za-z]'), ''));
      final cap = job.tail;
      job.lines.add(line);
      if (cap != null) {
        if (job.lines.length > cap) job.lines.removeRange(0, job.lines.length - cap);
        // Known errors show up while the session runs, once each.
        for (final m in classify(line, incidents.values)) {
          if (job.matched.length < 50 && !job.matched.any((x) => x.incident.id == m.incident.id)) {
            job.matched = [...job.matched, m];
          }
        }
        job._logBytes += line.length + 1;
        if (job._logBytes > logCapBytes) {
          if (job._logBytes - line.length - 1 <= logCapBytes) sink.writeln('[studio] log file full: later lines are only on screen');
        } else {
          sink.writeln(line);
        }
      } else {
        sink.writeln(line);
      }
      job._live.add(line);
    }

    var code = 0;
    for (final step in job.steps) {
      if (job._cancelled) break;
      emit('\$ ${step.display}');
      try {
        if (step.detached) {
          // No pipes at all: a program that outlives the job could otherwise
          // inherit them and keep the step open until it exits.
          final p = await Process.start(step.executable, step.args,
              workingDirectory: step.workingDirectory, mode: ProcessStartMode.detached);
          emit('started in the background (pid ${p.pid})');
          continue;
        }
        final List<String> extra;
        try {
          extra = await step.lateArgs?.call() ?? const [];
        } on StateError catch (e) {
          emit(e.message);
          code = 1;
          break;
        }
        if (job._cancelled) break;
        final p = await Process.start(step.executable, [...step.args, ...extra],
            workingDirectory: step.workingDirectory,
            // A .bat (flutter, gradlew) needs cmd on Windows.
            runInShell: Platform.isWindows && step.executable.toLowerCase().endsWith('.bat'));
        job._process = p;
        unawaited(p.stdin.close());
        Future<void> pipe(Stream<List<int>> s) =>
            s.transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter()).forEach(emit);
        await Future.wait([pipe(p.stdout), pipe(p.stderr)]);
        code = await p.exitCode;
      } on ProcessException catch (e) {
        emit('could not start ${step.display}: ${e.message}');
        code = 127;
      }
      job._process = null;
      if (code != 0) break;
    }
    job
      ..finished = DateTime.now()
      ..exitCode = job._cancelled ? null : code
      ..state = job._cancelled ? 'cancelled' : (code == 0 ? 'passed' : 'failed');
    if (job.state == 'failed' && job.tail == null) job.matched = classify(job.lines.join('\n'), incidents.values);
    final seconds = (job.finished!.difference(job.started!).inMilliseconds / 1000).toStringAsFixed(1);
    emit('[studio] ${job.state}${job.exitCode == null ? '' : ' (exit ${job.exitCode})'} after $seconds s');
    await sink.close();
    await job._live.close();
    job._done.complete();
  }
}

/// Stops [pid] and what it spawned.
// ponytail: pkill -P reaches children, not grandchildren, off Windows; walk
// the tree there if Studio ever runs Gradle on the Mac.
Future<void> killTree(int pid) async {
  if (Platform.isWindows) {
    await Process.run('taskkill', ['/PID', '$pid', '/T', '/F']);
  } else {
    await Process.run('pkill', ['-TERM', '-P', '$pid']);
    Process.killPid(pid);
  }
}

Future<bool> isRunning(int pid) async {
  if (Platform.isWindows) {
    final r = await Process.run('tasklist', ['/FI', 'PID eq $pid', '/NH']);
    return '${r.stdout}'.contains(' $pid ');
  }
  return (await Process.run('kill', ['-0', '$pid'])).exitCode == 0;
}

/// The Flutter SDK running this code: Studio and the tests both run on the
/// Dart (or tester) inside it, so it is found from the executable, never
/// assumed. Null when that executable is not inside a Flutter SDK.
String? flutterRoot() {
  for (var d = File(Platform.resolvedExecutable).parent; d.parent.path != d.path; d = d.parent) {
    if (Directory('${d.path}/bin/cache/dart-sdk').existsSync() && File('${d.path}/bin/flutter').existsSync()) {
      return d.path;
    }
  }
  return Platform.environment['FLUTTER_ROOT'];
}
