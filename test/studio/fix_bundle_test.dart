@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/studio/src/fix_bundle.dart';
import '../../tool/studio/src/incidents.dart';
import '../../tool/studio/src/redact.dart';
import '../../tool/studio/src/runner.dart';

/// The failure drills (docs/STUDIO-SPEC.md §12): a real job prints a real
/// failure, the runner classifies it, and the Fix Bundle carries what Claude
/// needs in under 8,000 characters with no secret in it.
void main() {
  late Directory dir;
  late Runner runner;
  final dart = '${flutterRoot()}/bin/cache/dart-sdk/bin/dart${Platform.isWindows ? '.exe' : ''}';
  const secrets = ['drill-secret-1', 'drill-secret-2', 'drill.customer@example.com', 'drill.token-value_3', 'sk_live_51Drill'];

  setUp(() {
    dir = Directory.systemTemp.createTempSync('bundle');
    runner = Runner(logsDir: '${dir.path}/logs', redact: Redactor(const []), incidents: loadIncidents());
  });
  tearDown(() => dir.deleteSync(recursive: true));

  /// A job that prints [log] and fails, the way a build would.
  Future<Job> failWith(String log) async {
    final text = File('${dir.path}/out.txt')..writeAsStringSync(log);
    final script = File('${dir.path}/fail.dart')
      ..writeAsStringSync('import "dart:io"; void main() { stdout.write(File(r"${text.path}").readAsStringSync()); exit(1); }');
    final job = runner.enqueue('sabily', 'build', [Step(dart, [script.path])]);
    await job.done;
    return job;
  }

  String bundle(Job job) => fixBundle(
        job: job,
        version: '1.1.9+22',
        tools: const {'Flutter': '3.47.5', 'Dart': '3.13.4', 'JDK': '21', 'OS': 'windows'},
        gitHash: '300f50c',
        dirty: const ['lib/core/onboarding/intro.dart'],
        brandJson: '{"slug":"sabily","support":{"email":"help@sabily.example"}}',
        missing: const ['Android OAuth client: not set'],
        redact: Redactor(const []),
      );

  const drills = {
    'missing-ndk.log': ('sdk-components-missing', "[CXX1300] CMake '3.22.1' was not found"),
    'oversized-logo.log': ('oversized-icon-bitmap', 'Canvas: trying to draw too large'),
    'missing-key-file.log': ('release-without-brand-key', 'not found for signing config'),
    'release-api-base-url.log': ('release-define-override', 'API_BASE_URL was overridden'),
    'stripe-activity.log': ('stripe-fragment-activity', 'subclassed by FlutterFragmentActivity'),
  };

  for (final MapEntry(key: file, value: (id, firstError)) in drills.entries) {
    test('drill $file: found as $id, bundled small and clean', () async {
      final job = await failWith(File('test/studio/fixtures/logs/$file').readAsStringSync());
      expect(job.matched.map((m) => m.incident.id), contains(id));
      final b = bundle(job);
      expect(b.length, lessThanOrEqualTo(fixBundleCap));
      expect(b, contains(id));
      expect(b, contains(firstError));
      expect(b, contains(job.logPath));
      expect(b, contains('Android OAuth client: not set'));
      for (final s in secrets) {
        expect(b, isNot(contains(s)), reason: s);
      }
    });
  }

  test('the first error is an error, not a count of none', () async {
    final b = bundle(await failWith([
      'ok   acorn: 0 errors, 5 warnings, generated files in sync',
      '00:00 +81: test/core/brand_wiring_test.dart: an unknown style names itself in the error',
      'Analyzing transasim-mobile...',
      '  error - lib/x.dart:3:1 - Undefined name foo. - undefined_identifier',
    ].join('\n')));
    // Line 5 of the log file: line 1 is the command.
    expect(b, contains('### First error (line 5)\n```\n  error - lib/x.dart'));
  });

  test('a huge log keeps the first error and the very end, and stays under the cap', () async {
    final log = [
      for (var i = 0; i < 3000; i++) '> Task :app:step$i',
      'java.lang.OutOfMemoryError: Java heap space',
      for (var i = 0; i < 20000; i++) 'noise line $i with some padding to make it long enough to matter',
      'THE LAST LINE',
    ].join('\n');
    final b = bundle(await failWith(log));
    expect(b.length, lessThanOrEqualTo(fixBundleCap));
    expect(b, contains('java.lang.OutOfMemoryError: Java heap space'));
    expect(b, contains('THE LAST LINE'));
    expect(b, contains('gradle-heap'));
    expect(b, contains('Stop the Gradle daemons'));
  });
}
