import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transasim_mobile/core/brand/app_flavor.dart';
import 'package:transasim_mobile/main_common.dart';

/// Slice H, test (d): fail closed. A build whose backend is the wrong kind of
/// host for its flavor shows why on screen and starts nothing else.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // The real generated bundles, served as the app's assets.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', (message) async {
      final file = File(utf8.decode(message!.buffer.asUint8List()));
      return file.existsSync() ? ByteData.view(Uint8List.fromList(file.readAsBytesSync()).buffer) : null;
    });
  });

  testWidgets("a store build on a host that is not its brand's production one shows why, and does not start", (tester) async {
    // Acorn's store bundle names acorn-api.transasim.com: compiled with another list, it is refused.
    await tester.runAsync(() => bootstrap('acorn', productionHosts: const ['api.other.example']));
    await tester.pump();
    expect(find.byType(ConfigErrorApp), findsOneWidget);
    expect(find.textContaining("talks to acorn-api.transasim.com, which is not acorn's production host"), findsOneWidget);
  });

  testWidgets('a store build with no production host compiled in does not start', (tester) async {
    await tester.runAsync(() => bootstrap('acorn'));
    await tester.pump();
    expect(find.textContaining('none compiled in'), findsOneWidget);
  });

  testWidgets('a DEV build on a production host does not start either', (tester) async {
    await tester.runAsync(() => bootstrap('acorn', flavor: AppFlavor.dev, productionHosts: const ['acorn.transasim.com']));
    await tester.pump();
    expect(find.byType(ConfigErrorApp), findsOneWidget);
    expect(find.textContaining("this DEV build talks to acorn.transasim.com, which is acorn's production host"), findsOneWidget);
  });
}
