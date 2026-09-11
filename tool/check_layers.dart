// Static guardrails. ARCHITECTURE-MOBILE.md §1.3 (L1–L4) and §8.7 (C1–C3).
//
// Run:  dart run tool/check_layers.dart
// Exits non-zero on any violation, so CI fails the build.
//
// A rule written in a style guide does not survive six months of delivery
// pressure. This is the cheapest defence that does — the web socle accumulated
// 73 hardcoded colours across 11 files without anyone deciding to, and the old
// mobile app 894 across 39.

import 'dart:io';

/// Resolve a relative import against the importing file, so a rule reasons
/// about the file it actually reaches rather than the text of the directive.
/// `lib/core/brand/x.dart` + `../modules/y.dart` -> `lib/core/modules/y.dart`.
String? resolveImport(String fromPath, String importPath) {
  if (importPath.startsWith('package:') || importPath.startsWith('dart:')) return null;
  final base = fromPath.split('/')..removeLast();
  for (final part in importPath.split('/')) {
    if (part == '.') continue;
    if (part == '..') {
      if (base.isNotEmpty) base.removeLast();
    } else {
      base.add(part);
    }
  }
  return base.join('/');
}

final _importRe = RegExp(r"""import\s+['\"]([^'\"]+)['\"]""");

final _violations = <String>[];

void violation(String rule, String file, int line, String detail) =>
    _violations.add('$rule  $file:$line  $detail');

Iterable<File> dartFiles(String dir) sync* {
  final d = Directory(dir);
  if (!d.existsSync()) return;
  for (final e in d.listSync(recursive: true)) {
    if (e is File && e.path.endsWith('.dart')) yield e;
  }
}

/// Strip line and block comments so a rule never fires on prose. Every file
/// here documents the very mistakes these rules forbid, and naming them must
/// not trip the check.
String stripComments(String source) {
  final withoutBlocks = source.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  return withoutBlocks
      .split('\n')
      .map((l) {
        final i = l.indexOf('//');
        return i == -1 ? l : l.substring(0, i);
      })
      .join('\n');
}

