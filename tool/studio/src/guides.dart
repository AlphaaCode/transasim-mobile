/// Guided fields (docs/STUDIO-SPEC.md §4a): every value that comes from a
/// console outside the repo has a guide, written as data in
/// `tool/studio/guides/<id>.yaml`. When a console changes, one file changes.
///
/// A guide says where its value goes, which page to open (filled with the
/// brand's own ids), the steps, the values to copy into the console, and the
/// rules a pasted value must pass. Validation runs here only: the card, the
/// tests and Apply all ask this file.
library;

import 'dart:convert';
import 'dart:io';

import 'package:transasim_mobile/core/brand/brand_config.dart';
import 'package:yaml/yaml.dart';

import '../../gen_brand_flavors.dart' show brandSlugs;
import 'assets.dart' show Plan;
import 'distinct.dart';
import 'generate.dart';

const guidesDir = 'tool/studio/guides';

class Rule {
  Rule(this.message, {this.match, this.refuse, this.differsFrom, this.unique = false});

  final String message;
  final RegExp? match;
  final RegExp? refuse;

  /// Another field (`brand:<path>` or `studio:<key>`) the value must not equal.
  final String? differsFrom;

  /// No other brand may hold this value in the same field.
  final bool unique;
}

class Derive {
  Derive(this.label, this.match, this.template, this.field);

  final String label;
  final RegExp match;
  final String template;

  /// Where the derived value is written; null: shown only.
  final String? field;
}

class Guide {
  Guide({
    required this.id,
    required this.title,
    required this.kind,
    required this.field,
    required this.urlTemplate,
    required this.steps,
    required this.copyValues,
    required this.rules,
    required this.derive,
    required this.requires,
    required this.normalizeUpper,
    required this.checklistItem,
    required this.accept,
    required this.reject,
  });

  final String id, title, kind, checklistItem;

  /// `brand:<dotted path>` or `studio:<key>`; null for a confirm guide.
  final String? field;
  final String? urlTemplate;
  final List<String> steps;
  final List<(String, String)> copyValues;
  final List<Rule> rules;
  final List<Derive> derive;

  /// Placeholders a confirm guide needs set before it can be ticked.
  final List<String> requires;
  final bool normalizeUpper;
  final List<String> accept, reject;
}

