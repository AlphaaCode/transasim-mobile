/// The backend phase (docs/STUDIO-SPEC.md §16): the server registry, a
/// brand's backend in studio.json, the checker's pasted report, the items
/// evaluated from it and from the probes, the gates they hold, and the
/// commands Studio prints.
///
/// Studio never connects to a server and never holds a server credential:
/// Alpha runs the printed commands and pastes the checker's JSON back.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:yaml/yaml.dart';

import '../../gen_brand_flavors.dart' show brandSlugs;
import 'assets.dart' show Plan;
import 'generate.dart' show FileChange, readStudio;
import 'guides.dart' show integrationsPlan;
import 'incidents.dart';
import 'redact.dart';

const serversFile = 'tool/studio/servers.yaml';
const backendScriptsDir = 'tool/studio/backend';
const reportsDir = '.studio/reports';
/// 2 (2026-10-11): `timestamp(6)` and `timestamp` hash alike, the same column
/// as Hibernate and Liquibase spell it. Version 1 hashes cannot be compared.
const reportSchemaVersion = 2;
const reportMaxAge = Duration(hours: 24);

class Server {
  Server({
    required this.id,
    required this.role,
    required this.prodFor,
    required this.host,
    required this.expectedHostname,
    required this.sshPort,
    required this.sshUser,
    required this.pgPort,
    required this.scripts,
    required this.notes,
  });

  final String id, role, host, expectedHostname, sshUser, notes;
  final int sshPort, pgPort;

  /// Brands whose production backend this box runs, whatever its role.
  final List<String> prodFor;

  /// Automation already on the box: name -> {path, use}.
  final Map<String, Map<String, String>> scripts;

  Map<String, Object?> toJson() => {
        'id': id,
        'role': role,
        'prodFor': prodFor,
        'host': host,
        'expectedHostname': expectedHostname,
        'sshPort': sshPort,
        'sshUser': sshUser,
        'pgPort': pgPort,
        'scripts': scripts,
        'notes': notes,
      };
}

Map<String, Server> loadServers([String root = '.']) {
  final y = loadYaml(File('$root/$serversFile').readAsStringSync());
  Never bad(String why) => throw FormatException('$serversFile: $why');
  if (y is! YamlList) bad('expected a list of servers');
  final out = <String, Server>{};
  for (final s in y) {
    if (s is! YamlMap) bad('each server is a map');
    String str(String k) => s[k] is String || s[k] is int ? '${s[k]}' : bad('${s['id']}: "$k" is missing');
    int number(String k) => s[k] is int ? s[k] as int : bad('${s['id']}: "$k" must be a number');
    final role = str('role');
    if (!const {'dev', 'prod', 'retired'}.contains(role)) bad('${s['id']}: role must be dev, prod or retired');
    out[str('id')] = Server(
      id: str('id'),
      role: role,
      prodFor: [for (final b in (s['prodFor'] as List? ?? const [])) '$b'],
      host: str('host'),
      expectedHostname: str('expectedHostname'),
      sshPort: number('sshPort'),
      sshUser: str('sshUser'),
      pgPort: number('pgPort'),
      scripts: {
        for (final e in ((s['scripts'] as Map?) ?? const {}).entries)
          '${e.key}': {for (final f in (e.value as Map).entries) '${f.key}': '${f.value}'},
      },
      notes: '${s['notes'] ?? ''}',
    );
  }
  return out;
}

// ---- the report ---------------------------------------------------------------

/// Every field the checker prints (tool/studio/backend/spc-backend-check.sh),
/// with its type. A test keeps the two lists equal. A type is a String (`str`,
/// `int`, `bool`, `[str]`, `[int]`, `{int?}` for a map of nullable ints,
/// `group` for `[str]` or "n/a", `hex8`; a trailing `?` allows null), or a Map
/// of exactly these fields.
const reportFields = <String, Object>{
  'hostname': 'str',
  'schema_version': 'int',
  'script_version': 'str',
  'generated_at': 'str',
  'hostname_match': 'bool',
  'slug': 'str',
  'port_listening': 'bool',
  'pg_ports_listening': '[int]',
  'health_local_status': 'int',
  'health_local_up': 'bool',
  'management_public_status': 'int',
  'management_public_exposed': 'bool',
  'jar_name': 'str?',
  'jar_version': 'str?',
  'jar_sha256_16': 'str?',
  'running_jar_from_dir': 'bool',
  'liquibase_disabled_on_cmdline': 'bool',
  'layout_missing': '[str]',
  'scripts_executable': 'bool?',
  'app_name_values_consistent': 'bool',
  'restart_method': 'str',
  'unit_enabled': 'bool',
  'pidfile_matches_process': 'bool',
  'conf_dir_mode': 'str?',
  'conf_world_readable': 'bool',
  'config_files_present': '[str]',
  'config_leaf_count': 'int',
  'config_required_missing': '[str]',
  'config_pending_count': 'int',
  'config_port_matches_arg': 'bool',
  'config_db_matches_arg': 'bool',
  'stripe_key_mode': 'str',
  'stripe_webhook_secret_key_present': 'bool',
  'transatel_host_class': 'str',
  'ddl_auto': 'str?',
  'liquibase_mode': 'str',
  'jwt_is_known_template_default': 'bool',
  'cors_allows_any_origin': 'bool',
  'logging_keys_ok': 'bool',
  'sftp_path_in_dir': 'bool?',
  'config_values': {
    'mail_base_host': 'str?',
    'stripe_success_host': 'str?',
    'stripe_cancel_host': 'str?',
    'mail_from_domain': 'str?',
    'spc_name': 'str?',
    'log_file': 'str?',
  },
  'url_host_resolves_to_this_box': {
    'mail_base_url': 'bool?',
    'stripe_success_url': 'bool?',
    'stripe_cancel_url': 'bool?',
  },
  'template_placeholder_left': '[str]',
  'secret_shared_with': {
    'jwt': 'group',
    'stripe': 'group',
    'mail_pw': 'group',
    'transatel_login_pw': 'group',
    'sftp_pw': 'group',
    'db_pw': 'group',
    'recaptcha': 'group',
  },
  'gcp_credentials_file_exists': 'bool',
  'gcp_credentials_shared_with': '[str]',
  'google_client_listed': 'bool?',
  'stripe_account_ok': 'bool?',
  'stripe_charges_enabled': 'bool?',
  'db_reachable': 'bool',
  'db_table_count': 'int?',
  'ref_table_counts': '{int?}',
  'authorities': '[str]',
  'anonymous_user_exists': 'bool?',
  'anonymous_subscriber_exists': 'bool?',
  'anonymous_subscriber_user_valid': 'bool?',
  'payment_method_check_present': 'bool?',
  'db_role': 'str?',
  'db_role_exists': 'bool?',
  'db_role_create_on_public': 'bool?',
  'db_role_owns_tables': 'int?',
  'schema': 'schema?',
  'pg_listen_all': 'bool',
  'ufw_pg_open_to_world': 'bool',
  'nginx_test_ok': 'bool',
  'nginx_server_name_present': 'bool',
  'nginx_conflicting_server_name': 'bool',
  'nginx_proxies_to_port': 'bool',
  'nginx_management_denied': 'bool',
  'cert_days_left': 'int?',
  'dns_a_count': 'int',
  'dns_match': 'bool',
  'transatel_last_health': 'str',
  'transatel_last_health_at': 'str?',
  'server': {
    'ufw_active': 'bool',
    'ufw_open_ports': '[str]',
    'pg_hba_external_rules': 'int?',
    'http_only_backend_vhosts': '[str]',
    'world_readable_dumps': 'int',
    'stray_live_stripe_files': 'int?',
    'certbot_timer_active': 'bool',
    'backups_scheduled': 'bool',
  },
};

const _maxString = 200;
final _key = RegExp(r'^[A-Za-z0-9_.\-\[\] ]{1,120}$');
final _hex8 = RegExp(r'^[0-9a-f]{8}$');
final _control = RegExp(r'[\x00-\x1f\x7f]');

/// Why [v] does not fit [spec] at [path], or null when it does.
String? _misfit(Object? v, Object spec, String path) {
  if (spec is Map) {
    if (v is! Map) return '$path must be an object';
    for (final k in spec.keys) {
      if (!v.containsKey(k)) return 'missing field ${path.isEmpty ? '' : '$path.'}$k';
    }
    for (final k in v.keys) {
      if (!spec.containsKey(k)) return 'unknown field ${path.isEmpty ? '' : '$path.'}$k';
    }
    for (final e in spec.entries) {
      final why = _misfit(v[e.key], e.value as Object, path.isEmpty ? '${e.key}' : '$path.${e.key}');
      if (why != null) return why;
    }
    return null;
  }
  var type = spec as String;
  if (type.endsWith('?')) {
    if (v == null) return null;
    type = type.substring(0, type.length - 1);
  }
  bool str(Object? s) => s is String && s.length <= _maxString && !_control.hasMatch(s);
  final ok = switch (type) {
    'str' => str(v),
    'int' => v is int,
    'bool' => v is bool,
    '[str]' => v is List && v.length <= 200 && v.every(str),
    '[int]' => v is List && v.length <= 200 && v.every((x) => x is int),
    '{int?}' => v is Map && v.length <= 200 && v.entries.every((e) => _key.hasMatch('${e.key}') && (e.value == null || e.value is int)),
    'group' => v == 'n/a' || (v is List && v.length <= 50 && v.every(str)),
    'schema' => v is Map &&
        v.length == 2 &&
        [v['tables'], v['checks']].every((m) =>
            m is Map && m.length <= 500 && m.entries.every((e) => _key.hasMatch('${e.key}') && e.value is String && _hex8.hasMatch(e.value as String))),
    _ => false,
  };
  return ok ? null : '$path must be $spec${type == 'str' ? ' (at most $_maxString characters, one line)' : ''}';
}

