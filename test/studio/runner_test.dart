@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/studio/src/incidents.dart';
import '../../tool/studio/src/redact.dart';
import '../../tool/studio/src/runner.dart';

/// The runner runs one job at a time, writes every line redacted, and can
/// stop a job together with everything it spawned. The jobs here are small
/// Dart scripts, run on the VM that runs the tests.
void main() {
  late Directory dir;
  late Runner runner;
  final dart = '${flutterRoot()}/bin/cache/dart-sdk/bin/dart${Platform.isWindows ? '.exe' : ''}';

  String script(String name, String body) {
    final f = File('${dir.path}/$name.dart')..writeAsStringSync(body);
    return f.path;
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('runner');
    runner = Runner(
      logsDir: '${dir.path}/logs',
      redact: Redactor(['s3cr3t-value']),
      incidents: loadIncidents(),
    );
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('two jobs run one after the other, never together', () async {
    final s = script('wait', 'import "dart:io"; void main(a) { print("start"); sleep(Duration(milliseconds: 400)); print("end"); }');
    final a = runner.enqueue('demo', 'first', [Step(dart, [s])]);
    final b = runner.enqueue('demo', 'second', [Step(dart, [s])]);
    expect(b.state, 'queued');
    await Future.wait([a.done, b.done]);
    expect([a.state, b.state], ['passed', 'passed']);
    expect(b.started!.isBefore(a.finished!), isFalse);
  });

  test('every line is redacted before it is streamed or written', () async {
    final s = script('leak',
        'void main() { print("password is s3cr3t-value"); print("token sk_live_51HxYzAbCdEfGh"); print("\\x1B[33mcolour\\x1B[0m"); }');
    final job = runner.enqueue('demo', 'leak', [Step(dart, [s])]);
    final streamed = <String>[];
    job.live.listen(streamed.add);
    await job.done;
    final written = File(job.logPath).readAsStringSync();
    for (final text in [written, streamed.join('\n'), job.lines.join('\n')]) {
      expect(text, isNot(contains('s3cr3t-value')));
      expect(text, isNot(contains('sk_live_')));
      expect(text, contains('password is [redacted]'));
      expect(text, contains('\ncolour'), reason: 'colour codes are stripped');
    }
    expect(job.logPath, contains('-demo-leak.log'));
  });

  test('a failure is classified against the incident list', () async {
    final s = script('oom', 'import "dart:io"; void main() { print("java.lang.OutOfMemoryError: Java heap space"); exit(3); }');
    final job = runner.enqueue('demo', 'build', [Step(dart, [s]), Step(dart, [s])]);
    await job.done;
    expect(job.state, 'failed');
    expect(job.exitCode, 3);
    expect(job.matched.map((m) => m.incident.id), ['gradle-heap']);
    // The second step never ran.
    expect(job.lines.where((l) => l.contains('OutOfMemoryError')), hasLength(1));
  });

  test('cancel stops the job and every process it started', () async {
    final pidFile = '${dir.path}/grandchild.pid';
    final child = script('sleeper', 'import "dart:io"; void main() { File(r"$pidFile").writeAsStringSync("\$pid"); sleep(Duration(seconds: 60)); }');
    final parent = script('parent', '''
import "dart:io";
Future<void> main() async {
  await Process.start(r"$dart", [r"$child"], mode: ProcessStartMode.detachedWithStdio);
  print("spawned");
  sleep(Duration(seconds: 60));
}
''');
    final job = runner.enqueue('demo', 'tree', [Step(dart, [parent])]);
    final queued = runner.enqueue('demo', 'after', [Step(dart, [parent])]);
    while (!File(pidFile).existsSync() || File(pidFile).readAsStringSync().isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final grandchild = int.parse(File(pidFile).readAsStringSync());
    expect(await isRunning(grandchild), isTrue);
    await runner.cancel(queued.id);
    await runner.cancel(job.id);
    await job.done;
    expect(job.state, 'cancelled');
    expect(queued.state, 'cancelled');
    expect(queued.started, isNull);
    expect(await isRunning(grandchild), isFalse);
  });
}