/// Every guide, by id. Throws [FormatException] naming the file and the
/// problem for a guide that does not follow the schema.
Map<String, Guide> loadGuides([String root = '.']) {
  final out = <String, Guide>{};
  final files = Directory('$root/$guidesDir').listSync().whereType<File>()
      .where((f) => f.path.endsWith('.yaml')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final f in files) {
    final name = f.uri.pathSegments.last;
    Never bad(String why) => throw FormatException('$guidesDir/$name: $why');
    final y = loadYaml(f.readAsStringSync());
    if (y is! YamlMap) bad('not a YAML map');
    String str(String k, {bool required = true}) {
      final v = y[k];
      if (v == null && !required) return '';
      if (v is! String || v.isEmpty) bad('"$k" must be a non-empty string');
      return v;
    }

    List<String> strings(String k) => [for (final v in (y[k] as List? ?? const [])) '$v'];
    RegExp? re(Object? v) {
      if (v == null) return null;
      try {
        return RegExp('$v');
      } on FormatException catch (e) {
        bad('regex "$v" does not compile: ${e.message}');
      }
    }

    final id = str('id');
    if ('$id.yaml' != name) bad('id "$id" must equal the file name');
    final kind = str('kind');
    if (kind != 'paste' && kind != 'confirm') bad('kind must be paste or confirm');
    final field = kind == 'paste' ? str('field') : null;
    if (field != null &&
        !RegExp(r'^(brand:[A-Za-z][A-Za-z0-9]*(\.[A-Za-z][A-Za-z0-9]*)*|studio:[A-Za-z][A-Za-z0-9]*)$')
            .hasMatch(field)) {
      bad('field must be brand:<dotted path> or studio:<key>, not "$field"');
    }
    final rules = [
      for (final r in (y['validate'] as List? ?? const []))
        if (r is YamlMap)
          Rule('${r['message'] ?? bad('every rule needs a message')}',
              match: re(r['match']),
              refuse: re(r['refuse']),
              differsFrom: r['differsFrom'] as String?,
              unique: r['uniqueAcrossBrands'] == true)
        else
          bad('a rule must be a map'),
    ];
    final ex = y['examples'] as YamlMap?;
    final guide = Guide(
      id: id,
      title: str('title'),
      kind: kind,
      field: field,
      urlTemplate: str('urlTemplate', required: false).isEmpty ? null : str('urlTemplate'),
      steps: strings('steps'),
      copyValues: [
        for (final c in (y['copyValues'] as List? ?? const []))
          ('${(c as YamlMap)['label']}', '${c['value']}'),
      ],
      rules: rules,
      derive: [
        for (final d in (y['derive'] as List? ?? const []))
          Derive('${(d as YamlMap)['label']}', re(d['match'])!, '${d['template']}', d['field'] as String?),
      ],
      requires: strings('requires'),
      normalizeUpper: y['normalize'] == 'upper',
      checklistItem: str('checklistItem'),
      accept: [for (final v in (ex?['accept'] as List? ?? const [])) '$v'],
      reject: [for (final v in (ex?['reject'] as List? ?? const [])) '$v'],
    );
    if (kind == 'paste' && (guide.rules.isEmpty || guide.accept.isEmpty || guide.reject.isEmpty)) {
      bad('a paste guide needs validate rules and accept and reject examples');
    }
    if (kind == 'confirm' && guide.requires.isEmpty) bad('a confirm guide must list what it requires');
    out[id] = guide;
  }
  return out;
}

// ---- reading and writing a field ------------------------------------------

Object? readField(String field, Map brand, Map studio) {
  final (side, path) = _split(field);
  return path.split('.').fold<Object?>(side == 'brand' ? brand : studio,
      (node, key) => node is Map ? node[key] : null);
}

void writeField(String field, Map brand, Map studio, String value) {
  final (side, path) = _split(field);
  final keys = path.split('.');
  var node = side == 'brand' ? brand : studio;
  for (final k in keys.take(keys.length - 1)) {
    node = (node[k] ??= <String, dynamic>{}) as Map;
  }
  node[keys.last] = value;
}

(String, String) _split(String field) {
  final i = field.indexOf(':');
  return (field.substring(0, i), field.substring(i + 1));
}

// ---- templates ---------------------------------------------------------------

/// The values a guide's URL, steps and copy values can name, from a brand's
/// pending brand.json and studio.json.
Map<String, String> placeholders(String slug, Map brand, Map studio) {
  String s(Object? v) => v is String ? v : '';
  final mobile = brand['mobile'] is Map ? brand['mobile'] as Map : const {};
  return {
    'slug': slug,
    'name': s(brand['name']),
    'package': s(mobile['applicationId']),
    'bundleId': s(mobile['bundleIdentifier']),
    'gcpProject': s(studio['gcpProjectId']),
    'authuser': s(studio['googleAccount']),
    'devId': s(studio['playDeveloperId']),
    'playAppId': s(studio['playAppId']),
    'teamId': s(studio['appleTeamId']),
    'uploadSha1': s(studio['uploadKeySha1']),
    'playSigningSha1': s(studio['playSigningSha1']),
  };
}

final _placeholder = RegExp(r'\{(\w+)\}');