/// The verdict on a pasted report: accepted, or refused with the reason.
/// A refused report is never stored, and the reason never quotes it.
({Map<String, Object?>? report, String? refused}) checkReport(String text,
    {required Server server, required String backend, required DateTime now, required Redactor redact}) {
  ({Map<String, Object?>? report, String? refused}) no(String why) => (report: null, refused: why);

  final secrets = redact.found(text);
  if (secrets.isNotEmpty) {
    return no('Refused: it carries something shaped like a secret (${secrets.join(', ')}). '
        'Nothing was stored. The checker never prints one: paste its output unchanged.');
  }
  final Object? json;
  try {
    json = jsonDecode(text.trim());
  } on FormatException {
    return no('Refused: this is not JSON. Paste the one line the checker prints.');
  }
  if (json is! Map<String, dynamic>) return no('Refused: expected one JSON object, the line the checker prints.');
  if (json.keys.toSet().containsAll(const {'hostname', 'error'}) && json.length == 2) {
    return no('The checker withheld its own output: it saw something secret-shaped in it. Nothing to store.');
  }
  final host = json['hostname'];
  if (host != server.expectedHostname) {
    return no('WRONG BOX: this report comes from $host, and ${server.id} (${server.host}) is '
        '${server.expectedHostname}. Nothing was stored.');
  }
  if (json['schema_version'] != reportSchemaVersion) {
    return no('Refused: unknown schema_version (${json['schema_version']}): this Studio reads version '
        '$reportSchemaVersion. Run the checker Studio shows.');
  }
  // Several brands' backends share a box: the box alone does not say whose report it is.
  if (json['slug'] != backend) {
    return no("WRONG BACKEND: this report is for ${json['slug']}, and this brand's backend on ${server.id} is "
        "$backend. Paste it into that brand's Backend tab. Nothing was stored.");
  }
  final misfit = _misfit(json, reportFields, '');
  if (misfit != null) return no('Refused: $misfit.');
  final at = DateTime.tryParse(json['generated_at'] as String);
  if (at == null || !at.isUtc) return no('Refused: generated_at must be a UTC time.');
  if (at.isAfter(now.add(const Duration(minutes: 5)))) {
    return no("Refused: generated_at is in the future; check the server's clock.");
  }
  if (now.difference(at) > reportMaxAge) {
    return no('Refused: stale, generated ${now.difference(at).inHours} h ago; a report counts for 24 h. '
        'Run the checker again.');
  }
  return (report: json, refused: null);
}

/// Keeps an accepted [report] under .studio/reports (gitignored).
void storeReport(String root, {required String slug, required String env, required Server server,
    required Map<String, Object?> report}) {
  final at = (report['generated_at'] as String).replaceAll(':', '');
  File('$root/$reportsDir/$slug/$env-$at.json')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(jsonEncode({'server': server.id, 'env': env, 'slug': slug, 'report': report}));
}

typedef StoredReport = ({Map<String, Object?> report, String server, DateTime at, bool fresh});

StoredReport? _read(File f, DateTime now) {
  final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  final report = (j['report'] as Map).cast<String, Object?>();
  final at = DateTime.parse(report['generated_at'] as String);
  return (report: report, server: j['server'] as String, at: at, fresh: now.difference(at) <= reportMaxAge);
}

/// The newest report pasted for [slug] on [env], fresh or not. With
/// [backend], only a report of that backend counts: one filed under the wrong
/// brand before Studio checked (2026-10-11) is ignored.
StoredReport? latestReport(String root, String slug, String env, {String? backend, required DateTime now}) {
  final dir = Directory('$root/$reportsDir/$slug');
  if (!dir.existsSync()) return null;
  final files = dir.listSync().whereType<File>().where((f) => f.uri.pathSegments.last.startsWith('$env-')).toList()
    ..sort((a, b) => b.path.compareTo(a.path));
  for (final f in files) {
    final r = _read(f, now);
    if (r != null && (backend == null || r.report['slug'] == backend)) return r;
  }
  return null;
}

/// The newest report from any backend on [serverId]: what the server items read.
StoredReport? latestServerReport(String root, String serverId, {required DateTime now}) {
  final dir = Directory('$root/$reportsDir');
  if (!dir.existsSync()) return null;
  StoredReport? best;
  for (final f in dir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.json'))) {
    final r = _read(f, now);
    if (r != null && r.server == serverId && (best == null || r.at.isAfter(best.at))) best = r;
  }
  return best;
}

// ---- the items ------------------------------------------------------------------

/// A source an item needs and does not have: a fresh report, or a probe.
class _Missing implements Exception {
  const _Missing(this.kind, this.why);
  final String kind, why;
}

/// Everything the items read about one brand's backend on one env.
class BackendView {
  BackendView({
    required this.slug,
    required this.env,
    required this.brand,
    required this.studio,
    required this.server,
    required this.iosFlavor,
    required this.now,
    this.report,
    this.reportStale = false,
    this.serverReport,
    this.probes,
    this.reference,
    this.others = const {},
  });

  final String slug, env;
  final Map<String, dynamic> brand, studio;
  final Server server;

  /// The newest fresh report for this brand and env, and for any backend on
  /// [server] (the server items read that one).
  final Map<String, Object?>? report, serverReport;
  final bool reportStale;
  final Map<String, Object?>? probes;

  /// The reference schema's hashes: `{tables, checks}`.
  final Map<String, Object?>? reference;

  /// The other brands' studio.json, for what must be unique on a server.
  final Map<String, Map<String, dynamic>> others;
  final bool iosFlavor;
  final DateTime now;

  Map<String, dynamic> get backend => (studio['backend'] as Map?)?.cast<String, dynamic>() ?? {};
  Map<String, dynamic> get cfg => (backend[env] as Map?)?.cast<String, dynamic>() ?? {};

  /// A brand live before the backend phase (`backendGate: legacy`): its items
  /// are information only.
  bool get legacy => isLegacy(studio);
  List<String> get clientDomains => [for (final d in (backend['clientDomains'] as List? ?? const [])) '$d'];

  Map<String, Object?> get r =>
      report ??
      (throw reportStale
          ? const _Missing('stale', 'the last report is older than 24 h: run the checker again')
          : const _Missing('report', 'no report yet: run the checker and paste its output'));
  Map<String, Object?> get sr =>
      serverReport ?? (throw _Missing('report', 'no report from the last 24 h from any backend on ${server.id}'));
  Map<String, Object?> get srv => (sr['server'] as Map).cast<String, Object?>();
  Map<String, Object?> p(String name) {
    final x = probes?[name];
    if (x is! Map) throw const _Missing('probe', 'not probed yet: press Check');
    return x.cast<String, Object?>();
  }
}

typedef Outcome = ({bool? ok, String reason});
Outcome _ok(String reason) => (ok: true, reason: reason);
Outcome _no(String reason) => (ok: false, reason: reason);
Outcome _unsure(String reason) => (ok: null, reason: reason);
Outcome _all(List<String> problems, String fine) => problems.isEmpty ? _ok(fine) : _no(problems.join('; '));

Map<String, Object?> _map(Object? v) => (v as Map?)?.cast<String, Object?>() ?? const {};
List<String> _list(Object? v) => v is List ? [for (final x in v) '$x'] : const [];
String _few(List<String> xs, [int n = 4]) =>
    xs.length <= n ? xs.join(', ') : '${xs.take(n).join(', ')} and ${xs.length - n} more';

/// The app's isUsableStripeKey (checkout_controllers.dart) for one mode.
/// Studio cannot import it: it is Flutter code.
bool usableStripeKey(String? key, {required String mode}) =>
    key != null && RegExp('^pk_${mode}_[A-Za-z0-9]{24,}\$').hasMatch(key);

/// Whether [studio] marks a brand live before the backend phase (Sabily,
/// eSimple): its backend items are shown for information and never block a
/// build, Go phase 2 or a release.
bool isLegacy(Map studio) => studio['backendGate'] == 'legacy';

/// What a brand has, as the items' `when` reads it. payments and vouchers are
/// declared in studio.json (null until they are), except for a legacy brand,
/// which is never asked: there they are read from the app (a usable key takes
/// payments; every brand's home offers vouchers). The rest is derived.
Map<String, bool?> backendFeatures(BackendView v) {
  final f = _map(v.backend['features']);
  final key = _map(v.brand['mobile'])['stripePublishableKey'] as String?;
  return {
    'payments': f['payments'] as bool? ??
        (v.legacy ? usableStripeKey(key, mode: 'live') || usableStripeKey(key, mode: 'test') : null),
    'vouchers': f['vouchers'] as bool? ?? (v.legacy ? true : null),
    'google': '${_map(v.brand['mobile'])['googleServerClientId'] ?? ''}'.isNotEmpty,
    'ios': v.iosFlavor,
    'provisions': true,
    'clientDomains': v.clientDomains.isNotEmpty,
  };
}

/// The other brands' backends recorded on [v]'s server, with their slug.
Iterable<(String, Map<String, Object?>)> _neighbours(BackendView v) sync* {
  for (final MapEntry(key: slug, value: studio) in v.others.entries) {
    for (final env in const ['dev', 'prod']) {
      final c = _map(_map(studio['backend'])[env]);
      if (c['server'] == v.server.id) yield (slug, c);
    }
  }
}

const _restartOf = {'systemd': 'systemd', 'startup.sh': 'scripts'};
const _apple = 'sabily.social-login.apple.client-ids[0]';
const _sharedLabels = {
  'stripe': 'the Stripe key',
  'transatel_login_pw': 'the Transatel login',
  'sftp_pw': 'the SFTP password',
  'db_pw': 'the database password',
  'recaptcha': 'the reCAPTCHA keys',
};

