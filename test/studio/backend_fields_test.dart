import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/studio/src/backend.dart';

/// What the Backend tab may write (docs/STUDIO-SPEC.md §16.4), and the
/// commands it prints (§16.11): golden files, so a change is seen in review.
void main() {
  final servers = loadServers();
  Map<String, dynamic> acorn() => {
        'features': {'payments': false, 'vouchers': false},
        'clientDomains': ['odysseysim.com'],
        'migrationPath': 'SQL files applied by deploy.sh',
        'dev': {
          'server': 'dev', 'name': 'acorn-backend', 'domain': 'acorn.transasim.com',
          'apiBaseUrl': 'https://acorn.transasim.com/api', 'port': 9074, 'dir': '/apps/acorn-backend',
          'db': 'acorn_prod', 'jar': 'acorn-backend.jar', 'restartMethod': 'scripts', 'shellUser': 'root',
        },
      };
  Map<String, dynamic> sabily() => {
        'features': {'payments': true, 'vouchers': true},
        'dev': {
          'server': 'dev', 'name': 'sabily', 'domain': 'sabily.transasim.com',
          'apiBaseUrl': 'https://sabily.transasim.com/api', 'port': 9060, 'dir': '/apps/sabily', 'db': 'sabily',
          'jar': 'sabily.jar', 'restartMethod': 'systemd', 'shellUser': 'root',
          'stripePublishableKeyTest': 'pk_test_${'b' * 30}',
        },
      };
  List<String> problems(String slug, Map<String, dynamic> backend, [Map<String, Map<String, dynamic>> others = const {}]) => [
        for (final (field, reason) in backendProblems(slug, backend, servers: servers, others: others)) '$field: $reason',
      ];

  test("every brand's committed backend passes the rules Apply holds it to", () {
    final studios = {
      for (final slug in ['acorn', 'esimple', 'sabily'])
        slug: jsonDecode(File('brands/$slug/studio.json').readAsStringSync()) as Map<String, dynamic>,
    };
    for (final MapEntry(key: slug, value: studio) in studios.entries) {
      final others = {for (final e in studios.entries) if (e.key != slug) e.key: e.value};
      expect(problems(slug, (studio['backend'] as Map?)?.cast<String, dynamic>() ?? {}, others), isEmpty, reason: slug);
    }
  });

  test("Acorn's DEV backend as entered is valid", () {
    expect(problems('acorn', acorn()), isEmpty);
  });

  test("eSimple's production box is never its DEV, and a production box's backend gets no test key", () {
    final e = acorn()..['dev'] = {...(acorn()['dev'] as Map), 'name': 'esimple-backend', 'port': 9073};
    expect(problems('esimple', e), contains(contains('production')));
    final prod = {
      'features': {'payments': true, 'vouchers': true},
      'prod': {...(acorn()['dev'] as Map), 'name': 'esimple-backend', 'port': 9073, 'domain': 'esimple.transasim.com',
        'apiBaseUrl': 'https://esimple.transasim.com/api', 'dir': '/apps/esimple-backend', 'db': 'esimple_prod',
        'jar': 'esimple-backend.jar'},
    };
    expect(problems('esimple', prod), isEmpty, reason: 'its PROD may be the dev box: it runs its production');
    (prod['prod'] as Map)['stripePublishableKeyTest'] = 'pk_test_${'c' * 30}';
    expect(problems('esimple', prod), contains(contains('stripePublishableKeyTest')));
  });

  test('a PROD backend sits on a prod box, a DEV one on a dev box, never on a retired one', () {
    final p = acorn()..['prod'] = {...(acorn()['dev'] as Map)};
    expect(problems('acorn', p), contains(startsWith('backend.prod.server')));
    final r = acorn()..['dev'] = {...(acorn()['dev'] as Map), 'server': 'retired'};
    expect(problems('acorn', r), contains(startsWith('backend.dev.server')));
    final u = acorn()..['dev'] = {...(acorn()['dev'] as Map), 'server': 'nowhere'};
    expect(problems('acorn', u), contains(startsWith('backend.dev.server')));
  });

  test('each field is checked for its shape', () {
    for (final (field, value) in [
      ('domain', 'not a domain'),
      ('apiBaseUrl', 'http://acorn.transasim.com/api'),
      ('apiBaseUrl', 'https://elsewhere.example/api'),
      ('port', 80),
      ('dir', '/home/acorn'),
      ('db', 'Acorn-Prod'),
      ('jar', 'acorn.war'),
      ('restartMethod', 'nohup'),
      ('shellUser', 'root; rm -rf /'),
      ('stripePublishableKeyTest', 'pk_live_${'a' * 30}'),
      ('stripePublishableKeyTest', 'pk_test_PLACEHOLDER'),
    ]) {
      final b = acorn()..['dev'] = {...(acorn()['dev'] as Map), field: value};
      expect(problems('acorn', b), contains(startsWith('backend.dev.$field')), reason: '$field = $value');
    }
    final missing = acorn()..remove('dev');
    expect(problems('acorn', missing), isEmpty, reason: 'an env not yet entered is not an error');
    final half = acorn()..['dev'] = {'server': 'dev'};
    expect(problems('acorn', half), contains(startsWith('backend.dev.port')));
  });

  test('a secret never gets in, whatever the field', () {
    final b = acorn()..['migrationPath'] = 'sk_${'live'}_${'9' * 30}';
    expect(problems('acorn', b), contains(contains('secret')));
  });

  test('port, folder, database and name are unique on a server; the domain everywhere', () {
    final other = {
      'backend': {'dev': {...(acorn()['dev'] as Map)}},
    };
    final clash = problems('acorn', acorn(), {'sabily': other});
    for (final f in ['port', 'dir', 'db', 'name', 'domain']) {
      expect(clash, contains(allOf(startsWith('backend.dev.$f'), contains('sabily'))), reason: f);
    }
  });

  test('the commands for a scripts backend, filled from the registry and the brand (golden)', () {
    final text = renderCommands(backendCommands(slug: 'acorn', env: 'dev', cfg: (acorn()['dev'] as Map).cast(),
        server: servers['dev']!, features: {'payments': false, 'google': false}));
    _golden('acorn-dev.commands.txt', text);
    expect(text, isNot(contains('systemctl')));
    expect(text, contains('script unknown'));
  });

  test('a systemd backend restarts through systemctl, never startup.sh (golden)', () {
    final text = renderCommands(backendCommands(slug: 'sabily', env: 'dev', cfg: (sabily()['dev'] as Map).cast(),
        server: servers['dev']!, features: {'payments': true, 'google': true},
        googleClientId: '123-abc.apps.googleusercontent.com'));
    _golden('sabily-dev.commands.txt', text);
    expect(text, contains('systemctl restart sabily'));
    expect(text, isNot(contains('bin/startup.sh &&')));
    expect(text, allOf(contains('--stripe-account'), contains('--google-client 123-abc.apps.googleusercontent.com')));
    // The report's method wins over the recorded one.
    final fromReport = renderCommands(backendCommands(slug: 'sabily', env: 'dev',
        cfg: {...(sabily()['dev'] as Map).cast<String, dynamic>(), 'restartMethod': 'scripts'},
        server: servers['dev']!, features: const {}, reportMethod: 'systemd'));
    expect(fromReport, contains('systemctl restart sabily'));
  });

  test('a login other than root runs the checker and the restart through sudo', () {
    final text = renderCommands(backendCommands(slug: 'acorn', env: 'prod',
        cfg: {...(acorn()['dev'] as Map).cast<String, dynamic>(), 'server': 'prod-esimple', 'shellUser': 'hostadmin'},
        server: servers['prod-esimple']!, features: const {}));
    expect(text, contains('ssh -p 52145 hostadmin@80.241.216.126'));
    expect(text, contains('sudo ~/spc-check/spc-backend-check.sh'));
  });

  test("the checker's install snippet carries each file exactly, with its SHA-256", () {
    final files = checkerFiles('.');
    expect(files.map((f) => f.name), ['spc-backend-check.sh', 'ymlmap.py', 'sharecheck.py']);
    final snippet = checkerInstallSnippet('.');
    for (final f in files) {
      final text = File('$backendScriptsDir/${f.name}').readAsStringSync();
      expect(f.sha256, sha256.convert(utf8.encode(text)).toString());
      expect(snippet, contains("cat > ${f.name} <<'SPC_STUDIO_EOF'\n$text"), reason: f.name);
      expect(text.endsWith('\n'), isTrue);
      expect(text, isNot(contains('SPC_STUDIO_EOF')));
    }
    expect(snippet, contains('sha256sum spc-backend-check.sh ymlmap.py sharecheck.py'));
  });
}

/// Compares [text] with the committed golden file; UPDATE_GOLDENS=1 rewrites it.
void _golden(String name, String text) {
  final f = File('test/studio/fixtures/backend/$name');
  if (Platform.environment['UPDATE_GOLDENS'] == '1' || !f.existsSync()) f.writeAsStringSync(text);
  expect(text, f.readAsStringSync(), reason: 'golden $name: rerun with UPDATE_GOLDENS=1 after checking the diff');
}
