/// The SPC intake (Slice I): `spc-intake-<slug>.json`, written by the
/// onboarding portal (SPC-easy-submit, `src/lib/intakeJson.ts`) into each
/// SPC's Drive folder. Untrusted public input: read strictly, never fetched
/// from, never rendered as HTML, and turned into brand.json and studio.json
/// values only through a previewed Apply.
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:transasim_mobile/core/brand/brand_config.dart';
import 'package:transasim_mobile/core/i18n/country_codes.g.dart';
import 'package:transasim_mobile/core/i18n/country_names.g.dart';
import 'package:transasim_mobile/core/i18n/fold.dart';
import 'package:transasim_mobile/core/i18n/locales.dart';

import '../../gen_brand_flavors.dart' show brandSlugs;
import 'assets.dart';
import 'distinct.dart';
import 'generate.dart';
import 'icons.dart' show tryDecode;

const intakeMaxBytes = 256 * 1024;
const _zipMaxEntries = 40;
const _zipMaxBytes = 25 * 1024 * 1024;
const _maxString = 2000;

/// The contract's keys, top level and `values` (intakeJson.ts VALUE_SECTIONS).
const _topKeys = {'kind', 'schemaVersion', 'submissionId', 'submittedAt', 'locale', 'values', 'files', 'strippedPaths'};
const _sections = {
  'company', 'scope', 'branding', 'legal', 'business', 'registration', 'google_cloud', 'transatel', 'smtp',
  'infrastructure', 'attachments',
};

/// The portal's own SECRET_PATTERNS: a value shaped like one refuses the file.
final _secrets = [
  RegExp('sk_', caseSensitive: false),
  RegExp('pk_live', caseSensitive: false),
  RegExp('eyJ'),
  RegExp('BEGIN ', caseSensitive: false),
  RegExp('password', caseSensitive: false),
];

final _hex = RegExp(r'^#[0-9a-fA-F]{6}$');
final _host = RegExp(r'^(?=.{4,253}$)([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$');
final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[a-z]{2,63}$', caseSensitive: false);

/// Hosts that hand out a file from someone's own storage rather than serve a
/// page. The portal lets a client upload a document when it has no page yet,
/// and the link it returns is one of these.
const _fileHosts = {'drive.google.com', 'docs.google.com', 'drive.usercontent.google.com'};

/// What the app can do with a legal URL the client gave.
enum LegalUrl {
  /// An https page the app can link to: it goes into brand.json.
  page,

  /// A file (a Drive link, or an upload the portal put there): host it first.
  host,

  /// Nothing given.
  blank,

  /// Not an https address at all (`http://`, a bare domain, a sentence).
  bad,
}

/// Where [url] belongs. [isPdf] when `files[]` says the client uploaded a
/// document for this field instead of giving a page.
LegalUrl classifyLegalUrl(String url, {bool isPdf = false}) {
  final text = url.trim();
  if (text.isEmpty) return LegalUrl.blank;
  final u = Uri.tryParse(text);
  if (u == null || u.scheme != 'https' || !u.host.contains('.')) return LegalUrl.bad;
  return isPdf || _fileHosts.contains(u.host.toLowerCase()) ? LegalUrl.host : LegalUrl.page;
}

/// A file the page sent: its name as dropped and its bytes.
class Dropped {
  const Dropped(this.name, this.bytes);
  final String name;
  final List<int> bytes;
}

/// One line of what the intake says, for the page and the plans.
/// [kind]: client (a value to apply), suggested (Studio's, never the file's),
/// info, ask (ask the client), todo (work for us), dropped (malformed).
class IntakeRow {
  const IntakeRow(this.kind, this.path, this.value, {this.from, this.note, this.suggestion = false});
  final String kind;
  final String path;
  final Object? value;
  final String? from;
  final String? note;

  /// A client value Studio offers but does not presume (the colours).
  final bool suggestion;

  Map<String, Object?> toJson() =>
      {'kind': kind, 'path': path, 'value': value, 'from': ?from, 'note': ?note, if (suggestion) 'suggestion': true};

  @override
  String toString() => '$kind $path = $value${note == null ? '' : ' ($note)'}';
}