/// One evaluator per backend item, in the runbook's order (§16.11): the box,
/// the backend's own state, its config and secrets, the web tier, the app's
/// endpoints, then the server as a whole.
final backendEvaluators = <String, Outcome Function(BackendView)>{
  'be-box': (v) {
    final age = v.now.difference(DateTime.parse(v.r['generated_at'] as String));
    return _ok('report from ${v.r['hostname']}, '
        '${age.inMinutes < 120 ? '${age.inMinutes} min' : '${age.inHours} h'} old');
  },
  'be-port': (v) {
    final port = v.cfg['port'];
    return _all([
      if (v.r['port_listening'] != true) 'nothing listens on $port',
      if (v.r['config_port_matches_arg'] != true) 'server.port in the config is not $port',
      for (final (slug, c) in _neighbours(v))
        if (c['port'] == port) '$slug records the same port on ${v.server.id}',
    ], 'listens on $port, recorded, unique on ${v.server.id}');
  },
  'be-layout': (v) {
    final r = v.r;
    final method = _restartOf[r['restart_method']];
    final jar = v.cfg['jar'] ?? '${v.cfg['name']}.jar';
    final missing = _list(r['layout_missing']);
    return _all([
      if (missing.isNotEmpty) '${v.cfg['dir']} lacks ${missing.join(', ')}',
      if (r['jar_name'] != jar) 'the running jar is ${r['jar_name']}, not $jar',
      if (r['running_jar_from_dir'] != true) 'the jar does not run from ${v.cfg['dir']}',
      if (method == 'scripts' && r['app_name_values_consistent'] != true)
        'APP_NAME differs between startup.sh and shutdown.sh, or from the folder name',
      if (r['scripts_executable'] == false) 'startup.sh or shutdown.sh is not executable',
      if (r['conf_world_readable'] == true) 'conf is readable by every account (mode ${r['conf_dir_mode']})',
      if (method == null) 'the report could not tell how the backend restarts',
      if (method != null && method != v.cfg['restartMethod'])
        'it restarts by $method, but ${v.cfg['restartMethod']} is recorded',
    ], '$jar in ${v.cfg['dir']}, restarts by $method');
  },
  'be-survives-reboot': (v) => v.r['restart_method'] == 'systemd' && v.r['unit_enabled'] == true
      ? _ok('an enabled systemd unit')
      : _no('no enabled systemd unit: a reboot leaves it down'),
  'be-db': (v) {
    final r = v.r;
    final pg = v.server.pgPort;
    final ports = _list(r['pg_ports_listening']);
    return _all([
      if (r['db_reachable'] != true) '${v.cfg['db']} does not answer',
      if (!ports.contains('$pg')) 'Postgres listens on ${ports.isEmpty ? 'no port seen' : ports.join(', ')}, not $pg',
      if (r['config_db_matches_arg'] != true) 'spring.datasource.url does not name ${v.cfg['db']} on port $pg',
      if (r['db_role_exists'] != true) 'the role ${r['db_role'] ?? '(none in the config)'} does not exist',
    ], '${v.cfg['db']} on $pg, role ${r['db_role']}');
  },
  'be-schema-drift': (v) {
    final ref = v.reference;
    if (ref?['outdated'] == true) {
      return _unsure('The schema reference was hashed by an older checker: paste a new Sabily DEV report, '
          'then press "Use as schema reference" again.');
    }
    if (ref == null || ref['tables'] is! Map) {
      return _unsure('No schema reference yet: paste Sabily\'s DEV report, then press "Use as schema reference".');
    }
    if (v.r['schema_version'] != reportSchemaVersion) {
      return _unsure('this report was hashed by an older checker: install the one Studio shows, run it, paste again');
    }
    final mine = _map(v.r['schema']);
    if (mine.isEmpty) return _unsure('the report has no schema: the database did not answer');
    final (:tables, :checks) = schemaDifferences(ref, mine, _map(v.backend['schemaAccepted']));
    return _all([
      if (tables.isNotEmpty)
        'tables differ from the reference: ${_few(tables)} (compare with pg_dump --schema-only -t <table>, '
            'and make them match through the schema ledger)',
      if (checks.isNotEmpty)
        '${checks.length} CHECK difference${checks.length == 1 ? '' : 's'} neither accepted nor fixed: ${_few(checks)}',
      if ('${v.backend['migrationPath'] ?? ''}'.trim().isEmpty) 'record the migration path',
    ], 'matches the reference');
  },
  'ddl-auto-cannot-alter': (v) {
    final owns = v.r['db_role_owns_tables'];
    if (owns == null) return _unsure('the report could not tell who owns the tables');
    return v.r['ddl_auto'] == 'update' && owns == 0
        ? _no('ddl-auto is update and ${v.r['db_role']} owns none of the ${v.r['db_table_count']} tables: '
            'schema changes are SQL')
        : _ok('${v.r['db_role']} owns $owns tables');
  },
  'be-seed': (v) {
    final counts = _map(v.r['ref_table_counts']);
    final roles = _list(v.r['authorities']);
    return _all([
      if (counts['jhi_authority'] != 4) 'jhi_authority holds ${counts['jhi_authority']} roles, not 4',
      for (final role in const ['ROLE_ADMIN', 'ROLE_USER', 'ROLE_SUBSCRIBER'])
        if (!roles.contains(role)) '$role is missing',
      for (final t in const ['country', 'currency', 'area', 'pack', 'price', 'allowance', 'esim_inventory'])
        if ((counts[t] as int? ?? 0) == 0) '$t is empty',
    ], '${counts['pack']} packs, ${counts['esim_inventory']} eSIMs in stock');
  },
  'be-anon': (v) => switch ((v.r['anonymous_subscriber_exists'], v.r['anonymous_subscriber_user_valid'])) {
        (false, _) => _no('no subscriber anonymous@anonymous.com'),
        (_, true) => _ok('anonymous@anonymous.com points at an existing user'),
        (_, false) => _no("anonymous@anonymous.com's user_id points at no user"),
        _ => _unsure('the report could not tell whether its user exists'),
      },
  'be-config': (v) {
    final c = _map(v.r['config_values']);
    final here = _map(v.r['url_host_resolves_to_this_box']);
    final left = _list(v.r['template_placeholder_left']);
    final name = '${v.brand['name']}';
    final log = '${c['log_file'] ?? ''}'.toLowerCase();
    return _all([
      if (left.isNotEmpty) 'template values left in ${left.join(', ')}',
      for (final (key, url, label) in const [
        ('mail_base_host', 'mail_base_url', 'the mail base URL'),
        ('stripe_success_host', 'stripe_success_url', 'the Stripe success URL'),
        ('stripe_cancel_host', 'stripe_cancel_url', 'the Stripe cancel URL'),
      ])
        if (c[key] == null)
          '$label is not set'
        else if (here[url] != true && !v.clientDomains.contains(c[key]))
          '$label points at ${c[key]}, neither this server nor a declared client domain',
      if ('${c['spc_name']}'.toLowerCase() != name.toLowerCase()) 'spc-name is "${c['spc_name']}", not "$name"',
      if (log.isNotEmpty && !log.contains(v.slug)) 'the log path $log does not name ${v.slug}',
      for (final other in v.others.keys)
        if (log.contains(other)) 'the log path names $other',
      if (v.r['sftp_path_in_dir'] == false) 'the SFTP local path is outside ${v.cfg['dir']}',
      if (v.r['logging_keys_ok'] != true) 'the com.tamarisoft.sabily logging keys are gone',
    ], "the brand's own values");
  },
  'be-mail': (v) {
    final domain = _map(v.r['config_values'])['mail_from_domain'];
    final support = '${_map(v.brand['support'])['email'] ?? ''}'.split('@').last.toLowerCase();
    final own = {support, '${v.brand['domain']}', '${v.cfg['domain']}', ...v.clientDomains};
    if (domain == null) return _no('jhipster.mail.from is not set');
    return own.contains(domain) ? _ok('sends from $domain') : _no("sends from $domain, which is not the brand's");
  },
  'be-jwt': (v) {
    final shared = _list(_map(v.r['secret_shared_with'])['jwt']);
    return _all([
      if (v.r['jwt_is_known_template_default'] == true) 'the JWT secret is the JHipster template default',
      if (shared.isNotEmpty) 'the JWT secret is shared with ${shared.join(', ')}',
    ], 'its own');
  },
  'be-unshared': (v) {
    final shared = _map(v.r['secret_shared_with']);
    final reasons = _map(v.cfg['sharedReasons']);
    bool excused(String g) => '${reasons[g] ?? ''}'.trim().isNotEmpty;
    final gcp = _list(v.r['gcp_credentials_shared_with']);
    return _all([
      for (final MapEntry(key: g, value: label) in _sharedLabels.entries)
        if (_list(shared[g]).isNotEmpty && !excused(g)) '$label is shared with ${_list(shared[g]).join(', ')}',
      if (gcp.isNotEmpty && !excused('gcp')) "the GCP credentials file is the same as ${gcp.join(', ')}'s",
    ], 'nothing shared');
  },
  'mail-shared-account': (v) {
    final peers = _list(_map(v.r['secret_shared_with'])['mail_pw']);
    return peers.isNotEmpty ? _no('the mail password is shared with ${peers.join(', ')}') : _ok('its own');
  },
  'be-stripe-test': (v) {
    final mode = v.r['stripe_key_mode'];
    final account = v.r['stripe_account_ok'];
    return _all([
      if (mode != 'test') "the backend's key is $mode, not test",
      if (mode == 'test' && account == null) 'run the checker with --stripe-account',
      if (account == false) 'the Stripe account did not answer the key',
      if (account == true && v.r['stripe_charges_enabled'] != true) 'charges are not enabled',
      if (!usableStripeKey(v.cfg['stripePublishableKeyTest'] as String?, mode: 'test'))
        'record the DEV pk_test_ key in the Backend tab',
    ], 'test mode, account answering, charges enabled');
  },
  'transatel-production-on-dev': (v) => v.r['transatel_host_class'] == 'production'
      ? _no('DEV calls api.transatel.com')
      : _ok('Transatel: ${v.r['transatel_host_class']}'),
  'be-start': (v) => _all([
        if (v.r['port_listening'] != true) 'nothing listens on ${v.cfg['port']}',
        if (v.r['health_local_status'] != 200) 'local /management/health answers ${v.r['health_local_status']}',
        if (v.r['health_local_status'] == 200 && v.r['health_local_up'] != true) 'health is not UP',
        if (v.r['running_jar_from_dir'] != true) 'the running jar is not from ${v.cfg['dir']}',
      ], 'up: local health 200 UP'),
  'be-transatel': (v) {
    final last = v.r['transatel_last_health'];
    final at = v.r['transatel_last_health_at'] as String?;
    final seen = at == null ? null : DateTime.tryParse('${at.replaceFirst(' ', 'T')}Z');
    final shared = _list(_map(v.r['secret_shared_with'])['transatel_login_pw']);
    final generated = DateTime.parse(v.r['generated_at'] as String);
    return _all([
      if (last == 'unknown') 'the log shows no "APIs Transatel" line in 2 days (a log level of INFO hides it)',
      if (last != 'unknown' && last != '8/8') 'Transatel answers $last',
      // The log's time is the server's local time: 50 h covers 48 h in any zone.
      if (seen != null && generated.difference(seen) > const Duration(hours: 50)) 'last seen $at',
      if (shared.isNotEmpty) 'its login is shared with ${shared.join(', ')}',
    ], '8/8 at $at');
  },
  'be-dns': (v) {
    final d = v.p('dns');
    final domain = v.cfg['domain'];
    if (d['error'] != null) return _no('$domain does not resolve: ${d['error']}');
    final addresses = _list(d['addresses']);
    return addresses.contains(v.server.host)
        ? _ok('$domain → ${v.server.host}')
        : _no('$domain resolves to ${addresses.join(', ')}, not ${v.server.host}');
  },
  'be-nginx': (v) => _all([
        if (v.r['nginx_test_ok'] != true) 'nginx -t fails',
        if (v.r['nginx_server_name_present'] != true) 'no server block names ${v.cfg['domain']}',
        if (v.r['nginx_conflicting_server_name'] == true) 'conflicting server name for ${v.cfg['domain']}',
        if (v.r['nginx_proxies_to_port'] != true) '/api/ does not proxy to 127.0.0.1:${v.cfg['port']}',
        if (v.r['nginx_management_denied'] != true) '/management/ is not denied',
      ], 'serves ${v.cfg['domain']}'),
  'be-tls': (v) {
    final t = v.p('tls');
    if (t['error'] != null) return _no('TLS: ${t['error']}');
    final days = t['daysLeft'] as int;
    return days > 14 ? _ok('$days days left') : _no('$days days left: renew it');
  },
  'be-mgmt-private': (v) {
    final https = v.p('mgmtHttps')['status'], http = v.p('mgmtHttp')['status'];
    return _all([
      if (https == 200) 'https://${v.cfg['domain']}/management/health answers 200',
      if (http == 200) 'http://${v.cfg['domain']}/management/health answers 200, over plain HTTP',
      if (v.report?['management_public_exposed'] == true) 'the server itself sees /management exposed',
    ], 'public /management answers ${https ?? 'nothing'}');
  },
  'be-packs': (v) {
    final p = v.p('packs');
    if (p['error'] != null) return _no('/packs/all: ${p['error']}');
    if (p['status'] != 200) return _no('/packs/all answers ${p['status']}');
    return (p['count'] as int? ?? 0) == 0
        ? _no('/packs/all answers no packs')
        : _ok('${p['count']} packs, first byte after ${p['ttfbMs']} ms');
  },
  'be-social-google': (v) => _all([
        ..._social(v.p('authGoogle'), 'google'),
        if (v.r['google_client_listed'] == false) "the backend does not list the app's web client id",
        if (v.r['google_client_listed'] == null) 'run the checker with --google-client',
      ], '/v1/auth/google answers ${v.p('authGoogle')['status']}; the web client id is listed'),
  'be-social-apple': (v) => _all([
        ..._social(v.p('authApple'), 'apple'),
        if (_list(v.r['config_required_missing']).contains(_apple)) 'no Apple client ids in the config',
      ], '/v1/auth/apple answers ${v.p('authApple')['status']}; Apple client ids set'),
  'be-app-config': (v) {
    final s = v.p('appConfig');
    return s['status'] == 200 ? _ok('answers 200') : _no('answers ${s['status'] ?? s['error']}');
  },
  'be-dev-purchase': _ticked('be-dev-purchase', 'buy one pack on a DEV build, then tick it with the evidence'),
  'bp-same-jar': (v) {
    final phase2 = _map(v.backend['phase2']);
    final tested = phase2['jarSha256'];
    if (tested == null) return _no('Go phase 2 first: no DEV jar is recorded');
    final running = v.r['jar_sha256_16'];
    return running == tested
        ? _ok('$running, as tested on DEV (backend ${phase2['backendCommit']})')
        : _no('PROD runs $running; DEV tested $tested');
  },
  'bp-live-stripe': (v) {
    final mode = v.r['stripe_key_mode'];
    final account = v.r['stripe_account_ok'];
    return _all([
      if (mode != 'live') "the backend's key is $mode, not live",
      if (mode == 'live' && account == null) 'run the checker with --stripe-account',
      if (account == false) 'the Stripe account did not answer the key',
      if (account == true && v.r['stripe_charges_enabled'] != true) 'charges are not enabled',
    ], 'live mode, account answering, charges enabled');
  },
  'bp-nopending': (v) {
    final n = v.r['config_pending_count'] as int;
    return n == 0 ? _ok('no PENDING_ value left') : _no('$n keys are still PENDING_');
  },
  'bp-fresh': _ticked('bp-fresh', 'generate the JWT secret and the passwords new for PROD, then tick it'),
  'bp-testdata': _ticked('bp-testdata', 'remove the test accounts and the default admin password, then tick it'),
  'bp-ledger': (v) {
    final ledger = [for (final e in (v.backend['schemaLedger'] as List? ?? const [])) _map(e)];
    final open = [for (final e in ledger) if ('${e['prodAt'] ?? ''}'.isEmpty) '${e['what']}'];
    if (ledger.isEmpty) return _ok('no SQL run by hand on DEV is recorded');
    return open.isEmpty
        ? _ok('all ${ledger.length} applied on PROD')
        : _no('not yet applied on PROD: ${_few(open, 3)}');
  },
  'bp-backup': _ticked('bp-backup', 'take a fresh pg_dump before the PROD database changes, then tick it with its path'),
  'bp-rotated': _ticked('bp-rotated', 'rotate every credential seen in a chat or a log, then tick it'),
  'bp-first-purchase': _ticked('bp-first-purchase', 'buy one pack on the release build, refund it, then tick it'),
  'reviewer-account': _ticked('reviewer-account', 'create the store reviewer account on PROD, then tick it'),
  'srv-ports': (v) {
    final allowed = {22, v.server.sshPort, 80, 443};
    final open = [
      for (final e in _list(v.srv['ufw_open_ports']))
        if (!const {'OpenSSH', 'Nginx Full', 'Nginx HTTP', 'Nginx HTTPS'}.contains(e) && !_ports(e).every(allowed.contains))
          e,
    ];
    return open.isEmpty ? _ok('only ssh and the web are open to everyone') : _no('open to everyone: ${open.join(', ')}');
  },
  'srv-pg-private': (v) {
    final rules = v.srv['pg_hba_external_rules'];
    return _all([
      if (v.sr['pg_listen_all'] == true && v.sr['ufw_pg_open_to_world'] == true)
        'Postgres ${v.server.pgPort} is reachable through ufw from anywhere',
      if (rules == null) 'the report could not read pg_hba',
      if (rules is int && rules > 0) 'pg_hba admits $rules outside address${rules == 1 ? '' : 'es'}',
    ], 'Postgres is not reachable from outside');
  },
  'srv-no-http-backend': (v) {
    final sites = _list(v.srv['http_only_backend_vhosts']);
    return sites.isEmpty ? _ok('none') : _no('plain-HTTP sites proxy a backend: ${sites.join(', ')}');
  },
  'srv-world-readable': (v) {
    final n = v.srv['world_readable_dumps'] as int;
    return n == 0 ? _ok('none') : _no('$n dumps or tarballs are readable by every account');
  },
  'srv-no-prod-secrets': (v) {
    final n = v.srv['stray_live_stripe_files'];
    if (n == null) return _unsure('the search for stray keys timed out');
    return n == 0 ? _ok('none') : _no("$n files outside a running backend's config hold a live Stripe key");
  },
  'srv-certbot': (v) =>
      v.srv['certbot_timer_active'] == true ? _ok('certbot.timer active') : _no('certbot.timer is not active'),
  'srv-backups': (v) =>
      v.srv['backups_scheduled'] == true ? _ok('a backup job is scheduled') : _no('no job dumps the databases'),
};