/// A guide filled in for one brand: the page to open (null while an id it
/// needs is missing), the ids still missing, the steps and copy values.
Map<String, Object?> resolve(Guide g, Map<String, String> values) {
  final used = <String>{
    for (final t in [g.urlTemplate ?? '', for (final c in g.copyValues) c.$2])
      for (final m in _placeholder.allMatches(t)) m[1]!,
    ...g.requires,
  };
  final unknown = used.where((k) => !values.containsKey(k));
  if (unknown.isNotEmpty) throw StateError('${g.id}: unknown placeholder ${unknown.join(', ')}');
  final missing = used.where((k) => values[k]!.isEmpty).toList()..sort();
  String fill(String t, {bool url = false}) => t.replaceAllMapped(_placeholder, (m) {
        final v = values[m[1]] ?? '';
        if (v.isEmpty) return '‹${m[1]}›';
        return url ? Uri.encodeComponent(v) : v;
      });
  final urlMissing = g.urlTemplate == null
      ? const <String>[]
      : [for (final m in _placeholder.allMatches(g.urlTemplate!)) if (values[m[1]]!.isEmpty) m[1]!];
  return {
    'id': g.id,
    'title': g.title,
    'kind': g.kind,
    'field': g.field,
    'checklistItem': g.checklistItem,
    'url': g.urlTemplate == null || urlMissing.isNotEmpty ? null : fill(g.urlTemplate!, url: true),
    'missing': missing,
    'steps': [for (final s in g.steps) fill(s)],
    'copyValues': [
      for (final (label, value) in g.copyValues) {'label': label, 'value': fill(value)},
    ],
  };
}

// ---- checking a value --------------------------------------------------------

/// Shapes of secrets Studio refuses to store anywhere: Stripe secret and
/// restricted keys, webhook secrets, Google client secrets, PEM keys.
final _secret = RegExp(r'^(sk|rk)_(live|test)_|^whsec_|^GOCSPX-|-----BEGIN ');

bool isSecretShaped(String v) => _secret.hasMatch(v.trim());

/// The verdict on [raw] pasted into [g]: the value as it would be stored, the
/// problems (empty: accepted), and what it derives.
({String value, List<String> errors, List<Map<String, String?>> derived}) checkPaste(
  Guide g,
  String raw, {
  Map brand = const {},
  Map studio = const {},
  Map<String, (Map, Map)> others = const {},
}) {
  final value = g.normalizeUpper ? raw.trim().toUpperCase() : raw.trim();
  final derived = <Map<String, String?>>[];
  for (final d in g.derive) {
    final m = d.match.firstMatch(value);
    if (m == null) continue;
    derived.add({
      'label': d.label,
      'field': d.field,
      'value': d.template.replaceAllMapped(RegExp(r'\{(\d)\}'), (x) => m[int.parse(x[1]!)] ?? ''),
    });
  }
  // A derive aimed at the guide's own field normalises it (a Play URL → its id).
  final stored = derived.where((d) => d['field'] == g.field).firstOrNull?['value'] ?? value;
  if (isSecretShaped(value)) {
    return (value: stored, errors: ['that looks like a secret; Studio never stores one'], derived: const []);
  }
  final errors = <String>[];
  for (final r in g.rules) {
    if (r.match != null && !r.match!.hasMatch(value)) errors.add(r.message);
    if (r.refuse != null && r.refuse!.hasMatch(value)) errors.add(r.message);
    if (r.differsFrom != null && stored.isNotEmpty && readField(r.differsFrom!, brand, studio) == stored) {
      errors.add(r.message);
    }
    if (r.unique && g.field != null && !isSocleValue(stored)) {
      for (final MapEntry(key: slug, value: (b, s)) in others.entries) {
        if (readField(g.field!, b, s) == stored) errors.add('${r.message} ($slug)');
      }
    }
  }
  return (value: stored, errors: errors, derived: errors.isEmpty ? derived : const []);
}

