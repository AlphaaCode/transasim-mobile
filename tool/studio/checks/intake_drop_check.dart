// ignore_for_file: avoid_print
/// The intake drop zone in a real Chrome: `dart run tool/studio/checks/intake_drop_check.dart`
/// with Studio running on 127.0.0.1:4777. Headless, previews only, writes nothing in the repo.
///
/// Drags go through DevTools' Input.dispatchDragEvent with real file paths:
/// Chrome builds the DataTransfer and its file entries itself, as it does for a
/// drag from Explorer. One fresh page per check: the headless renderer stalls
/// when one page runs long (CLAUDE.md, "Checking Studio's UI").
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;

const _studio = 'http://127.0.0.1:4777';
const _port = 9335;
final _fixture = File('test/studio/fixtures/intake/spc-intake-nimbus.json');

late WebSocket _ws;
var _id = 0;
final _pending = <int, Completer<Map>>{};
var _failed = 0;

Future<Map> _send(String method, [Map params = const {}]) {
  final c = Completer<Map>();
  _pending[++_id] = c;
  _ws.add(jsonEncode({'id': _id, 'method': method, 'params': params}));
  return c.future.timeout(const Duration(seconds: 20), onTimeout: () => throw StateError('no answer to $method'));
}

Future<Object?> _js(String expr) async {
  final r = (await _send('Runtime.evaluate', {'expression': expr, 'awaitPromise': true, 'returnByValue': true}))['result'] as Map;
  if (r['exceptionDetails'] != null) throw StateError('page: ${jsonEncode(r['exceptionDetails'])}');
  return (r['result'] as Map)['value'];
}

void _check(String what, bool ok, [Object? detail]) {
  if (!ok) _failed++;
  print('${ok ? 'ok  ' : 'FAIL'} $what${detail == null ? '' : ': $detail'}');
}

/// Waits in the page until [cond] (a JS expression) holds, at most [seconds].
Future<bool> _until(String cond, {int seconds = 10}) async =>
    await _js('(async () => { for (let i = 0; i < ${seconds * 10}; i++) { if ($cond) return true; '
        'await new Promise((r) => setTimeout(r, 100)); } return false; })()') == true;

/// A real drag of [paths] onto the page at the centre of [selector]'s box (or [at]).
Future<void> _drag(List<String> paths, String selector, {(double, double)? at}) async {
  final box = (await _js('(() => { const r = document.querySelector(${jsonEncode(selector)}).getBoundingClientRect(); '
      'return [r.left, r.top, r.width, r.height]; })()') as List).cast<num>();
  final (x, y) = at ?? (box[0] + box[2] / 2, box[1] + box[3] / 2);
  final data = {'items': <Map>[], 'files': paths, 'dragOperationsMask': 1};
  for (final type in ['dragEnter', 'dragOver', 'drop']) {
    await _send('Input.dispatchDragEvent', {'type': type, 'x': x, 'y': y, 'data': data});
  }
}

/// Opens [hash] in a fresh tab; with [early], runs [early] the moment the page's scripts exist.
Future<void> _open(String hash, {String? early}) async {
  final c = HttpClient()..findProxy = (_) => 'DIRECT';
  final tab = jsonDecode(await (await (await c.putUrl(Uri.parse('http://127.0.0.1:$_port/json/new?about:blank'))).close())
      .transform(utf8.decoder).join()) as Map;
  c.close(force: true);
  _ws = await WebSocket.connect(tab['webSocketDebuggerUrl'] as String);
  _ws.listen((m) {
    final d = jsonDecode(m as String) as Map;
    if (d['id'] case final int i) _pending.remove(i)?.complete(d);
    if (d['method'] == 'Runtime.exceptionThrown') {
      _failed++;
      print('FAIL page exception: ${jsonEncode(d['params']['exceptionDetails']['exception']?['description'])}');
    }
  });
  await _send('Runtime.enable');
  await _send('Page.enable');
  await _send('Page.navigate', {'url': '$_studio/#$hash'});
  if (early != null) {
    await _until("typeof showView === 'function' && document.getElementById('new-brand')", seconds: 10);
    await _js(early);
  }
  await _until("typeof state === 'object' && state.slug === '$hash'", seconds: 20);
}