/// Where [mine] differs from [ref]: the tables, and the CHECKs not yet
/// accepted in [accepted]. Names only: the report holds hashes.
({List<String> tables, List<String> checks}) schemaDifferences(
    Map<String, Object?> ref, Map<String, Object?> mine, Map<String, Object?> accepted) {
  List<String> differ(Object? a, Object? b) {
    final x = _map(a), y = _map(b);
    return {...x.keys, ...y.keys}.where((k) => x[k] != y[k]).toList()..sort();
  }

  return (
    tables: differ(ref['tables'], mine['tables']),
    checks: [
      for (final c in differ(ref['checks'], mine['checks']))
        if ('${accepted[c] ?? ''}'.trim().isEmpty) c,
    ],
  );
}

/// A manual item: passes once ticked in studio.json `checklist` with a note.
Outcome Function(BackendView) _ticked(String id, String todo) => (v) {
      final tick = _map(_map(v.studio['checklist'])[id]);
      return '${tick['note'] ?? ''}'.trim().isEmpty
          ? _no('not ticked: $todo')
          : _ok('ticked ${tick['at'] ?? ''}: ${tick['note']}');
    };

List<String> _social(Map<String, Object?> probe, String which) {
  final s = probe['status'];
  if (s == 404) return ['/v1/auth/$which is missing (404)'];
  if (s is! int || s < 400 || s > 499) return ['/v1/auth/$which answers ${s ?? probe['error']} to a junk token, not 4xx'];
  return const [];
}

