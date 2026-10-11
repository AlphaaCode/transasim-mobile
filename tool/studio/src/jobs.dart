/// The jobs Studio can start, by name. A request names one of these; it
/// never carries a command.
library;

import 'dart:io';

import 'doctor.dart';
import 'runner.dart';

const jobNames = {
  'validate-fast': 'Validate (fast): wiring and brand tests, layers, generated files',
  'validate-full': 'Validate (full): pub get, analyze, layers, generated files, every test',
  'gradle-stop': 'Stop the Gradle daemons',
  'sdk-install': 'Install the missing Android SDK packages',
};

/// The steps of [name], or null when it is not a job or has nothing to do.
List<Step>? jobSteps(String root, String name) {
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
  }
  return null;
}
