/// SPC Studio, the local brand builder (docs/STUDIO-SPEC.md).
///
/// ```
/// dart run tool/studio/bin/studio.dart            # serve on 127.0.0.1:4777, open the browser
/// dart run tool/studio/bin/studio.dart --no-open  # serve only
/// dart run tool/studio/bin/studio.dart --check    # validate + golden check every brand, exit 1 on drift
/// dart run tool/studio/bin/studio.dart --regenerate  # write every brand's generated files, as Apply would
/// dart run tool/studio/bin/studio.dart --verify-release <slug> [--acknowledge-exception]  # the release job's last step
/// dart run tool/studio/bin/studio.dart --verify-ipa <slug> <ipa> [--acknowledge-exception]  # the Mac's, before an upload
/// dart run tool/studio/bin/studio.dart --stage-apk <slug> <prod|dev>  # name a profile APK for its flavor
/// dart run tool/studio/bin/studio.dart --pin-production <slug> <url> --reason "<why>"
///     [--exception <url> | --end-exception]   # move the production pin, logged (Slice H)
/// ```
///
/// Run from the repo root (tool/studio/studio.bat does). Runs on the plain Dart
/// VM, which is why lib/core/headless.dart exists.
library;

import 'dart:convert';
import 'dart:io';

import 'package:transasim_mobile/core/brand/app_flavor.dart';
import 'package:transasim_mobile/core/brand/brand_config.dart';

import '../../gen_brand_flavors.dart' show brandSlugs, devFlavorEnabled;
import '../src/generate.dart';
import '../src/hosts.dart';
import '../src/release.dart';
import '../src/server.dart';

Future<void> main(List<String> args) async {
  final root = Directory.current.path;
  if (!File('$root/pubspec.yaml').existsSync() || !Directory('$root/brands').existsSync()) {
    stderr.writeln('Run Studio from the repo root (tool/studio/studio.bat does).');
    exit(2);
  }
  String? after(String flag, [int n = 1]) =>
      switch (args.indexOf(flag)) { final i when i >= 0 && i + n < args.length => args[i + n], _ => null };
  final acknowledged = args.contains('--acknowledge-exception');
  if (args.contains('--check')) exit(checkAll(root));
  if (args.contains('--regenerate')) exit(regenerateAll(root));
  if (after('--verify-release') case final slug?) {
    exit(await verifyRelease(root, slug, acknowledgeException: acknowledged));
  }
  if ((after('--verify-ipa'), after('--verify-ipa', 2)) case (final slug?, final ipa?)) {
    exit(verifyIpa(root, slug, ipa, acknowledgeException: acknowledged));
  }
  if ((after('--stage-apk'), after('--stage-apk', 2)) case (final slug?, final flavor?)) {
    exit(stageApk(root, slug, flavor == 'dev' ? AppFlavor.dev : AppFlavor.prod));
  }
  if ((after('--pin-production'), after('--pin-production', 2)) case (final slug?, final url?)) {
    exit(pinProduction(root, slug, url,
        reason: after('--reason') ?? '', exceptionUrl: after('--exception'), endException: args.contains('--end-exception')));
  }
  await serve(root, open: !args.contains('--no-open'));
}

Map<String, dynamic> _brand(String root, String slug) =>
    jsonDecode(File('$root/brands/$slug/brand.json').readAsStringSync()) as Map<String, dynamic>;

/// The dev flavor's files on disk for a brand that has no dev flavor: left
/// over, and refused, since Gradle and Xcode would still build them.
List<String> staleDevFiles(String root, String slug, Map<String, dynamic> brand) => [
      if (!devFlavorEnabled(brand))
        for (final p in ['brands/$slug/flavor/${slug}Dev.json', 'lib/flavors/main_${slug}_dev.dart', 'ios/Flutter/${slug}Dev.xcconfig'])
          if (File('$root/$p').existsSync()) p,
    ];

