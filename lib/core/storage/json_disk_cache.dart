import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// One JSON document kept on disk with the time it was saved.
///
/// For server responses too big for SharedPreferences, which loads its whole
/// store before the first frame. In core because modules do not touch
/// `dart:io` (rule L4).
///
/// Every failure reads as "nothing cached": the worst a broken or purged file
/// can cost is the network fetch the app would have made anyway.
class JsonDiskCache {
  final String _name;

  /// Where the document came from. A copy saved from another source (a debug
  /// build pointed at another backend) is not this document.
  final String _source;

  final Future<Directory> Function() _directory;

  JsonDiskCache({
    required String name,
    required String source,
    Future<Directory> Function()? directory,
  })  : _name = name,
        _source = source,
        // The OS may purge this directory; for a cache that only costs a fetch.
        _directory = directory ?? getApplicationCacheDirectory;

  Future<File> _file() async => File('${(await _directory()).path}/$_name.json');

  Future<({DateTime savedAt, Object? body})?> read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final source = _source;
      // Decoded off the UI isolate: this runs while the intro is playing.
      return await Isolate.run(() {
        final json = jsonDecode(file.readAsStringSync());
        if (json is! Map || json['source'] != source || json['savedAt'] is! int) return null;
        return (
          savedAt: DateTime.fromMillisecondsSinceEpoch(json['savedAt'] as int),
          body: json['body'],
        );
      });
    } catch (e) {
      debugPrint('[cache] $_name unreadable, ignored: $e');
      return null;
    }
  }

  Future<void> write(DateTime savedAt, Object? body) async {
    try {
      final file = await _file();
      final source = _source;
      await Isolate.run(() {
        // Written aside, then renamed: a kill mid-write leaves the old copy.
        final tmp = File('${file.path}.tmp')
          ..writeAsStringSync(jsonEncode({
            'source': source,
            'savedAt': savedAt.millisecondsSinceEpoch,
            'body': body,
          }));
        tmp.renameSync(file.path);
      });
    } catch (e) {
      debugPrint('[cache] $_name not written: $e');
    }
  }
}
