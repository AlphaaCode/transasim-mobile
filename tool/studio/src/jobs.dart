/// The jobs Studio can start, by name. A request names one of these; it
/// never carries a command.
library;

import 'dart:convert';
import 'dart:io';

import '../../gen_brand_flavors.dart' show brandSlugs;
import 'backend.dart';
import 'doctor.dart';
import 'emulator.dart';
import 'generate.dart' show readStudio;
import 'incidents.dart';
import 'runner.dart';
import 'store.dart' show shotHeight, shotWidth;
import 'testrecord.dart';

const jobNames = {
  'validate-fast': 'Validate (fast): wiring and brand tests, layers, generated files',
  'validate-full': 'Validate (full): pub get, analyze, layers, generated files, every test',
  'gradle-stop': 'Stop the Gradle daemons',
  'sdk-install': 'Install the missing Android SDK packages',
  'build-dev': 'Build for test (DEV): build the DEV APK, stop Gradle, start the emulator, install, open the app',
  'build-store': 'Build for the store: the APK as brand.json says (no DEV address), stop Gradle, start the emulator, install, open the app',
  'launch-dev': 'Launch on emulator again, without building: stop Gradle, start the AVD, install, open',
  'uninstall-retry': 'Uninstall the app from the emulator (deletes its data there), then install and open it again',
  'logcat': 'Logcat: the app errors and flutter lines from the emulator, until cancelled',
  'release-android': 'Release (Android): the AAB and the APK, signed, checked, filed under dist/. Never uploaded',
  'store-capture-on': 'Store screenshots: the emulator at 1080×1920 (9:16), status bar in demo mode',
  'store-capture-off': 'Store screenshots done: the emulator back to its own size, demo mode off',
};

/// Why the emulator cannot take store screenshots now, or null when it can.
String? storeCaptureRefusal(String root) {
  final adb = adbOf(root);
  if (adb == null || !File(adb).existsSync()) return 'open Doctor first: it finds the Android SDK and its adb on this machine';
  if (!_emulatorRunning(adb)) return 'start the emulator first (Build for test, or Launch again), then open the screen to capture';
  return null;
}

/// Android's demo mode, the status bar fastlane screenshots use: a fixed clock,
/// a full battery and signal, no notification icons.
List<List<String>> get _demoMode => [
      ['settings', 'put', 'global', 'sysui_demo_allowed', '1'],
      for (final extras in [
        ['command', 'enter'],
        ['command', 'clock', '-e', 'hhmm', '0930'],
        ['command', 'battery', '-e', 'level', '100', '-e', 'plugged', 'false'],
        // Without "fully", Android 16 draws a satellite icon in place of the Wi-Fi.
        ['command', 'network', '-e', 'wifi', 'show', '-e', 'level', '4', '-e', 'fully', 'true'],
        ['command', 'notifications', '-e', 'visible', 'false'],
      ])
        ['am', 'broadcast', '-a', 'com.android.systemui.demo', '-e', ...extras],
    ];

/// Why [slug] cannot be released now (§6 step 3, §16.9); empty when it may.
/// [dirty] is git's word and [tested] the brand's test record, unless a test gives them.
List<String> releaseAndroidRefusal(String root, String slug,
    {required Map<String, Incident> items, Map<String, Object?>? probes, bool? dirty, TestState? tested}) {
  if (!brandSlugs(root).contains(slug)) return const ['pick a brand first'];
  return [
    if (!File('$root/android/$slug-key.properties').existsSync())
      'release-without-brand-key: android/$slug-key.properties is missing, so the release would carry the debug key',
    if (dirty ?? treeDirty(root)) 'commit first: a release names one commit, and the tree has changes',
    ?testRefusal(tested ?? testState(root, slug)),
    ...releaseRefusal(root, slug, items: items, probes: probes, now: DateTime.now().toUtc()),
  ];
}

/// Whether git shows any change (dist/ and .studio/ are ignored).
bool treeDirty(String root) {
  final r = Process.runSync('git', ['status', '--porcelain'], workingDirectory: root);
  return r.exitCode != 0 || '${r.stdout}'.trim().isNotEmpty;
}

/// The profile APK the emulator gets for [slug]: Build for test (DEV) makes it with
/// DEV's address compiled in, Build for the store without (brand.json's own).
String profileApk(String root, String slug) => '$root/build/app/outputs/flutter-apk/app-$slug-profile.apk';

/// Why nothing can go onto the emulator for [slug] yet, or null when it can.
String? emulatorRefusal(String root, String slug) {
  if (!brandSlugs(root).contains(slug)) return 'pick a brand first';
  final m = readMachine(root);
  if (m['sdkRoot'] == null || m['avd'] == null) {
    return 'open Doctor first: it finds the Android SDK and the emulator (AVD) on this machine';
  }
  return null;
}

/// Why Studio cannot launch [slug] on the emulator yet, or null when it can.
String? launchRefusal(String root, String slug) =>
    emulatorRefusal(root, slug) ??
    (File(profileApk(root, slug)).existsSync()
        ? null
        : 'press Build for test (DEV) or Build for the store first: there is no APK yet');

