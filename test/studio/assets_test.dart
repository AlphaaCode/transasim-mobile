import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../../tool/studio/src/assets.dart';
import '../../tool/studio/src/video.dart';

/// An MP4 reduced to the boxes Studio reads: ftyp, then moov holding mvhd
/// (timescale, duration) and one trak per [handlers] entry.
List<int> mp4(List<String> handlers, {int timescale = 1000, int duration = 4000}) {
  List<int> box(String type, List<int> body) {
    final b = BytesBuilder()
      ..add((ByteData(4)..setUint32(0, body.length + 8)).buffer.asUint8List())
      ..add(type.codeUnits)
      ..add(body);
    return b.toBytes();
  }

  final mvhd = ByteData(100)
    ..setUint32(12, timescale)
    ..setUint32(16, duration);
  return [
    ...box('ftyp', 'isom'.codeUnits),
    ...box('moov', [
      ...box('mvhd', mvhd.buffer.asUint8List()),
      for (final h in handlers)
        ...box('trak', box('mdia', box('hdlr', [0, 0, 0, 0, 0, 0, 0, 0, ...h.codeUnits, 0, 0, 0, 0]))),
    ]),
  ];
}

void main() {
  group('the intro video reader', () {
    test('finds an audio track, which would stop the intro from playing', () {
      final info = readMp4(mp4(['vide', 'soun']));
      expect(info.isMp4, isTrue);
      expect(info.hasVideo, isTrue);
      expect(info.hasAudio, isTrue);
      expect(info.seconds, 4.0);
    });

    test('a video-only file is clean', () {
      final info = readMp4(mp4(['vide'], timescale: 600, duration: 2910));
      expect((info.hasAudio, info.seconds), (false, 4.85));
    });

    test('anything else is not an MP4', () {
      expect(readMp4([1, 2, 3, 4, 5, 6, 7, 8, 9]).isMp4, isFalse);
    });

    test('the three shipped intros have no audio track', () {
      for (final slug in ['sabily', 'esimple', 'acorn']) {
        final info = readMp4(File('brands/$slug/assets/logo-intro.mp4').readAsBytesSync());
        expect((info.hasVideo, info.hasAudio), (true, false), reason: slug);
      }
    });
  });

  group('a dropped file', () {
    final photo = img.encodeJpg(img.Image(width: 1600, height: 1200), quality: 50);

    test('a pack image without a source and a licence is refused', () async {
      final plan = await assetPlan('.', 'acorn', 'pack:europe', photo);
      expect(plan.errors.map((e) => e['reason']), [contains('source'), contains('licence')]);
      expect(plan.binary, isEmpty);
    });

    test('a pack image becomes a 1200×675 JPEG and a credits row', () async {
      final plan = await assetPlan('.', 'acorn', 'pack:europe', photo,
          credit: {'source': 'test fixture', 'licence': 'CC0'});
      expect(plan.errors, isEmpty);
      final out = img.decodeJpg(Uint8List.fromList(plan.binary.single.after))!;
      expect((out.width, out.height), (1200, 675));
      final credits = plan.text.singleWhere((c) => c.path.endsWith('PACK-IMAGES-CREDITS.md'));
      expect(credits.after, contains('| `pack-europe.jpg` | europe | test fixture | CC0 | — |'));
    });

    test('a photo is not a logo mark: refused with the reason', () async {
      final plan = await assetPlan('.', 'acorn', 'mark', photo);
      expect(plan.errors.single['reason'], contains('not square'));
    });

    test('bytes that are not an image are refused, not crashed on', () async {
      final plan = await assetPlan('.', 'acorn', 'full', [0, 1, 2, 3]);
      expect(plan.errors.single['reason'], contains('not an image'));
    });

    test('an unknown drop zone is refused', () async {
      expect((await assetPlan('.', 'acorn', 'pack:../../etc', photo)).errors, isNotEmpty);
    });
  });
}
