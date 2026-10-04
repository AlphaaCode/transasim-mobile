import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/gen_brand_flavors.dart' show brandSlugs;
import '../../tool/studio/src/generate.dart' show readStudio;
import '../../tool/studio/src/guides.dart';
import '../../tool/studio/src/signing.dart';

Map<String, dynamic> brandOf(String slug) =>
    jsonDecode(File('brands/$slug/brand.json').readAsStringSync()) as Map<String, dynamic>;
Map<String, dynamic> copy(Map m) => jsonDecode(jsonEncode(m)) as Map<String, dynamic>;

void main() {
  final guides = loadGuides();

  test('the seed guides are all there, and each follows the schema', () {
    // loadGuides itself refuses a guide without rules, examples, or a valid
    // field; reaching here means all of them passed.
    expect(guides.keys.toSet(), {
      'google-web-client', 'google-ios-client', 'google-android-client', 'play-signing-sha1', //
      'oauth-consent', 'stripe-publishable-key', 'apple-team-id', 'play-app-id',
    });
  });

  group('each guide accepts and rejects its own examples', () {
    for (final g in guides.values.where((g) => g.kind == 'paste')) {
      test(g.id, () {
        for (final v in g.accept) {
          expect(checkPaste(g, v).errors, isEmpty, reason: 'should accept "$v"');
        }
        for (final v in g.reject) {
          expect(checkPaste(g, v).errors, isNotEmpty, reason: 'should reject "$v"');
        }
      });
    }
  });

  group('URL templates', () {
    for (final slug in brandSlugs()) {
      test('$slug: every page opens fully filled in, or names exactly what is missing', () {
        final values = placeholders(slug, brandOf(slug), readStudio('.', slug));
        for (final g in guides.values.where((g) => g.urlTemplate != null)) {
          final r = resolve(g, values);
          final needed = RegExp(r'\{(\w+)\}').allMatches(g.urlTemplate!).map((m) => m[1]!);
          final empty = needed.where((k) => values[k]!.isEmpty).toList();
          if (empty.isEmpty) {
            expect(r['url'] as String, allOf(startsWith('https://'), isNot(contains('{'))), reason: g.id);
          } else {
            expect(r['url'], isNull, reason: '${g.id} must not open a page with holes');
            expect(r['missing'] as List, containsAll(empty), reason: g.id);
          }
        }
      });
    }

    test('with every id known, each page carries this brand\'s ids', () {
      final values = placeholders('sabily', brandOf('sabily'), {
        ...readStudio('.', 'sabily'),
        'gcpProjectId': 'sabily-prod-123',
        'googleAccount': 'owner@example.com',
        'playDeveloperId': '5166846112789041453',
        'playAppId': '4974502866215427836',
        'uploadKeySha1': 'D0:87:9B:B2:AE:1D:D0:40:D1:50:57:33:20:92:45:69:46:66:5B:A7',
        'playSigningSha1': '3A:4B:5C:6D:7E:8F:90:A1:B2:C3:D4:E5:F6:07:18:29:3A:4B:5C:6D',
      });
      String url(String id) => resolve(guides[id]!, values)['url']! as String;
      expect(url('google-web-client'),
          'https://console.cloud.google.com/apis/credentials?project=sabily-prod-123&authuser=owner%40example.com');
      expect(url('oauth-consent'), contains('/apis/credentials/consent?project=sabily-prod-123'));
      expect(url('play-signing-sha1'),
          'https://play.google.com/console/u/0/developers/5166846112789041453/app/4974502866215427836/keymanagement');
      final android = resolve(guides['google-android-client']!, values);
      expect(android['missing'], isEmpty);
      expect([for (final c in android['copyValues']! as List) (c as Map)['value']],
          ['com.sabily.esim', values['uploadSha1'], values['playSigningSha1']]);
    });
  });

  group('cross-field and cross-brand rules', () {
    final sabily = brandOf('sabily');
    final studio = readStudio('.', 'sabily');
    final others = otherBrands('.', 'sabily');
    final ios = sabily['mobile']['googleIosClientId'] as String;
    final web = sabily['mobile']['googleServerClientId'] as String;

    test('a pasted web client ID equal to the iOS one is refused', () {
      final v = checkPaste(guides['google-web-client']!, ios, brand: sabily, studio: studio, others: others);
      expect(v.errors, contains(contains('iOS client')));
    });

    test('and the reverse: the web client pasted as the iOS one', () {
      final v = checkPaste(guides['google-ios-client']!, web, brand: sabily, studio: studio, others: others);
      expect(v.errors, contains(contains('web client')));
    });

    test('a Stripe secret key is refused, and so is another brand\'s publishable key', () {
      final g = guides['stripe-publishable-key']!;
      expect(checkPaste(g, 'sk_live_51AbCdEfGhIjKlMnOp', brand: sabily, studio: studio, others: others).errors,
          isNotEmpty);
      final esimpleKey = brandOf('esimple')['mobile']['stripePublishableKey'] as String;
      expect(checkPaste(g, esimpleKey, brand: sabily, studio: studio, others: others).errors,
          contains(contains('esimple')));
    });

    test('the shared placeholder key is not "another brand\'s key"', () {
      // Not a key anyone pastes (it fails the format rule, rightly); what
      // matters is that brands still waiting for one do not clash over it.
      final g = guides['stripe-publishable-key']!;
      final acorn = brandOf('acorn');
      expect(checkPaste(g, 'pk_test_PLACEHOLDER_AWAITING_CLIENT',
              brand: acorn, studio: readStudio('.', 'acorn'), others: otherBrands('.', 'acorn'))
          .errors, isNot(contains(contains('another brand'))));
    });

    test('the Play App Signing SHA-1 must not be the upload key\'s', () {
      const upload = 'D0:87:9B:B2:AE:1D:D0:40:D1:50:57:33:20:92:45:69:46:66:5B:A7';
      final v = checkPaste(guides['play-signing-sha1']!, upload.toLowerCase(),
          studio: {'uploadKeySha1': upload});
      expect(v.errors, contains(contains('upload key')));
    });

    test('a Play Console address gives both the developer id and the app id', () {
      final v = checkPaste(guides['play-app-id']!,
          'https://play.google.com/console/u/0/developers/5166846112789041453/app/4974502866215427836/app-dashboard');
      expect(v.errors, isEmpty);
      expect(v.value, '4974502866215427836');
      expect({for (final d in v.derived) d['field']: d['value']}, {
        'studio:playAppId': '4974502866215427836',
        'studio:playDeveloperId': '5166846112789041453',
      });
    });
  });

  group('the Integrations Apply', () {
    test('changes nothing when nothing was edited', () {
      final plan = integrationsPlan('.', 'sabily', brandOf('sabily'), readStudio('.', 'sabily'));
      expect(plan.errors, isEmpty);
      expect(plan.text.where((c) => c.changed).map((c) => c.path), isEmpty);
    });

    test('a new iOS client shows in brand.json and the xcconfig\'s reversed scheme', () {
      final brand = copy(brandOf('sabily'));
      brand['mobile']['googleIosClientId'] = '83118739145-zzzz1111.apps.googleusercontent.com';
      final plan = integrationsPlan('.', 'sabily', brand, readStudio('.', 'sabily'));
      final xcconfig = plan.text.singleWhere((c) => c.path == 'ios/Flutter/sabily.xcconfig');
      expect(xcconfig.after, contains('GOOGLE_REVERSED_CLIENT_ID = com.googleusercontent.apps.83118739145-zzzz1111'));
      expect(plan.text.map((c) => c.path), contains('brands/sabily/brand.json'));
    });

    test('studio.json edits are previewed like any other file', () {
      final studio = {...readStudio('.', 'sabily'), 'gcpProjectId': 'sabily-prod-123'};
      final plan = integrationsPlan('.', 'sabily', brandOf('sabily'), studio);
      final change = plan.text.singleWhere((c) => c.path == 'brands/sabily/studio.json');
      expect(change.after, contains('"gcpProjectId": "sabily-prod-123"'));
    });

    test('a secret is refused wherever it is put', () {
      final studio = {...readStudio('.', 'sabily'), 'gcpProjectId': 'GOCSPX-abcdefgh12345'};
      final plan = integrationsPlan('.', 'sabily', brandOf('sabily'), studio);
      expect(plan.errors.map((e) => e['field']), contains('studio.gcpProjectId'));
      expect(plan.errors.map((e) => e['reason']), contains(contains('secret')));
    });

    test('a confirmation made for another fingerprint is flagged as stale', () {
      final studio = {
        ...readStudio('.', 'sabily'),
        'uploadKeySha1': 'D0:87:9B:B2:AE:1D:D0:40:D1:50:57:33:20:92:45:69:46:66:5B:A7',
        'playSigningSha1': '3A:4B:5C:6D:7E:8F:90:A1:B2:C3:D4:E5:F6:07:18:29:3A:4B:5C:6D',
        'checklist': {
          'google.android-clients': {
            'doneAt': '2026-10-04',
            'for': {'package': 'com.sabily.esim', 'uploadSha1': 'OLD', 'playSigningSha1': 'OLD'},
          },
        },
      };
      final plan = integrationsPlan('.', 'sabily', brandOf('sabily'), studio);
      expect(plan.warnings.map((w) => w['field']), contains('studio.checklist.google.android-clients'));
    });
  });

  test('the upload key fingerprint comes from the keystore, with no password typed', () async {
    // Signing files are not in the repo: on a machine without Sabily's, skip.
    if (!File('android/sabily-key.properties').existsSync()) return markTestSkipped('no Sabily keystore here');
    expect(await uploadKeySha1('.', 'sabily'), 'D0:87:9B:B2:AE:1D:D0:40:D1:50:57:33:20:92:45:69:46:66:5B:A7');
    expect(() => uploadKeySha1('.', 'acorn'), throwsA(isA<StateError>()));
  });
}