/// The ports a ufw entry such as "80,443/tcp" or "9060:9099/tcp" opens; -1
/// for a name Studio does not know, which is never "allowed".
Iterable<int> _ports(String entry) sync* {
  for (final part in entry.split('/').first.split(',')) {
    final range = part.split(':').map(int.tryParse).toList();
    if (range.any((p) => p == null)) {
      yield -1;
    } else if (range.length == 2) {
      for (var p = range[0]!; p <= range[1]!; p++) {
        yield p;
      }
    } else {
      yield range.single!;
    }
  }
}

class ItemResult {
  ItemResult(this.item, {required this.status, required this.reason, required this.severity, required this.gate});

  final Incident item;
  final String status, reason, severity, gate;
  String get id => item.id;

  Map<String, Object?> toJson() => {
        'id': id,
        'title': item.title,
        'kind': item.kind,
        'env': item.env,
        'status': status,
        'reason': reason,
        'severity': severity,
        'gate': gate,
        'cause': item.cause,
        'fix': item.fix,
        'acceptedRisk': item.acceptedRisk,
      };
}

/// Every item that applies to [v]'s env, in the runbook's order. An item
/// whose `when` is off reads n/a, one an undeclared feature decides reads
/// unknown, a fail on a warn item reads warn, an accepted risk reads accepted.
List<ItemResult> evaluateBackend(BackendView v, Map<String, Incident> items) {
  if (v.env == 'dev' && v.server.prodFor.contains(v.slug)) {
    throw ArgumentError("${v.server.id} (${v.server.host}) runs ${v.slug}'s production: it is never ${v.slug}'s DEV.");
  }
  final features = backendFeatures(v);
  return [
    for (final MapEntry(key: id, value: check) in backendEvaluators.entries)
      if (items[id] case final item? when item.env == 'both' || item.env == 'server' || item.env == v.env)
        _result(v, item, check, features),
  ];
}

ItemResult _result(BackendView v, Incident item, Outcome Function(BackendView) check, Map<String, bool?> features) {
  final severity = v.legacy ? 'info' : item.severity[v.env]!;
  final gate = v.legacy
      ? 'none'
      : v.env == 'prod' && item.env != 'prod'
          ? 'release'
          : item.gate;
  ItemResult make(String status, String reason) =>
      ItemResult(item, status: status, reason: reason, severity: severity, gate: gate);
  final undeclared = item.when.where((c) => features[c] == null).toList();
  if (undeclared.isNotEmpty) {
    return make('unknown', 'declare whether the brand has ${undeclared.join(' and ')} in the Backend tab');
  }
  final off = item.when.where((c) => features[c] == false).toList();
  if (off.isNotEmpty) return make('na', 'not applicable: ${off.join(' and ')} off');
  final Outcome o;
  try {
    o = check(v);
  } on _Missing catch (m) {
    return make(m.kind == 'stale' ? 'stale' : 'unknown', m.why);
  }
  return switch (o.ok) {
    true => make('pass', o.reason),
    null => make('unknown', o.reason),
    false when item.acceptedRisk != null => make('accepted', '${o.reason}. Accepted risk: ${item.acceptedRisk}'),
    false => make(severity == 'warn' ? 'warn' : 'fail', o.reason),
  };
}

/// What holds [gate] shut: every blocking item that has not passed.
List<ItemResult> blockers(List<ItemResult> results, String gate) => [
      for (final r in results)
        if (r.gate == gate && r.severity == 'block' && !const {'pass', 'na', 'accepted'}.contains(r.status)) r,
    ];

// ---- the Backend tab's fields ---------------------------------------------------

final _host = RegExp(r'^(?=.{4,253}$)([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$');
const _envFields = {
  'server', 'name', 'domain', 'apiBaseUrl', 'port', 'dir', 'db', 'jar', 'restartMethod', 'shellUser',
  'stripePublishableKeyTest', 'sharedReasons',
};
const _required = ['server', 'name', 'domain', 'apiBaseUrl', 'port', 'dir', 'db', 'restartMethod', 'shellUser'];
const _sharedGroups = {'stripe', 'transatel_login_pw', 'sftp_pw', 'db_pw', 'recaptcha', 'gcp'};

/// Shapes of a secret: Studio never stores one (the guides' rule, applied to
/// every string of the backend section).
final _secretShaped = RegExp(r'(^|\W)(sk|rk)_(live|test)_|whsec_|GOCSPX-|-----BEGIN |eyJ[\w-]{5,}\.');

/// What is wrong with [backend] (studio.json `backend`) for [slug], as
/// (field, reason). [others] are the other brands' studio.json.
List<(String, String)> backendProblems(String slug, Map<String, dynamic> backend,
    {required Map<String, Server> servers, required Map<String, Map<String, dynamic>> others}) {
  final out = <(String, String)>[];
  void bad(String field, String reason) => out.add(('backend.$field', reason));

  void scan(Object? node, String path) {
    if (node is String && _secretShaped.hasMatch(node)) bad(path, 'looks like a secret; Studio never stores one');
    if (node is Map) {
      for (final e in node.entries) {
        scan(e.value, path.isEmpty ? '${e.key}' : '$path.${e.key}');
      }
    }
    if (node is List) {
      for (final v in node) {
        scan(v, path);
      }
    }
  }

  scan(backend, '');
  final features = backend['features'];
  if (features != null) {
    if (features is! Map) {
      bad('features', 'must be {payments, vouchers}');
    } else {
      for (final k in const ['payments', 'vouchers']) {
        if (features[k] != null && features[k] is! bool) bad('features.$k', 'must be true or false');
      }
    }
  }
  for (final d in (backend['clientDomains'] as List? ?? const [])) {
    if (!_host.hasMatch('$d')) bad('clientDomains', '"$d" is not a domain name');
  }
  if ('${backend['migrationPath'] ?? ''}'.length > 300) bad('migrationPath', 'at most 300 characters');
  final ledgerIds = <String>{};
  for (final (i, raw) in ((backend['schemaLedger'] as List?) ?? const []).indexed) {
    final e = raw is Map ? raw : const {};
    final id = '${e['id'] ?? ''}';
    if (!RegExp(r'^[a-z0-9][a-z0-9-]{0,59}$').hasMatch(id) || !ledgerIds.add(id)) {
      bad('schemaLedger[$i].id', 'a short unique name: lowercase letters, digits, hyphens');
    }
    if ('${e['what'] ?? ''}'.trim().isEmpty || '${e['what']}'.length > 300) {
      bad('schemaLedger[$i].what', 'what the SQL did, in at most 300 characters');
    }
    for (final k in const ['devAt', 'prodAt']) {
      if (e[k] != null && !RegExp(r'^\d{4}-\d\d-\d\d').hasMatch('${e[k]}')) bad('schemaLedger[$i].$k', 'a date, 2026-10-11');
    }
    if (e['devAt'] == null) bad('schemaLedger[$i].devAt', 'when it ran on DEV');
  }
  for (final e in ((backend['schemaAccepted'] as Map?) ?? const {}).entries) {
    if ('${e.value}'.trim().isEmpty || '${e.value}'.length > 300) {
      bad('schemaAccepted.${e.key}', 'say why the difference is accepted (at most 300 characters)');
    }
  }

  for (final env in const ['dev', 'prod']) {
    final raw = backend[env];
    if (raw == null) continue;
    if (raw is! Map) {
      bad(env, 'must be an object');
      continue;
    }
    final c = raw.cast<String, dynamic>();
    void field(String f, String why) => bad('$env.$f', why);
    for (final k in c.keys.where((k) => !_envFields.contains(k))) {
      field(k, 'not a field Studio knows');
    }
    for (final f in _required) {
      if (c[f] == null || '${c[f]}'.isEmpty) field(f, 'required');
    }
    final server = servers[c['server']];
    if (c['server'] != null && server == null) field('server', 'no server "${c['server']}" in servers.yaml');
    if (server != null) {
      final runsProd = server.prodFor.contains(slug);
      if (server.role == 'retired') {
        field('server', '${server.id} is retired');
      } else if (env == 'dev' && runsProd) {
        field('server', "${server.id} (${server.host}) runs $slug's production: it can only be $slug's PROD");
      } else if (env == 'dev' && server.role != 'dev') {
        field('server', '${server.id} is a ${server.role} box, not a dev one');
      } else if (env == 'prod' && server.role != 'prod' && !runsProd) {
        field('server', '${server.id} is a ${server.role} box; a PROD backend needs a prod box');
      }
    }
    final domain = '${c['domain'] ?? ''}';
    if (c['domain'] != null && !_host.hasMatch(domain)) field('domain', 'a host name, such as acorn.transasim.com');
    final url = c['apiBaseUrl'];
    if (url != null && !RegExp('^https://${RegExp.escape(domain)}(/[A-Za-z0-9._~/-]*)?\$').hasMatch('$url')) {
      field('apiBaseUrl', 'https:// on the domain, such as https://$domain/api');
    }
    final port = c['port'];
    if (port != null && (port is! int || port < 1024 || port > 65535)) field('port', 'a number from 1024 to 65535');
    if (c['dir'] != null && !RegExp(r'^/apps/[a-z0-9][a-z0-9._-]*$').hasMatch('${c['dir']}')) {
      field('dir', 'a folder under /apps, such as /apps/acorn-backend');
    }
    if (c['db'] != null && !RegExp(r'^[a-z_][a-z0-9_]{0,62}$').hasMatch('${c['db']}')) {
      field('db', 'a Postgres database name: lowercase letters, digits, underscores');
    }
    if (c['name'] != null && !RegExp(r'^[a-z][a-z0-9-]{1,40}$').hasMatch('${c['name']}')) {
      field('name', "the backend's name on the box: lowercase letters, digits, hyphens");
    }
    if (c['jar'] != null && !RegExp(r'^[A-Za-z0-9._-]+\.jar$').hasMatch('${c['jar']}')) {
      field('jar', 'a jar file name, such as acorn-backend.jar');
    }
    if (c['restartMethod'] != null && !const {'systemd', 'scripts'}.contains(c['restartMethod'])) {
      field('restartMethod', 'systemd or scripts');
    }
    if (c['shellUser'] != null && !RegExp(r'^[a-z_][a-z0-9_-]{0,31}$').hasMatch('${c['shellUser']}')) {
      field('shellUser', 'a Unix user name');
    }
    final key = c['stripePublishableKeyTest'];
    if (key != null && env == 'prod') {
      field('stripePublishableKeyTest', "a PROD backend has no test key: PROD uses brand.json's own key");
    } else if (key != null && !usableStripeKey('$key', mode: 'test')) {
      field('stripePublishableKeyTest', 'a Stripe pk_test_ key (never a live one on DEV)');
    }
    for (final e in ((c['sharedReasons'] as Map?) ?? const {}).entries) {
      if (!_sharedGroups.contains(e.key)) field('sharedReasons.${e.key}', 'one of ${_sharedGroups.join(', ')}');
      if ('${e.value}'.trim().isEmpty) field('sharedReasons.${e.key}', 'say why the secret is shared');
    }

    // What must be unique: per server, and the domain everywhere.
    for (final MapEntry(key: other, value: studio) in others.entries) {
      for (final oenv in const ['dev', 'prod']) {
        final o = ((studio['backend'] as Map?)?[oenv] as Map?) ?? const {};
        if (o.isEmpty) continue;
        if (o['domain'] == c['domain'] && c['domain'] != null) field('domain', '$other uses ${c['domain']} too');
        if (o['server'] != c['server']) continue;
        for (final f in const ['port', 'dir', 'db', 'name']) {
          if (c[f] != null && o[f] == c[f]) field(f, '$other uses ${c[f]} on ${c['server']} too');
        }
      }
      final otherKey = ((((studio['backend'] as Map?)?['dev']) as Map?) ?? const {})['stripePublishableKeyTest'];
      if (key != null && otherKey == key) field('stripePublishableKeyTest', '$other uses this key too');
    }
  }
  return out;
}

