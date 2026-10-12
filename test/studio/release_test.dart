import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../../tool/studio/src/incidents.dart';
import '../../tool/studio/src/jobs.dart';
import '../../tool/studio/src/release.dart';

/// The release (Slice E): the artifacts are checked, not the intent. The tool
/// output below is what aapt2, apksigner and keytool printed for a real Sabily
/// release on 2026-10-12.
void main() {
  Map<String, dynamic> brand(String slug) =>
      jsonDecode(File('brands/$slug/brand.json').readAsStringSync()) as Map<String, dynamic>;
  const upload = 'D0:87:9B:B2:AE:1D:D0:40:D1:50:57:33:20:92:45:69:46:66:5B:A7';
  const badging = "package: name='com.sabily.esim' versionCode='22' versionName='1.1.9' platformBuildVersionName='16' "
      "platformBuildVersionCode='36' compileSdkVersion='36' compileSdkVersionCodename='16'\n"
      "sdkVersion:'24'\ntargetSdkVersion:'36'\napplication-label:'Sabily'\n";
  const apksigner = 'Signer #1 certificate DN: CN=yazid, OU=Unknown\n'
      'Signer #1 certificate SHA-256 digest: ecc5847e8921da7531eaab1fa433d9717185601240cc8df527a1e3f6beea27fa\n'
      'Signer #1 certificate SHA-1 digest: d0879bb2ae1dd040d15057332092456946665ba7\n';
  const keytool = 'Signer #1:\n\nCertificate #1:\nOwner: CN=yazid\nCertificate fingerprints:\n'
      '\t SHA1: D0:87:9B:B2:AE:1D:D0:40:D1:50:57:33:20:92:45:69:46:66:5B:A7\n'
      '\t SHA256: EC:C5:84:7E:89:21:DA:75:31:EA:AB:1F:A4:33:D9:71:71:85:60:12:40:CC:8D:F5:27:A1:E3:F6:BE:EA:27:FA\n';
  const sabilyAab = [
    'base/assets/flutter_assets/brands/sabily/assets/logo-intro.mp4',
    'base/assets/flutter_assets/brands/sabily/assets/logo-mark.png',
    'base/assets/flutter_assets/brands/sabily/brand.json',
    'base/res/drawable/brand_mark.png',
    'base/res/mipmap-xxxhdpi-v4/ic_launcher.png',
  ];
  const sabilyApk = ['assets/flutter_assets/brands/sabily/assets/logo-intro.mp4', 'assets/flutter_assets/brands/sabily/brand.json'];
  const icons = {'base/res/mipmap-xxxhdpi-v4/ic_launcher.png': (192, 192), 'base/res/drawable/brand_mark.png': (432, 432)};

  List<ReleaseCheck> check({
    String slug = 'sabily',
    String version = '1.1.9+22',
    String bad = badging,
    String? apkSha1 = upload,
    String? aabSha1 = upload,
    List<String> aab = sabilyAab,
    List<String> apk = sabilyApk,
    Map<String, (int, int)> pngs = icons,
  }) =>
      checkRelease(
        slug: slug, brand: brand(slug), pubspecVersion: version, badging: parseBadging(bad),
        apkSha1: apkSha1, aabSha1: aabSha1, uploadSha1: upload, aabEntries: aab, apkEntries: apk, aabPngs: pngs,
      );
  Map<String, bool> results(List<ReleaseCheck> cs) => {for (final c in cs) c.id: c.ok};

  test('the tools are read as they print', () {
    expect(parseBadging(badging), (package: 'com.sabily.esim', versionCode: 22, versionName: '1.1.9', targetSdk: 36));
    expect(signerSha1(apksigner), upload, reason: "apksigner's lowercase hex");
    expect(signerSha1(keytool), upload, reason: "keytool's colons");
    final png = img.encodePng(img.Image(width: 1473, height: 900));
    expect(pngSize(png), (1473, 900));
    expect(pngSize(const [1, 2, 3]), isNull);
  });

  test("a sound Sabily release passes every check, its intro video included", () {
    final cs = check();
    expect(cs.where((c) => !c.ok), isEmpty, reason: cs.join('\n'));
    expect(results(cs).keys, ['package', 'version', 'target-sdk-below-36', 'release-without-brand-key',
        'release-foreign-assets', 'oversized-icon-bitmap']);
  });

  test('each failure names its incident', () {
    expect(results(check(bad: badging.replaceFirst('com.sabily.esim', 'com.esimple.esim')))['package'], isFalse);
    expect(results(check(version: '1.1.10+23'))['version'], isFalse);
    expect(results(check(bad: badging.replaceFirst("targetSdkVersion:'36'", "targetSdkVersion:'35'")))['target-sdk-below-36'],
        isFalse);
    final debug = check(apkSha1: 'AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD');
    expect(debug.firstWhere((c) => c.id == 'release-without-brand-key').detail, contains('debug or a foreign key'));
    final leaked = check(aab: [...sabilyAab, 'base/assets/flutter_assets/brands/esimple/brand.json']);
    expect(leaked.firstWhere((c) => c.id == 'release-foreign-assets').detail, contains('esimple'));
    expect(results(check(pngs: {...icons, 'base/res/mipmap-xxxhdpi-v4/ic_launcher.png': (1473, 1473)}))['oversized-icon-bitmap'],
        isFalse, reason: 'the bitmap Google\'s account picker refused to draw');
  });

  test('an intro video ships only with a video intro', () {
    // eSimple holds its logo: a video packed for it is dead weight.
    final esimple = check(
      slug: 'esimple',
      bad: badging.replaceFirst('com.sabily.esim', 'com.esimple.esim'),
      aab: [for (final e in sabilyAab) e.replaceAll('/sabily/', '/esimple/')],
      apk: [for (final e in sabilyApk) e.replaceAll('/sabily/', '/esimple/')],
    );
    expect(esimple.firstWhere((c) => c.id == 'release-foreign-assets').detail, contains('not a video'));
    final silent = check(aab: [for (final e in sabilyAab) if (!e.endsWith('.mp4')) e], apk: [sabilyApk.last]);
    expect(silent.firstWhere((c) => c.id == 'release-foreign-assets').detail, contains('none is packed'));
  });

  test('a version code already filed under dist/ is a warning', () {
    final root = Directory.systemTemp.createTempSync('dist');
    addTearDown(() => root.deleteSync(recursive: true));
    expect(versionCodeWarning(root.path, 'sabily', 22), isNull);
    File('${root.path}/dist/sabily/1.1.9+22/release.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode({'versionCode': 22, 'builtAt': '2026-10-12T09:00:00Z', 'commit': 'fcdbf95'}));
    expect(versionCodeWarning(root.path, 'sabily', 22), allOf(contains('version-code-used'), contains('fcdbf95')));
    expect(releaseHistory(root.path, 'sabily').single['commit'], 'fcdbf95');
  });

  test('the release job: AAB, APK, Gradle stopped, then the check; never a --dart-define', () {
    final steps = jobSteps('.', 'release-android', slug: 'sabily')!;
    final lines = [for (final s in steps) '${s.executable.split(RegExp(r'[\\/]')).last} ${s.args.join(' ')}'];
    expect(lines[0], contains('build appbundle --release --flavor sabily -t lib/flavors/main_sabily.dart'));
    expect(lines[1], contains('build apk --release --flavor sabily'));
    expect(lines[2], contains('--stop'));
    expect(lines[3], contains('--verify-release sabily'));
    expect(lines.join('\n'), isNot(contains('--dart-define')));
  });

  test('the release check refuses Acorn for its three reasons, and stops neither legacy brand', () {
    final items = loadIncidents();
    expect(releaseAndroidRefusal('.', 'acorn', items: items, dirty: false), [
      'release-without-brand-key: android/acorn-key.properties is missing, so the release would carry the debug key',
      'Go prod first: the backend phase is still on DEV',
      'release-points-at-dev: brand.json apiBaseUrl is https://acorn.transasim.com/api, not the PROD backend',
      'apple-account-deletion: legal.accountDeletionUrl is not set, so the app hides "Delete my account" (Apple 5.1.1(v))',
    ]);
    expect(releaseAndroidRefusal('.', 'sabily', items: items, dirty: false), isEmpty);
    expect(releaseAndroidRefusal('.', 'esimple', items: items, dirty: false), isEmpty);
    expect(releaseAndroidRefusal('.', 'sabily', items: items, dirty: true), [contains('commit first')]);
  });

  test('the prompt for the Mac: the commit, the commands, and a STOP before Submit (golden)', () {
    final text = macPrompt(
      slug: 'sabily', brand: brand('sabily'),
      studio: jsonDecode(File('brands/sabily/studio.json').readAsStringSync()) as Map<String, dynamic>,
      branch: 'master', commit: 'fcdbf95', iosVersion: '2.0.1', build: 21,
    );
    final f = File('test/studio/fixtures/release/sabily-mac-prompt.txt');
    if (Platform.environment['UPDATE_GOLDENS'] == '1' || !f.existsSync()) {
      f
        ..createSync(recursive: true)
        ..writeAsStringSync(text);
    }
    expect(text, f.readAsStringSync());
    expect(text, allOf(contains('git checkout fcdbf95'), contains('--build-name 2.0.1 --build-number 21'),
        contains('STOP. Do not press "Submit for Review"'), contains('docs.google.com/forms')));
    final acorn = macPrompt(slug: 'acorn', brand: brand('acorn'), studio: const {'appleTeamId': 'DP7F8WQCJD'},
        branch: 'master', commit: 'fcdbf95', iosVersion: '1.0.0', build: 1);
    expect(acorn, contains('legal.accountDeletionUrl is NOT set'));
  });
}