/// The adb of this machine's SDK (Doctor found it), or null before Doctor has.
String? adbOf(String root) {
  final sdk = readMachine(root)['sdkRoot'];
  return sdk == null ? null : '$sdk/platform-tools/adb${Platform.isWindows ? '.exe' : ''}';
}

/// Why [slug]'s logcat cannot start, or null when it can.
String? logcatRefusal(String root, String slug) {
  if (!brandSlugs(root).contains(slug)) return 'pick a brand first';
  final adb = adbOf(root);
  if (adb == null || !File(adb).existsSync()) return 'open Doctor first: it finds the Android SDK and its adb on this machine';
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
      final m = readMachine(root);
      return [
        fl([
          'build', 'apk', '--profile', '--flavor', slug, '-t', 'lib/flavors/main_$slug.dart',
          '--dart-define=API_BASE_URL=${dev['apiBaseUrl']}',
          // Only a recorded test key: a brand with payments cannot get here without one.
          if (usableStripeKey(key, mode: 'test')) '--dart-define=STRIPE_PUBLISHABLE_KEY=$key',
        ]),
        // Then straight onto the emulator, once Doctor has found one on this machine.
        if (m['sdkRoot'] != null && m['avd'] != null) ..._launch(root, slug, m, gradleStop),
      ];
    case 'build-store':
      if (emulatorRefusal(root, slug) != null) return null;
      // No --dart-define: the app talks to the backend brand.json names, as a release
      // does, so store screenshots show the real catalogue and prices.
      return [
        fl(['build', 'apk', '--profile', '--flavor', slug, '-t', 'lib/flavors/main_$slug.dart']),
        ..._launch(root, slug, readMachine(root), gradleStop),
      ];
    case 'release-android':
      // Never a --dart-define: a release reads brand.json and throws if overridden.
      final target = ['--release', '--flavor', slug, '-t', 'lib/flavors/main_$slug.dart'];
      return [
        fl(['build', 'appbundle', ...target]),
        fl(['build', 'apk', ...target]),
        gradleStop,
        dart(['run', 'tool/studio/bin/studio.dart', '--verify-release', slug]),
      ];
    case 'logcat':
      if (logcatRefusal(root, slug) != null) return null;
      final adb = adbOf(root)!;
      final appId = '${(jsonDecode(File('$root/brands/$slug/brand.json').readAsStringSync()) as Map)['mobile']['applicationId']}';
      return [
        // The app's own process only, its errors and everything it says through flutter.
        // adb talks to the emulator (-e), never a phone plugged in.
        Step(adb, ['-e', 'logcat'], display: 'adb -e logcat --pid=<$appId> flutter:V *:E', lateArgs: () async {
          final pid = await findAppPid(appId, (a) => adbOutput(adb, a));
          if (pid == null) {
            throw StateError('$appId is not running on the emulator: open the app (Launch on emulator), then start the logcat again');
          }
          return ['--pid=$pid', 'flutter:V', '*:E'];
        }),
      ];
    case 'launch-dev':
      if (launchRefusal(root, slug) != null) return null;
      return _launch(root, slug, readMachine(root), gradleStop);
    case 'uninstall-retry':
      // Offered only by the incident install-update-incompatible, and only run when pressed.
      if (launchRefusal(root, slug) != null) return null;
      return _launch(root, slug, readMachine(root), gradleStop, uninstallFirst: true);
    case 'store-capture-on' || 'store-capture-off':
      final adb = adbOf(root);
      if (adb == null) return null;
      // -e everywhere: the emulator, never a phone plugged in.
      Step shell(List<String> a) => Step(adb, ['-e', 'shell', ...a]);
      return name == 'store-capture-on'
          ? [shell(['wm', 'size', '${shotWidth}x$shotHeight']), for (final a in _demoMode) shell(a)]
          : [shell(['am', 'broadcast', '-a', 'com.android.systemui.demo', '-e', 'command', 'exit']), shell(['wm', 'size', 'reset'])];
  }
  return null;
}

/// Stop Gradle, start the AVD unless one runs, wait for boot, network on,
/// install the profile APK, open the app.
List<Step> _launch(String root, String slug, Map<String, Object?> m, Step gradleStop, {bool uninstallFirst = false}) {
  final win = Platform.isWindows;
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
    // And Wi-Fi on: after a cold boot it was off, with no network at all (2026-10-17).
    Step(adb, ['-e', 'shell', 'svc', 'wifi', 'enable'], display: 'adb: Wi-Fi on'),
    // Deletes the app and its data on the emulator, so only when the user pressed the button.
    if (uninstallFirst) Step(adb, ['-e', 'uninstall', appId], display: 'adb -e uninstall $appId'),
    Step(adb, ['-e', 'install', '-r', profileApk(root, slug)]),
    Step(adb, ['-e', 'shell', 'monkey', '-p', appId, '-c', 'android.intent.category.LAUNCHER', '1'],
        display: 'adb: open $appId'),
  ];
}
