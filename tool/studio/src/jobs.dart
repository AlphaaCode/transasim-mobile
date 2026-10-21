/// The jobs Studio can start, by name. A request names one of these; it
/// never carries a command.
library;

import 'dart:convert';
import 'dart:io';

import 'package:transasim_mobile/core/brand/app_flavor.dart';

import '../../gen_brand_flavors.dart' show brandSlugs;
import 'backend.dart';
import 'doctor.dart';
import 'emulator.dart';
import 'generate.dart' show readStudio;
import 'hosts.dart';
import 'incidents.dart';
import 'release.dart' show stagedApk;
import 'runner.dart';
import 'store.dart' show shotHeight, shotWidth;
import 'testrecord.dart';

const jobNames = {
  'validate-fast': 'Validate (fast): wiring and brand tests, layers, generated files',
  'validate-full': 'Validate (full): pub get, analyze, layers, generated files, every test',
  'gradle-stop': 'Stop the Gradle daemons',
  'sdk-install': 'Install the missing Android SDK packages',
  'build-dev': 'Build for test (DEV): the dev flavor (ids + .dev, the DEV server, a red banner), stop Gradle, start the emulator, install, open the app',
  'build-store': 'Build for the store: the prod flavor, on the production host as a release is, stop Gradle, start the emulator, install, open the app',
  'launch-dev': 'Launch the DEV build again, without building: stop Gradle, start the AVD, install, open',
  'launch-store': 'Launch the store build again, without building: stop Gradle, start the AVD, install, open',
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
/// The host rules hold for every brand, legacy ones included (Slice H);
/// [acknowledged]: this release accepted the brand's standing production exception.
List<String> releaseAndroidRefusal(String root, String slug,
    {required Map<String, Incident> items,
    Map<String, Object?>? probes,
    bool? dirty,
    TestState? tested,
    bool acknowledged = false}) {
  if (!brandSlugs(root).contains(slug)) return const ['pick a brand first'];
  return [
    if (!File('$root/android/$slug-key.properties').existsSync())
      'release-without-brand-key: android/$slug-key.properties is missing, so the release would carry the debug key',
    if (dirty ?? treeDirty(root)) 'commit first: a release names one commit, and the tree has changes',
    ?testRefusal(tested ?? testState(root, slug)),
    ...hostReleaseRefusal(root, slug, acknowledged: acknowledged),
    ...releaseRefusal(root, slug, items: items, probes: probes, now: DateTime.now().toUtc()),
  ];
}

/// Whether git shows any change (dist/ and .studio/ are ignored).
bool treeDirty(String root) {
  final r = Process.runSync('git', ['status', '--porcelain'], workingDirectory: root);
  return r.exitCode != 0 || '${r.stdout}'.trim().isNotEmpty;
}

/// The profile APK the emulator gets for [slug]'s [flavor]: Build for test (DEV)
/// stages the dev flavor's, Build for the store the prod one's, each under its
/// own name, so neither overwrites the other. Their ids differ, so both can sit
/// on the emulator side by side.
String profileApk(String root, String slug, AppFlavor flavor) => stagedApk(root, slug, flavor);

/// The flavor a launch job installs: the DEV build unless it names the store one.
AppFlavor launchFlavor(String job) => const {'build-store', 'launch-store'}.contains(job) ? AppFlavor.prod : AppFlavor.dev;

/// Why nothing can go onto the emulator for [slug] yet, or null when it can.
String? emulatorRefusal(String root, String slug) {
  if (!brandSlugs(root).contains(slug)) return 'pick a brand first';
  final m = readMachine(root);
  if (m['sdkRoot'] == null || m['avd'] == null) {
    return 'open Doctor first: it finds the Android SDK and the emulator (AVD) on this machine';
  }
  return null;
}

/// Why Studio cannot launch [slug]'s [flavor] build on the emulator yet, or null when it can.
String? launchRefusal(String root, String slug, AppFlavor flavor) =>
    emulatorRefusal(root, slug) ??
    (File(profileApk(root, slug, flavor)).existsSync()
        ? null
        : 'press ${flavor == AppFlavor.dev ? 'Build for test (DEV)' : 'Build for the store'} first: there is no '
            '${flavor == AppFlavor.dev ? 'DEV' : 'store'} APK yet');

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
  final studio = readStudio(root, slug);
  final mobile = (_brand(root, slug)['mobile'] as Map?) ?? const {};
  // The dev flavor exists only with a DEV host of the brand's own (Slice H):
  // eSimple's DEV server is its production until the server merge.
  if (devFlavorRefusal(slug, _brand(root, slug), studio) case final why?) return why;
  final backend = (studio['backend'] as Map?) ?? const {};
  final dev = (backend['dev'] as Map?) ?? const {};
  if (loadServers(root)[dev['server']]?.prodFor.contains(slug) ?? false) {
    return "the DEV server is $slug's production: a DEV build never points at it";
  }
  // A legacy brand's backend items are information only: nothing waits on them.
  if (isLegacy(studio)) return null;
  if (backend['phase2'] == null) return 'Go phase 2 first: the DEV backend must pass its gate';
  final payments = (backend['features'] as Map?)?['payments'] == true;
  if (payments && !usableStripeKey(mobile['devStripePublishableKey'] as String?, mode: 'test')) {
    return "payments are on: put the DEV backend's pk_test_ key in mobile.devStripePublishableKey (Integrations)";
  }
  return null;
}

