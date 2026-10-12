/// Doctor (docs/STUDIO-SPEC.md §7): what this machine has, read every time,
/// never assumed. Each check says ok, warn or fail, why in one line, and,
/// where it is safe, the job that fixes it. Nothing installs unless the user
/// presses that job's button, and no licence is ever accepted for them.
library;

import 'dart:convert';
import 'dart:io';

import '../../gen_brand_flavors.dart' show brandSlugs;
import 'runner.dart';

const ndkVersion = '28.2.13676358';
const cmakeVersion = '3.22.1';
const targetSdk = 36;

class Check {
  Check(this.id, this.group, this.label, this.status, this.detail, {this.fix});

  final String id, group, label, detail;

  /// ok, warn or fail.
  final String status;

  /// `{job, label}` for a fix the user may start.
  final Map<String, String>? fix;

  Map<String, Object?> toJson() =>
      {'id': id, 'group': group, 'label': label, 'status': status, 'detail': detail, 'fix': fix};
}

/// The SDK root: `android/local.properties` `sdk.dir` (Java-properties
/// escaped), then `ANDROID_HOME`, then `ANDROID_SDK_ROOT`.
String? sdkRootFrom(String? localProperties, Map<String, String> env) {
  for (final line in const LineSplitter().convert(localProperties ?? '')) {
    if (RegExp(r'^\s*sdk\.dir\s*=\s*(.+?)\s*$').firstMatch(line) case final m?) {
      return m[1]!.replaceAllMapped(RegExp(r'\\(.)'), (e) => e[1]!);
    }
  }
  return env['ANDROID_HOME'] ?? env['ANDROID_SDK_ROOT'];
}

/// The sdkmanager packages the build needs and [sdk] lacks; `build-tools`
/// stands for "any version".
List<String> missingSdkPackages(String sdk) => [
      for (final p in ['platforms;android-35', 'platforms;android-$targetSdk'])
        if (!Directory('$sdk/${p.replaceFirst(';', '/')}').existsSync()) p,
      if (!File('$sdk/ndk/$ndkVersion/source.properties').existsSync()) 'ndk;$ndkVersion',
      if (!Directory('$sdk/cmake/$cmakeVersion').existsSync()) 'cmake;$cmakeVersion',
      if (!Directory('$sdk/build-tools').existsSync() || Directory('$sdk/build-tools').listSync().isEmpty)
        'build-tools',
    ];

List<String> parseAvds(String out) => [
      for (final l in const LineSplitter().convert(out))
        if (RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(l.trim())) l.trim(),
    ];

String? chooseAvd(List<String> listed, {String? remembered}) =>
    listed.contains(remembered) ? remembered : (listed.isEmpty ? null : listed.first);

/// `-gpu host` segfaults the emulator on the Windows laptop's driver;
/// angle_indirect works there.
String gpuModeFor(String os) => os == 'windows' ? 'angle_indirect' : 'host';

int? javaMajor(String out) {
  final m = RegExp(r'version "(\d+)(?:\.(\d+))?').firstMatch(out);
  if (m == null) return null;
  final major = int.parse(m[1]!);
  return major == 1 ? int.tryParse(m[2] ?? '') : major;
}

int? flutterDefaultTargetSdk(String flutterExtensionKt) =>
    int.tryParse(RegExp(r'val targetSdkVersion: Int = (\d+)').firstMatch(flutterExtensionKt)?[1] ?? '');

/// The daemon heap set by the `org.gradle.jvmargs` line (not a comment
/// quoting another value).
num? gradleHeapGb(String gradleProperties) {
  final m = RegExp(r'^\s*org\.gradle\.jvmargs\s*=.*?-Xmx(\d+)([gGmM])', multiLine: true).firstMatch(gradleProperties);
  if (m == null) return null;
  final n = int.parse(m[1]!);
  return m[2]!.toLowerCase() == 'g' ? n : n / 1024;
}

int? xcodeMajor(String out) => int.tryParse(RegExp(r'Xcode (\d+)').firstMatch(out)?[1] ?? '');

