/// The release (docs/STUDIO-SPEC.md §6 step 3, Slice E): check the artifacts
/// themselves, not the intent, file them under dist/, and write the iOS
/// release for the Mac to follow. Studio never uploads anything: Play, App
/// Store Connect and Submit stay with Alpha.
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import 'doctor.dart' show javaExecutable, sdkRoot, targetSdk;
import 'signing.dart';

// ---- reading what the tools print ------------------------------------------------

typedef Badging = ({String package, int versionCode, String versionName, int targetSdk});

/// What `aapt2 dump badging` says about an APK.
Badging? parseBadging(String text) {
  final p = RegExp(r"^package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'", multiLine: true)
      .firstMatch(text);
  final t = RegExp(r"^targetSdkVersion:'(\d+)'", multiLine: true).firstMatch(text);
  if (p == null || t == null) return null;
  return (package: p[1]!, versionCode: int.parse(p[2]!), versionName: p[3]!, targetSdk: int.parse(t[1]!));
}

/// The first signer's SHA-1, as `AB:CD:…`, from `apksigner verify --print-certs`
/// (lowercase hex) or `keytool -printcert` (colons).
String? signerSha1(String text) {
  final a = RegExp(r'Signer #1 certificate SHA-1 digest: ([0-9a-f]{40})').firstMatch(text);
  if (a != null) return [for (var i = 0; i < 40; i += 2) a[1]!.substring(i, i + 2)].join(':').toUpperCase();
  return RegExp(r'SHA1: ((?:[0-9A-F]{2}:){19}[0-9A-F]{2})').firstMatch(text)?[1];
}

/// A PNG's width and height, from its IHDR header.
(int, int)? pngSize(List<int> b) {
  if (b.length < 24 || b[0] != 0x89 || b[1] != 0x50) return null;
  int u32(int at) => (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3];
  return (u32(16), u32(20));
}

// ---- the checks -------------------------------------------------------------------

class ReleaseCheck {
  ReleaseCheck(this.id, this.ok, this.detail);

  /// The incident the check guards against (tool/studio/incidents/).
  final String id;
  final bool ok;
  final String detail;

  Map<String, Object?> toJson() => {'id': id, 'ok': ok, 'detail': detail};
  @override
  String toString() => '${ok ? '[ok]  ' : '[FAIL]'} $id: $detail';
}

/// Every check on one release: the APK's manifest, both signatures, what is
/// packed, and the icons. [aabPngs] holds the sizes of the AAB's launcher icon
/// and brand mark, by entry name.
List<ReleaseCheck> checkRelease({
  required String slug,
  required Map<String, dynamic> brand,
  required String pubspecVersion,
  required Badging? badging,
  required String? apkSha1,
  required String? aabSha1,
  required String uploadSha1,
  required List<String> aabEntries,
  required List<String> apkEntries,
  required Map<String, (int, int)> aabPngs,
}) {
  final mobile = (brand['mobile'] as Map?) ?? const {};
  final (name, code) = switch (pubspecVersion.split('+')) {
    [final n, final c] => (n, int.tryParse(c)),
    _ => (pubspecVersion, null),
  };
  final video = (brand['intro'] as Map?)?['style'] == 'video';
  final brandsDir = RegExp(r'flutter_assets/brands/([^/]+)/');
  final foreign = <String>{
    for (final e in [...aabEntries, ...apkEntries])
      if (brandsDir.firstMatch(e)?[1] case final s? when s != slug) s,
  };
  final mp4 = [...aabEntries, ...apkEntries].any((e) => e.endsWith('.mp4'));
  (int, int)? size(String pattern) =>
      aabPngs.entries.where((e) => RegExp(pattern).hasMatch(e.key)).map((e) => e.value).firstOrNull;
  final launcher = size(r'^base/res/mipmap-xxxhdpi[^/]*/ic_launcher\.png$');
  final mark = size(r'^base/res/drawable[^/]*/brand_mark\.png$');
  String signed(String? sha1) => sha1 == null
      ? 'no signature read'
      : sha1 == uploadSha1
          ? 'the upload key ($sha1)'
          : '$sha1, not the upload key $uploadSha1: a debug or a foreign key';
  return [
    ReleaseCheck('package', badging?.package == mobile['applicationId'],
        'APK ${badging?.package ?? 'unreadable'}, brand.json ${mobile['applicationId']}'),
    ReleaseCheck('version', badging != null && badging.versionName == name && badging.versionCode == code,
        'APK ${badging?.versionName}+${badging?.versionCode}, pubspec $pubspecVersion'),
    ReleaseCheck('target-sdk-below-36', (badging?.targetSdk ?? 0) >= targetSdk,
        'targetSdkVersion ${badging?.targetSdk}, Play wants $targetSdk'),
    ReleaseCheck('release-without-brand-key', apkSha1 == uploadSha1 && aabSha1 == uploadSha1,
        'AAB: ${signed(aabSha1)}; APK: ${signed(apkSha1)}'),
    ReleaseCheck(
        'release-foreign-assets',
        foreign.isEmpty && mp4 == video,
        [
          if (foreign.isNotEmpty) "another brand's files are packed: ${foreign.join(', ')}",
          if (mp4 && !video) 'an intro video is packed, and the intro is not a video',
          if (!mp4 && video) 'the intro is a video, and none is packed',
          if (foreign.isEmpty && mp4 == video) 'only $slug\'s assets${video ? ', its intro video included' : ''}',
        ].join('; ')),
    ReleaseCheck(
        'oversized-icon-bitmap',
        launcher != null && mark != null && launcher.$1 <= 192 && launcher.$2 <= 192 && mark.$1 <= 432 && mark.$2 <= 432,
        'launcher ${launcher == null ? 'missing' : '${launcher.$1}×${launcher.$2}'} (192 max), '
            'brand_mark ${mark == null ? 'missing' : '${mark.$1}×${mark.$2}'} (432 max)'),
  ];
}

