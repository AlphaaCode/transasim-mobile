import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/studio/src/redact.dart';

/// Every line Studio stores, streams or bundles passes through the redactor
/// first. These are the shapes it must remove, and the lines it must leave be.
void main() {
  late Directory root;
  setUp(() {
    root = Directory.systemTemp.createTempSync('redact');
    Directory('${root.path}/android').createSync();
    File('${root.path}/android/demo-key.properties').writeAsStringSync(
        'storePassword=Tr0ub4dor&3\nkeyPassword=correct-horse-9\nkeyAlias=upload\nstoreFile=demo.jks\n');
    // A key parked until Play activates it is still a secret.
    File('${root.path}/android/other-key.properties.pending').writeAsStringSync('storePassword=pending-pass-7\n');
  });
  tearDown(() => root.deleteSync(recursive: true));

  const secrets = [
    'Tr0ub4dor&3',
    'correct-horse-9',
    'pending-pass-7',
    'sk_live_51HxYzAbCdEfGhIjKlMnOp',
    'rk_test_51HxYzAbCdEfGhIjKlMnOp',
    'whsec_AbCdEf0123456789',
    'GOCSPX-AbCdEf0123456789_xyz',
    'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiI0MiJ9.dBjftJeZ4CVPmB92K27uhbUJU1p1r_wW1gFWFOEjXk',
    'MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC7VJTUt9Us8cKjMzEfYyjiWA4R4',
    'alice.customer@example.com',
    'abc.def-ghi_jkl',
  ];

  test('known values and known shapes disappear from a log', () {
    final redact = Redactor.forRepo(root.path);
    final log = [
      'storePassword=Tr0ub4dor&3',
      'keytool -storepass correct-horse-9',
      'retrying with pending-pass-7',
      'STRIPE_SECRET=sk_live_51HxYzAbCdEfGhIjKlMnOp and rk_test_51HxYzAbCdEfGhIjKlMnOp',
      'webhook whsec_AbCdEf0123456789',
      'client_secret: GOCSPX-AbCdEf0123456789_xyz',
      'Authorization: Bearer abc.def-ghi_jkl',
      'token eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiI0MiJ9.dBjftJeZ4CVPmB92K27uhbUJU1p1r_wW1gFWFOEjXk',
      '-----BEGIN PRIVATE KEY-----',
      'MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC7VJTUt9Us8cKjMzEfYyjiWA4R4',
      '-----END PRIVATE KEY-----',
      'I/flutter: [auth] signed in as alice.customer@example.com',
    ].join('\n');
    final out = redact(log);
    for (final s in secrets) {
      expect(out, isNot(contains(s)), reason: s);
    }
    expect(out, contains('[redacted]'));
  });

  test('ordinary lines are untouched', () {
    final redact = Redactor.forRepo(root.path);
    const lines = [
      '> Task :app:compileSabilyReleaseKotlin',
      'I/flutter ( 4242): [brand:sabily] stripePublishableKey pk_live_51Abc is public',
      'SHA1: D0:87:9B:B2:AE:1D:D0:40:D1:50:57:33:20:92:45:69:46:66:5B:A7',
      'BUILD SUCCESSFUL in 1m 12s',
      r'C:\Users\akaro\Documents\GitHub\transasim-mobile\build\app\outputs\flutter-apk\app-sabily-release.apk',
      'Running Gradle task \'bundleSabilyRelease\'...',
    ];
    for (final l in lines) {
      expect(redact(l), l);
    }
  });

  test('a password too short to be a keystore password is not used as a pattern', () {
    // keytool refuses store passwords under 6 characters; a shorter value is
    // not one, and replacing it everywhere would shred the log.
    File('${root.path}/android/demo-key.properties').writeAsStringSync('storePassword=abc\n');
    expect(Redactor.forRepo(root.path)('abc def'), 'abc def');
  });
}