/// The SDK installer, called directly, never through `sdkmanager.bat`
/// (which split "ndk;28…" at the semicolon). cmdline-tools up to 19 have
/// sdkmanager's Java class; 23 dropped it for the Android CLI ([androidCli]),
/// which names packages with "/". Stdin is closed by the runner, so a
/// licence prompt fails the job instead of being answered for the user.
Step sdkInstallStep(String sdk, List<String> packages, {required String java, String? androidCli}) =>
    androidCli != null
        ? Step(androidCli, ['--sdk=$sdk', 'sdk', 'install', for (final p in packages) p.replaceAll(';', '/')],
            display: 'android sdk install ${packages.join(' ')}')
        : Step(java, [
            '-cp',
            '$sdk/cmdline-tools/latest/lib/sdkmanager-classpath.jar',
            'com.android.sdklib.tool.sdkmanager.SdkManagerCli',
            '--sdk_root=$sdk',
            ...packages,
          ], display: 'sdkmanager ${packages.join(' ')}');

/// The Android CLI of cmdline-tools 23+, when the SDK has no sdkmanager
/// Java class; null when the old class is there (or neither is).
String? androidCliOf(String sdk) =>
    !File('$sdk/cmdline-tools/latest/lib/sdkmanager-classpath.jar').existsSync() &&
            File(_exe('$sdk/cmdline-tools/latest/bin/android')).existsSync()
        ? _exe('$sdk/cmdline-tools/latest/bin/android')
        : null;

/// Whether [sdk] can install packages at all.
bool hasInstaller(String sdk) =>
    File('$sdk/cmdline-tools/latest/lib/sdkmanager-classpath.jar').existsSync() || androidCliOf(sdk) != null;

String _exe(String path) => Platform.isWindows ? '$path.exe' : path;

String? _read(String path) => File(path).existsSync() ? File(path).readAsStringSync() : null;

/// The JDK Flutter builds with, in Flutter's order: its `jdk-dir` setting,
/// then JAVA_HOME, then PATH.
// ponytail: Flutter also prefers Android Studio's bundled JBR over JAVA_HOME;
// add that when a machine with Android Studio meets Studio.
String javaExecutable() {
  final env = Platform.environment;
  for (final settings in [
    '${env['APPDATA']}/.flutter_settings',
    '${env['HOME']}/.flutter_settings',
    '${env['HOME']}/.config/flutter/settings',
  ]) {
    final dir = (jsonDecode(_read(settings) ?? '{}') as Map)['jdk-dir'];
    if (dir is String && File(_exe('$dir/bin/java')).existsSync()) return _exe('$dir/bin/java');
  }
  final home = env['JAVA_HOME'];
  if (home != null && File(_exe('$home/bin/java')).existsSync()) return _exe('$home/bin/java');
  return 'java';
}

String? sdkRoot(String root) => sdkRootFrom(_read('$root/android/local.properties'), Platform.environment);

/// `.studio/machine.json`: what this machine uses (gitignored, per machine).
Map<String, Object?> readMachine(String root) =>
    (jsonDecode(_read('$root/.studio/machine.json') ?? '{}') as Map).cast<String, Object?>();

Future<String> _out(String exe, List<String> args, {String? cwd}) async {
  try {
    final r = await Process.run(exe, args, workingDirectory: cwd, runInShell: Platform.isWindows && exe.endsWith('.bat'));
    return '${r.stdout}\n${r.stderr}';
  } on ProcessException {
    return '';
  }
}

Future<List<Check>> runDoctor(String root) async {
  final groups = await Future.wait([
    _toolchain(),
    _android(root),
    _repo(root),
    _machine(root),
    if (Platform.isMacOS) _mac(),
  ]);
  return [for (final g in groups) ...g];
}

Future<List<Check>> _toolchain() async {
  const g = 'Toolchain';
  final flutter = flutterRoot();
  final version = flutter == null
      ? null
      : (jsonDecode(_read('$flutter/bin/cache/flutter.version.json') ?? '{}') as Map)['frameworkVersion'];
  final sdk = flutter == null
      ? null
      : flutterDefaultTargetSdk(
          _read('$flutter/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt') ?? '');
  final java = javaExecutable();
  final major = javaMajor(await _out(java, ['-version']));
  return [
    Check('flutter', g, 'Flutter', version == null ? 'fail' : 'ok',
        version == null ? 'Studio is not running on a Flutter SDK\'s Dart' : '$version at $flutter'),
    Check('flutter-target-sdk', g, 'Flutter default target SDK', sdk == targetSdk ? 'ok' : 'fail',
        sdk == null ? 'not found in flutter_tools' : 'API $sdk${sdk == targetSdk ? '' : ': Play requires $targetSdk'}'),
    Check('dart', g, 'Dart', 'ok', Platform.version.split(' ').first),
    if (!Platform.isMacOS)
      Check('ios-builds', g, 'iOS builds', 'ok',
          "on the Mac: Build's \"Copy prompt for the Mac\". xtool (iOS builds off the Mac) is not set up"),
    Check('jdk', g, 'JDK', major == 21 ? 'ok' : (major == null ? 'fail' : 'warn'),
        major == null ? 'no java at $java' : 'JDK $major at $java${major == 21 ? '' : ' (the build is tested on 21)'}'),
  ];
}

