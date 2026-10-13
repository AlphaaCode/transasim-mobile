/// What Studio does with a running emulator, read-only (Slices C3 and C4,
/// docs/STUDIO-SPEC.md §6.2): find the app's pid for logcat, and notice when
/// the emulator window is closed. Nothing here starts, stops or changes a
/// device: it only runs `adb devices` and `adb shell pidof`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Runs `adb [args]` and returns its stdout, or null when it fails or takes
/// longer than [timeout]. A process that overstays is killed with its children.
///
/// It does not wait for the output stream to end, only for the exit: when the
/// adb daemon has to start, it can inherit the pipes and hold them open long
/// after the client has gone, which hung a step before (the emulator, 2026-10-11).
Future<String?> adbOutput(String adb, List<String> args, {Duration timeout = const Duration(seconds: 8)}) async {
  final Process p;
  try {
    p = await Process.start(adb, args);
  } on ProcessException {
    return null;
  }
  unawaited(p.stdin.close().catchError((_) {}));
  final out = StringBuffer();
  final sub = p.stdout.transform(const Utf8Decoder(allowMalformed: true)).listen(out.write, onError: (_) {});
  unawaited(p.stderr.drain<void>().catchError((_) {}));
  try {
    final code = await p.exitCode.timeout(timeout);
    // Whatever arrived with the exit; a daemon holding the pipe cannot delay us.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return code == 0 ? out.toString() : null;
  } on TimeoutException {
    if (Platform.isWindows) {
      await Process.run('taskkill', ['/PID', '${p.pid}', '/T', '/F']);
    } else {
      p.kill();
    }
    return null;
  } finally {
    await sub.cancel();
  }
}

/// Whether `adb devices` output lists an emulator that is up.
bool hasEmulator(String devices) => RegExp(r'^emulator-\d+\s+device\b', multiLine: true).hasMatch(devices);

/// The app's pid, asking again every [wait] for up to [tries] times: right
/// after a launch the process may not exist yet. [shell] answers
/// `pidof -s <id>`.
Future<int?> findAppPid(String applicationId, Future<String?> Function(List<String> args) shell,
    {int tries = 10, Duration wait = const Duration(seconds: 1)}) async {
  for (var i = 0; i < tries; i++) {
    final out = await shell(['-e', 'shell', 'pidof', '-s', applicationId]);
    if (int.tryParse(out?.trim().split(RegExp(r'\s+')).first ?? '') case final pid?) return pid;
    if (i < tries - 1) await Future<void>.delayed(wait);
  }
  return null;
}

/// Watches for the emulator window being closed. The emulator is started
/// detached on purpose, so a Studio restart cannot kill the user's session:
/// this only polls. It reports `watching` once an emulator is seen, and
/// `closed` when it has been gone for [misses] polls in a row.
class EmulatorWatch {
  EmulatorWatch({
    required this.devices,
    this.interval = const Duration(seconds: 3),
    this.misses = 2,
    this.giveUp = const Duration(minutes: 3),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// `adb devices`, or null when adb did not answer.
  final Future<String?> Function() devices;
  final Duration interval;
  final int misses;

  /// How long to wait for an emulator that never appears.
  final Duration giveUp;
  final DateTime Function() _now;

  /// idle, waiting (started, no emulator seen yet), watching, closed or gone
  /// (never appeared, or Studio stopped watching).
  String status = 'idle';
  String? slug;
  DateTime? since, closedAt;
  Timer? _timer;
  bool _polling = false;
  int _missed = 0;

  bool get active => status == 'waiting' || status == 'watching';

  /// The page waits for this before it offers the result buttons.
  Map<String, Object?> toJson() => {
        'status': status,
        'slug': slug,
        'since': since?.toUtc().toIso8601String(),
        'closedAt': closedAt?.toUtc().toIso8601String(),
        'open': status == 'watching',
      };

  void start(String slug) {
    stop();
    this.slug = slug;
    status = 'waiting';
    since = _now();
    closedAt = null;
    _missed = 0;
    _timer = Timer.periodic(interval, (_) => poll());
    unawaited(poll());
  }

  /// One look. Public so a test can drive it without waiting.
  Future<void> poll() async {
    if (_polling || !active) return;
    _polling = true;
    try {
      final out = await devices();
      if (!active) return; // stopped while adb was answering
      final up = out != null && hasEmulator(out);
      if (up) {
        status = 'watching';
        _missed = 0;
      } else if (status == 'watching') {
        // Two misses in a row: adb answers slowly while the emulator boots or shuts.
        if (++_missed >= misses) _end('closed');
      } else if (_now().difference(since!) > giveUp) {
        _end('gone');
      }
    } finally {
      _polling = false;
    }
  }

  void _end(String to) {
    status = to;
    closedAt = _now();
    _timer?.cancel();
    _timer = null;
  }

  /// Studio stops watching (the button, or shutdown). Never touches the emulator.
  void stop() {
    _timer?.cancel();
    _timer = null;
    if (active) status = 'gone';
  }
}
