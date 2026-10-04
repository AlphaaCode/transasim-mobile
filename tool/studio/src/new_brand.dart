/// "New brand": a complete brand from one form, in one previewed Apply.
library;

import 'dart:convert';
import 'dart:io';

import 'package:transasim_mobile/core/brand/brand_config.dart';

import '../../gen_brand_flavors.dart' show brandSlugs;
import 'assets.dart';
import 'distinct.dart';
import 'generate.dart';
import 'icons.dart';

/// Names Gradle already uses for source sets: a flavor called one of these
/// would merge into the socle's own folders.
const _reserved = {'main', 'debug', 'profile', 'release', 'test', 'androidtest'};

/// brand.json for the form's [f]ields. What the form does not ask is set to
/// the socle's default and written out, so the Brand tab shows every value.
Map<String, dynamic> newBrandJson(Map<String, dynamic> f) {
  String s(String k) => (f[k] as String? ?? '').trim();
  final locales = [for (final l in (f['locales'] as List? ?? const [])) '$l'];
  final applicationId = s('applicationId');
  return {
    'slug': s('slug'),
    'name': s('name'),
    'colors': {
      for (final role in ['primary', 'accent', 'surface', 'cta', 'ctaText'])
        role: '${(f['colors'] as Map?)?[role] ?? ''}'.toLowerCase(),
    },
    // The mark stands in for the full lockup until one is dropped on Assets.
    'logo': {'mark': 'logo-mark.png', 'full': 'logo-mark.png'},
    'locales': locales,
    'defaultLocale': locales.isEmpty ? '' : locales.first,
    'currency': 'EUR',
    'support': {'email': s('supportEmail')},
    'legal': {
      'companyName': s('companyName'),
      'country': s('country').toUpperCase(),
      'termsUrl': s('termsUrl'),
      'privacyUrl': s('privacyUrl'),
    },
    'mobile': {
      'applicationId': applicationId,
      'bundleIdentifier': applicationId,
      'displayName': s('name'),
      'deepLinkScheme': s('slug'),
      'apiBaseUrl': s('apiBaseUrl'),
      'stripePublishableKey': 'pk_test_PLACEHOLDER_AWAITING_CLIENT',
      'minimumSupportedVersion': '1.0.0',
    },
  };
}

/// studio.json for a new brand: the Apple team the other brands all use, so
/// the iOS build signs the way theirs do. Changed later in Integrations (1c).
Map<String, dynamic> newStudioJson(String root) {
  final teams = {
    for (final slug in brandSlugs(root)) readStudio(root, slug)['appleTeamId'],
  }..remove(null);
  return {'appleTeamId': teams.length == 1 ? teams.single : ''};
}

/// Everything the brand needs, as one plan: brand.json, studio.json, the logo,
/// the icon set, every generated text file and the pubspec block.
Plan newBrandPlan(String root, Map<String, dynamic> form, List<int>? logo) {
  final plan = Plan();
  final brand = newBrandJson(form);
  final slug = brand['slug'] as String;
  final existing = brandSlugs(root);

  if (!RegExp(r'^[a-z][a-z0-9]*$').hasMatch(slug)) {
    plan.error('slug', 'lowercase letters and digits, starting with a letter');
  } else if (_reserved.contains(slug)) {
    plan.error('slug', '"$slug" is a name Android builds already use for their own folders');
  } else if (existing.contains(slug) || Directory('$root/brands/$slug').existsSync()) {
    plan.error('slug', 'brands/$slug already exists');
  }
  final id = brand['mobile']['applicationId'] as String;
  if (!RegExp(r'^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$').hasMatch(id)) {
    plan.error('mobile.applicationId', 'a store id looks like com.company.app: lowercase, dotted');
  }
  final v = BrandConfig.parse(brand, expectedSlug: slug);
  for (final e in v.errors) {
    plan.error(e.field, e.reason);
  }
  for (final w in v.warnings) {
    plan.warn(w.field, w.reason);
  }
  final others = {
    for (final s in existing)
      s: jsonDecode(File('$root/brands/$s/brand.json').readAsStringSync()) as Map<String, dynamic>,
  };
  for (final MapEntry(key: field, value: reason) in clashes(brand, others).entries) {
    plan.error(field, reason);
  }
  if (logo == null) {
    plan.error('logo.mark', 'drop the logo mark: the icons are made from it');
  }
  if (plan.errors.any((e) => e['field'] == 'slug')) return plan;

  final studio = newStudioJson(root);
  if (logo != null) {
    final launch = templateValues(slug, brand, studio)['launchColour']!;
    final markPlan = Plan();
    if (tryDecode(logo) case final image?) {
      plan.binary.add(BinaryChange('brands/$slug/assets/logo-mark.png', null, logo));
      plan.previews['brands/$slug/assets/logo-mark.png'] = thumbnail(image);
      if (RegExp(r'^#[0-9a-f]{6}$').hasMatch(launch)) addIcons(markPlan, root, slug, logo, launch);
    } else {
      plan.error('logo.mark', 'not an image Studio can read: drop a PNG or JPEG');
    }
    plan.binary.addAll(markPlan.binary);
    plan.previews.addAll(markPlan.previews);
    plan.errors.addAll(markPlan.errors);
  }
  plan.text
    ..addAll(generate(root, slug, brand, withIcons: true, studio: studio).where((c) => c.changed))
    ..add(FileChange('brands/$slug/studio.json', null,
        '${const JsonEncoder.withIndent('  ').convert(studio)}\n'));
  plan.notes.add('Once published, ${brand['mobile']['applicationId']} is frozen: a new id is a '
      'new store listing that orphans every install. Choose it as the final one.');
  plan.notes.add('iOS: Studio writes the xcconfig and asset catalog; adding the brand to the Xcode '
      'project is `ruby tool/ios_flavors.rb`, on the Mac.');
  return plan;
}
