/// A launch-relative timeline for measuring on a real phone.
///
/// Prints `[perf] +<ms since launch> <event>` in debug and profile builds, and
/// nothing in release. Read it with:
///
///     adb logcat -s flutter | findstr "[perf]"
///
/// Put on the question "where do the eSIM list's 8 seconds go": each stage the
/// list waits on logs when it starts and ends, so the gaps between lines ARE
/// the breakdown.
library;

import 'package:flutter/foundation.dart';

final Stopwatch _sinceLaunch = Stopwatch()..start();

/// Milliseconds since the Dart side started (the first call of anything here).
int get perfNow => _sinceLaunch.elapsedMilliseconds;

void perfLog(String event) {
  if (kReleaseMode) return;
  debugPrint('[perf] +${perfNow}ms $event');
}

/// Times [run] and logs `<label> <n>ms`, returning its result.
Future<T> perfTime<T>(String label, Future<T> Function() run) async {
  if (kReleaseMode) return run();
  final start = perfNow;
  try {
    return await run();
  } finally {
    perfLog('$label ${perfNow - start}ms');
  }
}