/// A warning when [code] was already built into dist/: Play refuses a version
/// code it has seen.
String? versionCodeWarning(String root, String slug, int code) {
  final dir = Directory('$root/dist/$slug');
  if (!dir.existsSync()) return null;
  for (final f in dir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('release.json'))) {
    final r = jsonDecode(f.readAsStringSync()) as Map;
    if (r['versionCode'] == code) {
      return 'version-code-used: $code was already built on ${r['builtAt']} (commit ${r['commit']}). '
          'If that one went to Play, it refuses this upload: raise the version in pubspec.yaml.';
    }
  }
  return null;
}

/// The dist/ releases of [slug], newest first: what the Build tab lists.
List<Map<String, Object?>> releaseHistory(String root, String slug) {
  final dir = Directory('$root/dist/$slug');
  if (!dir.existsSync()) return const [];
  final out = [
    for (final f in dir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('release.json')))
      (jsonDecode(f.readAsStringSync()) as Map).cast<String, Object?>(),
  ]..sort((a, b) => '${b['builtAt']}'.compareTo('${a['builtAt']}'));
  return out;
}

String pubspecVersion(String root) =>
    RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(File('$root/pubspec.yaml').readAsStringSync())?[1] ?? '?';

// ---- the iOS release, for the Mac -----------------------------------------------------

/// The launch window's colour, as the native launch screens use it.
String launchColour(Map<String, dynamic> brand) =>
    '${(brand['logo'] as Map?)?['introBackground'] ?? (brand['colors'] as Map?)?['surface']}';

/// What the Mac does for an iOS release of [slug], to paste to Claude Code
/// there or to follow by hand. It stops before Submit for Review.
String macPrompt({
  required String slug,
  required Map<String, dynamic> brand,
  required Map<String, dynamic> studio,
  required String branch,
  required String commit,
  required String iosVersion,
  required int build,
}) {
  final mobile = (brand['mobile'] as Map?) ?? const {};
  final team = studio['appleTeamId'] ?? '(appleTeamId missing from studio.json)';
  final deletion = (brand['legal'] as Map?)?['accountDeletionUrl'];
  final archive = '~/archives/$slug-$iosVersion-$build.xcarchive';
  return '''
# iOS release: ${brand['name']} ($slug) $iosVersion ($build)

You are on the Mac that builds iOS. Do these steps in order and stop where it says STOP.
Never pass --dart-define to this build: a release reads its backend and Stripe key from
brand.json, and throws on launch if either is overridden.

- Source: branch $branch, commit $commit
- Flavor: $slug · bundle id ${mobile['bundleIdentifier']} · team $team
- iOS version $iosVersion, build $build (App Store numbering, separate from Android's)

1. export PATH="\$HOME/development/flutter/bin:\$PATH"
2. git fetch && git checkout $commit && git status
   The tree must be clean.
3. ruby tool/ios_flavors.rb
   Idempotent: makes sure the $slug configurations and scheme exist.
4. Check before building:
   - ios/Flutter/$slug.xcconfig names bundle id ${mobile['bundleIdentifier']} and team $team.
   - The 1024 icon in ios/Runner/Brands/Brand-$slug.xcassets/AppIcon.appiconset has no alpha
     channel: sips -g hasAlpha <the 1024 png> must say "no".
   - The LaunchBackground colour in the same catalog is ${launchColour(brand)}.
5. flutter build ipa --release --flavor $slug -t lib/flavors/main_$slug.dart --build-name $iosVersion --build-number $build
6. Copy the archive aside before any other brand builds (build ipa overwrites it):
   mkdir -p ~/archives && cp -R build/ios/archive/Runner.xcarchive $archive
7. xcodebuild -exportArchive -archivePath $archive -exportOptionsPlist ExportOptions.plist -exportPath build/ios/upload -allowProvisioningUpdates
   ExportOptions.plist: method app-store-connect, destination upload, teamID $team.
8. In App Store Connect, wait until the build has finished processing. Then check:
   - "What's New" is set;
   - App Privacy matches PrivacyInfo.xcprivacy;
   - export compliance (ITSAppUsesNonExemptEncryption) is answered.

STOP. Do not press "Submit for Review". Report the build's state and leave Submit to Alpha.

Apple 5.1.1(v): an app that lets users create an account must let them start deleting it
from inside the app. ${deletion is String && deletion.startsWith('https://') ? '${brand['name']}\'s Profile → Account → "Delete my account" opens $deletion. Open it signed out, in a private window: it must load and accept a request.' : 'legal.accountDeletionUrl is NOT set: the row is hidden, so do not submit this build.'}
''';
}

