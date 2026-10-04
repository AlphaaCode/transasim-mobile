/// What Studio reads from a brand's signing key. Phase 4 (key management)
/// grows this; for now, only the upload key's fingerprint.
library;

import 'dart:io';

/// The SHA-1 of [slug]'s upload certificate, read with keytool from the
/// keystore its `android/<slug>-key.properties` names.
///
/// The store password goes from that file to keytool through the child
/// process's environment (`-storepass:env`), never its command line, and
/// never leaves this function: not logged, not returned, not stored. Nobody
/// types it.
Future<String> uploadKeySha1(String root, String slug) async {
  final props = File('$root/android/$slug-key.properties');
  if (!props.existsSync()) {
    throw StateError('no android/$slug-key.properties: this brand has no upload key yet '
        '(Phase 4 creates one), so its builds are signed with the debug key');
  }
  final p = {
    for (final line in props.readAsLinesSync())
      if (line.indexOf('=') case final i when i > 0) line.substring(0, i).trim(): line.substring(i + 1).trim(),
  };
  final store = File('$root/android/app/${p['storeFile']}');
  if (!store.existsSync()) throw StateError('the keystore ${p['storeFile']} is not in android/app/');
  final home = Platform.environment['JAVA_HOME'];
  final bundled = home == null ? null : '$home/bin/keytool${Platform.isWindows ? '.exe' : ''}';
  final r = await Process.run(
    bundled != null && File(bundled).existsSync() ? bundled : 'keytool',
    ['-list', '-v', '-keystore', store.path, '-alias', '${p['keyAlias']}', '-storepass:env', 'STUDIO_STOREPASS'],
    environment: {'STUDIO_STOREPASS': p['storePassword'] ?? ''},
  );
  final sha1 = RegExp(r'SHA1:\s*((?:[0-9A-F]{2}:){19}[0-9A-F]{2})').firstMatch('${r.stdout}');
  if (r.exitCode != 0 || sha1 == null) {
    throw StateError('keytool could not read the upload key of $slug (exit ${r.exitCode})');
  }
  return sha1[1]!;
}
