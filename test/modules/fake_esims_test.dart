import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' show Color;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transasim_mobile/core/brand/brand_config.dart';
import 'package:transasim_mobile/core/theme/app_theme.dart';
import 'package:transasim_mobile/modules/esim/data/fake_esims.dart';
import 'package:transasim_mobile/modules/esim/domain/esim.dart';
import 'package:transasim_mobile/modules/esim/presentation/esim_screens.dart';
import 'package:transasim_mobile/modules/esim/presentation/esim_controllers.dart';

/// The demo eSIMs exist to be looked at on a device. Two things about them are
/// worth pinning: that they cannot reach a release build, and that they are
/// shaped to render rather than to sit there half-drawn.

void main() {
  test('the gate is !kReleaseMode, and nothing weaker', () {
    // Read as source, because a test binary is never compiled in release mode
    // and so cannot observe the constant doing its job. What it CAN do is stop
    // the gate being quietly widened — to `true`, or to a runtime flag — by
    // someone who wants the demo data in a build that ships.
    final source = File('lib/modules/esim/data/fake_esims.dart').readAsStringSync();
    expect(source, contains('const bool kFakeEsimsAllowed = !kReleaseMode;'));

    // And every reader goes through it, so there is one gate rather than four.
    for (final path in [
      'lib/modules/esim/presentation/esim_controllers.dart',
      'lib/modules/esim/presentation/esim_screens.dart',
    ]) {
      final text = File(path).readAsStringSync();
      for (final line in text.split('\n')) {
        if (line.contains('fakeEsimsProvider') && line.contains('watch')) {
          expect(line, contains('kFakeEsimsAllowed'),
              reason: '$path reads the toggle without the release gate: $line');
        }
      }
    }
  });

  test('both plans render: active, unexpired, installable', () {
    for (final plan in fakeEsimPlans()) {
      // `esimUsageProvider` only fetches for plans that can still consume, and
      // `isExpired` hides the QR through `canInstall`. A fake that fails either
      // check would paint a card with no bar and no code — the two things the
      // demo exists to show.
      expect(plan.status, EsimStatus.active, reason: plan.packName);
      expect(plan.isExpired, isFalse, reason: plan.packName);
      expect(plan.canInstall, isTrue, reason: plan.packName);
      expect(plan.daysRemaining, greaterThan(0));

      final activation = plan.activation!;
      expect(activation.code, startsWith(r'LPA:1$'));
      expect(activation.smdpAddress, isNotEmpty);
      expect(activation.matchingId, isNotEmpty);
      expect(plan.simSerial, isNotNull);
    }
  });

  test('usage covers both ends of the bar', () {
    final usage = fakeEsimUsage();
    final ids = fakeEsimPlans().map((p) => p.id).toSet();
    expect(usage.keys.toSet(), ids, reason: 'a plan with no usage draws no bar');

    final fractions = usage.values.map((u) => u.fraction).toList()..sort();
    expect(fractions.first, lessThan(0.25), reason: 'the barely-touched end');
    expect(fractions.last, greaterThan(0.9), reason: 'the nearly-gone end');
    for (final u in usage.values) {
      expect(u.fraction, inInclusiveRange(0, 1));
      expect(u.usedData, greaterThanOrEqualTo(0));
    }
  });

  group('the bar says how much is LEFT, in the semantic colours of the socle', () {
    // Built from the real Sabily config, so the "healthy" case is the brand's
    // own shop fill rather than a colour invented for the test.
    final brand = () {
      final json = jsonDecode(File('brands/sabily/brand.json').readAsStringSync());
      return BrandConfig.parse(json as Map<String, dynamic>, expectedSlug: 'sabily').config
          as BrandConfig;
    }();
    final t = AppTokens.from(brand);
    final shop = ShopTokens.from(brand, t);

    Color colorFor(EsimUsage u) => usageBarColor(t, shop, u.fraction);

    test('the two demo eSIMs land at opposite ends', () {
      final usage = fakeEsimUsage();
      // EU28PLUS: 8.4 of 10 GB left — 84% remaining.
      expect(colorFor(usage[-1]!), shop.fill, reason: 'healthy should keep the brand fill');
      // Turkey: 0.4 of 5 GB left — 8% remaining.
      expect(colorFor(usage[-2]!), t.danger, reason: 'under 20% left must read as critical');
      expect(shop.fill, isNot(t.danger), reason: 'otherwise this test proves nothing');
    });

    test('the boundaries fall on the documented side', () {
      Color at(double remainingFraction) =>
          colorFor(EsimUsage(totalData: 100, remainingData: remainingFraction * 100, unit: 'MB'));

      expect(at(1.0), shop.fill);
      expect(at(0.5), shop.fill, reason: 'exactly half left is still healthy');
      expect(at(0.49), t.warning);
      expect(at(0.2), t.warning, reason: 'exactly a fifth left is still a warning');
      expect(at(0.19), t.danger);
      expect(at(0), t.danger);
    });

    test('an over-consumed plan clamps instead of flipping colour', () {
      // remainingData > totalData, or negative, are both things a backend can
      // send. `fraction` clamps, so the colour cannot land outside the scale.
      expect(colorFor(const EsimUsage(totalData: 5, remainingData: 9, unit: 'GB')), shop.fill);
      expect(colorFor(const EsimUsage(totalData: 5, remainingData: -1, unit: 'GB')), t.danger);
      expect(colorFor(const EsimUsage(totalData: 0, remainingData: 0, unit: 'GB')), shop.fill,
          reason: 'a zero allowance is not a critical one');
    });
  });

  test('the toggle swaps the list without any network', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(fakeEsimsProvider), isFalse);
    container.read(fakeEsimsProvider.notifier).toggle();
    expect(container.read(fakeEsimsProvider), isTrue);

    // No repository override: reaching one would throw here, so this also
    // proves the fake path short-circuits before the network.
    final plans = await container.read(esimPlansProvider.future);
    expect(plans, hasLength(2));
    expect(plans.first.packName, contains('EU28PLUS'));

    final usage = await container.read(esimUsageProvider.future);
    expect(usage, hasLength(2));
  });

  group('the demo plans can reach the install screen', () {
    // The install card is gated on `canInstall`, and the demo eSIMs are the
    // only way to exercise the Android hand-off without burning a real
    // profile. If this ever goes false, that test path quietly disappears.
    test('at least one demo plan offers Install on this device', () {
      final plans = fakeEsimPlans();
      expect(plans.where((p) => p.canInstall), isNotEmpty);
    });

    test('every demo activation is the GSMA form, and obviously fake', () {
      for (final plan in fakeEsimPlans().where((p) => p.canInstall)) {
        expect(plan.activation!.code, startsWith(r'LPA:1$'));
        expect(plan.activation!.smdpAddress, contains('example.com'),
            reason: 'scanning it must fail at the operator, not provision');
      }
    });
  });

}