class IntakeRead {
  IntakeRead.refused(this.refusal)
      : json = const {},
        text = '',
        rows = const [],
        mark = null;
  IntakeRead._(this.json, this.text, this.rows, this.mark) : refusal = null;

  final String? refusal;
  final Map<String, dynamic> json;

  /// The intake as dropped, which the page sends back with each preview.
  final String text;
  final List<IntakeRow> rows;

  /// The logo mark's bytes, when the dropped files held it.
  final List<int>? mark;

  String get submissionId => '${json['submissionId']}';
  String get source => 'client intake $submissionId';

  Map<String, Object?> toJson() => {
        'refusal': ?refusal,
        if (refusal == null) ...{
          'submissionId': submissionId,
          'submittedAt': json['submittedAt'],
          'text': text,
          'rows': [for (final r in rows) r.toJson()],
          if (mark != null) 'mark': base64Encode(mark!),
          if (mark != null) 'markPreview': ?switch (tryDecode(mark!)) { final i? => thumbnail(i), _ => null },
        },
      };
}

/// Reads what was dropped: the intake JSON, a zip of the Drive folder, or
/// loose files. Never throws; a refusal names the reason.
IntakeRead readIntake(List<Dropped> dropped) {
  final files = <Dropped>[];
  for (final d in dropped) {
    final zip = d.bytes.length > 3 && d.bytes[0] == 0x50 && d.bytes[1] == 0x4b && d.bytes[2] == 3 && d.bytes[3] == 4;
    if (!zip) {
      files.add(Dropped(_base(d.name), d.bytes));
      continue;
    }
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(d.bytes);
    } on Object {
      return IntakeRead.refused('${d.name} is not a zip Studio can read');
    }
    final entries = archive.files.where((f) => f.isFile).toList();
    if (entries.length > _zipMaxEntries) {
      return IntakeRead.refused('${d.name} holds ${entries.length} files; an intake folder has at most $_zipMaxEntries');
    }
    // The headers' sizes, before anything is inflated; the real sizes again after.
    if (entries.fold<int>(0, (n, f) => n + f.size) > _zipMaxBytes) {
      return IntakeRead.refused('${d.name} would inflate to more than 25 MB');
    }
    var total = 0;
    for (final f in entries) {
      final bytes = f.readBytes() ?? const <int>[];
      total += bytes.length;
      if (total > _zipMaxBytes) return IntakeRead.refused('${d.name} would inflate to more than 25 MB');
      files.add(Dropped(_base(f.name), bytes));
    }
  }
  final jsons = files.where((f) => f.name.toLowerCase().endsWith('.json')).toList();
  final intakes = jsons.where((f) => f.name.toLowerCase().startsWith('spc-intake')).toList();
  // The zip and its own JSON dropped together are one intake: identical copies count once.
  final seen = <String>{};
  final pick = [
    for (final f in intakes.isNotEmpty ? intakes : jsons)
      if (seen.add(sha256.convert(f.bytes).toString())) f,
  ];
  if (pick.isEmpty) return IntakeRead.refused('no spc-intake-<slug>.json among the dropped files');
  if (pick.length > 1) return IntakeRead.refused('two intake files were dropped (${pick.map((f) => f.name).join(', ')}): drop one');
  return parseIntake(pick.single.bytes, files);
}

/// The last segment of a dropped or zipped path: names are matched, never used as paths.
String _base(String name) => name.split(RegExp(r'[\\/]')).last;

