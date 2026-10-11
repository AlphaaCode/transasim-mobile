import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/studio/src/incidents.dart';

/// The one incident list (tool/studio/incidents/): Studio's log signatures,
/// the release checklist and the case store all read it, so it is tested as
/// data. Every incident's examples are its own tests.
void main() {
  final incidents = loadIncidents();

  test('the list loads, and every signature carries examples of both kinds', () {
    expect(incidents.length, greaterThanOrEqualTo(20));
    for (final i in incidents.values.where((i) => i.kind == 'signature')) {
      expect(i.match, isNotEmpty, reason: i.id);
      expect(i.matchExamples, isNotEmpty, reason: i.id);
      expect(i.missExamples, isNotEmpty, reason: i.id);
    }
  });

  test('each example is recognised as its own incident and no other', () {
    // Two incidents claiming the same line would be one incident listed twice.
    for (final i in incidents.values) {
      for (final line in i.matchExamples) {
        expect(classify(line, incidents.values).map((m) => m.incident.id), [i.id], reason: line);
      }
      for (final line in i.missExamples) {
        expect(classify(line, [i]), isEmpty, reason: '${i.id} should not match: $line');
      }
    }
  });

  test('a log line the app prints is still printed by the file that says it does', () {
    // An incident matched on our own log text breaks silently if the line is
    // reworded; the source file is checked instead.
    final sourced = incidents.values.where((i) => i.source != null).toList();
    expect(sourced.map((i) => i.id), contains('intro-audio-track'));
    for (final i in sourced) {
      final (file, text) = i.source!;
      expect(File(file).readAsStringSync(), contains(text), reason: '${i.id}: $file');
      expect(i.matchExamples.any((e) => e.contains(text)), isTrue, reason: '${i.id}: no example of "$text"');
    }
  });

  test('classify names the first line that matched, once per incident', () {
    final log = [
      '> Task :app:compileSabilyReleaseKotlin',
      'Gradle build daemon has been stopped: since the JVM garbage collector is thrashing',
      'java.lang.OutOfMemoryError: Java heap space',
      'FAILURE: Build failed with an exception.',
    ].join('\n');
    final found = classify(log, incidents.values);
    expect(found.map((m) => m.incident.id), ['gradle-heap']);
    expect(found.single.line, contains('thrashing'));
  });

  test('a malformed incident is refused with its file name', () {
    final dir = Directory.systemTemp.createTempSync('incidents');
    addTearDown(() => dir.deleteSync(recursive: true));
    Directory('${dir.path}/$incidentsDir').createSync(recursive: true);
    void write(String body) => File('${dir.path}/$incidentsDir/bad.yaml').writeAsStringSync(body);
    const base = 'id: bad\ntitle: t\ncause: c\nfix: f\nevidence: e\ndate: 2026-10-11\ngate: none\n';

    write('${base}kind: signature\nmatch: ["(unclosed"]\nexamples: {match: [x], miss: [y]}\n');
    expect(() => loadIncidents(dir.path), throwsA(isA<FormatException>()
        .having((e) => e.message, 'message', allOf(contains('bad.yaml'), contains('does not compile')))));

    write('${base}kind: signature\nmatch: [x]\n');
    expect(() => loadIncidents(dir.path), throwsA(isA<FormatException>()
        .having((e) => e.message, 'message', contains('examples'))));

    write('${base}kind: check\nautofix: {job: rm-rf, label: x}\n');
    expect(() => loadIncidents(dir.path), throwsA(isA<FormatException>()
        .having((e) => e.message, 'message', contains('rm-rf'))));

    write('${base.replaceFirst('id: bad', 'id: other')}kind: check\n');
    expect(() => loadIncidents(dir.path), throwsA(isA<FormatException>()
        .having((e) => e.message, 'message', contains('file name'))));

    // A check seen in a log too carries examples like a signature.
    write('${base}kind: check\nmatch: [x]\n');
    expect(() => loadIncidents(dir.path), throwsA(isA<FormatException>()
        .having((e) => e.message, 'message', contains('examples'))));

    // The backend phase's fields (§9): env, when, severity.
    for (final (extra, says) in [
      ('env: staging\n', 'env'),
      ('env: dev\nwhen: [weather]\n', 'weather'),
      ('env: dev\nseverity: loud\n', 'severity'),
      ('env: dev\nseverity: {dev: warn, prod: loud}\n', 'severity'),
    ]) {
      write('${base}kind: check\n$extra');
      expect(() => loadIncidents(dir.path), throwsA(isA<FormatException>()
          .having((e) => e.message, 'message', contains(says))), reason: extra);
    }
  });

  test('a backend item says where it is evaluated, when it applies, and how hard it blocks', () {
    final i = incidents['be-unshared']!;
    expect(i.env, 'both');
    expect(i.severity, {'dev': 'warn', 'prod': 'block'});
    expect(incidents['be-anon']!.when, ['vouchers']);
    expect(incidents['mail-shared-account']!.acceptedRisk, isNotEmpty);
    expect(incidents['be-dev-purchase']!.kind, 'checklist');
    expect(incidents['be-dev-purchase']!.gate, 'release');
    expect(incidents.containsKey('backend-tls-expired'), isFalse, reason: 'be-tls took it over');
  });

  test('the checklist items are gates a release or a submission waits on', () {
    final checklist = incidents.values.where((i) => i.kind == 'checklist');
    expect(checklist.map((i) => i.id), contains('deletion-form-reachable'));
    // Since G2 a release waits on it, read from brand.json rather than ticked.
    expect(incidents['apple-account-deletion']!.kind, 'check');
    expect(incidents['apple-account-deletion']!.gate, 'release');
    for (final i in checklist) {
      expect(['test', 'release', 'submit'], contains(i.gate), reason: i.id);
    }
  });
}