/// Every brand valid, and every generated file what Studio would write.
int checkAll(String root) {
  var failures = 0;
  for (final slug in brandSlugs(root)) {
    final brand = _brand(root, slug);
    final studio = readStudio(root, slug);
    final v = BrandConfig.parse(brand, expectedSlug: slug);
    final drift = [
      for (final c in generate(root, slug, brand)) if (c.changed) c.path,
      ...staleDevFiles(root, slug, brand),
    ];
    final errors = [
      for (final e in v.errors) '$e',
      for (final MapEntry(key: f, value: r) in frozenViolations(brand, studio).entries) '$f: $r',
      for (final (f, r) in hostErrors(root, slug, brand, studio)) '$f: $r',
    ];
    final ok = errors.isEmpty && drift.isEmpty;
    if (!ok) failures++;
    stdout.writeln('${ok ? 'ok  ' : 'FAIL'} $slug: ${errors.length} errors, '
        '${v.warnings.length} warnings, '
        '${drift.isEmpty ? 'generated files in sync' : 'would change ${drift.join(', ')}'}');
    for (final e in errors) {
      stdout.writeln('       error $e');
    }
  }
  return failures == 0 ? 0 : 1;
}

/// `--regenerate`: every brand's generated files written as its Apply would
/// write them, and a dev flavor's left-over files deleted. Refused for a
/// brand with errors: fix those in the Brand tab first.
int regenerateAll(String root) {
  var failures = 0;
  for (final slug in brandSlugs(root)) {
    final brand = _brand(root, slug);
    final studio = readStudio(root, slug);
    final errors = [
      ...BrandConfig.parse(brand, expectedSlug: slug).errors.map((e) => '$e'),
      for (final MapEntry(key: f, value: r) in frozenViolations(brand, studio).entries) '$f: $r',
      for (final (f, r) in hostErrors(root, slug, brand, studio)) '$f: $r',
    ];
    if (errors.isNotEmpty) {
      failures++;
      stdout.writeln('FAIL $slug, nothing written:\n       ${errors.join('\n       ')}');
      continue;
    }
    final written = [
      for (final c in generate(root, slug, brand))
        if (c.changed) c.path,
    ];
    for (final c in generate(root, slug, brand).where((c) => c.changed)) {
      File('$root/${c.path}')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(c.after);
    }
    final stale = staleDevFiles(root, slug, brand);
    for (final p in stale) {
      File('$root/$p').deleteSync();
    }
    stdout.writeln('ok   $slug: ${written.isEmpty && stale.isEmpty ? 'nothing to write' : [
          if (written.isNotEmpty) 'wrote ${written.join(', ')}',
          if (stale.isNotEmpty) 'deleted ${stale.join(', ')}',
        ].join('; ')}');
  }
  return failures == 0 ? 0 : 1;
}

/// `--pin-production`: the explicit, logged move of [slug]'s production pin
/// (Slice H), with or without a temporary exception. It writes studio.json
/// only: Go prod's Apply then writes the new host into brand.json.
int pinProduction(String root, String slug, String url,
    {required String reason, String? exceptionUrl, bool endException = false}) {
  if (!brandSlugs(root).contains(slug)) {
    stdout.writeln('no brand "$slug"');
    return 2;
  }
  final file = File('$root/brands/$slug/studio.json');
  final Map<String, dynamic> after;
  try {
    after = repinned(readStudio(root, slug),
        apiBaseUrl: url, reason: reason, exceptionUrl: exceptionUrl, endException: endException, now: DateTime.now());
  } on ArgumentError catch (e) {
    stdout.writeln('refused: ${e.message}');
    return 2;
  }
  file.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(after)}\n');
  final e = productionException(after);
  stdout.writeln('$slug: production pinned to ${productionOf(after)['apiBaseUrl']}'
      '${e == null ? '' : ', exception ${e.apiBaseUrl} (${e.reason})'}.');
  stdout.writeln('Logged in brands/$slug/studio.json production.log. Now press Go prod in the Backend tab: '
      'its Apply writes ${expectedApiBaseUrl(after)} into brand.json. Then review and commit.');
  return 0;
}