/// Checks [bytes] against contract v1, then maps it. [files] are the other
/// dropped files, where the logo is looked for.
IntakeRead parseIntake(List<int> bytes, [List<Dropped> files = const []]) {
  if (bytes.length > intakeMaxBytes) return IntakeRead.refused('the intake is over 256 KB');
  final String text;
  final Object? decoded;
  try {
    text = utf8.decode(bytes);
    decoded = jsonDecode(text);
  } on FormatException catch (e) {
    return IntakeRead.refused('not JSON: ${e.message}');
  }
  if (decoded is! Map<String, dynamic>) return IntakeRead.refused('not an intake: expected a JSON object');
  final j = decoded;
  if (j['kind'] != 'spc-intake') return IntakeRead.refused('not an intake: kind must be "spc-intake"');
  if (j['schemaVersion'] != 1) {
    return IntakeRead.refused('schemaVersion ${j['schemaVersion']} is not one Studio reads (it reads 1)');
  }
  for (final k in j.keys) {
    if (!_topKeys.contains(k)) return IntakeRead.refused('unknown key "$k": contract v1 has no such field');
  }
  if (j['values'] is! Map) return IntakeRead.refused('values must be an object');
  for (final k in (j['values'] as Map).keys) {
    if (!_sections.contains(k)) return IntakeRead.refused('unknown section values.$k');
  }
  if (!RegExp(r'^[A-Za-z0-9-]{1,64}$').hasMatch('${j['submissionId']}')) {
    return IntakeRead.refused('submissionId must be letters, digits and hyphens');
  }
  if (DateTime.tryParse('${j['submittedAt']}') == null) return IntakeRead.refused('submittedAt is not a date');
  if (j['files'] is! List || j['strippedPaths'] is! List) return IntakeRead.refused('files and strippedPaths must be lists');
  if ((j['files'] as List).length > 50) return IntakeRead.refused('more than 50 files');
  for (final (i, f) in (j['files'] as List).indexed) {
    if (f is! Map || f['field'] is! String || f['name'] is! String) {
      return IntakeRead.refused('files[$i] needs a field and a name');
    }
  }
  // strippedPaths name what the portal removed ("smtp.password_id"): paths, not values.
  for (final (i, p) in (j['strippedPaths'] as List).indexed) {
    if (p is! String || !RegExp(r'^[a-z0-9_]+(\.[a-z0-9_]+){0,6}$').hasMatch(p)) {
      return IntakeRead.refused('strippedPaths[$i] is not a field path');
    }
  }
  if (_scan({...j}..remove('strippedPaths'), '') case final why?) return IntakeRead.refused(why);
  return _map(j, text, files);
}

/// The first string that is too long or shaped like a secret, by its path; the value is never echoed.
String? _scan(Object? node, String path, [int depth = 0]) {
  if (depth > 8) return '$path is nested deeper than an intake is';
  if (node is String) {
    if (node.length > _maxString) return '$path is longer than $_maxString characters';
    if (_secrets.any((re) => re.hasMatch(node))) {
      return '$path holds a value shaped like a secret (a key, a token or a password): '
          'the whole file is refused and nothing is kept';
    }
  }
  if (node is List) {
    if (node.length > 100) return '$path has more than 100 entries';
    for (final (i, v) in node.indexed) {
      if (_scan(v, '$path[$i]', depth + 1) case final why?) return why;
    }
  }
  if (node is Map) {
    for (final e in node.entries) {
      if (_scan(e.value, path.isEmpty ? '${e.key}' : '$path.${e.key}', depth + 1) case final why?) return why;
    }
  }
  return null;
}

/// Language names a client writes, beyond the codes and endonyms.
const _languageNames = {
  'english': 'en', 'french': 'fr', 'arabic': 'ar', 'spanish': 'es', 'slovenian': 'sl', 'slovene': 'sl',
  'german': 'de', 'albanian': 'sq', 'francais': 'fr', 'anglais': 'en', 'arabe': 'ar', 'allemand': 'de',
  'espagnol': 'es', 'deutsch': 'de', 'englisch': 'en', 'franzosisch': 'fr',
};

/// ISO 3166 alpha-2 for a country as a person writes it, in any language the
/// app names countries in; null when it is not one.
String? countryCode(String input) {
  final t = input.trim();
  final alpha2 = {...kAlpha3ToAlpha2.values};
  if (RegExp(r'^[A-Za-z]{2}$').hasMatch(t) && alpha2.contains(t.toUpperCase())) return t.toUpperCase();
  if (RegExp(r'^[A-Za-z]{3}$').hasMatch(t)) return kAlpha3ToAlpha2[t.toUpperCase()];
  final q = foldForSearch(t);
  for (final names in kCountryNamesByLanguage.values) {
    for (final MapEntry(key: a3, value: name) in names.entries) {
      if (foldForSearch(name) == q) return kAlpha3ToAlpha2[a3];
    }
  }
  return null;
}

