@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:transasim_mobile/core/brand/app_flavor.dart';

import '../../tool/studio/src/emulator.dart';
import '../../tool/studio/src/incidents.dart';
import '../../tool/studio/src/jobs.dart';
import '../../tool/studio/src/redact.dart';
import '../../tool/studio/src/runner.dart';

/// Slices C3 and C4: logcat as a job that never ends on its own, and the
/// watcher for the emulator window. No emulator is involved: the "device" is a
/// small Dart script, and adb's answers are faked.
void main() {
  late Directory dir;
  late Runner runner;
  final dart = '${flutterRoot()}/bin/cache/dart-sdk/bin/dart${Platform.isWindows ? '.exe' : ''}';
  final fixture = File('test/studio/fixtures/logs/logcat-session.log').absolute.path.replaceAll(r'\', '/');

  String script(String name, String body) => (File('${dir.path}/$name.dart')..writeAsStringSync(body)).path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('logcat');
    runner = Runner(logsDir: '${dir.path}/logs', redact: Redactor(const []), incidents: loadIncidents());
  });
  tearDown(() => dir.deleteSync(recursive: true));

  group('logcat lines', () {
    // Each of these must be gone from the file, the stream and the memory.
    const secrets = [
      'abc123.def456_ghi789', // a Bearer token
      'eyJhbGciOiJIUzI1NiJ9', // a JWT
      'jane.doe@example.com', // an e-mail address
      'pk_live_51AbCdEfGhIjKlMnOpQrStUv', // a publishable key
      'sk_test_51ZyXwVuTsRqPoNmLkJiHg', // a secret key
      'hunter2hunter2', // a password in a JSON body
      'hunter3hunter3', // password=
      'deadbeef1234', // a signed URL's signature
      'token=abc.def', // a token in a query
    ];

    test('a session is redacted before it is stored, streamed or kept', () async {
      final s = script('session', 'import "dart:io"; void main() { stdout.write(File("$fixture").readAsStringSync()); }');
      final job = runner.enqueue('demo', 'logcat', [Step(dart, [s])], tail: 100);
      final streamed = <String>[];
      job.live.listen(streamed.add);
      await job.done;
      final written = File(job.logPath).readAsStringSync();
      for (final text in [written, streamed.join('\n'), job.lines.join('\n')]) {
        for (final secret in secrets) {
          expect(text, isNot(contains(secret)), reason: secret);
        }
        expect(text, contains('request failed, Authorization: Bearer [redacted]'));
        expect(text, contains('[email]'));
        expect(text, contains('X-Amz-Signature=[redacted]&X-Amz-Expires=60'), reason: 'only the signature goes');
        expect(text, contains('"password":"[redacted]"'));
      }
    });

    test('a known error shows as an incident while the job is still the same job', () async {
      final s = script('session', 'import "dart:io"; void main() { stdout.write(File("$fixture").readAsStringSync()); }');
      final job = runner.enqueue('demo', 'logcat', [Step(dart, [s])], tail: 100);
      await job.done;
      expect(job.matched.map((m) => m.incident.id), ['transatel-bad-sim']);
      expect(job.matched.single.line, contains('SUBSCRIBER_STATUS_NOT_ELIGIBLE'));
    });

    test('an incident is listed once however many lines match it', () async {
      final s = script('many', 'void main() { for (var i = 0; i < 40; i++) { print("E Transatel: SUBSCRIBER_STATUS_NOT_ELIGIBLE \$i"); } }');
      final job = runner.enqueue('demo', 'logcat', [Step(dart, [s])], tail: 100);
      await job.done;
      expect(job.matched, hasLength(1));
    });

    test('only the last lines stay in memory, however long the session', () async {
      final s = script('long', 'void main() { for (var i = 0; i < 2000; i++) { print("I flutter : line \$i"); } }');
      final job = runner.enqueue('demo', 'logcat', [Step(dart, [s])], tail: 50);
      await job.done;
      expect(job.lines.length, lessThanOrEqualTo(50));
      expect(job.lines.where((l) => l.contains('line 1999')), isNotEmpty, reason: 'the newest are kept');
      expect(job.lines.where((l) => l.contains('line 0')), isEmpty, reason: 'the oldest are dropped');
    });

    test('a job with a tail ends when cancelled, with nothing left running', () async {
      final s = script('forever', 'import "dart:io"; void main() async { print("pid \${pid}"); while (true) { await Future.delayed(Duration(milliseconds: 100)); } }');
      final job = runner.enqueue('demo', 'logcat', [Step(dart, [s])], tail: 50);
      for (var i = 0; i < 100 && !job.lines.any((l) => l.startsWith('pid ')); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      final pid = int.parse(job.lines.firstWhere((l) => l.startsWith('pid ')).substring(4));
      expect(job.state, 'running');
      await runner.cancel(job.id);
      await job.done;
      expect(job.state, 'cancelled');
      expect(await isRunning(pid), isFalse);
    });
  });

  group('the step that finds the app first', () {
    test('its arguments are added after the fixed ones, once known', () async {
      final s = script('echo', 'void main(List<String> a) { print("args: \${a.join(" ")}"); }');
      final job = runner.enqueue('demo', 'logcat', [Step(dart, [s, '-e'], lateArgs: () async => ['--pid=4242', '*:E'])]);
      await job.done;
      expect(job.lines, contains('args: -e --pid=4242 *:E'));
    });

    test('when the app never starts the job fails with the reason, not a hang', () async {
      final job = runner.enqueue('demo', 'logcat', [
        Step(dart, ['unused'], lateArgs: () async => throw StateError('com.x.y is not running on the emulator: open the app')),
      ]);
      await job.done;
      expect(job.state, 'failed');
      expect(job.lines.join('\n'), contains('is not running on the emulator'));
    });

    test('the pid is asked again until it exists, then given up on', () async {
      var asked = 0;
      final pid = await findAppPid('com.x.y', (_) async => ++asked < 4 ? '' : '4242\n', wait: Duration.zero);
      expect(pid, 4242);
      expect(asked, 4);
      var times = 0;
      expect(await findAppPid('com.x.y', (_) async { times++; return null; }, tries: 5, wait: Duration.zero), isNull);
      expect(times, 5);
    });
  });

  group('adb, read-only and never left running', () {
    test('devices output: an emulator that is up, and nothing else, counts', () {
      expect(hasEmulator('List of devices attached\nemulator-5554\tdevice\n\n'), isTrue);
      expect(hasEmulator('List of devices attached\nemulator-5554\toffline\n'), isFalse);
      expect(hasEmulator('List of devices attached\nR58M12ABCDE\tdevice\n'), isFalse, reason: 'a phone is not the emulator');
      expect(hasEmulator('List of devices attached\n\n'), isFalse);
    });

    test('an answer comes back; a command that hangs is killed, not left running', () async {
      final ok = script('ok', 'void main() { print("emulator-5554\\tdevice"); }');
      expect(await adbOutput(dart, [ok]), contains('emulator-5554'));
      final pidFile = '${dir.path}/pid.txt'.replaceAll(r'\', '/');
      final hang = script('hang', 'import "dart:io"; void main() { File("$pidFile").writeAsStringSync("\${pid}"); sleep(Duration(seconds: 60)); }');
      final watch = Stopwatch()..start();
      expect(await adbOutput(dart, [hang], timeout: const Duration(seconds: 3)), isNull);
      expect(watch.elapsed, lessThan(const Duration(seconds: 20)));
      final pid = int.parse(File(pidFile).readAsStringSync());
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(await isRunning(pid), isFalse);
    });

    test('a program that does not exist is a null answer', () async {
      expect(await adbOutput('${dir.path}/no-such-adb', ['devices']), isNull);
    });
  });

  group('INSTALL_FAILED_UPDATE_INCOMPATIBLE: the button that deletes the app', () {
    const line = 'adb: failed to install build/app/outputs/flutter-apk/app-sabily-profile.apk: Failure '
        '[INSTALL_FAILED_UPDATE_INCOMPATIBLE: Existing package com.sabily.esim signatures do not match newer version; ignoring!]';

    test('the real log line is matched, with the one-press recovery', () {
      final hits = classify(line, loadIncidents().values);
      expect(hits.map((h) => h.incident.id), ['install-update-incompatible']);
      expect(hits.single.incident.autofix, {'job': 'uninstall-retry', 'label': 'Uninstall from the emulator and retry'});
      expect(hits.single.incident.cause, contains('different key'));
    });

    test('only this signature offers it, and no other line matches it', () {
      final all = loadIncidents().values;
      expect([for (final i in all) if (i.autofix?['job'] == 'uninstall-retry') i.id], ['install-update-incompatible']);
      for (final other in ['INSTALL_FAILED_VERSION_DOWNGRADE', 'INSTALL_FAILED_INSUFFICIENT_STORAGE', 'BUILD SUCCESSFUL in 1m 12s',
          'Performing Streamed Install', 'Success']) {
        expect(classify(other, all).where((h) => h.incident.autofix?['job'] == 'uninstall-retry'), isEmpty, reason: other);
      }
    });

    test('the job uninstalls from the emulator only (-e), then installs again, and nothing runs by itself', () {
      final root = Directory('${dir.path}/repo')..createSync();
      Directory('${root.path}/brands/sabily').createSync(recursive: true);
      File('${root.path}/brands/sabily/brand.json').writeAsStringSync(jsonEncode({'mobile': {'applicationId': 'com.sabily.esim'}}));
      File('${root.path}/.studio/machine.json')
        ..createSync(recursive: true)
        ..writeAsStringSync(jsonEncode({'sdkRoot': '${root.path}/sdk', 'avd': 'a', 'gpu': 'angle_indirect'}));
      for (final f in AppFlavor.values) {
        File(profileApk(root.path, 'sabily', f)).createSync(recursive: true);
      }
      // The build whose install failed: the store one here, the DEV one by default.
      expect([for (final s in jobSteps(root.path, 'uninstall-retry', slug: 'sabily', flavor: AppFlavor.prod)!) s.args.join(' ')],
          contains('-e uninstall com.sabily.esim'));

      final steps = jobSteps(root.path, 'uninstall-retry', slug: 'sabily')!;
      final lines = [for (final s in steps) s.args.join(' ')];
      final uninstall = lines.indexWhere((l) => l.contains('uninstall'));
      final install = lines.indexWhere((l) => l.contains(' install '.trim()) && !l.contains('uninstall'));
      expect(lines[uninstall], '-e uninstall com.sabily.esim.dev');
      expect(install, greaterThan(uninstall), reason: 'the install is repeated after the app is gone');
      expect(lines.where((l) => l.contains('uninstall')), hasLength(1));
      // Every adb call is addressed to the emulator, so a phone plugged in can never be touched.
      for (final s in steps.where((s) => s.executable.contains('adb'))) {
        expect(s.args.first, '-e', reason: s.display);
      }
      // The normal launch has no uninstall in it.
      final plain = [for (final s in jobSteps(root.path, 'launch-dev', slug: 'sabily')!) s.args.join(' ')];
      expect(plain.where((l) => l.contains('uninstall')), isEmpty);
      // Not available before Doctor and a build: no machine, no job.
      File('${root.path}/.studio/machine.json').deleteSync();
      expect(jobSteps(root.path, 'uninstall-retry', slug: 'sabily'), isNull);
    });
  });

  group('the emulator window watcher', () {
    const up = 'List of devices attached\nemulator-5554\tdevice\n';
    const none = 'List of devices attached\n\n';

    EmulatorWatch watcher(List<String?> answers, [DateTime Function()? now]) {
      var i = 0;
      return EmulatorWatch(
        devices: () async => answers[i < answers.length ? i++ : answers.length - 1],
        interval: const Duration(hours: 1), // polled by hand
        now: now,
      );
    }

    test('closing the window is noticed after two polls without the emulator, and ends the watch', () async {
      final w = watcher([up, up, none, none])..start('sabily');
      await Future<void>.delayed(Duration.zero);
      expect(w.status, 'watching');
      expect(w.toJson()['open'], isTrue);
      await w.poll();
      expect(w.status, 'watching');
      await w.poll();
      expect(w.status, 'watching', reason: 'one miss is not a close');
      await w.poll();
      expect(w.status, 'closed');
      expect(w.toJson()['open'], isFalse);
      expect(w.closedAt, isNotNull);
      expect(w.active, isFalse);
    });

    test('one slow answer from adb is not a closed window', () async {
      final w = watcher([up, null, up, up, none])..start('sabily');
      for (var i = 0; i < 4; i++) {
        await Future<void>.delayed(Duration.zero);
        await w.poll();
      }
      expect(w.status, 'watching');
    });

    test('an emulator that never shows up is given up on, not reported closed', () async {
      var t = DateTime.utc(2026, 10, 13);
      final w = watcher([none], () => t)..start('sabily');
      await Future<void>.delayed(Duration.zero);
      expect(w.status, 'waiting');
      t = t.add(const Duration(minutes: 4));
      await w.poll();
      expect(w.status, 'gone');
    });

    test('stopping ends the watch and nothing more is polled', () async {
      var calls = 0;
      final w = EmulatorWatch(devices: () async { calls++; return up; }, interval: const Duration(milliseconds: 20))..start('sabily');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      w.stop();
      final at = calls;
      expect(w.status, 'gone');
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(calls, at, reason: 'the timer is cancelled');
    });
  });
}