// ---- the commands Studio prints ---------------------------------------------------

typedef Command = ({String title, String text});

/// The commands for [slug]'s backend on [env] (§16.11), filled from the
/// registry and the Backend tab. [reportMethod] is the fresh report's restart
/// method, which wins over the recorded one.
List<Command> backendCommands({
  required String slug,
  required String env,
  required Map<String, dynamic> cfg,
  required Server server,
  required Map<String, bool?> features,
  String? googleClientId,
  String? reportMethod,
}) {
  final root = (cfg['shellUser'] ?? server.sshUser) == 'root';
  final sudo = root ? '' : 'sudo ';
  final name = cfg['name'];
  final method = switch (reportMethod) {
    'systemd' => 'systemd',
    'startup.sh' => 'scripts',
    _ => cfg['restartMethod'],
  };
  return [
    (title: 'Log in to ${server.id} (${server.expectedHostname})', text: 'ssh -p ${server.sshPort} ${cfg['shellUser'] ?? server.sshUser}@${server.host}'),
    (
      title: 'Run the checker: read-only, prints one JSON line to paste back',
      text: [
        '$sudo~/spc-check/spc-backend-check.sh --slug $name --dir ${cfg['dir']} --db ${cfg['db']}',
        '--pgport ${server.pgPort} --port ${cfg['port']} --domain ${cfg['domain']}',
        '--expect-host ${server.expectedHostname} --public-ip ${server.host}',
        if (features['google'] == true && googleClientId != null) '--google-client $googleClientId',
        if (features['payments'] == true) '--stripe-account',
      ].join(' '),
    ),
    if (method == 'systemd')
      (
        title: 'Restart $name (systemd; never bin/startup.sh: it would start a second JVM on ${cfg['port']})',
        text: '${sudo}systemctl restart $name',
      )
    else
      (title: 'Restart $name (its own scripts: stop, then start)', text: 'cd ${cfg['dir']} && ${sudo}bin/shutdown.sh && ${sudo}bin/startup.sh'),
    if (server.scripts.isEmpty)
      (
        title: "This box's own scripts (install.sh, deploy.sh)",
        text: '# script unknown: no server report has described them on ${server.id} yet',
      )
    else
      for (final MapEntry(key: script, value: s) in server.scripts.entries)
        for (final sub in (s['use'] ?? 'check').split(','))
          (title: '$script ${sub.trim()} (${s['path']})', text: '$sudo${s['path']} ${sub.trim()}'),
  ];
}

String renderCommands(List<Command> commands) =>
    [for (final c in commands) '## ${c.title}\n${c.text}\n'].join('\n');

const _checkerFiles = ['spc-backend-check.sh', 'ymlmap.py', 'sharecheck.py'];
const _eof = 'SPC_STUDIO_EOF';

/// The checker's files with their SHA-256, as Studio shows them.
List<({String name, String sha256})> checkerFiles(String root) => [
      for (final f in _checkerFiles)
        (name: f, sha256: sha256.convert(File('$root/$backendScriptsDir/$f').readAsBytesSync()).toString()),
    ];

/// One paste that writes the checker to ~/spc-check on a server and prints
/// the SHA-256 of each file, to compare with [checkerFiles].
String checkerInstallSnippet(String root) => [
      'mkdir -p ~/spc-check && cd ~/spc-check',
      for (final f in _checkerFiles) "cat > $f <<'$_eof'\n${File('$root/$backendScriptsDir/$f').readAsStringSync()}$_eof",
      'chmod 700 ${_checkerFiles.join(' ')}',
      'sha256sum ${_checkerFiles.join(' ')}',
      '',
    ].join('\n');

// ---- what the tab shows, and what it writes ------------------------------------------

const referenceSchemaFile = '$backendScriptsDir/reference-schema.json';

/// The brand whose DEV database is the schema reference (§16.8).
const referenceBrand = 'sabily';

/// Probes older than this do not open a gate.
const probeMaxAge = Duration(hours: 1);

Map<String, dynamic> _readBrand(String root, String slug) =>
    jsonDecode(File('$root/brands/$slug/brand.json').readAsStringSync()) as Map<String, dynamic>;

Map<String, Map<String, dynamic>> _otherStudios(String root, String slug) => {
      for (final s in brandSlugs(root))
        if (s != slug) s: readStudio(root, s),
    };

/// The reference schema's hashes, or null before "Use as schema reference";
/// `{outdated: true}` when an older checker hashed them.
Map<String, Object?>? readReference(String root) {
  final f = File('$root/$referenceSchemaFile');
  if (!f.existsSync()) return null;
  final j = jsonDecode(f.readAsStringSync()) as Map;
  if (j['schemaVersion'] != reportSchemaVersion) return const {'outdated': true};
  return (j['schema'] as Map).cast();
}

/// The items of [slug]'s backend on [env], from the newest reports and
/// [probes]; null with the reason when the env is not entered yet.
({List<ItemResult>? items, String? error, StoredReport? report}) evaluateStored(String root, String slug, String env,
    {required Map<String, Incident> items, Map<String, Object?>? probes, required DateTime now}) {
  final studio = readStudio(root, slug);
  final cfg = ((studio['backend'] as Map?)?[env] as Map?) ?? const {};
  final server = loadServers(root)[cfg['server']];
  if (server == null) return (items: null, error: 'Enter the ${env.toUpperCase()} backend first.', report: null);
  final report = latestReport(root, slug, env, backend: cfg['name'] as String?, now: now);
  try {
    return (
      items: evaluateBackend(
        BackendView(
          slug: slug,
          env: env,
          brand: _readBrand(root, slug),
          studio: studio,
          server: server,
          report: report?.fresh == true ? report!.report : null,
          reportStale: report != null && !report.fresh,
          serverReport: switch (latestServerReport(root, server.id, now: now)) { final r? when r.fresh => r.report, _ => null },
          probes: probes,
          reference: readReference(root),
          others: _otherStudios(root, slug),
          iosFlavor: File('$root/ios/Flutter/$slug.xcconfig').existsSync(),
          now: now,
        ),
        items,
      ),
      error: null,
      report: report,
    );
  } on ArgumentError catch (e) {
    return (items: null, error: '${e.message}', report: report);
  }
}