/// A free-text or listed value as a list of trimmed, non-empty strings.
List<String> _list(Object? v) => switch (v) {
      final String s => [for (final p in s.split(RegExp(r'[,;\n]|\band\b'))) if (p.trim().isNotEmpty) p.trim()],
      final List l => [for (final e in l) if (e is String && e.trim().isNotEmpty) e.trim()],
      _ => const [],
    };

int? _port(Object? v) => switch (v) {
      final int p when p > 0 && p < 65536 => p,
      final String s => switch (int.tryParse(s.trim())) { final p? when p > 0 && p < 65536 => p, _ => null },
      _ => null,
    };

/// A slug the app accepts, from a brand name: ASCII letters and digits.
String suggestedSlug(String name) {
  final s = foldForSearch(name).replaceAll(RegExp('[^a-z0-9]'), '');
  final t = s.replaceFirst(RegExp('^[0-9]+'), '');
  return t.length > 20 ? t.substring(0, 20) : t;
}

IntakeRead _map(Map<String, dynamic> j, String text, List<Dropped> files) {
  final v = j['values'] as Map;
  final rows = <IntakeRow>[];
  Object? at(String path) => path.split('.').fold<Object?>(v, (n, k) => n is Map ? n[k] : null);
  String str(String path) => switch (at(path)) { final String s => s.trim(), _ => '' };
  bool flag(String path) => at(path) == true;
  void client(String path, Object? value, String from, {String? note, bool suggestion = false}) =>
      rows.add(IntakeRow('client', path, value, from: from, note: note, suggestion: suggestion));
  void info(String from, Object? value, [String? note]) => rows.add(IntakeRow('info', from, value, from: from, note: note));
  void ask(String path, String note) => rows.add(IntakeRow('ask', path, null, note: note));
  void todo(String path, String note) => rows.add(IntakeRow('todo', path, null, note: note));
  void dropped(String from, Object? value, String why) => rows.add(IntakeRow('dropped', from, value, from: from, note: why));

  // Identity.
  final brandName = str('branding.brand_name');
  final name = brandName.isNotEmpty ? brandName : str('company.spc_name');
  if (name.isEmpty) {
    ask('name', 'the brand name (branding.brand_name is blank)');
  } else {
    client('name', name, brandName.isNotEmpty ? 'branding.brand_name' : 'company.spc_name');
    final slug = suggestedSlug(name);
    if (slug.isNotEmpty) {
      rows
        ..add(IntakeRow('suggested', 'slug', slug, note: 'from the brand name'))
        ..add(IntakeRow('suggested', 'mobile.applicationId', 'com.transasim.$slug',
            note: 'Studio\'s pattern; frozen once published'))
        ..add(IntakeRow('suggested', 'mobile.apiBaseUrl', 'https://$slug.transasim.com/api', note: 'the DEV backend\'s pattern'));
    }
  }
  final android = str('branding.display_names.android_app');
  final ios = str('branding.display_names.ios_app');
  if (android.isNotEmpty) {
    client('mobile.displayName', android, 'branding.display_names.android_app');
  } else if (name.isNotEmpty) {
    client('mobile.displayName', name, brandName.isNotEmpty ? 'branding.brand_name' : 'company.spc_name',
        note: 'display_names.android_app is blank');
  }
  final shown = android.isNotEmpty ? android : name;
  if (ios.isNotEmpty && ios != shown) {
    info('branding.display_names.ios_app', ios, 'the iOS name differs ("$ios"); the app has one name, "$shown"');
  }

  // Legal.
  final legalName = str('company.legal_name');
  if (legalName.isEmpty) {
    ask('legal.companyName', 'the legal company name');
  } else {
    client('legal.companyName', legalName, 'company.legal_name');
  }
  final region = str('company.country_region');
  switch (region.isEmpty ? null : countryCode(region)) {
    case final code?:
      client('legal.country', code, 'company.country_region', note: region == code ? null : '"$region"');
    case null:
      ask('legal.country', region.isEmpty ? 'the country (ISO code)' : '"$region" is not a country Studio knows: ask for its ISO code');
  }
  final pdfFields = {
    for (final f in (j['files'] as List).cast<Map>())
      if ('${f['mime']}' == 'application/pdf' || '${f['name']}'.toLowerCase().endsWith('.pdf')) '${f['field']}',
  };
  // Apple 5.1.1(v) and Play ask for this one; the release check refuses a brand without it.
  const deletionAsk = 'a page or form where a user asks to delete their account (Apple 5.1.1(v), and Play)';
  // A legal URL reaches brand.json only as a page the app can open. A file in
  // the client's Drive is listed to be hosted first (§17).
  for (final (from, path, what) in const [
    ('legal.terms_url', 'legal.termsUrl', 'terms'),
    ('legal.privacy_policy_url', 'legal.privacyUrl', 'privacy policy'),
    ('legal.account_deletion_url', 'legal.accountDeletionUrl', 'account deletion'),
  ]) {
    final url = str(from);
    final isPdf = pdfFields.contains(from);
    final deletion = path == 'legal.accountDeletionUrl';
    switch (classifyLegalUrl(url, isPdf: isPdf)) {
      case LegalUrl.page:
        client(path, url, from);
      case LegalUrl.host:
        todo(path, 'client sent ${isPdf ? 'a PDF' : 'a Drive link'} for the $what: '
            'host this as a public page, then set the URL');
      case LegalUrl.blank:
        ask(path, deletion ? deletionAsk : 'the $what page URL');
      case LegalUrl.bad:
        // Not an address the app can open. The deletion URL is still asked for,
        // because a release without one is refused.
        if (deletion) {
          ask(path, 'the one given is not an https address: $deletionAsk');
        } else {
          dropped(from, url, 'not an https address');
        }
    }
  }
  ask('support.email', 'the public support address (a contact email is never used for it)');
  if (str('legal.refund_policy_url').isNotEmpty) info('legal.refund_policy_url', str('legal.refund_policy_url'), 'the app has no refund link');

  // Colours: suggestions, primary and accent only.
  for (final (from, path) in const [('branding.primary_color_hex', 'colors.primary'), ('branding.accent_color_hex', 'colors.accent')]) {
    final c = str(from);
    if (c.isEmpty) continue;
    if (_hex.hasMatch(c)) {
      client(path, c.toLowerCase(), from, suggestion: true);
    } else {
      dropped(from, c, 'not a #rrggbb colour');
    }
  }
  if (_hex.hasMatch(str('branding.secondary_color_hex'))) {
    info('branding.secondary_color_hex', str('branding.secondary_color_hex').toLowerCase(), 'the app has no secondary colour');
  }

  // Languages: names or codes the app has.
  final codes = <String>[];
  final unknown = <String>[];
  for (final word in _list(at('business.languages'))) {
    final f = foldForSearch(word);
    final code = kSocleSupportedLanguages.contains(f)
        ? f
        : _languageNames[f] ??
            kLanguageEndonyms.entries.where((e) => foldForSearch(e.value) == f).map((e) => e.key).firstOrNull;
    if (code == null) {
      unknown.add(word);
    } else if (!codes.contains(code)) {
      codes.add(code);
    }
  }
  if (codes.isNotEmpty) client('locales', codes, 'business.languages', note: 'the first is the default language');
  if (codes.isEmpty || unknown.isNotEmpty) {
    ask('locales', codes.isEmpty && unknown.isEmpty
        ? 'the app\'s languages (business.languages is blank)'
        : '${unknown.map((u) => '"$u"').join(', ')}: not a language the app has (${kSocleSupportedLanguages.join(', ')})');
  }

  // Registration: the end user's flags; the backend's required fields always.
  const flags = {'phone_number': ['phoneNum'], 'date_of_birth': ['dateOfBirth'], 'address': ['address', 'zipCode', 'city']};
  final user = 'registration.fields_required.end_user';
  if (at(user) is Map) {
    final wanted = {...kUserRequiredRegistrationFields, for (final e in flags.entries) if (flag('$user.${e.key}')) ...e.value};
    client('mobile.registration.fields', [for (final f in kKnownRegistrationFields) if (wanted.contains(f)) f], user,
        note: flag('$user.full_name') ? null : 'full_name is off, but the backend needs a first and last name');
  }
  if (at('registration.fields_required.reseller') is Map) {
    info('registration.fields_required.reseller', null, 'the app has no reseller sign-up');
  }

  // Scope.
  client('studio:backend.features.payments', flag('scope.in_app_payments'), 'scope.in_app_payments');
  client('studio:backend.features.vouchers', flag('scope.voucher_activation'), 'scope.voucher_activation');
  if (flag('scope.ios_app')) todo('ios', 'iOS wanted: run `ruby tool/ios_flavors.rb` on the Mac, then the Mac prompt in Build');
  if (flag('scope.social_media_integration')) {
    todo('google', 'Google sign-in wanted: the Google guides in Integrations (web, Android and iOS clients)');
  }
  if (!flag('scope.android_app')) info('scope.android_app', false, 'the client did not tick the Android app');
  for (final k in const ['portal', 'reseller_panel', 'qr_sharing']) {
    if (flag('scope.$k')) info('scope.$k', true, 'outside the mobile app');
  }

  // Google Cloud: the project id where Studio has its own field.
  final project = str('google_cloud.project_id');
  if (project.isNotEmpty) {
    if (RegExp(r'^[a-z][a-z0-9-]{4,28}[a-z0-9]$').hasMatch(project)) {
      client('studio:gcpProjectId', project, 'google_cloud.project_id');
    } else {
      dropped('google_cloud.project_id', project, 'not a Google Cloud project id');
    }
  }

  // The logo: by sha256 first, then by name; non-image files are not read.
  final images = [for (final f in files) if (tryDecode(f.bytes) != null) f];
  List<int>? mark;
  for (final field in const ['branding.icon_file_id', 'branding.logo_file_id']) {
    final entry = (j['files'] as List).cast<Map>().where((f) => f['field'] == field).firstOrNull;
    if (entry == null || mark != null) continue;
    final sha = entry['sha256'] is String ? '${entry['sha256']}'.toLowerCase() : null;
    final hit = sha != null
        ? images.where((f) => sha256.convert(f.bytes).toString() == sha).firstOrNull
        : images.where((f) => f.name == entry['name']).firstOrNull;
    if (hit == null) {
      ask('logo.mark', sha != null
          ? 'drop the file whose sha256 is $sha (${entry['name']}): no dropped image has it'
          : 'drop ${entry['name']} with the intake');
      continue;
    }
    mark = hit.bytes;
    client('logo.mark', '${entry['name']}', field, note: sha != null ? 'matched by sha256' : 'matched by name');
  }
  if (mark == null && !rows.any((r) => r.path == 'logo.mark')) ask('logo.mark', 'the logo (no logo file in the intake)');
  if (mark != null && rows.any((r) => r.path == 'logo.mark' && r.kind == 'ask')) {
    rows.removeWhere((r) => r.path == 'logo.mark' && r.kind == 'ask');
  }

  // Shown, never stored: people's names and addresses stay in the portal.
  for (final k in const ['main_contact_name', 'main_contact_email', 'technical_contact_email']) {
    if (str('company.$k').isNotEmpty) info('company.$k', str('company.$k'), 'not stored');
  }
  if (str('smtp.host').isNotEmpty && !_host.hasMatch(str('smtp.host'))) dropped('smtp.host', str('smtp.host'), 'not a host name');
  final api = str('transatel.api.base_url');
  if (api.isNotEmpty && Uri.tryParse(api)?.scheme != 'https') dropped('transatel.api.base_url', api, 'not an https address');
  final from = str('smtp.from_address');
  if (from.isNotEmpty && !_email.hasMatch(from)) dropped('smtp.from_address', from, 'not an email address');
  final sftp = str('transatel.sftp.host');
  if (sftp.isNotEmpty && !_host.hasMatch(sftp)) dropped('transatel.sftp.host', sftp, 'not a host name');
  for (final k in const ['main_domain', 'portal_domain', 'api_domain', 'backoffice_domain']) {
    final d = str('infrastructure.$k').toLowerCase();
    if (d.isNotEmpty && !_host.hasMatch(d)) dropped('infrastructure.$k', d, 'not a domain name');
  }
  return IntakeRead._(j, text, rows, mark);
}

