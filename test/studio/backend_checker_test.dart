@Timeout(Duration(minutes: 1))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/studio/src/backend.dart';

/// The checker Alpha runs on a server (tool/studio/backend/, §16.6). It
/// cannot run here (no Postgres, nginx or systemd), so its parsers run
/// through its own --selftest, and ymlmap masks a file of fake secrets.
/// Skipped where there is no Python 3.
void main() {
  String? python;
  setUpAll(() async {
    for (final candidate in ['python3', 'python']) {
      try {
        final r = await Process.run(candidate, ['--version']);
        if (r.exitCode == 0 && '${r.stdout}${r.stderr}'.startsWith('Python 3')) {
          python = candidate;
          break;
        }
      } on ProcessException {
        continue;
      }
    }
  });

  test("the checker's parsers pass its own selftest", () async {
    if (python == null) return markTestSkipped('no Python 3 on this machine');
    final script = File('$backendScriptsDir/spc-backend-check.sh').readAsStringSync();
    final body = RegExp(r"<<'PY'\n([\s\S]*?)\nPY\n").firstMatch(script)![1]!;
    final p = await Process.start(python!, ['-I', '-', backendScriptsDir, '--selftest']);
    p.stdin.write(body);
    await p.stdin.close();
    final out = await p.stdout.transform(const SystemEncoding().decoder).join();
    final err = await p.stderr.transform(const SystemEncoding().decoder).join();
    expect(await p.exitCode, 0, reason: err);
    expect(out.trim(), 'selftest ok');
  });

  test('ymlmap prints no secret, masks credentials in any URL, and finds `key: #`', () async {
    if (python == null) return markTestSkipped('no Python 3 on this machine');
    final dir = Directory.systemTemp.createTempSync('ymlmap');
    addTearDown(() => dir.deleteSync(recursive: true));
    // Fake secrets, assembled here so no secret-shaped literal sits in the repo.
    final secrets = {
      'stripe': 'sk_${'live'}_FAKE${'1' * 24}',
      'jwt': 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJGQUtFIn0.c2lnbmF0dXJlRkFLRQ',
      'pem': 'FAKEPEMBODYFAKE',
      'password': 'Fa!ke#Pw[1]*+:x',
      'url-password': 'FAKEPASS',
      'datasource-password': 'FAKEDSPW',
      'webhook': 'whsec_FAKE000',
    };
    final yml = File('${dir.path}/fake.yml')..writeAsStringSync('''
spring:
  datasource:
    url: jdbc:postgresql://fakeuser:${secrets['datasource-password']}@localhost:6478/fakedb
    password: "${secrets['password']}"   # trailing comment
  mail:
    from: # todo
jhipster:
  mail:
    base-url: https://user:${secrets['url-password']}@x.example/
  security:
    authentication:
      jwt:
        base64-secret: ${secrets['jwt']}
sabily:
  stripe:
    secret-key: ${secrets['stripe']}
    webhook-secret: ${secrets['webhook']}
    success-url: https://fake.example/ok?session={CHECKOUT_SESSION_ID}
  cert: |
    -----BEGIN PRIVATE KEY-----
    ${secrets['pem']}
    -----END PRIVATE KEY-----
''');
    final r = await Process.run(python!, ['-I', '$backendScriptsDir/ymlmap.py', yml.path]);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    final out = '${r.stdout}';
    for (final MapEntry(key: what, value: secret) in secrets.entries) {
      expect(out, isNot(contains(secret)), reason: what);
    }
    expect(out, contains('spring.datasource.url: <url-with-credentials>'), reason: 'an allowlisted key too');
    expect(out, contains('sabily.stripe.success-url: https://fake.example/ok'));

    final nulls = await Process.run(python!, [
      '-I', '-c', 'import sys; sys.path.insert(0, sys.argv[1]); import ymlmap; print(ymlmap.hash_nulls(sys.argv[2]))',
      backendScriptsDir, yml.path,
    ]);
    expect('${nulls.stdout}'.trim(), "['spring.mail.from']");
  });
}