/// Everything the Backend tab shows for [slug] on [env].
Map<String, Object?> backendState(String root, String slug, String env,
    {required Map<String, Incident> items, Map<String, Object?>? probes, required DateTime now}) {
  final studio = readStudio(root, slug);
  final backend = (studio['backend'] as Map?)?.cast<String, dynamic>() ?? {};
  final cfg = (backend[env] as Map?)?.cast<String, dynamic>() ?? {};
  final servers = loadServers(root);
  final server = servers[cfg['server']];
  final brand = _readBrand(root, slug);
  final e = evaluateStored(root, slug, env, items: items, probes: probes, now: now);
  final features = backendFeatures(BackendView(
      slug: slug, env: env, brand: brand, studio: studio, server: server ?? servers.values.first,
      iosFlavor: File('$root/ios/Flutter/$slug.xcconfig').existsSync(), now: now));
  final ref = File('$root/$referenceSchemaFile');
  // Every CHECK difference still to accept, for the tab to offer: the item's reason names four.
  final reference = readReference(root);
  final mine = e.report?.fresh == true && e.report!.report['schema_version'] == reportSchemaVersion
      ? _map(e.report!.report['schema'])
      : const <String, Object?>{};
  final schemaChecks = reference?['tables'] is Map && mine.isNotEmpty
      ? schemaDifferences(reference!, mine, _map(backend['schemaAccepted'])).checks
      : const <String>[];
  return {
    'env': env,
    'schemaChecks': schemaChecks,
    'activeEnv': backend['activeEnv'] ?? 'dev',
    if (env == 'prod') ...{
      'goProd': [
        for (final (id, why) in goProdBlockers(root, slug, items: items, probes: probes, now: now)) {'id': id, 'reason': why},
      ],
      'releaseCheck': releaseRefusal(root, slug, items: items, probes: probes, now: now),
    },
    'legacy': isLegacy(studio),
    'backend': backend,
    'features': features,
    'servers': [for (final s in servers.values) s.toJson()],
    'error': e.error,
    'report': e.report == null
        ? null
        : {
            'at': e.report!.at.toIso8601String(),
            'fresh': e.report!.fresh,
            'hostname': e.report!.report['hostname'],
            'scriptVersion': e.report!.report['script_version'],
            'jar': e.report!.report['jar_sha256_16'],
            'restartMethod': e.report!.report['restart_method'],
          },
    'probesAt': probes?['at'],
    'items': [for (final r in e.items ?? const <ItemResult>[]) r.toJson()],
    'gates': {
      for (final g in const ['test', 'release']) g: [for (final r in blockers(e.items ?? const [], g)) r.id],
    },
    'commands': server == null
        ? const []
        : [
            for (final c in backendCommands(
                slug: slug,
                env: env,
                cfg: cfg,
                server: server,
                features: features,
                googleClientId: (brand['mobile'] as Map?)?['googleServerClientId'] as String?,
                reportMethod: e.report?.fresh == true ? e.report!.report['restart_method'] as String? : null))
              {'title': c.title, 'text': c.text},
          ],
    'checker': {
      'files': [for (final f in checkerFiles(root)) {'name': f.name, 'sha256': f.sha256}],
      'install': checkerInstallSnippet(root),
    },
    'reference': {
      'brand': referenceBrand,
      'exists': ref.existsSync(),
      if (ref.existsSync()) 'generatedAt': (jsonDecode(ref.readAsStringSync()) as Map)['generatedAt'],
    },
  };
}

/// The Backend tab's Apply: the edited `backend` section, and ticks of the
/// manual backend items, under every rule of studio.json. Go phase 2 and Go
/// prod own `phase2`, `prodAt` and `activeEnv`: the form cannot write them.
Plan backendPlan(String root, String slug, Map<String, dynamic> edited,
    {Map<String, Object?> ticks = const {}, required Map<String, Incident> items, required DateTime now}) {
  final studio = readStudio(root, slug);
  final current = (studio['backend'] as Map?)?.cast<String, dynamic>() ?? {};
  final backend = {...edited};
  // The form creates these as it renders: empty, they are not written.
  if ((backend['features'] as Map?)?.isEmpty ?? false) backend.remove('features');
  if ((backend['schemaLedger'] as List?)?.isEmpty ?? false) backend.remove('schemaLedger');
  for (final k in const ['phase2', 'prodAt', 'activeEnv']) {
    if (current.containsKey(k)) {
      backend[k] = current[k];
    } else {
      backend.remove(k);
    }
  }
  final next = {...studio, 'backend': backend};
  final refused = <String>[];
  if (ticks.isNotEmpty) {
    final checklist = {...((studio['checklist'] as Map?) ?? const {})};
    for (final MapEntry(key: id, value: tick) in ticks.entries) {
      final item = items[id];
      if (item == null || item.env == null || item.kind != 'checklist') {
        refused.add(id);
      } else if (tick == null) {
        checklist.remove(id);
      } else {
        final t = (tick as Map).cast<String, Object?>();
        checklist[id] = {'note': '${t['note'] ?? ''}'.trim(), 'evidence': '${t['evidence'] ?? ''}'.trim(), 'at': now.toUtc().toIso8601String()};
      }
    }
    next['checklist'] = checklist;
  }
  final plan = integrationsPlan(root, slug, _readBrand(root, slug), next);
  for (final id in refused) {
    plan.error('checklist.$id', 'not a backend item a person ticks');
  }
  for (final (field, reason) in backendProblems(slug, backend, servers: loadServers(root), others: _otherStudios(root, slug))) {
    plan.error(field, reason);
  }
  return plan;
}

/// Go phase 2 (§16.10): open only when gate test is green on DEV, with a
/// report from the last 24 h and probes from the last hour. It records when,
/// the DEV jar's hash and the backend commit Alpha names.
Plan phase2Plan(String root, String slug, String commit,
    {required Map<String, Incident> items, Map<String, Object?>? probes, required DateTime now}) {
  final studio = readStudio(root, slug);
  final backend = (studio['backend'] as Map?)?.cast<String, dynamic>() ?? {};
  final problems = <(String, String)>[];
  final e = evaluateStored(root, slug, 'dev', items: items, probes: probes, now: now);
  if (isLegacy(studio)) {
    problems.add(('backendGate', '$slug is a legacy brand: its backend items are information only, and there is no Go phase 2'));
  }
  if (e.error != null) problems.add(('backend.dev', e.error!));
  if (e.report?.fresh != true) problems.add(('report', 'paste a report from the last 24 h'));
  final probedAt = DateTime.tryParse('${probes?['at']}');
  if (probedAt == null || now.difference(probedAt) > probeMaxAge) {
    problems.add(('probes', 'press Check: the probes must be from the last hour'));
  }
  for (final b in blockers(e.items ?? const [], 'test')) {
    problems.add((b.id, b.reason));
  }
  if (!RegExp(r'^[0-9a-f]{7,40}$').hasMatch(commit)) {
    problems.add(('backendCommit', "the backend's git commit, 7 to 40 hex characters (54dd318 on 2026-10-11)"));
  }
  final next = {
    ...studio,
    'backend': {
      ...backend,
      'activeEnv': backend['activeEnv'] ?? 'dev',
      'phase2': {'at': now.toUtc().toIso8601String(), 'jarSha256': e.report?.report['jar_sha256_16'], 'backendCommit': commit},
    },
  };
  final plan = integrationsPlan(root, slug, _readBrand(root, slug), next);
  for (final (field, reason) in problems) {
    plan.error(field, reason);
  }
  return plan;
}

/// "Use as schema reference" (§16.8): the reference brand's fresh DEV report's
/// schema hashes, written to tool/studio/backend/reference-schema.json.
Plan referencePlan(String root, String slug, {required DateTime now}) {
  final plan = Plan();
  final name = ((readStudio(root, slug)['backend'] as Map?)?['dev'] as Map?)?['name'] as String?;
  final report = latestReport(root, slug, 'dev', backend: name, now: now);
  if (slug != referenceBrand) plan.error('reference', "only $referenceBrand's DEV database is the reference");
  if (report?.fresh != true) plan.error('report', "paste $slug's DEV report from the last 24 h first");
  final schema = report?.report['schema'];
  if (report?.fresh == true && schema == null) plan.error('report', 'that report has no schema: its database did not answer');
  if (plan.errors.isNotEmpty) return plan;
  final f = File('$root/$referenceSchemaFile');
  plan.text.add(FileChange(
    referenceSchemaFile,
    f.existsSync() ? f.readAsStringSync() : null,
    '${const JsonEncoder.withIndent('  ').convert({
          'from': '$slug DEV on ${report!.server} (${report.report['hostname']}), database as the checker hashed it',
          'schemaVersion': reportSchemaVersion,
          'generatedAt': report.report['generated_at'],
          'schema': schema,
        })}\n',
  ));
  return plan;
}