/// studio.json `intake`: where the values came from, the PROD domains to
/// confirm, and what the client provided for the backend. No contact data.
Map<String, Object?> intakeBlock(IntakeRead r, {Map<String, Object?> applied = const {}}) {
  final v = r.json['values'] as Map;
  Object? at(String path) => path.split('.').fold<Object?>(v, (n, k) => n is Map ? n[k] : null);
  String str(String path) => switch (at(path)) { final String s => s.trim(), _ => '' };
  Map<String, Object?> pick(Map<String, Object?> m) => {
        for (final e in m.entries)
          if (e.value != null && e.value != '' && !(e.value is Map && (e.value as Map).isEmpty) && !(e.value is List && (e.value as List).isEmpty))
            e.key: e.value,
      };
  String? host(String path) => _host.hasMatch(str(path).toLowerCase()) ? str(path).toLowerCase() : null;
  String? https(String path) => Uri.tryParse(str(path))?.scheme == 'https' ? str(path) : null;
  Map<String, Object?> recaptcha(String p) => pick({
        if (at('$p.enabled') == true) 'enabled': true,
        'key_name': str('$p.key_name'),
        'site_key': str('$p.site_key'),
        'domain_restrictions': [for (final d in _list(at('$p.domain_restrictions'))) if (_host.hasMatch(d.toLowerCase())) d.toLowerCase()],
        'package_name': str('$p.package_name'),
        'sha1_fingerprint': str('$p.sha1_fingerprint'),
      });
  return {
    'submissionId': r.submissionId,
    'submittedAt': r.json['submittedAt'],
    'sha256': sha256.convert(utf8.encode(r.text)).toString(),
    'applied': applied,
    'prodPending': {
      'domains': [
        for (final k in const ['main_domain', 'portal_domain', 'api_domain', 'backoffice_domain']) ?host('infrastructure.$k'),
      ],
    },
    'clientProvided': pick({
      'transatel': pick({
        'account_status': str('transatel.account_status'),
        'api': pick({
          'base_url': https('transatel.api.base_url'),
          for (final k in const ['cos_ref', 'mvno_ref', 'grant_type']) k: str('transatel.api.$k'),
        }),
        'rate_plans': _list(at('transatel.rate_plans')),
        'sftp': pick({'host': host('transatel.sftp.host'), 'port': _port(at('transatel.sftp.port'))}),
      }),
      'smtp': pick({
        'host': host('smtp.host'),
        'port': _port(at('smtp.port')),
        'from_address': _email.hasMatch(str('smtp.from_address')) ? str('smtp.from_address') : null,
      }),
      'google_cloud': pick({
        'project_id': str('google_cloud.project_id'),
        'project_name': str('google_cloud.project_name'),
        'recaptcha': pick({for (final p in const ['web', 'android', 'ios']) p: recaptcha('google_cloud.recaptcha.$p')}),
      }),
    }),
    'stripped': [for (final p in r.json['strippedPaths'] as List) '$p'],
  };
}

