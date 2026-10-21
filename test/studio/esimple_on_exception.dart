import 'dart:convert';
import 'dart:io';

import '../../tool/studio/src/hosts.dart' show repinned;

/// eSimple as it was until 21/10/2026: its DEV server (esimple.transasim.com)
/// standing in for production under a recorded exception "until the merge".
///
/// The exception is ended, and brands/esimple/ now points at production. The
/// exception MACHINERY is still the product (a brand can be put back on one),
/// and several tests exist to prove it refuses what it must. They used the live
/// eSimple as their example; now they build this state themselves, on a map or
/// on their own copy of the repo, and never touch the real files.
const esimpleProductionUrl = 'https://api.esimple.at/api';
const esimpleDevUrl = 'https://esimple.transasim.com/api';
const esimpleExceptionReason = 'DEV server serving as production until the merge';

Map<String, dynamic> _copy(Map<String, dynamic> m) => jsonDecode(jsonEncode(m)) as Map<String, dynamic>;

/// [brand] with its store host on the exception's URL, as it was then.
Map<String, dynamic> brandOnException(Map<String, dynamic> brand) {
  final b = _copy(brand);
  (b['mobile'] as Map)['apiBaseUrl'] = esimpleDevUrl;
  return b;
}

/// [studio] with the production pin kept and the exception standing.
Map<String, dynamic> studioOnException(Map<String, dynamic> studio, {DateTime? now}) => repinned(
      _copy(studio),
      apiBaseUrl: esimpleProductionUrl,
      reason: esimpleExceptionReason,
      exceptionUrl: esimpleDevUrl,
      now: now ?? DateTime.utc(2026, 10, 20, 23, 42),
    );

/// A temporary root holding every brand's brand.json and studio.json: all the
/// host and release rules read. The caller deletes it.
Directory copyOfBrandFiles() {
  final copy = Directory.systemTemp.createTempSync('brands');
  for (final slug in ['acorn', 'esimple', 'sabily']) {
    for (final f in ['brand.json', 'studio.json']) {
      File('${copy.path}/brands/$slug/$f')
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(File('brands/$slug/$f').readAsBytesSync());
    }
  }
  return copy;
}

/// Puts eSimple, in [root] (a copy of the repo), back on its exception:
/// brand.json and studio.json, which is all the release and host rules read.
void putEsimpleOnException(String root) {
  const pretty = JsonEncoder.withIndent('  ');
  final brandFile = File('$root/brands/esimple/brand.json');
  final studioFile = File('$root/brands/esimple/studio.json');
  brandFile.writeAsStringSync(
      '${pretty.convert(brandOnException(jsonDecode(brandFile.readAsStringSync()) as Map<String, dynamic>))}\n');
  studioFile.writeAsStringSync(
      '${pretty.convert(studioOnException(jsonDecode(studioFile.readAsStringSync()) as Map<String, dynamic>))}\n');
}

/// Makes eSimple's generated files in [root] the ones it had before the
/// exception ended, so Go prod has something to change: no DEV flavor, the
/// exception's host in the store entry point and bundle.
void putEsimpleGeneratedFilesBack(String root) {
  for (final dev in [
    'brands/esimple/flavor/esimpleDev.json',
    'lib/flavors/main_esimple_dev.dart',
    'ios/Flutter/esimpleDev.xcconfig',
  ]) {
    final f = File('$root/$dev');
    if (f.existsSync()) f.deleteSync();
  }
  final entry = File('$root/lib/flavors/main_esimple.dart');
  entry.writeAsStringSync(entry.readAsStringSync().replaceFirst(
      "const ['api.esimple.at', 'api.esimple.transasim.com']",
      "const ['api.esimple.at', 'api.esimple.transasim.com', 'esimple.transasim.com']"));
  final bundle = File('$root/brands/esimple/flavor/esimple.json');
  bundle.writeAsStringSync(bundle.readAsStringSync().replaceFirst(esimpleProductionUrl, esimpleDevUrl));
  final pubspec = File('$root/pubspec.yaml');
  pubspec.writeAsStringSync(pubspec.readAsStringSync()
      .replaceFirst('    - path: brands/esimple/flavor/esimpleDev.json\n      flavors: [esimpleDev]\n', '')
      .replaceFirst('flavors: [esimple, esimpleDev]', 'flavors: [esimple]'));
}