Future<List<Check>> _android(String root) async {
  const g = 'Android SDK';
  final sdk = sdkRoot(root);
  if (sdk == null || !Directory(sdk).existsSync()) {
    return [
      Check('sdk-root', g, 'SDK root', 'fail',
          sdk == null
              ? 'not in android/local.properties (sdk.dir), ANDROID_HOME or ANDROID_SDK_ROOT'
              : '$sdk does not exist'),
    ];
  }
  final missing = missingSdkPackages(sdk);
  final hasCmdline = hasInstaller(sdk);
  final licensed = File('$sdk/licenses/android-sdk-license').existsSync();
  final adb = _exe('$sdk/platform-tools/adb');
  final emulator = _exe('$sdk/emulator/emulator');
  final avds = File(emulator).existsSync() ? parseAvds(await _out(emulator, ['-list-avds'])) : <String>[];
  final machine = readMachine(root);
  final avd = chooseAvd(avds, remembered: machine['avd'] as String?);
  final gpu = gpuModeFor(Platform.operatingSystem);
  final next = {...machine, 'sdkRoot': sdk, 'avd': avd, 'gpu': gpu};
  if (jsonEncode(next) != jsonEncode(machine)) {
    (File('$root/.studio/machine.json')..createSync(recursive: true))
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(next));
  }
  return [
    Check('sdk-root', g, 'SDK root', 'ok', sdk),
    Check('adb', g, 'adb', File(adb).existsSync() ? 'ok' : 'fail',
        File(adb).existsSync() ? adb : 'no platform-tools in $sdk'),
    Check('sdk-packages', g, 'Platforms 35 and 36, NDK $ndkVersion, CMake $cmakeVersion, build-tools',
        missing.isEmpty ? 'ok' : 'fail', missing.isEmpty ? 'all present' : 'missing: ${missing.join(', ')}',
        fix: missing.isEmpty || !hasCmdline || !licensed
            ? null
            : {'job': 'sdk-install', 'label': 'Install ${missing.join(', ')}'}),
    Check('cmdline-tools', g, 'SDK installer', hasCmdline ? 'ok' : 'fail',
        !hasCmdline
            ? 'no sdkmanager or Android CLI under $sdk/cmdline-tools/latest: install the command-line tools first'
            : (androidCliOf(sdk) != null ? 'Android CLI (cmdline-tools 23+)' : 'sdkmanager Java class')),
    Check('licences', g, 'SDK licences', licensed ? 'ok' : 'fail',
        licensed
            ? 'accepted'
            : 'not accepted. Read and accept them yourself: sdkmanager --licenses (Studio never accepts one for you)'),
    Check('avd', 'Emulator', 'AVD', avd == null ? 'warn' : 'ok',
        avd == null
            ? (File(emulator).existsSync() ? 'none yet: Launch app creates one' : 'no emulator in $sdk')
            : '$avd${avds.length > 1 ? ' (of ${avds.join(', ')})' : ''}'),
    Check('gpu', 'Emulator', 'GPU mode', 'ok', '-gpu $gpu'),
  ];
}