/// New brand's form, filled from the intake's client values and Studio's suggestions.
Map<String, dynamic> intakeForm(IntakeRead r) {
  Object? val(String path) =>
      r.rows.where((x) => x.path == path && (x.kind == 'client' || x.kind == 'suggested')).firstOrNull?.value;
  return {
    for (final (key, path) in const [
      ('slug', 'slug'), ('name', 'name'), ('applicationId', 'mobile.applicationId'), ('apiBaseUrl', 'mobile.apiBaseUrl'),
      ('displayName', 'mobile.displayName'), ('companyName', 'legal.companyName'), ('country', 'legal.country'),
      ('termsUrl', 'legal.termsUrl'), ('privacyUrl', 'legal.privacyUrl'),
      ('accountDeletionUrl', 'legal.accountDeletionUrl'), ('locales', 'locales'),
      ('registrationFields', 'mobile.registration.fields'),
    ])
      if (val(path) != null) key: val(path),
    'colors': {
      for (final role in const ['primary', 'accent']) if (val('colors.$role') != null) role: val('colors.$role'),
    },
  };
}

/// The client values [brand] and [studio] hold now, by row path.
Object? _current(String path, Map<String, dynamic> brand, Map<String, dynamic> studio) {
  if (path.startsWith('studio:')) return valueAt(studio, path.substring(7));
  if (path == 'logo.mark') return valueAt(brand, 'logo.mark');
  return valueAt(brand, path);
}

