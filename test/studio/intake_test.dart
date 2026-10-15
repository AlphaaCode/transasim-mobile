import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../../tool/studio/src/intake.dart';
import '../../tool/studio/src/new_brand.dart';
import 'unconfigured.dart';

/// Slice I: the SPC intake file the onboarding portal writes. Untrusted
/// public input, read strictly; the fixture is fake, in the portal's shape
/// (SPC-easy-submit src/lib/schema.ts and intakeJson.ts).
void main() {
  final fixture = File('test/studio/fixtures/intake/spc-intake-nimbus.json').readAsStringSync();
  Map<String, dynamic> intake() => jsonDecode(fixture) as Map<String, dynamic>;
  List<int> bytesOf(Map<String, dynamic> j) => utf8.encode(jsonEncode(j));
  final png = img.encodePng(img.Image(width: 512, height: 512)..clear(img.ColorRgb8(30, 90, 168)));
  const logoName = '[Upload] Logo File — nimbus-mark.png';

  IntakeRead read(List<Dropped> files) => readIntake(files);
  IntakeRow row(IntakeRead r, String path, [String kind = 'client']) =>
      r.rows.firstWhere((x) => x.path == path && x.kind == kind, orElse: () => throw StateError('no $kind row $path in\n${r.rows.join('\n')}'));
  Iterable<String> asks(IntakeRead r) => r.rows.where((x) => x.kind == 'ask').map((x) => x.path);

  group('reading', () {
    test('the fixture and its logo: every mapped field carries its source', () {
      final r = read([Dropped('spc-intake-nimbus.json', utf8.encode(fixture)), Dropped(logoName, png)]);
      expect(r.refusal, isNull);
      expect(row(r, 'name').value, 'Nimbus Roam');
      expect(row(r, 'name').from, 'branding.brand_name');
      expect(row(r, 'legal.companyName').value, 'Nimbus Roam SARL');
      expect(row(r, 'legal.country').value, 'DZ', reason: '"algeria" by its name');
      expect(row(r, 'colors.primary').value, '#1e5aa8');
      expect(row(r, 'colors.accent').value, '#dcebfa');
      expect(row(r, 'colors.primary').suggestion, isTrue);
      expect(row(r, 'branding.secondary_color_hex', 'info').value, '#896d70');
      expect(row(r, 'mobile.displayName').value, 'Nimbus');
      expect(row(r, 'branding.display_names.ios_app', 'info').note, contains('Nimbus Roam'));
      expect(row(r, 'legal.termsUrl').value, 'https://nimbus.example/terms');
      expect(row(r, 'legal.accountDeletionUrl').value, 'https://nimbus.example/delete-account');
      expect(row(r, 'legal.privacyUrl', 'todo').note, allOf(contains('a PDF'), contains('host this as a public page')));
      expect(r.rows.where((x) => x.path == 'legal.privacyUrl' && x.kind == 'client'), isEmpty);
      expect(row(r, 'locales').value, ['en', 'fr']);
      expect(row(r, 'locales', 'ask').note, contains('Klingon'));
      expect(row(r, 'mobile.registration.fields').value, ['email', 'password', 'firstName', 'lastName', 'phoneNum']);
      expect(row(r, 'studio:backend.features.payments').value, isTrue);
      expect(row(r, 'studio:backend.features.vouchers').value, isTrue);
      expect(row(r, 'studio:gcpProjectId').value, 'nimbus-roam-0001');
      expect(row(r, 'logo.mark').value, logoName);
      expect(r.mark, png);
      expect(row(r, 'smtp.host', 'dropped').note, contains('not a host name'));
      expect(asks(r), containsAll(['support.email', 'locales']));
      expect(asks(r), isNot(contains('legal.accountDeletionUrl')), reason: 'the client gave a page for it');
      expect(r.rows.where((x) => x.kind == 'todo').map((x) => x.note).join('\n'),
          allOf(contains('iOS'), contains('Google sign-in')));
    });

    test('suggestions are never read from the file', () {
      final r = read([Dropped('spc-intake-nimbus.json', utf8.encode(fixture))]);
      expect(row(r, 'slug', 'suggested').value, 'nimbusroam');
      expect(row(r, 'mobile.applicationId', 'suggested').value, 'com.transasim.nimbusroam');
      expect(row(r, 'mobile.apiBaseUrl', 'suggested').value, 'https://nimbusroam.transasim.com/api');
      expect(asks(r), contains('logo.mark'), reason: 'the logo was not dropped with the JSON');
    });

    test('the studio.json block: pending PROD domains, client-provided values, no contact data', () {
      final r = read([Dropped('spc-intake-nimbus.json', utf8.encode(fixture))]);
      final block = intakeBlock(r, applied: const {'name': 'Nimbus Roam'});
      expect(block['submissionId'], '0f3c2b9e-1111-4a2b-9c3d-000000000001');
      expect(block['sha256'], sha256.convert(utf8.encode(fixture)).toString());
      expect(block['prodPending'], {'domains': ['nimbus.example', 'portal.nimbus.example', 'api.nimbus.example']});
      final provided = block['clientProvided'] as Map;
      expect(provided['transatel'], {
        'account_status': 'active',
        'api': {'base_url': 'https://api.transatel.example/', 'cos_ref': 'COS-FAKE-1', 'mvno_ref': 'MVNO-FAKE-1', 'grant_type': 'client_credentials'},
        'rate_plans': ['RP-FAKE-EU', 'RP-FAKE-WORLD'],
        'sftp': {'host': 'sftp.transatel.example', 'port': 22},
      });
      expect(provided['smtp'], {'port': 587, 'from_address': 'noreply@nimbus.example'}, reason: 'the malformed host is dropped');
      expect((provided['google_cloud'] as Map)['recaptcha'], {
        'web': {'enabled': true, 'key_name': 'nimbus-web', 'site_key': '6LcFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKE0',
            'domain_restrictions': ['nimbus.example', 'portal.nimbus.example']},
      });
      expect(block['stripped'], contains('transatel.api.password_id'));
      expect(block['applied'], {'name': 'Nimbus Roam'});
      final text = jsonEncode(block);
      expect(text, isNot(contains('sam@nimbus.example')));
      expect(text, isNot(contains('tech@nimbus.example')));
      expect(text, isNot(contains('Sam Example')));
    });

    test('the real sample\'s shapes: arrays, numeric ports, blanks and false flags are asks, not errors', () {
      final j = intake();
      final v = j['values'] as Map<String, dynamic>;
      (v['business'] as Map)['languages'] = <String>[];
      (v['transatel'] as Map)['rate_plans'] = 'RP-ONE, RP-TWO';
      ((v['transatel'] as Map)['sftp'] as Map)['port'] = 22;
      ((v['transatel'] as Map)['sftp'] as Map)['host'] = '123';
      (v['company'] as Map)['country_region'] = 'Atlantis';
      (v['scope'] as Map).updateAll((k, _) => false);
      (v['branding'] as Map)['display_names'] = {'portal': '', 'android_app': '', 'ios_app': ''};
      final r = read([Dropped('spc-intake-x.json', bytesOf(j))]);
      expect(r.refusal, isNull);
      expect(asks(r), containsAll(['locales', 'legal.country']));
      expect(row(r, 'mobile.displayName').value, 'Nimbus Roam', reason: 'falls back to brand_name');
      expect(row(r, 'mobile.displayName').from, 'branding.brand_name');
      expect(row(r, 'studio:backend.features.payments').value, isFalse);
      expect(row(r, 'transatel.sftp.host', 'dropped').note, contains('not a host name'));
      expect(read([Dropped('a.json', bytesOf(j..['values'] = {...v, 'transatel': {...v['transatel'] as Map, 'api': {'base_url': 'tesst'}}}))]).rows
          .firstWhere((x) => x.path == 'transatel.api.base_url').note, 'not an https address');
      final t = (intakeBlock(r)['clientProvided'] as Map)['transatel'] as Map;
      expect(t['rate_plans'], ['RP-ONE', 'RP-TWO']);
      expect(t['sftp'], {'port': 22});
    });

    test('an ISO code is taken as given', () {
      final j = intake();
      ((j['values'] as Map)['company'] as Map)['country_region'] = 'be';
      expect(row(read([Dropped('a.json', bytesOf(j))]), 'legal.country').value, 'BE');
    });
  });

  group('the legal URLs: a page is kept, a file is to be hosted', () {
    /// The intake with [url] as the account deletion URL; null removes the field.
    IntakeRead withDeletion(String? url) {
      final j = intake();
      final legal = (j['values'] as Map)['legal'] as Map;
      url == null ? legal.remove('account_deletion_url') : legal['account_deletion_url'] = url;
      return read([Dropped('spc-intake-x.json', bytesOf(j))]);
    }

    test('what the app can do with a URL', () {
      expect(classifyLegalUrl('https://nimbus.example/delete'), LegalUrl.page);
      expect(classifyLegalUrl('  https://nimbus.example/delete  '), LegalUrl.page, reason: 'trimmed');
      expect(classifyLegalUrl('https://nimbus.example/delete', isPdf: true), LegalUrl.host);
      for (final url in ['https://drive.google.com/file/d/FAKE/view', 'https://docs.google.com/document/d/FAKE/edit',
          'https://DRIVE.GOOGLE.COM/file/d/FAKE/view', 'https://drive.usercontent.google.com/download?id=FAKE']) {
        expect(classifyLegalUrl(url), LegalUrl.host, reason: url);
      }
      for (final url in ['http://nimbus.example/delete', 'nimbus.example/delete', 'ask us by email', 'https://localhost/x']) {
        expect(classifyLegalUrl(url), LegalUrl.bad, reason: url);
      }
      for (final url in ['', '   ']) {
        expect(classifyLegalUrl(url), LegalUrl.blank, reason: '"$url"');
      }
    });

    test('an https page is written, tagged, and no longer asked for', () {
      final r = withDeletion('https://nimbus.example/account/delete');
      final got = row(r, 'legal.accountDeletionUrl');
      expect(got.value, 'https://nimbus.example/account/delete');
      expect(got.from, 'legal.account_deletion_url');
      expect(got.suggestion, isFalse, reason: "the client's own value, not Studio's");
      expect(r.source, 'client intake 0f3c2b9e-1111-4a2b-9c3d-000000000001');
      expect(asks(r), isNot(contains('legal.accountDeletionUrl')));
      expect(r.rows.where((x) => x.path == 'legal.accountDeletionUrl' && x.kind == 'todo'), isEmpty);
    });

    test('http, a bare domain or a sentence is not written, and is still asked for', () {
      for (final url in ['http://nimbus.example/delete', 'nimbus.example/delete', 'write to support']) {
        final r = withDeletion(url);
        expect(r.rows.where((x) => x.path == 'legal.accountDeletionUrl' && x.kind == 'client'), isEmpty, reason: url);
        expect(row(r, 'legal.accountDeletionUrl', 'ask').note,
            allOf(contains('not an https address'), contains('5.1.1(v)')), reason: url);
      }
    });

    test('a Drive or Docs link is work to do, not a value and not an ask', () {
      for (final url in ['https://drive.google.com/file/d/FAKEDELETION00001/view?usp=drivesdk',
          'https://docs.google.com/forms/d/e/FAKEFORM00001/viewform']) {
        final r = withDeletion(url);
        expect(r.rows.where((x) => x.path == 'legal.accountDeletionUrl' && x.kind == 'client'), isEmpty, reason: url);
        expect(asks(r), isNot(contains('legal.accountDeletionUrl')), reason: url);
        expect(row(r, 'legal.accountDeletionUrl', 'todo').note,
            allOf(contains('a Drive link'), contains('host this as a public page')), reason: url);
      }
    });

    test('an intake written before the field existed still reads, and asks for it', () {
      final r = withDeletion(null);
      expect(r.refusal, isNull, reason: 'the field is additive: schemaVersion stays 1');
      expect(r.json['schemaVersion'], 1);
      expect(row(r, 'legal.accountDeletionUrl', 'ask').note, contains('delete their account'));
      expect(withDeletion('').rows.where((x) => x.path == 'legal.accountDeletionUrl' && x.kind == 'ask'), hasLength(1));
    });

    test('an uploaded document for the privacy policy or the terms is work to do', () {
      final j = intake();
      (j['values'] as Map)['legal'] = {
        'privacy_policy_url': 'https://nimbus.example/privacy',
        'terms_url': 'https://nimbus.example/terms',
      };
      // files[] says the client uploaded a PDF for the privacy policy anyway.
      (j['files'] as List)[1] = {
        'field': 'legal.privacy_policy_url', 'name': 'privacy.pdf', 'mime': 'application/pdf',
        'sizeBytes': 10, 'sha256': null, 'driveFileId': 'FAKEPDF00001', 'shareUrl': null,
      };
      final r = read([Dropped('spc-intake-x.json', bytesOf(j))]);
      expect(row(r, 'legal.privacyUrl', 'todo').note, contains('a PDF'));
      expect(r.rows.where((x) => x.path == 'legal.privacyUrl' && x.kind == 'client'), isEmpty);
      expect(row(r, 'legal.termsUrl').value, 'https://nimbus.example/terms', reason: 'a page of its own is kept');
    });

    test('the deletion URL is a known key, and a secret in it still refuses the file', () {
      expect(read([Dropped('a.json', bytesOf(intake()))]).refusal, isNull);
      final j = intake();
      ((j['values'] as Map)['legal'] as Map)['account_deletion_url'] = 'https://nimbus.example/delete?key=sk_live_FAKE';
      final why = read([Dropped('a.json', bytesOf(j))]).refusal!;
      expect(why, contains('values.legal.account_deletion_url'));
      expect(why, isNot(contains('sk_live_FAKE')));
    });
  });

  group('refusals: the whole file, naming the path, never the value', () {
    String? refusal(Map<String, dynamic> j) => read([Dropped('spc-intake-x.json', bytesOf(j))]).refusal;

    test('size, kind, version and unknown keys', () {
      expect(read([Dropped('spc-intake-x.json', List.filled(256 * 1024 + 1, 32))]).refusal, contains('256 KB'));
      expect(refusal(intake()..['schemaVersion'] = 2), contains('schemaVersion 2'));
      expect(refusal(intake()..['kind'] = 'other'), contains('kind'));
      expect(refusal(intake()..['extra'] = 1), contains('extra'));
      expect(refusal(intake()..['values'] = {...intake()['values'] as Map, 'confirmation': {}}), contains('values.confirmation'));
      expect(read([Dropped('spc-intake-x.json', utf8.encode('{nope'))]).refusal, contains('not JSON'));
      expect(read([Dropped('logo.png', png)]).refusal, contains('no spc-intake'));
    });

    for (final secret in ['sk_live_abc', 'xx pk_live_abc', 'eyJhbGciOi', '-----BEGIN PRIVATE KEY-----', 'my Password is']) {
      test('a secret-shaped value: $secret', () {
        final j = intake();
        (((j['values'] as Map)['transatel'] as Map)['api'] as Map)['cos_ref'] = secret;
        final why = refusal(j)!;
        expect(why, contains('values.transatel.api.cos_ref'));
        expect(why, isNot(contains(secret)));
      });
    }

    test('a key named password is fine; only values are read for secrets', () {
      expect(refusal(intake()), isNull, reason: 'fields_required.end_user.password is a key');
    });

    test("strippedPaths are paths: the portal's own names pass, anything else is refused", () {
      expect(refusal(intake()), isNull, reason: 'transatel.api.password_id names a removed field');
      expect(refusal(intake()..['strippedPaths'] = ['sk_live_abc 123']), contains('strippedPaths[0]'));
    });

    test('too long, too deep', () {
      final j = intake();
      ((j['values'] as Map)['company'] as Map)['business_model_summary'] = 'x' * 2001;
      expect(refusal(j), contains('values.company.business_model_summary'));
    });
  });

  group('files', () {
    test('the logo by sha256 first, whatever its name; PDFs are ignored', () {
      final j = intake();
      ((j['files'] as List).first as Map)['sha256'] = sha256.convert(png).toString();
      final r = read([Dropped('spc-intake-x.json', bytesOf(j)), Dropped('renamed by Drive.png', png), Dropped('nimbus-privacy.pdf', [37, 80, 68, 70])]);
      expect(r.mark, png);
      expect(row(r, 'logo.mark').note, contains('sha256'));
    });

    test('a sha256 that matches nothing does not fall back to a same-named impostor', () {
      final j = intake();
      ((j['files'] as List).first as Map)['sha256'] = 'f' * 64;
      final r = read([Dropped('spc-intake-x.json', bytesOf(j)), Dropped(logoName, png)]);
      expect(r.mark, isNull);
      expect(row(r, 'logo.mark', 'ask').note, contains('sha256'));
    });

    test('the downloaded Drive folder as a zip, with a nested path', () {
      final zip = Archive()
        ..addFile(ArchiveFile.bytes('Nimbus/spc-intake-nimbus.json', utf8.encode(fixture)))
        ..addFile(ArchiveFile.bytes('Nimbus/$logoName', png))
        ..addFile(ArchiveFile.bytes('Nimbus/../../evil.png', png));
      final r = read([Dropped('Nimbus-20261012.zip', ZipEncoder().encodeBytes(zip))]);
      expect(r.refusal, isNull);
      expect(r.mark, png);
    });

    test('a zip with too many entries, or too large once inflated, is refused unread', () {
      final many = Archive();
      for (var i = 0; i < 41; i++) {
        many.addFile(ArchiveFile.bytes('f$i.txt', [1]));
      }
      expect(read([Dropped('a.zip', ZipEncoder().encodeBytes(many))]).refusal, contains('40'));
      final big = Archive()..addFile(ArchiveFile.bytes('big.png', List.filled(26 * 1024 * 1024, 0)));
      expect(read([Dropped('a.zip', ZipEncoder().encodeBytes(big))]).refusal, contains('25 MB'));
    });

    test('the zip and its own JSON dropped together are one intake, not two', () {
      final zip = Archive()..addFile(ArchiveFile.bytes('Nimbus/spc-intake-nimbus.json', utf8.encode(fixture)));
      final r = read([Dropped('spc-intake-nimbus.json', utf8.encode(fixture)), Dropped('Nimbus.zip', ZipEncoder().encodeBytes(zip))]);
      expect(r.refusal, isNull);
    });

    test('two intake files are refused, not guessed between', () {
      final other = fixture.replaceFirst('Nimbus Roam SARL', 'Other SARL');
      final r = read([Dropped('spc-intake-a.json', utf8.encode(fixture)), Dropped('spc-intake-b.json', utf8.encode(other))]);
      expect(r.refusal, contains('two'));
    });
  });

  group('applying', () {
    test('New brand: the intake fills the form, and the plan records where each value came from', () {
      final r = read([Dropped('spc-intake-nimbus.json', utf8.encode(fixture)), Dropped(logoName, png)]);
      final form = intakeForm(r);
      expect(form, containsPair('slug', 'nimbusroam'));
      expect(form, containsPair('companyName', 'Nimbus Roam SARL'));
      expect(form['colors'], containsPair('primary', '#1e5aa8'));
      expect(form, isNot(contains('supportEmail')), reason: 'a contact is never the public support address');
      final plan = newBrandPlan('.', form, r.mark, intakeText: fixture);
      final studio = plan.text.firstWhere((c) => c.path == 'brands/nimbusroam/studio.json').after;
      final block = (jsonDecode(studio) as Map)['intake'] as Map;
      expect(block['applied'], containsPair('legal.country', 'DZ'));
      expect(block['applied'], isNot(contains('mobile.applicationId')), reason: 'a suggestion, not the client\'s');
      expect((jsonDecode(studio) as Map)['backend'], {'features': {'payments': true, 'vouchers': true}});
      final brand = jsonDecode(plan.text.firstWhere((c) => c.path == 'brands/nimbusroam/brand.json').after) as Map;
      expect((brand['mobile'] as Map)['displayName'], 'Nimbus');
      expect((brand['legal'] as Map)['accountDeletionUrl'], 'https://nimbus.example/delete-account',
          reason: 'without it every release of this brand is refused');
      expect(block['applied'], containsPair('legal.accountDeletionUrl', 'https://nimbus.example/delete-account'));
      expect(((brand['mobile'] as Map)['registration'] as Map)['fields'], ['email', 'password', 'firstName', 'lastName', 'phoneNum']);
    });

    test('Brand tab: blanks are ticked, values already set are not, and only ticked rows are written', () {
      final r = read([Dropped('spc-intake-nimbus.json', utf8.encode(fixture))]);
      final sample = unconfiguredRoot();
      addTearDown(() => sample.deleteSync(recursive: true));
      final offer = intakeOffer(sample.path, 'acorn', r);
      bool? take(String p) => offer.firstWhere((o) => o['path'] == p)['take'] as bool?;
      expect(take('name'), isFalse, reason: 'acorn already has a name');
      expect(take('studio:gcpProjectId'), isTrue, reason: 'blank in acorn\'s studio.json');
      expect(take('legal.accountDeletionUrl'), isTrue, reason: 'acorn has none, and cannot be released without one');
      final plan = intakePlan(sample.path, 'acorn', r, {'legal.country', 'studio:gcpProjectId', 'legal.accountDeletionUrl'});
      final brandDiff = (plan.toJson()['changes'] as List).firstWhere((c) => c['path'] == 'brands/acorn/brand.json')['diff'] as String;
      expect(brandDiff, contains('"country": "DZ"'));
      expect(brandDiff, contains('"accountDeletionUrl": "https://nimbus.example/delete-account"'));
      expect(brandDiff, isNot(contains('"name": "Nimbus Roam"')), reason: 'the name was not ticked');
      final studio = jsonDecode(plan.text.firstWhere((c) => c.path == 'brands/acorn/studio.json').after) as Map;
      expect(studio['gcpProjectId'], 'nimbus-roam-0001');
      expect((studio['intake'] as Map)['applied'], {
        'legal.accountDeletionUrl': 'https://nimbus.example/delete-account',
        'legal.country': 'DZ',
        'studio:gcpProjectId': 'nimbus-roam-0001',
      });
      expect((studio['backend'] as Map)['phase2'], isNotNull, reason: 'the rest of studio.json is kept');
    });

    test("a value another brand has is refused, as in New brand", () {
      final j = intake();
      ((j['values'] as Map)['branding'] as Map)['brand_name'] = 'Sabily';
      final r = read([Dropped('a.json', bytesOf(j))]);
      final sample = unconfiguredRoot();
      addTearDown(() => sample.deleteSync(recursive: true));
      expect(intakePlan(sample.path, 'acorn', r, {'name'}).errors.map((e) => e['field']), contains('name'));
    });
  });
}
