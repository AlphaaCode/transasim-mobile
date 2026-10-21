import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transasim_mobile/core/ui/dev_banner.dart';

/// Slice H: every screen of a DEV build says it talks to a test server, so a
/// DEV build is never taken for the store app.
void main() {
  testWidgets('the banner sits above every screen, under the status bar, and the screen keeps its layout', (tester) async {
    tester.view.padding = const FakeViewPadding(top: 72);
    addTearDown(tester.view.reset);
    late double screenTop;
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => DevBanner(child: child!),
      home: Scaffold(
        body: Builder(builder: (context) {
          screenTop = MediaQuery.paddingOf(context).top;
          return const Text('a screen');
        }),
      ),
    ));
    expect(find.text('TEST SERVER - not for customers'), findsOneWidget);
    expect(tester.getBottomLeft(find.text(DevBanner.text)).dy, lessThanOrEqualTo(tester.getTopLeft(find.text('a screen')).dy));
    // The banner takes the status bar's height, so no screen slides under it.
    expect(tester.getTopLeft(find.text(DevBanner.text)).dy, greaterThanOrEqualTo(72 / tester.view.devicePixelRatio));
    expect(screenTop, 0);
  });
}