bool _blank(Object? v) => v == null || v == '' || (v is List && v.isEmpty);

/// The Brand tab's offer: each client row with what the brand holds now, and
/// whether it is ticked by default (only where the brand is blank).
List<Map<String, Object?>> intakeOffer(String root, String slug, IntakeRead r) {
  final brand = jsonDecode(File('$root/brands/$slug/brand.json').readAsStringSync()) as Map<String, dynamic>;
  final studio = readStudio(root, slug);
  return [
    for (final row in r.rows)
      if (row.kind == 'client')
        {
          ...row.toJson(),
          'current': _current(row.path, brand, studio),
          'take': _blank(_current(row.path, brand, studio)) ||
              (row.path != 'logo.mark' && jsonEncode(_current(row.path, brand, studio)) == jsonEncode(row.value)),
        },
  ];
}

String? _read(String root, String path) {
  final f = File('$root/$path');
  return f.existsSync() ? f.readAsStringSync() : null;
}

void _set(Map<String, dynamic> json, String path, Object? value) {
  final keys = path.split('.');
  var node = json;
  for (final k in keys.take(keys.length - 1)) {
    node = (node[k] ??= <String, dynamic>{}) as Map<String, dynamic>;
  }
  node[keys.last] = value;
}

/// The Brand tab's Apply: the [take]n client rows into brand.json and
/// studio.json, the intake block, and the logo file when taken. [mark] is the
/// logo the page kept from the first read, when the request carries it again.
Plan intakePlan(String root, String slug, IntakeRead r, Set<String> take, {List<int>? mark}) {
  mark ??= r.mark;
  final plan = Plan();
  final brand = jsonDecode(File('$root/brands/$slug/brand.json').readAsStringSync()) as Map<String, dynamic>;
  final studio = readStudio(root, slug);
  final applied = <String, Object?>{};
  for (final row in r.rows.where((x) => x.kind == 'client' && take.contains(x.path))) {
    if (row.path == 'logo.mark') continue;
    applied[row.path] = row.value;
    if (row.path.startsWith('studio:')) {
      _set(studio, row.path.substring(7), row.value);
    } else {
      _set(brand, row.path, row.value);
      if (row.path == 'locales' && !(row.value as List).contains(brand['defaultLocale'])) {
        brand['defaultLocale'] = (row.value as List).first;
      }
    }
  }
  final v = BrandConfig.parse(brand, expectedSlug: slug);
  for (final e in v.errors) {
    plan.error(e.field, e.reason);
  }
  for (final w in v.warnings) {
    plan.warn(w.field, w.reason);
  }
  final others = {
    for (final s in brandSlugs(root))
      if (s != slug) s: jsonDecode(File('$root/brands/$s/brand.json').readAsStringSync()) as Map<String, dynamic>,
  };
  for (final MapEntry(key: field, value: reason) in clashes(brand, others).entries) {
    if (applied.containsKey(field)) plan.error(field, reason);
  }
  for (final MapEntry(key: field, value: reason) in frozenViolations(brand, studio).entries) {
    plan.error(field, reason);
  }
  studio['intake'] = intakeBlock(r, applied: applied);
  plan.text
    ..addAll(generate(root, slug, brand, studio: studio).where((c) => c.changed))
    ..add(FileChange('brands/$slug/studio.json', _read(root, 'brands/$slug/studio.json'),
        '${const JsonEncoder.withIndent('  ').convert(studio)}\n'));
  if (take.contains('logo.mark') && mark != null) {
    final path = 'brands/$slug/assets/${(brand['logo'] as Map?)?['mark'] ?? 'logo-mark.png'}';
    plan.binary.add(BinaryChange(path, readBytes(root, path), mark));
    if (tryDecode(mark) case final i?) plan.previews[path] = thumbnail(i);
    plan.notes.add('The logo mark changes, the icons do not: press Regenerate assets in Assets to remake them.');
  }
  plan.notes.add('From ${r.source}. Ask the client: '
      '${r.rows.where((x) => x.kind == 'ask').map((x) => x.path).toSet().join(', ')}.');
  return plan;
}
