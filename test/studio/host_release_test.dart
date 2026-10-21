import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transasim_mobile/core/brand/app_flavor.dart';

import '../../tool/studio/src/generate.dart' show readStudio;
import '../../tool/studio/src/hosts.dart';
import '../../tool/studio/src/release.dart';

/// Slice H, test (c): the release checks read the built artifact, not the
/// intent. A DEV artifact, or a store one that names a DEV host anywhere in
/// its bytes, is refused before it can land in dist/.
void main() {
  Map<String, dynamic> bundle(String slug, AppFlavor flavor) => flavorBundle(
      jsonDecode(File('brands/$slug/brand.json').readAsStringSync()) as Map<String, dynamic>, flavor);

  /// An artifact as the release reads it: the flavor's bundle where Flutter
  /// puts it, and a compiled binary holding [binary].
  Map<String, List<int>> artifact(String slug, AppFlavor flavor, {String binary = 'nothing of note', Map<String, dynamic>? with_}) => {
        'base/assets/flutter_assets/brands/$slug/flavor/${flavorName(slug, flavor)}.json':
            utf8.encode(jsonEncode(with_ ?? bundle(slug, flavor))),
        // The byte before a string in a Dart snapshot is its length or hash: here a letter.
        'base/lib/arm64-v8a/libapp.so': [0, 1, ...latin1.encode('x$binary'), 0],
      };

  List<ReleaseCheck> check(String slug, Map<String, List<int>> files, {bool acknowledged = false}) => checkArtifactHosts(
        slug: slug,
        artifact: 'AAB',
        files: files,
        studio: readStudio('.', slug),
        devHosts: devHosts('.'),
        knownHosts: knownHosts('.'),
        acknowledged: acknowledged,
      );
  List<String> failed(List<ReleaseCheck> cs) => [for (final c in cs) if (!c.ok) c.detail];

  test('a store build of Acorn on its production host passes', () {
    final cs = check('acorn', artifact('acorn', AppFlavor.prod, binary: 'acorn-api.transasim.com'));
    expect(failed(cs), isEmpty);
    expect(cs.first.detail, contains("acorn-api.transasim.com, acorn's PRODUCTION host"));
  });

  test('a DEV artifact is refused: its bundle, its ids, its host', () {
    final files = artifact('acorn', AppFlavor.dev, binary: 'acorn.transasim.com');
    final why = failed(check('acorn', files));
    expect(why, hasLength(3));
    expect(why[0], contains('no prod bundle'));
    expect(why[1], allOf(contains('com.odyssey.esim.dev'), contains("a DEV build's ids")));
    expect(why[2], contains('names a DEV host: acorn.transasim.com in'));
    // Both bundles packed: the dev one alone is enough to refuse it.
    final both = {...artifact('acorn', AppFlavor.prod), ...files};
    expect(failed(check('acorn', both)), contains(contains('ships the dev bundle')));
  });

  test('a store artifact naming a DEV host anywhere is refused, whoever\'s DEV it is', () {
    for (final dev in ['acorn.transasim.com', 'api.sabily.transasim.com', 'esimple.transasim.com']) {
      final why = failed(check('acorn', artifact('acorn', AppFlavor.prod, binary: 'https://$dev/api')));
      expect(why, [contains('names a DEV host: $dev in')], reason: dev);
    }
    // As UTF-16 too, the way a resource string can be stored.
    final wide = artifact('acorn', AppFlavor.prod)
      ..['base/resources.pb'] = [for (final c in 'acorn.transasim.com'.codeUnits) ...[c, 0]];
    expect(failed(check('acorn', wide)), [contains('acorn.transasim.com in base/resources.pb')]);
  });

  test('a store bundle pointing at a DEV host is refused', () {
    final b = bundle('acorn', AppFlavor.prod);
    (b['mobile'] as Map)['apiBaseUrl'] = 'https://acorn.transasim.com/api';
    expect(failed(check('acorn', artifact('acorn', AppFlavor.prod, with_: b))),
        containsAll([contains("not acorn's production host"), contains('names a DEV host: acorn.transasim.com')]));
  });

  test("eSimple's production exception: refused until acknowledged, and only for its own host", () {
    final files = artifact('esimple', AppFlavor.prod, binary: "esimple.transasim.com', 'api.esimple.transasim.com");
    expect(failed(check('esimple', files)), [
      allOf(contains('PRODUCTION EXCEPTION'), contains('not acknowledged')),
      contains('names a DEV host: esimple.transasim.com in'),
    ]);
    final acked = check('esimple', files, acknowledged: true);
    expect(failed(acked), isEmpty);
    expect(acked.first.detail, allOf(contains('DEV server serving as production until the merge'), contains('acknowledged')));
    // The acknowledgement excuses eSimple's exception host, never another DEV one.
    final other = artifact('esimple', AppFlavor.prod, binary: 'acorn.transasim.com');
    expect(failed(check('esimple', other, acknowledged: true)), [contains('acorn.transasim.com')]);
  });

  test("eSimple's production alias is never taken for its DEV host", () {
    final b = bundle('esimple', AppFlavor.prod);
    (b['mobile'] as Map)['apiBaseUrl'] = 'https://api.esimple.at/api';
    final files = artifact('esimple', AppFlavor.prod, with_: b, binary: "api.esimple.at', 'api.esimple.transasim.com");
    expect(failed(check('esimple', files)), isEmpty, reason: 'after the merge: the pinned host and its alias');
    expect(standaloneCount('xapi.esimple.transasim.com', 'esimple.transasim.com', knownHosts('.')), 0);
    expect(standaloneCount('xesimple.transasim.com', 'esimple.transasim.com', knownHosts('.')), 1);
  });

  test('--verify-ipa refuses a DEV IPA and accepts a store one', () {
    final dir = Directory.systemTemp.createTempSync('ipa');
    addTearDown(() => dir.deleteSync(recursive: true));
    String ipa(AppFlavor flavor) {
      final b = bundle('acorn', flavor);
      final archive = Archive()
        ..addFile(ArchiveFile.bytes('Payload/Runner.app/Info.plist',
            latin1.encode('bplist00 CFBundleIdentifier ${(b['mobile'] as Map)['bundleIdentifier']}')))
        ..addFile(ArchiveFile.bytes('Payload/Runner.app/Frameworks/App.framework/flutter_assets/brands/acorn/flavor/${flavorName('acorn', flavor)}.json',
            utf8.encode(jsonEncode(b))))
        ..addFile(ArchiveFile.bytes('Payload/Runner.app/Frameworks/App.framework/App', latin1.encode('x${(b['mobile'] as Map)['apiBaseUrl']}')));
      final f = File('${dir.path}/${flavor.name}.ipa')..writeAsBytesSync(ZipEncoder().encode(archive));
      return f.path;
    }

    expect(verifyIpa('.', 'acorn', ipa(AppFlavor.prod)), 0);
    expect(verifyIpa('.', 'acorn', ipa(AppFlavor.dev)), 1);
    expect(verifyIpa('.', 'acorn', '${dir.path}/missing.ipa'), 1);
  });

  test('the release check refuses before building: no pin, a moved host, an exception not acknowledged', () {
    expect(hostReleaseRefusal('.', 'acorn'), isEmpty);
    expect(hostReleaseRefusal('.', 'sabily'), isEmpty);
    expect(hostReleaseRefusal('.', 'esimple'), [contains('PRODUCTION EXCEPTION')]);
    expect(hostReleaseRefusal('.', 'esimple', acknowledged: true), isEmpty);
  });
}