/// Fields of studio.json that no guide owns, with their rule.
final plainStudioRules = {
  'gcpProjectId': (RegExp(r'^([a-z][a-z0-9-]{4,28}[a-z0-9]|\d{6,})$'),
      'a Google Cloud project ID (6–30 lowercase letters, digits, hyphens) or its number'),
  'googleAccount': (RegExp(r'^[^@\s]+@[^@\s]+\.[a-z]{2,}$'), 'the email of the Google account'),
  'uploadKeySha1': (RegExp(r'^([0-9A-F]{2}:){19}[0-9A-F]{2}$'), 'a SHA-1: 20 hex pairs with colons'),
  'playDeveloperId': (RegExp(r'^\d{6,25}$'), 'the number after /developers/ in Play Console'),
};

/// The other brands' brand.json and studio.json, for the cross-brand rules.
Map<String, (Map, Map)> otherBrands(String root, String slug) => {
      for (final s in brandSlugs(root))
        if (s != slug)
          s: (
            jsonDecode(File('$root/brands/$s/brand.json').readAsStringSync()) as Map,
            readStudio(root, s),
          ),
    };

/// The Integrations tab's Apply: brand.json and studio.json as edited, every
/// generated file they change, and every rule the guides and the app hold.
Plan integrationsPlan(String root, String slug, Map<String, dynamic> brand, Map<String, dynamic> studio) {
  final plan = Plan();
  final others = otherBrands(root, slug);
  final v = BrandConfig.parse(brand, expectedSlug: slug);
  for (final e in v.errors) {
    plan.error(e.field, e.reason);
  }
  for (final w in v.warnings) {
    plan.warn(w.field, w.reason);
  }
  for (final MapEntry(key: f, value: r) in clashes(brand, {for (final e in others.entries) e.key: e.value.$1.cast()}).entries) {
    plan.error(f, r);
  }
  for (final MapEntry(key: f, value: r) in frozenViolations(brand, readStudio(root, slug)).entries) {
    plan.error(f, r);
  }

  // Every string, wherever it sits: a secret is never written.
  void scan(Object? node, String path) {
    switch (node) {
      case String s when isSecretShaped(s):
        plan.error(path, 'looks like a secret; Studio never stores one');
      case Map m:
        for (final e in m.entries) {
          scan(e.value, path.isEmpty ? '${e.key}' : '$path.${e.key}');
        }
      case List l:
        for (final v in l) {
          scan(v, path);
        }
    }
  }

  scan(brand, '');
  scan(studio, 'studio');

  for (final g in loadGuides(root).values.where((g) => g.field != null)) {
    final current = readField(g.field!, brand, studio);
    if (current is! String || current.isEmpty || isSocleValue(current)) continue;
    for (final e in checkPaste(g, current, brand: brand, studio: studio, others: others).errors) {
      plan.error(g.field!.replaceFirst('brand:', '').replaceFirst(':', '.'), e);
    }
  }
  for (final MapEntry(key: k, value: (re, why)) in plainStudioRules.entries) {
    final value = studio[k];
    if (value is String && value.isNotEmpty && !re.hasMatch(value)) plan.error('studio.$k', why);
  }
  // A confirmation names the fingerprints it was made for; a new key makes it stale.
  for (final g in loadGuides(root).values.where((g) => g.kind == 'confirm')) {
    final record = (studio['checklist'] as Map?)?[g.checklistItem];
    if (record is! Map) continue;
    final now = placeholders(slug, brand, studio);
    for (final k in g.requires) {
      if ((record['for'] as Map?)?[k] != now[k]) {
        plan.warn('studio.checklist.${g.checklistItem}',
            '"${g.title}" was confirmed for a different $k: check it again');
      }
    }
  }

  plan.text.addAll(generate(root, slug, brand, studio: studio).where((c) => c.changed));
  final path = 'brands/$slug/studio.json';
  final before = File('$root/$path').existsSync() ? File('$root/$path').readAsStringSync() : null;
  final after = '${const JsonEncoder.withIndent('  ').convert(studio)}\n';
  if (before != after) plan.text.add(FileChange(path, before, after));
  return plan;
}
