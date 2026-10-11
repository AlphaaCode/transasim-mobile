import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/studio/src/doctor.dart';

/// Doctor reads this machine; these are the readings, from fixtures, so the
/// rules hold on any machine. The real run is checked by hand (Slice B notes).
void main() {
  group('the Android SDK root is found, never assumed', () {
    test('from android/local.properties first, escaped the way Gradle writes it', () {
      expect(sdkRootFrom(r'sdk.dir=C\:\\Android', {'ANDROID_HOME': '/elsewhere'}), r'C:\Android');
      expect(sdkRootFrom('flutter.sdk=C:\\\\src\\\\flutter\nsdk.dir=C:/Android\n', {}), 'C:/Android');
    });

    test('then ANDROID_HOME, then ANDROID_SDK_ROOT, else nothing', () {
      expect(sdkRootFrom(null, {'ANDROID_HOME': '/a', 'ANDROID_SDK_ROOT': '/b'}), '/a');
      expect(sdkRootFrom('flutter.sdk=/f', {'ANDROID_SDK_ROOT': '/b'}), '/b');
      expect(sdkRootFrom(null, {}), isNull);
    });
  });

  test('the components the build needs are named when missing', () {
    final sdk = Directory.systemTemp.createTempSync('sdk');
    addTearDown(() => sdk.deleteSync(recursive: true));
    expect(missingSdkPackages(sdk.path),
        ['platforms;android-35', 'platforms;android-36', 'ndk;28.2.13676358', 'cmake;3.22.1', 'build-tools']);
    for (final d in ['platforms/android-35', 'platforms/android-36', 'cmake/3.22.1', 'build-tools/36.0.0']) {
      Directory('${sdk.path}/$d').createSync(recursive: true);
    }
    // An NDK folder without source.properties is a half-finished download.
    Directory('${sdk.path}/ndk/28.2.13676358').createSync(recursive: true);
    expect(missingSdkPackages(sdk.path), ['ndk;28.2.13676358']);
    File('${sdk.path}/ndk/28.2.13676358/source.properties').writeAsStringSync('Pkg.Revision = 28.2.13676358\n');
    expect(missingSdkPackages(sdk.path), isEmpty);
  });

  test('the AVD list is read from the emulator, its log lines ignored', () {
    expect(parseAvds('INFO    | Storing crashdata in: C:\\x\nsabily_test\nPixel_6_API_35\n\n'),
        ['sabily_test', 'Pixel_6_API_35']);
    expect(chooseAvd(['a', 'b'], remembered: 'b'), 'b');
    expect(chooseAvd(['a', 'b'], remembered: 'gone'), 'a');
    expect(chooseAvd([], remembered: 'gone'), isNull);
  });

  test('the emulator GPU mode is angle_indirect on Windows', () {
    // -gpu host segfaults the emulator on this machine's GPU driver.
    expect(gpuModeFor('windows'), 'angle_indirect');
    expect(gpuModeFor('macos'), 'host');
  });

  test('versions are read from what the tools print', () {
    expect(javaMajor('openjdk version "21.0.12.1" 2026-08-18 LTS'), 21);
    expect(javaMajor('java version "1.8.0_281"'), 8);
    expect(javaMajor('nothing useful'), isNull);
    expect(flutterDefaultTargetSdk('class FlutterExtension {\n    val targetSdkVersion: Int = 36\n'), 36);
    expect(gradleHeapGb('org.gradle.jvmargs=-Xmx4g -XX:MaxMetaspaceSize=1g'), 4);
    expect(gradleHeapGb('org.gradle.jvmargs=-Xmx1536m'), 1.5);
    // The comment above the setting quotes the template's value; only the setting counts.
    expect(gradleHeapGb('# The Flutter template ships -Xmx8G\norg.gradle.jvmargs=-Xmx4g'), 4);
    expect(xcodeMajor('Xcode 26.0.1\nBuild version 17A400'), 26);
  });

  test('an SDK install runs the installer itself, never sdkmanager.bat', () {
    // cmdline-tools up to 19: sdkmanager's Java class.
    final java = sdkInstallStep('C:/Android', ['ndk;28.2.13676358', 'cmake;3.22.1'], java: 'C:/jdk/bin/java.exe');
    expect(java.executable, 'C:/jdk/bin/java.exe');
    expect(java.args, [
      '-cp',
      'C:/Android/cmdline-tools/latest/lib/sdkmanager-classpath.jar',
      'com.android.sdklib.tool.sdkmanager.SdkManagerCli',
      '--sdk_root=C:/Android',
      'ndk;28.2.13676358',
      'cmake;3.22.1',
    ]);
    // cmdline-tools 23 dropped that class: sdkmanager.bat now wraps the
    // Android CLI, which names packages with "/".
    final cli = sdkInstallStep('C:/Android', ['ndk;28.2.13676358'], java: 'java', androidCli: 'C:/Android/cmdline-tools/latest/bin/android.exe');
    expect(cli.executable, 'C:/Android/cmdline-tools/latest/bin/android.exe');
    expect(cli.args, ['--sdk=C:/Android', 'sdk', 'install', 'ndk/28.2.13676358']);
    for (final s in [java, cli]) {
      expect('${s.executable} ${s.args.join(' ')}', isNot(contains('sdkmanager.bat')));
    }
  });
}
