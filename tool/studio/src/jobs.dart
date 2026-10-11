/// The jobs Studio can start, by name. A request names one of these; it
/// never carries a command.
library;

import 'dart:convert';
import 'dart:io';

import '../../gen_brand_flavors.dart' show brandSlugs;
import 'backend.dart';
import 'doctor.dart';
import 'generate.dart' show readStudio;
import 'runner.dart';

const jobNames = {
  'validate-fast': 'Validate (fast): wiring and brand tests, layers, generated files',
  'validate-full': 'Validate (full): pub get, analyze, layers, generated files, every test',
  'gradle-stop': 'Stop the Gradle daemons',
  'sdk-install': 'Install the missing Android SDK packages',
  'build-dev': 'Build for test (DEV): a profile APK pointed at the DEV backend',
  'launch-dev': 'Launch on the emulator: stop Gradle, start the AVD, install the DEV build, open the app',
};

/// The APK Build for test (DEV) makes for [slug].
String devApk(String root, String slug) => '$root/build/app/outputs/flutter-apk/app-$slug-profile.apk';

/// Why Studio cannot launch [slug] on the emulator yet, or null when it can.
String? launchRefusal(String root, String slug) {
  if (!brandSlugs(root).contains(slug)) return 'pick a brand first';
  final m = readMachine(root);
  if (m['sdkRoot'] == null || m['avd'] == null) {
    return 'open Doctor first: it finds the Android SDK and the emulator (AVD) on this machine';
  }
  if (!File(devApk(root, slug)).existsSync()) return 'press Build for test (DEV) first: there is no APK yet';
  return null;
}

/// Whether an emulator already answers adb, so Launch does not start a second one.
bool _emulatorRunning(String adb) {
  try {
    return RegExp(r'^emulator-\d+\s+device', multiLine: true).hasMatch('${Process.runSync(adb, ['devices']).stdout}');
  } on ProcessException {
    return false;
  }
}

/// Run by the device's own shell: until Android says it has booted, five minutes at most.
const _bootWait = r'i=0; while [ "$(getprop sys.boot_completed)" != "1" ] && [ $i -lt 150 ]; do sleep 2; '
    r'i=$((i+1)); done; [ "$(getprop sys.boot_completed)" = "1" ]';

/// Why [slug] cannot build for DEV yet (docs/STUDIO-SPEC.md §16.9), or null
/// when it can.
String? buildDevRefusal(String root, String slug) {
  if (!brandSlugs(root).contains(slug)) return 'pick a brand first';
  final backend = (readStudio(root, slug)['backend'] as Map?) ?? const {};
  final dev = (backend['dev'] as Map?) ?? const {};
  if (dev['apiBaseUrl'] == null) return 'enter the DEV backend in the Backend tab first';
  if (loadServers(root)[dev['server']]?.prodFor.contains(slug) ?? false) {
    return "the DEV server is $slug's production: a DEV build never points at it";
  }
  // A legacy brand's backend items are information only: nothing waits on them.
  if (isLegacy(readStudio(root, slug))) return null;
  if (backend['phase2'] == null) return 'Go phase 2 first: the DEV backend must pass its gate';
  final payments = (backend['features'] as Map?)?['payments'] == true;
  if (payments && !usableStripeKey(dev['stripePublishableKeyTest'] as String?, mode: 'test')) {
    return 'payments are on: record the DEV pk_test_ key in the Backend tab';
  }
  return null;
}

/// The steps of [name] for [slug], or null when it is not a job or has
/// nothing to do.
List<Step>? jobSteps(String root, String name, {String slug = 'studio'}) {
  final win = Platform.isWindows;
  final flutter = flutterRoot();
  Step fl(List<String> a) => Step('$flutter/bin/flutter${win ? '.bat' : ''}', a, workingDirectory: root);
  Step dart(List<String> a) =>
      Step('$flutter/bin/cache/dart-sdk/bin/dart${win ? '.exe' : ''}', a, workingDirectory: root);
  final gradleStop = Step('$root/android/gradlew${win ? '.bat' : ''}', ['--stop'], workingDirectory: '$root/android');
  final layers = dart(['run', 'tool/check_layers.dart']);
  final generated = dart(['run', 'tool/studio/bin/studio.dart', '--check']);
  switch (name) {
    case 'validate-fast':
      return [fl(['test', 'test/core/brand_wiring_test.dart', 'test/core/brand_config_test.dart']), layers, generated];
    case 'validate-full':
      return [fl(['pub', 'get']), fl(['analyze']), layers, generated, fl(['test'])];
    case 'gradle-stop':
      return [gradleStop];
    case 'sdk-install':
      final sdk = sdkRoot(root);
      if (sdk == null) return null;
      final missing = [for (final p in missingSdkPackages(sdk)) p == 'build-tools' ? 'build-tools;36.0.0' : p];
      return missing.isEmpty
          ? null
          : [sdkInstallStep(sdk, missing, java: javaExecutable(), androidCli: androidCliOf(sdk))];
    case 'build-dev':
      if (buildDevRefusal(root, slug) != null) return null;
      final dev = (readStudio(root, slug)['backend'] as Map)['dev'] as Map;
      final key = dev['stripePublishableKeyTest'] as String?;
      // Profile, never release: a release refuses these defines (brand_loader.dart).
      // Universal, not split: one APK for the x86_64 emulator and a phone alike.
      return [
        fl([
          'build', 'apk', '--profile', '--flavor', slug, '-t', 'lib/flavors/main_$slug.dart',
          '--dart-define=API_BASE_URL=${dev['apiBaseUrl']}',
          // Only a recorded test key: a brand with payments cannot get here without one.
          if (usableStripeKey(key, mode: 'test')) '--dart-define=STRIPE_PUBLISHABLE_KEY=$key',
        ]),
      ];
    case 'launch-dev':
      if (launchRefusal(root, slug) != null) return null;
      final m = readMachine(root);
      final sdk = '${m['sdkRoot']}';
      final adb = '$sdk/platform-tools/adb${win ? '.exe' : ''}';
      final emulator = '$sdk/emulator/emulator${win ? '.exe' : ''}';
      final avd = ['-avd', '${m['avd']}', '-gpu', '${m['gpu'] ?? 'auto'}', '-no-boot-anim', '-no-snapshot-save'];
      final brand = jsonDecode(File('$root/brands/$slug/brand.json').readAsStringSync()) as Map;
      final appId = '${(brand['mobile'] as Map)['applicationId']}';
      // -e everywhere: the emulator, even with a phone plugged in.
      return [
        gradleStop,
        // The emulator outlives the job: its window is the test, and Cancel leaves it be.
        if (!_emulatorRunning(adb)) Step(emulator, avd, detached: true),
        Step(adb, ['-e', 'wait-for-device', 'shell', _bootWait], display: 'adb: wait until Android has booted'),
        // A DEV test needs the backend: this AVD had airplane mode on (2026-10-11).
        Step(adb, ['-e', 'shell', 'cmd', 'connectivity', 'airplane-mode', 'disable'], display: 'adb: airplane mode off'),
        Step(adb, ['-e', 'install', '-r', devApk(root, slug)]),
        Step(adb, ['-e', 'shell', 'monkey', '-p', appId, '-c', 'android.intent.category.LAUNCHER', '1'],
            display: 'adb: open $appId'),
      ];
  }
  return null;
}
