import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/studio/src/generate.dart';
import '../../tool/studio/src/server.dart' show trusted;

void main() {
  group('the request guard', () {
    test('serves its own page', () {
      expect(trusted('GET', '127.0.0.1:4777', null), isTrue);
      expect(trusted('POST', 'localhost:4777', '1'), isTrue);
    });

    test('refuses any other Host, which is what DNS rebinding sends', () {
      expect(trusted('GET', 'evil.example:4777', null), isFalse);
      expect(trusted('POST', 'evil.example', '1'), isFalse);
    });

    test('refuses a write without the Studio header, which no other tab can send', () {
      expect(trusted('POST', '127.0.0.1:4777', null), isFalse);
    });
  });

  test('a diff shows the changed line with three lines of context', () {
    final before = [for (var i = 1; i <= 10; i++) 'line $i'].join('\n');
    final after = before.replaceFirst('line 5', 'line five');
    expect(
      unifiedDiff(before, after),
      '@@ -2,7 +2,7 @@\n line 2\n line 3\n line 4\n-line 5\n+line five\n line 6\n line 7\n line 8\n',
    );
  });

  test('a brand with no files yet gets every one of them, as new', () {
    final acorn =
        jsonDecode(File('brands/acorn/brand.json').readAsStringSync()) as Map<String, dynamic>;
    final changes = generate('.', 'zzdemo', {...acorn, 'slug': 'zzdemo'});
    final byPath = {for (final c in changes) c.path: c};
    for (final c in changes.where((c) => c.path != 'pubspec.yaml')) {
      expect(c.before, isNull, reason: c.path);
    }
    expect(byPath.keys, containsAll([
      'brands/zzdemo/brand.json',
      'lib/flavors/main_zzdemo.dart',
      'android/app/src/zzdemo/res/values/colors.xml',
      'ios/Flutter/zzdemo.xcconfig',
      'ios/Runner/Brands/Brand-zzdemo.xcassets/LaunchBackground.colorset/Contents.json',
    ]));
    expect(byPath['pubspec.yaml']!.after, contains('- path: brands/zzdemo/assets/'));
    expect(byPath['lib/flavors/main_zzdemo.dart']!.after,
        contains("void main() => bootstrap('zzdemo');"));
  });

  test('a published store id cannot change; an unpublished one can', () {
    final brand = {
      'mobile': {'applicationId': 'com.example.new', 'bundleIdentifier': 'com.example.app'},
    };
    const published = {
      'published': {'applicationId': 'com.example.app', 'bundleIdentifier': 'com.example.app'},
    };
    expect(frozenViolations(brand, published).keys, ['mobile.applicationId']);
    expect(frozenViolations(brand, const {}), isEmpty);
  });

  test('Studio runs on the plain Dart VM, where it actually runs', () async {
    // flutter test has dart:ui, so a Flutter import creeping into anything
    // Studio loads (lib/core/brand, lib/core/i18n/locales.dart) would pass
    // every other test and still break Studio. See lib/core/headless.dart.
    final flutter = Platform.environment['FLUTTER_ROOT'];
    expect(flutter, isNotNull, reason: 'flutter test sets FLUTTER_ROOT');
    final dart = '$flutter/bin/cache/dart-sdk/bin/dart${Platform.isWindows ? '.exe' : ''}';
    final r = await Process.run(dart, ['run', 'tool/studio/bin/studio.dart', '--check']);
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