Map<String, dynamic> _brand(String root, String slug) =>
    jsonDecode(File('$root/brands/$slug/brand.json').readAsStringSync()) as Map<String, dynamic>;

/// The steps of [name] for [slug], or null when it is not a job or has
/// nothing to do. [flavor] is the build `uninstall-retry` puts back (the DEV
/// one unless said); [acknowledgeException] carries the release's
/// acknowledgement of a standing production exception to its last check.
List<Step>? jobSteps(String root, String name,
    {String slug = 'studio', AppFlavor flavor = AppFlavor.dev, bool acknowledgeException = false}) {
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
      // The dev flavor: its bundle carries the DEV host and its pk_test_ key, so no
      // --dart-define (Slice H). Profile, never release. Universal, not split: one
      // APK for the x86_64 emulator and a phone alike.
      final m = readMachine(root);
      return [
        fl(['build', 'apk', '--profile', '--flavor', flavorName(slug, AppFlavor.dev), '-t', entryPoint(slug, AppFlavor.dev)]),
        dart(['run', 'tool/studio/bin/studio.dart', '--stage-apk', slug, 'dev']),
        // Then straight onto the emulator, once Doctor has found one on this machine.
        if (m['sdkRoot'] != null && m['avd'] != null) ..._launch(root, slug, AppFlavor.dev, m, gradleStop),
      ];
    case 'build-store':
      if (emulatorRefusal(root, slug) != null) return null;
      // The prod flavor, as a release is: the production host, so store screenshots
      // show the real catalogue and prices.
      return [
        fl(['build', 'apk', '--profile', '--flavor', slug, '-t', entryPoint(slug, AppFlavor.prod)]),
        dart(['run', 'tool/studio/bin/studio.dart', '--stage-apk', slug, 'prod']),
        ..._launch(root, slug, AppFlavor.prod, readMachine(root), gradleStop),
      ];
    case 'release-android':
      // The prod flavor, and never a --dart-define: the app refuses one in every mode.
      final target = ['--release', '--flavor', slug, '-t', entryPoint(slug, AppFlavor.prod)];
      return [
        fl(['build', 'appbundle', ...target]),
        fl(['build', 'apk', ...target]),
        gradleStop,
        dart(['run', 'tool/studio/bin/studio.dart', '--verify-release', slug, if (acknowledgeException) '--acknowledge-exception']),
      ];
    case 'logcat':
      if (logcatRefusal(root, slug) != null) return null;
      final adb = adbOf(root)!;
      final store = '${(_brand(root, slug)['mobile'] as Map)['applicationId']}';
      // The DEV build or the store one, whichever runs: the DEV one first.
      final ids = ['$store.dev', store];
      return [
        // The app's own process only, its errors and everything it says through flutter.
        // adb talks to the emulator (-e), never a phone plugged in.
        Step(adb, ['-e', 'logcat'], display: 'adb -e logcat --pid=<$store(.dev)> flutter:V *:E', lateArgs: () async {
          for (final id in ids) {
            final pid = await findAppPid(id, (a) => adbOutput(adb, a));
            if (pid != null) return ['--pid=$pid', 'flutter:V', '*:E'];
          }
          throw StateError('neither ${ids.join(' nor ')} is running on the emulator: open the app (Launch on emulator), then start the logcat again');
        }),
      ];
    case 'launch-dev' || 'launch-store':
      final f = launchFlavor(name);
      if (launchRefusal(root, slug, f) != null) return null;
      return _launch(root, slug, f, readMachine(root), gradleStop);
    case 'uninstall-retry':
      // Offered only by the incident install-update-incompatible, and only run when pressed.
      if (launchRefusal(root, slug, flavor) != null) return null;
      return _launch(root, slug, flavor, readMachine(root), gradleStop, uninstallFirst: true);
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
/// install [flavor]'s profile APK, open the app. Its lines say which build
/// went on: the store one or the DEV one, its id and its host.
List<Step> _launch(String root, String slug, AppFlavor flavor, Map<String, Object?> m, Step gradleStop,
    {bool uninstallFirst = false}) {
  final win = Platform.isWindows;
  final sdk = '${m['sdkRoot']}';
  final adb = '$sdk/platform-tools/adb${win ? '.exe' : ''}';
  final emulator = '$sdk/emulator/emulator${win ? '.exe' : ''}';
  final avd = ['-avd', '${m['avd']}', '-gpu', '${m['gpu'] ?? 'auto'}', '-no-boot-anim', '-no-snapshot-save'];
  final bundle = flavorBundle(_brand(root, slug), flavor)['mobile'] as Map;
  final appId = '${bundle['applicationId']}';
  final apk = profileApk(root, slug, flavor);
  final which = '${flavor == AppFlavor.dev ? 'the DEV build' : 'the STORE build'}: $appId, on ${hostOf('${bundle['apiBaseUrl']}')}';
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
    Step(adb, ['-e', 'install', '-r', apk], display: 'adb -e install -r ${apk.split('/').last} ($which)'),
    Step(adb, ['-e', 'shell', 'monkey', '-p', appId, '-c', 'android.intent.category.LAUNCHER', '1'],
        display: 'adb: open $which'),
  ];
}
