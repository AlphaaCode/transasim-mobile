import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// Brand assets are bundled per flavor (pubspec.yaml `flavors:`), so no app
/// carries another client's logo or configuration. `flutter test` has no
/// flavor and bundles none of them, which would leave every golden drawing an
/// error box where the logo is.
///
/// Tests therefore serve `brands/<slug>/…` straight from the repository, the
/// way the matching flavor's bundle would. Everything else still comes from
/// the test bundle, exactly as flutter_test's own handler does.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final bundle = Platform.environment['UNIT_TEST_ASSETS'];

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
    'flutter/assets',
    (message) async {
      final key = Uri.decodeFull(utf8.decode(message!.buffer.asUint8List()));
      for (final file in [
        if (bundle != null) File('$bundle/$key'),
        if (key.startsWith('brands/')) File(key),
      ]) {
        if (file.existsSync()) {
          return ByteData.sublistView(Uint8List.fromList(file.readAsBytesSync()));
        }
      }
      return null;
    },
  );
  await testMain();
}
