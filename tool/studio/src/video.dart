/// The intro video's checks. Reading needs no tool: the MP4 box structure says
/// which tracks exist and how long the movie is. Only stripping an audio track
/// needs ffmpeg.
library;

import 'dart:io';
import 'dart:typed_data';

class Mp4Info {
  Mp4Info(this.isMp4, this.handlers, this.seconds);

  final bool isMp4;

  /// Track handler types: `vide`, `soun`, `tmcd`...
  final Set<String> handlers;
  final double? seconds;

  bool get hasVideo => handlers.contains('vide');

  /// Even a silent one: a second decoder on a cold start makes the intro miss
  /// its 1.5 s start deadline, and then it never plays (ARCHITECTURE-MOBILE.md
  /// §2.4.1).
  bool get hasAudio => handlers.contains('soun');
}

Mp4Info readMp4(List<int> bytes) {
  final b = Uint8List.fromList(bytes);
  final d = ByteData.sublistView(b);
  var isMp4 = false;
  double? seconds;
  final handlers = <String>{};

  void walk(int start, int end) {
    var i = start;
    while (i + 8 <= end) {
      var size = d.getUint32(i);
      final type = String.fromCharCodes(b.sublist(i + 4, i + 8));
      var header = 8;
      if (size == 1) {
        if (i + 16 > end) return;
        size = d.getUint64(i + 8);
        header = 16;
      } else if (size == 0) {
        size = end - i;
      }
      if (size < header || i + size > end) return; // truncated or not MP4
      final body = i + header;
      switch (type) {
        case 'ftyp':
          isMp4 = true;
        case 'moov' || 'trak' || 'mdia':
          walk(body, i + size);
        case 'mvhd' when body + 32 <= i + size:
          final v1 = b[body] == 1;
          final timescale = d.getUint32(body + (v1 ? 20 : 12));
          final duration = v1 ? d.getUint64(body + 24) : d.getUint32(body + 16);
          if (timescale > 0) seconds = duration / timescale;
        case 'hdlr' when body + 12 <= i + size:
          handlers.add(String.fromCharCodes(b.sublist(body + 8, body + 12)));
      }
      i += size;
    }
  }

  walk(0, b.length);
  return Mp4Info(isMp4, handlers, seconds);
}

/// How to get ffmpeg on this machine, for the message shown when it is missing.
String get ffmpegInstallHint => Platform.isMacOS
    ? 'brew install ffmpeg, then restart Studio'
    : Platform.isWindows
        ? 'winget install Gyan.FFmpeg, then restart Studio (and its terminal) so PATH picks it up'
        : 'install ffmpeg with your package manager, then restart Studio';

Future<bool> hasFfmpeg() async {
  try {
    return (await Process.run('ffmpeg', ['-version'])).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

/// [bytes] with every track but the first video one dropped. Stream copy:
/// the video bytes themselves do not change.
Future<List<int>> stripAudio(List<int> bytes) async {
  final dir = await Directory.systemTemp.createTemp('studio-intro');
  try {
    final input = File('${dir.path}/in.mp4')..writeAsBytesSync(bytes);
    final output = '${dir.path}/out.mp4';
    final r = await Process.run('ffmpeg',
        ['-y', '-i', input.path, '-map', '0:v:0', '-c', 'copy', '-an', '-write_tmcd', '0', output]);
    if (r.exitCode != 0) throw StateError('ffmpeg failed: ${r.stderr}');
    return File(output).readAsBytesSync();
  } finally {
    dir.deleteSync(recursive: true);
  }
}