void main() {
  // Client names that must never appear in socle code (C1).
  const clientNames = <String>['sabily', 'esimple', 'djezzy', 'djeezy', 'castrum'];

  // The one file allowed to hold colour literals (C2).
  const themeFile = 'lib/core/theme/app_theme.dart';

  for (final file in dartFiles('lib')) {
    final path = file.path.replaceAll(r'\', '/');
    final raw = file.readAsStringSync();
    final code = stripComments(raw);
    final lines = code.split('\n');
    final rawLines = raw.split('\n');

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final n = i + 1;

      // ---- C1: no client name anywhere in lib/ -------------------------
      //
      // lib/flavors/ is the ONE exception, and it is the point rather than a
      // loophole: ARCHITECTURE-MOBILE.md §5.4 makes a flavor a single line,
      // `void main() => bootstrap('<slug>');`. The brief's criterion §3.3.3
      // asks that no client name appear outside that client's own declaration,
      // and this is it. If a flavor file ever grows past that one line, this
      // exemption is what needs revisiting.
      // A line marked `// wire-contract` is exempt from C1. Some backend field
      // names are literally named after the first client — `sabilyAmount` is
      // the worst of them, and ANALYSE-EXISTANT.md §4.2 calls it the deepest
      // piece of white-label debt precisely because it sits in the DATA
      // contract, not the UI. We cannot rename someone else's API, so the
      // string has to appear exactly once, in a DTO, wearing this marker.
      //
      // The marker is deliberately noisy and greppable: it makes each exception
      // a decision someone wrote down, not a hole in the rule.
      final exempt = i < rawLines.length && rawLines[i].contains('// wire-contract');

      if (!path.startsWith('lib/flavors/') && !exempt) {
        final lower = line.toLowerCase();
        for (final name in clientNames) {
          if (lower.contains(name)) {
            violation('C1', path, n, 'client name "$name" in socle code');
          }
        }
      }

      // ---- C2: colour literals only in the theme ------------------------
      if (path != themeFile) {
        if (RegExp(r'Color\(0x[0-9a-fA-F]{6,8}\)').hasMatch(line)) {
          violation('C2', path, n, 'colour literal outside the theme');
        }
        if (RegExp(r'\bColors\.[a-zA-Z]').hasMatch(line)) {
          violation('C2', path, n, 'Material Colors.* outside the theme');
        }
      }

      // ---- C4: modules use the component layer, not raw Material --------
      //
      // The reason this rule exists rather than a note in a review checklist:
      // the first pass of the account module styled each screen against its own
      // Figma frame, and the frames disagree. Three buttons that were nearly
      // the same shipped, which is the exact mechanism by which the old app
      // reached 894 colour decisions across 39 files. `lib/core/ui/` resolves
      // the disagreement once; a raw Material control in a module reopens it.
      if (path.startsWith('lib/modules/')) {
        const banned = <String, String>{
          'FilledButton': 'AppButton',
          'ElevatedButton': 'AppButton',
          'OutlinedButton': 'AppButton(tone: AppButtonTone.danger)',
          'TextFormField': 'AppTextField',
        };
        for (final entry in banned.entries) {
          // A raw string for the boundary: '\b' inside an ordinary Dart
          // string is the BACKSPACE character, and the check silently matches
          // nothing. It did exactly that when this rule was first written.
          if (RegExp(r'\b' + entry.key + r'[(.]').hasMatch(line)) {
            violation('C4', path, n, '${entry.key} in a module; use ${entry.value}');
          }
        }
      }

      // ---- C2b: no inline font sizes; the type scale is named -----------
      if (path != themeFile && RegExp(r'fontSize:\s*[0-9]').hasMatch(line)) {
        violation('C2', path, n, 'inline fontSize outside the type scale');
      }

      // ---- Layer rules reason about the resolved target ----------------
      final importMatch = _importRe.firstMatch(line);
      final target = importMatch == null ? null : resolveImport(path, importMatch.group(1)!);
      final rawImport = importMatch?.group(1) ?? '';

      // ---- L1: core must not know any module ---------------------------
      if (path.startsWith('lib/core/') && target != null && target.startsWith('lib/modules/')) {
        violation('L1', path, n, 'core imports a module');
      }

      // ---- L2: modules must not know each other ------------------------
      final self = RegExp(r'^lib/modules/([^/]+)/').firstMatch(path)?.group(1);
      if (self != null && target != null) {
        final other = RegExp(r'^lib/modules/([^/]+)/').firstMatch(target)?.group(1);
        if (other != null && other != self) {
          violation('L2', path, n, 'module "$self" imports module "$other"');
        }
      }

      // ---- L3: a module's domain layer depends on nothing external -----
      if (RegExp(r'^lib/modules/[^/]+/domain/').hasMatch(path)) {
        final outward = rawImport.startsWith('package:flutter/') ||
            rawImport.startsWith('dart:io') ||
            rawImport.startsWith('package:dio/') ||
            rawImport.startsWith('package:http/') ||
            (target != null && target.contains('/data/'));
        if (importMatch != null && outward) {
          violation('L3', path, n, 'domain layer imports an outer layer');
        }
      }

      // ---- L4: modules never reach the network directly ----------------
      if (path.startsWith('lib/modules/') &&
          (rawImport.startsWith('package:dio/') ||
              rawImport.startsWith('package:http/') ||
              rawImport.startsWith('dart:io'))) {
        violation('L4', path, n, 'module bypasses core/network');
      }
    }
  }

  // ---- C3: no client name in the dictionaries --------------------------
  // Checked on the raw source: a client name inside a translated STRING is the
  // exact defect (88 occurrences in the old app), so comments are not stripped
  // here — instead only string literals are examined.
  final strings = File('lib/core/i18n/strings.dart');
  if (strings.existsSync()) {
    final lines = strings.readAsStringSync().split('\n');
    for (var i = 0; i < lines.length; i++) {
      final literal = RegExp(r"""'([^']*)'""").allMatches(lines[i]);
      for (final match in literal) {
        final lower = match.group(1)!.toLowerCase();
        for (final name in clientNames) {
          if (lower.contains(name)) {
            violation('C3', 'lib/core/i18n/strings.dart', i + 1,
                'client name "$name" in a dictionary string — interpolate {brand} instead');
          }
        }
      }
    }
  }

  if (_violations.isEmpty) {
    stdout.writeln('check_layers: OK — no violations');
    exit(0);
  }
  stderr.writeln('check_layers: ${_violations.length} violation(s)\n');
  for (final v in _violations) {
    stderr.writeln('  $v');
  }
  stderr.writeln('\nSee ARCHITECTURE-MOBILE.md §1.3 and §8.7.');
  exit(1);
}
