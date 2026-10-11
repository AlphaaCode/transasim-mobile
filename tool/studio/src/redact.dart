/// Studio's redactor (docs/STUDIO-SPEC.md §8, §10): every line Studio
/// stores, streams or bundles passes through it first. It removes the
/// values it knows (the keystore passwords on this machine) and the shapes
/// it knows. An unknown secret format passes, which is why the Fix Bundle is
/// shown in full before it is copied.
library;

import 'dart:io';

const _hidden = '[redacted]';

String _all(Match _) => _hidden;
String _keepLabel(Match m) => '${m[1]}$_hidden';

final _shapes = <(String, RegExp, String Function(Match))>[
  // Private keys: a whole block, and a bare base64 body line (a streamed log
  // arrives line by line, so the block may never be seen whole).
  ('a private key', RegExp(r'-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----'), _all),
  ('a base64 key line', RegExp(r'^[A-Za-z0-9+/]{60,}={0,2}$', multiLine: true), _all),
  ('a Stripe secret key', RegExp(r'\b(?:sk|rk)_(?:live|test)_[A-Za-z0-9]+'), _all),
  ('a webhook secret', RegExp(r'\bwhsec_[A-Za-z0-9]+'), _all),
  ('a Google client secret', RegExp(r'\bGOCSPX-[A-Za-z0-9_-]+'), _all),
  ('a keystore password', RegExp(r'\b((?:store|key)Password\s*[=:]\s*)\S+', caseSensitive: false), _keepLabel),
  ('a bearer token', RegExp(r'\b(Bearer\s+)[A-Za-z0-9._~+/-]+=*'), _keepLabel),
  ('a JWT', RegExp(r'\beyJ[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{5,}'), _all),
  // Customer data in device logs, and anyone's address in a git or Gradle line.
  ('an e-mail address', RegExp(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'), (_) => '[email]'),
];

class Redactor {
  Redactor(Iterable<String> known) : _known = known.where((v) => v.length >= 6).toSet().toList()
    // Longest first, so a value containing another is replaced whole.
    ..sort((a, b) => b.length.compareTo(a.length));

  /// The store and key passwords of every `android/<slug>-key.properties`,
  /// parked `.pending` ones included. Read here, used here, never returned.
  factory Redactor.forRepo(String root) {
    final dir = Directory('$root/android');
    final known = <String>[];
    if (dir.existsSync()) {
      for (final f in dir.listSync().whereType<File>()) {
        if (!RegExp(r'-key\.properties(\.pending)?$').hasMatch(f.path)) continue;
        for (final line in f.readAsLinesSync()) {
          if (RegExp(r'^\s*(?:store|key)Password\s*=\s*(.*?)\s*$').firstMatch(line) case final m?) {
            known.add(m[1]!);
          }
        }
      }
    }
    return Redactor(known);
  }

  /// keytool refuses store passwords under 6 characters, so a shorter value
  /// is not one, and replacing it everywhere would shred the log.
  final List<String> _known;

  String call(String text) {
    var out = text;
    for (final v in _known) {
      out = out.replaceAll(v, _hidden);
    }
    for (final (_, re, to) in _shapes) {
      out = out.replaceAllMapped(re, to);
    }
    return out;
  }

  /// What [call] would mask in [text], by kind, never by value.
  List<String> found(String text) => [
        if (_known.any(text.contains)) 'a known password',
        for (final (what, re, _) in _shapes)
          if (re.hasMatch(text)) what,
      ];
}