Future<void> main() async {
  final tmp = Directory.systemTemp.createTempSync('intake-drop');
  final chromeDir = Directory('${tmp.path}/chrome')..createSync();
  // The fixture's logo is named in files[] and has no sha256: matched by name.
  final logo = File('${tmp.path}/[Upload] Logo File — nimbus-mark.png')
    ..writeAsBytesSync(img.encodePng(img.Image(width: 512, height: 512)..clear(img.ColorRgb8(30, 90, 168))));
  final json = File('${tmp.path}/spc-intake-nimbus.json')..writeAsBytesSync(_fixture.readAsBytesSync());
  final zip = File('${tmp.path}/Nimbus-Drive.zip')
    ..writeAsBytesSync(ZipEncoder().encodeBytes(Archive()
      ..addFile(ArchiveFile.bytes('Nimbus/spc-intake-nimbus.json', json.readAsBytesSync()))
      ..addFile(ArchiveFile.bytes('Nimbus/${logo.uri.pathSegments.last}', logo.readAsBytesSync()))));
  String p(File f) => f.absolute.path;

  final chrome = await Process.start(
      Platform.environment['CHROME'] ?? r'C:\Program Files\Google\Chrome\Application\chrome.exe', [
    '--headless=new', '--no-first-run', '--remote-debugging-port=$_port', '--remote-allow-origins=*',
    '--window-size=1600,1100', '--user-data-dir=${chromeDir.absolute.path}', 'about:blank',
  ]);
  try {
    for (var i = 0; i < 40; i++) {
      try {
        await (await Socket.connect('127.0.0.1', _port)).close();
        break;
      } on SocketException {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
    await _checks(p(json), p(logo), p(zip)).timeout(const Duration(minutes: 3));
  } on Object catch (e) {
    _failed++;
    print('FAIL $e');
  } finally {
    chrome.kill();
    await chrome.exitCode;
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException {
      // Chrome may still hold its profile for a moment; the temp folder is the OS's to clean.
    }
  }
  print(_failed == 0 ? 'intake drop: all checks passed' : 'intake drop: $_failed failed');
  exit(_failed == 0 ? 0 : 1);
}

Future<void> _checks(String json, String logo, String zip) async {
  // 1. "+ New brand" pressed before the brands have loaded stays on New brand, tabs off.
  await _open('sabily', early: "document.getElementById('new-brand').click()");
  _check('an early "+ New brand" click is kept', await _js('state.view') == 'wizard', await _js('state.view'));
  _check('brand tabs are off on New brand, with the hint shown',
      await _js("[...document.querySelectorAll('.tab[data-view]')].filter((t) => t.disabled).map((t) => t.dataset.view).join(',')") ==
              'brand,assets,integrations,backend,build' &&
          await _js("!document.getElementById('tabs-hint').hidden") == true);

  // 2. A real drag of the JSON and the logo, onto the panel's corner, not its text.
  await _js("document.querySelector('#view-wizard .intake-panel').scrollIntoView()");
  final corner = (await _js("(() => { const r = document.querySelector('#view-wizard .intake-panel').getBoundingClientRect(); "
      "return [r.right - 12, r.bottom - 12]; })()") as List).cast<num>();
  await _send('Input.dispatchDragEvent', {'type': 'dragEnter', 'x': corner[0], 'y': corner[1], 'data': {'items': [], 'files': [json, logo], 'dragOperationsMask': 1}});
  await _send('Input.dispatchDragEvent', {'type': 'dragOver', 'x': corner[0], 'y': corner[1], 'data': {'items': [], 'files': [json, logo], 'dragOperationsMask': 1}});
  _check('the panel lights up while a file is over it', await _js("document.querySelector('#view-wizard .intake-panel').classList.contains('over')") == true);
  await _send('Input.dispatchDragEvent', {'type': 'drop', 'x': corner[0], 'y': corner[1], 'data': {'items': [], 'files': [json, logo], 'dragOperationsMask': 1}});
  _check('New brand: a real drag fills the form', await _until("wizard.form.slug === 'nimbusroam' && wizard.form.country === 'DZ'"),
      await _js('JSON.stringify({slug: wizard.form.slug, logo: wizard.logoName})'));
  _check('New brand: the logo came with it', await _js('wizard.logoName') == '[Upload] Logo File — nimbus-mark.png');
  _check('New brand: the status stays after the re-render',
      '${await _js("document.querySelector('#view-wizard .intake-said')?.textContent")}'.startsWith('Read: '),
      await _js("document.querySelector('#view-wizard .intake-said')?.textContent"));

  // 3. The Brand tab: the Drive zip and its JSON dragged together, as a user does.
  await _open('acorn');
  await _drag([zip, json], '#intake-brand');
  _check('Brand tab: zip + JSON together are read as one intake', await _until("document.querySelectorAll('.intake-offer tr').length > 1"),
      await _js("document.querySelector('#intake-brand .intake-said')?.textContent"));
  _check('Brand tab: the status names what was read',
      '${await _js("document.querySelector('#intake-brand .intake-said')?.textContent")}'.contains('client intake 0f3c2b9e'));

  // 4. A File built in the page, dropped through a DataTransfer onto a child of the zone.
  await _open('acorn');
  final synthetic = await _js('(async () => { const dt = new DataTransfer(); '
      'dt.items.add(new File([${jsonEncode(_fixture.readAsStringSync())}], "spc-intake-nimbus.json", { type: "application/json" })); '
      'document.querySelector("#intake-brand .intake-hint").dispatchEvent(new DragEvent("drop", { dataTransfer: dt, bubbles: true, cancelable: true })); '
      'for (let i = 0; i < 100 && !document.querySelector(".intake-offer"); i++) await new Promise((r) => setTimeout(r, 100)); '
      'return document.querySelectorAll(".intake-offer tr").length; })()');
  _check('a File dropped via DataTransfer on the hint text reaches the zone', (synthetic as int) > 1, '$synthetic rows');

  // 5. A drop outside every zone: refused, and Chrome does not open the file.
  await _open('acorn');
  final before = await _js('location.href');
  await _drag([json], '#form');
  await Future<void>.delayed(const Duration(seconds: 1));
  _check('a drop outside the zone does not open the file', await _js('location.href') == before, await _js('location.href'));
  _check('a drop outside the zone reads nothing', await _js("document.querySelector('.intake-offer') === null") == true);

  // 6. A refusal is said, and stays said.
  await _open('acorn');
  final bad = File('${File(json).parent.path}/spc-intake-bad.json')..writeAsStringSync('{"kind": "other"}');
  await _drag([bad.path], '#intake-brand');
  _check('a refusal is shown', await _until("(document.querySelector('#intake-brand .intake-said')?.textContent ?? '').startsWith('Refused')"),
      await _js("document.querySelector('#intake-brand .intake-said')?.textContent"));
}
