/// The jobs Studio can start, by name. A request names one of these; it
/// never carries a command.
library;

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
};

/// Why [slug] cannot build for DEV yet (docs/STUDIO-SPEC.md §16.9), or null
/// when it can.
String? buildDevRefusal(String root, String slug) {
  if (!brandSlugs(root).contains(slug)) return 'pick a brand first';
  final backend = (readStudio(root, slug)['backend'] as Map?) ?? const {};
  final dev = (backend['dev'] as Map?) ?? const {};
  if (dev['apiBaseUrl'] == null) return 'enter the DEV backend in the Backend tab first';
  if (backend['phase2'] == null) return 'Go phase 2 first: the DEV backend must pass its gate';
  if (loadServers(root)[dev['server']]?.prodFor.contains(slug) ?? false) {
    return "the DEV server is $slug's production: a DEV build never points at it";
  }
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
  final layers = dart(['run', 'tool/check_layers.dart']);
  final generated = dart(['run', 'tool/studio/bin/studio.dart', '--check']);
  switch (name) {
    case 'validate-fast':
      return [fl(['test', 'test/core/brand_wiring_test.dart', 'test/core/brand_config_test.dart']), layers, generated];
    case 'validate-full':
      return [fl(['pub', 'get']), fl(['analyze']), layers, generated, fl(['test'])];
    case 'gradle-stop':
      return [Step('$root/android/gradlew${win ? '.bat' : ''}', ['--stop'], workingDirectory: '$root/android')];
    case 'sdk-install':
      final sdk = sdkRoot(root);
      if (sdk == null) return null;
      final missing = [for (final p in missingSdkPackages(sdk)) p == 'build-tools' ? 'build-tools;36.0.0' : p];
      return missing.isEmpty
          ? null
          : [sdkInstallStep(sdk, missing, java: javaExecutable(), androidCli: androidCliOf(sdk))];
    case 'build-dev':
      if (buildDevRefusal(root, slug) != null) return null;
      final backend = readStudio(root, slug)['backend'] as Map;
      final dev = backend['dev'] as Map;
      final payments = (backend['features'] as Map?)?['payments'] == true;
      // Profile, never release: a release refuses these defines (brand_loader.dart).
      // Universal, not split: one APK for the x86_64 emulator and a phone alike.
      return [
        fl([
          'build', 'apk', '--profile', '--flavor', slug, '-t', 'lib/flavors/main_$slug.dart',
          '--dart-define=API_BASE_URL=${dev['apiBaseUrl']}',
          if (payments) '--dart-define=STRIPE_PUBLISHABLE_KEY=${dev['stripePublishableKeyTest']}',
        ]),
      ];
  }
  return null;
}