/// The Fix Bundle's Backend section: the newest report and what is not
/// green on the brand's active env. Null for a brand with no backend yet.
String? backendSummary(String root, String slug, {required Map<String, Incident> items, required DateTime now}) {
  final studio = readStudio(root, slug);
  final backend = (studio['backend'] as Map?) ?? const {};
  if (backend.isEmpty) return null;
  final env = '${backend['activeEnv'] ?? 'dev'}';
  final e = evaluateStored(root, slug, env, items: items, now: now);
  String clip(String s) => s.length <= 160 ? s : '${s.substring(0, 160)}…';
  final open = [
    for (final r in e.items ?? const <ItemResult>[])
      // Probes are not run for a bundle: only what the report and the data say.
      if (const {'fail', 'warn', 'stale', 'unknown'}.contains(r.status) && !r.reason.startsWith('not probed'))
        '- ${r.id} (${r.status}): ${clip(r.reason)}',
  ];
  return [
    '### Backend (${env.toUpperCase()}${isLegacy(studio) ? ', legacy: information only' : ''})',
    if (e.error != null) e.error!,
    if (e.report == null)
      '- No report pasted yet.'
    else
      '- Report from ${e.report!.report['hostname']} at ${e.report!.at.toIso8601String()}'
          '${e.report!.fresh ? '' : ' (stale: older than 24 h)'}, jar ${e.report!.report['jar_sha256_16']}',
    if (open.isEmpty && e.items != null) '- Nothing failing in the report (probes not run here).',
    ...open.take(12),
    if (open.length > 12) '- and ${open.length - 12} more',
  ].join('\n');
}

// ---- Go prod, the release check, the runbook (G2) ------------------------------------

/// Checked when a release is built, from the brand's own data rather than a
/// server: the runbook lists them last, and [releaseRefusal] checks them.
const releaseChecks = ['release-points-at-dev', 'apple-account-deletion'];

bool _paymentsOn(String root, String slug, Map<String, dynamic> studio, Map<String, dynamic> brand) =>
    backendFeatures(BackendView(
        slug: slug, env: 'prod', brand: brand, studio: studio, server: loadServers(root).values.first,
        iosFlavor: false, now: DateTime.now()))['payments'] ==
    true;

/// What still holds Go prod, as (item, reason): a fresh PROD report and
/// probes, every release item on PROD, and the DEV items a release waits on.
List<(String, String)> goProdBlockers(String root, String slug,
    {required Map<String, Incident> items, Map<String, Object?>? probes, required DateTime now}) {
  final out = <(String, String)>[];
  final e = evaluateStored(root, slug, 'prod', items: items, probes: probes, now: now);
  if (e.error != null) out.add(('backend.prod', e.error!));
  if (e.report?.fresh != true) out.add(('report', 'paste a PROD report from the last 24 h'));
  final probedAt = DateTime.tryParse('${probes?['at']}');
  if (probedAt == null || now.difference(probedAt) > probeMaxAge) {
    out.add(('probes', 'press Check on PROD: the probes must be from the last hour'));
  }
  for (final b in blockers(e.items ?? const [], 'release')) {
    out.add((b.id, b.reason));
  }
  final d = evaluateStored(root, slug, 'dev', items: items, now: now);
  for (final b in blockers(d.items ?? const [], 'release')) {
    out.add((b.id, b.reason));
  }
  return out;
}

/// Go prod (§16.10, option B): open when every release item passes. Its
/// previewed Apply points brand.json's apiBaseUrl at the PROD backend's own
/// hostname (and writes the pk_live_ key, with payments), and records
/// `activeEnv: prod` with the time. Never commits.
Plan goProdPlan(String root, String slug,
    {String? stripeKeyLive, required Map<String, Incident> items, Map<String, Object?>? probes, required DateTime now}) {
  final studio = readStudio(root, slug);
  final brand = _readBrand(root, slug);
  final backend = (studio['backend'] as Map?)?.cast<String, dynamic>() ?? {};
  final dev = _map(backend['dev']), prod = _map(backend['prod']);
  final problems = <(String, String)>[];
  if (isLegacy(studio)) {
    problems.add(('backendGate', '$slug is a legacy brand: its backend items are information only, and there is no Go prod'));
  }
  if (backend['phase2'] == null) problems.add(('phase2', 'Go phase 2 first'));
  if (prod['apiBaseUrl'] == null) {
    problems.add(('backend.prod', 'enter the PROD backend and Apply it first'));
  } else if (prod['apiBaseUrl'] == dev['apiBaseUrl'] || prod['domain'] == dev['domain']) {
    problems.add(('backend.prod.domain',
        'PROD needs its own hostname (option B, STUDIO-SPEC §16.10): DEV already uses ${dev['domain']}'));
  }
  problems.addAll(goProdBlockers(root, slug, items: items, probes: probes, now: now));
  final mobile = {
    ...(brand['mobile'] as Map).cast<String, dynamic>(),
    if (prod['apiBaseUrl'] != null) 'apiBaseUrl': prod['apiBaseUrl'],
  };
  if (_paymentsOn(root, slug, studio, brand)) {
    final key = stripeKeyLive ?? mobile['stripePublishableKey'] as String?;
    if (usableStripeKey(key, mode: 'live')) {
      mobile['stripePublishableKey'] = key;
    } else {
      problems.add(('mobile.stripePublishableKey',
          "payments are on: paste the brand's pk_live_ key, from the same Stripe account as PROD's secret key"));
    }
  }
  final plan = integrationsPlan(root, slug, {...brand, 'mobile': mobile}, {
    ...studio,
    'backend': {...backend, 'activeEnv': 'prod', 'prodAt': now.toUtc().toIso8601String()},
  });
  for (final (field, reason) in problems) {
    plan.error(field, reason);
  }
  return plan;
}

/// Why a release of [slug] must not be built now; empty when it may. Slice E's
/// release job asks this first. A legacy brand is never stopped.
List<String> releaseRefusal(String root, String slug,
    {required Map<String, Incident> items, Map<String, Object?>? probes, required DateTime now}) {
  final studio = readStudio(root, slug);
  if (isLegacy(studio)) return const [];
  final brand = _readBrand(root, slug);
  final backend = _map(studio['backend']);
  final dev = _map(backend['dev']), prod = _map(backend['prod']);
  final mobile = _map(brand['mobile']);
  final url = mobile['apiBaseUrl'];
  final key = mobile['stripePublishableKey'] as String?;
  final payments = _paymentsOn(root, slug, studio, brand);
  final onProd = backend['activeEnv'] == 'prod';
  final deletion = '${_map(brand['legal'])['accountDeletionUrl'] ?? ''}';
  return [
    if (!onProd) 'Go prod first: the backend phase is still on DEV',
    if (prod['apiBaseUrl'] == null || url != prod['apiBaseUrl'] || url == dev['apiBaseUrl'])
      'release-points-at-dev: brand.json apiBaseUrl is $url, not the PROD backend${prod['apiBaseUrl'] == null ? '' : ' ${prod['apiBaseUrl']}'}',
    if (payments && !usableStripeKey(key, mode: 'live'))
      'release-points-at-dev: payments are on, and brand.json has no pk_live_ key',
    if (!payments && usableStripeKey(key, mode: 'test')) 'release-points-at-dev: a usable pk_test_ key would ship in a release',
    if (!deletion.startsWith('https://'))
      'apple-account-deletion: legal.accountDeletionUrl is not set, so the app hides "Delete my account" (Apple 5.1.1(v))',
    if (onProd)
      for (final (id, why) in goProdBlockers(root, slug, items: items, probes: probes, now: now)) '$id: $why',
  ];
}

/// The written runbook for [slug]'s backend on [env] (§16.11): the commands,
/// then every item in the evaluators' order. It is built from the same entries
/// as the checklist, so the two cannot drift.
String backendRunbook(String root, String slug, String env, {required Map<String, Incident> items}) {
  final studio = readStudio(root, slug);
  final brand = _readBrand(root, slug);
  final cfg = (_map(studio['backend'])[env] as Map?)?.cast<String, dynamic>() ?? {};
  final servers = loadServers(root);
  final server = servers[cfg['server']];
  final features = backendFeatures(BackendView(
      slug: slug, env: env, brand: brand, studio: studio, server: server ?? servers.values.first,
      iosFlavor: File('$root/ios/Flutter/$slug.xcconfig').existsSync(), now: DateTime.now()));
  final name = env.toUpperCase();
  final lines = <String>[
    '# ${brand['name']}: the $name backend, step by step',
    '',
    "Generated by Studio from tool/studio/incidents/ and tool/studio/servers.yaml: this page and the Backend tab's "
        'checklist are the same entries. Studio never runs these commands: you do, then paste the checker\'s report back.',
    if (isLegacy(studio)) ...['', '${brand['name']} is a legacy brand: these items are information only.'],
    '',
    '## Commands',
    if (server == null) ...['', 'Enter the $name backend in the Backend tab first.'],
    if (server != null)
      for (final c in backendCommands(
          slug: slug, env: env, cfg: cfg, server: server, features: features,
          googleClientId: _map(brand['mobile'])['googleServerClientId'] as String?))
        ...['', '### ${c.title}', '```', c.text, '```'],
    '',
    '## Steps',
  ];
  var n = 0;
  for (final id in backendEvaluators.keys) {
    final item = items[id]!;
    if (item.env != 'both' && item.env != 'server' && item.env != env) continue;
    final notes = [
      'gate ${env == 'prod' && item.env != 'prod' ? 'release' : item.gate}',
      if (item.severity[env] == 'warn') 'warns only',
      if (item.when.isNotEmpty) 'when ${item.when.join(' and ')}',
      if (item.env == 'server') 'once per server',
    ];
    lines.addAll([
      '',
      '${++n}. **${item.title}** (`$id`; ${notes.join('; ')})',
      '   - Why: ${item.cause}',
      '   - Do: ${item.fix}',
      if (item.acceptedRisk != null) '   - Accepted risk: ${item.acceptedRisk}',
    ]);
  }
  if (env == 'prod') {
    lines.addAll(['', '## Before a release build']);
    for (final id in releaseChecks) {
      lines.addAll(['', '- **${items[id]!.title}** (`$id`)', '  - Do: ${items[id]!.fix}']);
    }
  }
  return '${lines.join('\n')}\n';
}