// ---- the impure part: run the tools, file the release ------------------------------

String _latestBuildTools(String sdk) {
  final dirs = Directory('$sdk/build-tools').listSync().whereType<Directory>().map((d) => d.uri.pathSegments
      .where((s) => s.isNotEmpty)
      .last).toList()
    ..sort();
  return '$sdk/build-tools/${dirs.last}';
}

Future<String> _run(String exe, List<String> args) async {
  final r = await Process.run(exe, args, runInShell: Platform.isWindows && exe.endsWith('.bat'));
  return '${r.stdout}${r.stderr}';
}

/// `studio --verify-release <slug>`: the last step of the release job. Checks
/// both artifacts and, when every check passes, copies them to
/// `dist/<slug>/<versionName>+<versionCode>/` with release.json. Returns the
/// exit code.
Future<int> verifyRelease(String root, String slug) async {
  final win = Platform.isWindows;
  final aab = File('$root/build/app/outputs/bundle/${slug}Release/app-$slug-release.aab');
  final apk = File('$root/build/app/outputs/flutter-apk/app-$slug-release.apk');
  for (final f in [aab, apk]) {
    if (!f.existsSync()) {
      stdout.writeln('[FAIL] ${f.path} is missing: the build did not produce it');
      return 1;
    }
  }
  final sdk = sdkRoot(root);
  if (sdk == null) {
    stdout.writeln('[FAIL] no Android SDK found: open Doctor');
    return 1;
  }
  final tools = _latestBuildTools(sdk);
  final keytool = '${File(javaExecutable()).parent.path}/keytool${win ? '.exe' : ''}';
  final brand = jsonDecode(File('$root/brands/$slug/brand.json').readAsStringSync()) as Map<String, dynamic>;
  final version = pubspecVersion(root);
  final upload = await uploadKeySha1(root, slug);
  final aabZip = ZipDecoder().decodeBytes(aab.readAsBytesSync());
  final apkZip = ZipDecoder().decodeBytes(apk.readAsBytesSync());
  final checks = checkRelease(
    slug: slug,
    brand: brand,
    pubspecVersion: version,
    badging: parseBadging(await _run('$tools/aapt2${win ? '.exe' : ''}', ['dump', 'badging', apk.path])),
    apkSha1: signerSha1(await _run('$tools/apksigner${win ? '.bat' : ''}', ['verify', '--print-certs', apk.path])),
    aabSha1: signerSha1(await _run(keytool, ['-printcert', '-jarfile', aab.path])),
    uploadSha1: upload,
    aabEntries: [for (final f in aabZip.files) f.name],
    apkEntries: [for (final f in apkZip.files) f.name],
    aabPngs: {
      for (final f in aabZip.files)
        if (RegExp(r'(ic_launcher|brand_mark)\.png$').hasMatch(f.name))
          f.name: ?pngSize(f.content as List<int>),
    },
  );
  checks.forEach(stdout.writeln);
  final code = int.tryParse(version.split('+').last) ?? 0;
  final warning = versionCodeWarning(root, slug, code);
  if (warning != null) stdout.writeln('[warn] $warning');
  if (checks.any((c) => !c.ok)) {
    stdout.writeln('Not filed under dist/: fix what failed, then build again.');
    return 1;
  }

  final git = await Process.run('git', ['rev-parse', '--short', 'HEAD'], workingDirectory: root);
  final out = Directory('$root/dist/$slug/$version')..createSync(recursive: true);
  final files = <String, String>{};
  for (final f in [aab, apk]) {
    final copy = f.copySync('${out.path}/${f.uri.pathSegments.last}');
    files[copy.uri.pathSegments.last] = sha256.convert(copy.readAsBytesSync()).toString();
  }
  final record = {
    'slug': slug,
    'versionName': version.split('+').first,
    'versionCode': code,
    'commit': '${git.stdout}'.trim(),
    'builtAt': DateTime.now().toUtc().toIso8601String(),
    'applicationId': (brand['mobile'] as Map)['applicationId'],
    'uploadKeySha1': upload,
    'files': files,
    'checks': [for (final c in checks) c.toJson()],
    'tools': {'buildTools': tools.split('/').last, 'dart': Platform.version.split(' ').first},
    'uploaded': false,
  };
  File('${out.path}/release.json').writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(record)}\n');
  stdout.writeln('Filed under dist/$slug/$version/ with release.json. Nothing was uploaded.');
  return 0;
}