Future<List<Check>> _repo(String root) async {
  const g = 'Repository';
  final heap = gradleHeapGb(_read('$root/android/gradle.properties') ?? '');
  final status = (await _out('git', ['status', '--porcelain'], cwd: root)).trim();
  final dirty = status.isEmpty ? 0 : const LineSplitter().convert(status).length;
  final crlf = [
    for (final l in const LineSplitter().convert(await _out('git', ['ls-files', '--eol'], cwd: root)))
      if (l.contains('w/crlf') && l.contains('eol=lf')) l.split('\t').last,
  ];
  final keys = {
    for (final slug in brandSlugs(root))
      slug: File('$root/android/$slug-key.properties').existsSync()
          ? 'key'
          : (File('$root/android/$slug-key.properties.pending').existsSync() ? 'pending' : 'debug'),
  };
  final unsigned = [for (final e in keys.entries) if (e.value != 'key') '${e.key} (${e.value})'];
  final ffmpeg = await _out(Platform.isWindows ? 'where' : 'which', ['ffmpeg']);
  return [
    Check('gradle-heap', g, 'Gradle heap', heap != null && heap >= 4 ? 'ok' : 'warn',
        heap == null ? 'no -Xmx in android/gradle.properties' : '-Xmx ${heap}g${heap >= 4 ? '' : ': R8 needs 4g for a release'}'),
    Check('git-clean', g, 'Working tree', dirty == 0 ? 'ok' : 'warn',
        dirty == 0 ? 'clean' : '$dirty changed files (a release records the git hash)'),
    Check('line-endings', g, 'Line endings', crlf.isEmpty ? 'ok' : 'warn',
        crlf.isEmpty
            ? 'LF, as .gitattributes says'
            : '${crlf.length} files are CRLF on disk though git stores LF (${crlf.take(3).join(', ')}…). '
                'Harmless until a tool diffs them; delete and git checkout them to rewrite'),
    Check('upload-keys', g, 'Upload keys', unsigned.isEmpty ? 'ok' : 'warn',
        unsigned.isEmpty ? 'every brand has its key' : 'signed with the debug key: ${unsigned.join(', ')}'),
    Check('ffmpeg', g, 'ffmpeg', ffmpeg.trim().isEmpty ? 'warn' : 'ok',
        ffmpeg.trim().isEmpty
            ? 'not found: needed only to strip an intro\'s audio (winget install Gyan.FFmpeg)'
            : const LineSplitter().convert(ffmpeg.trim()).first),
  ];
}

Future<List<Check>> _machine(String root) async {
  const g = 'Machine';
  int? freeDiskGb, freeRamGb;
  if (Platform.isWindows) {
    final drive = Directory(root).absolute.path.substring(0, 1);
    final out = await _out('powershell', [
      '-NoProfile',
      '-Command',
      '(Get-PSDrive $drive).Free; (Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory',
    ]);
    final n = [for (final l in const LineSplitter().convert(out)) ?int.tryParse(l.trim())];
    if (n.length == 2) {
      freeDiskGb = n[0] ~/ (1 << 30);
      freeRamGb = n[1] ~/ (1 << 20);
    }
  } else {
    // ponytail: free RAM is read on Windows only; add vm_stat when the Mac builds.
    final cols = (await _out('df', ['-k', root])).trim().split('\n').last.split(RegExp(r'\s+'));
    if (cols.length > 3) freeDiskGb = (int.tryParse(cols[3]) ?? 0) ~/ (1 << 20);
  }
  return [
    Check('disk', g, 'Free disk', freeDiskGb == null ? 'warn' : (freeDiskGb >= 20 ? 'ok' : 'fail'),
        freeDiskGb == null ? 'not read' : '$freeDiskGb GB${freeDiskGb >= 20 ? '' : ': a release build needs 20 GB'}'),
    if (freeRamGb != null)
      Check('ram', g, 'Free memory', freeRamGb >= 4 ? 'ok' : 'warn',
          '$freeRamGb GB${freeRamGb >= 4 ? '' : ': a build and the emulator together need about 6 GB'}'),
  ];
}

Future<List<Check>> _mac() async {
  const g = 'Mac';
  final xcode = xcodeMajor(await _out('xcodebuild', ['-version']));
  final pod = (await _out('pod', ['--version'])).trim();
  return [
    Check('xcode', g, 'Xcode', xcode != null && xcode >= 26 ? 'ok' : 'fail',
        xcode == null ? 'not found' : 'Xcode $xcode${xcode >= 26 ? '' : ': Apple refuses SDKs older than Xcode 26'}'),
    Check('cocoapods', g, 'CocoaPods', pod.isEmpty ? 'fail' : 'ok', pod.isEmpty ? 'not found' : pod),
  ];
}
