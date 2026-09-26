import 'package:flutter/foundation.dart';

import '../domain/esim.dart';

/// Two plausible eSIMs, for looking at the screen on a real phone without a
/// purchase, a backend or a Transatel provisioning call.
///
/// ⚠️ **Never in a release build.** [kFakeEsimsAllowed] is
/// `!kReleaseMode`, a compile-time constant, so in release the toggle is
/// `false`, the branches that read it are dead, and the tree shaker removes
/// this data from the binary. That is the same guarantee the API_BASE_URL and
/// STRIPE_PUBLISHABLE_KEY overrides give, by the same mechanism.
///
/// `!kReleaseMode` rather than `kDebugMode` deliberately: the builds handed to
/// testers are PROFILE builds, where `kDebugMode` is false. Gating on
/// `kDebugMode` would compile this out of exactly the build it exists for.
const bool kFakeEsimsAllowed = !kReleaseMode;

/// Plans shaped to exercise both ends of the usage maths.
///
/// Both are `active` and expire in the future, which is what it takes for them
/// to render fully: `esimUsageProvider` fetches usage only for plans that can
/// still consume data, and `isExpired` — true the moment `daysRemaining` hits
/// zero — would hide the QR by way of `canInstall`.
List<EsimPlan> fakeEsimPlans() {
  final now = DateTime.now();
  final started = now.subtract(const Duration(days: 3));
  final ends = now.add(const Duration(days: 27));

  return [
    EsimPlan(
      id: -1,
      packName: 'One-off EU28PLUS 10GB 30 day(s)',
      countryCodes: const ['FRA', 'ESP', 'ITA', 'DEU'],
      status: EsimStatus.active,
      dataValueKb: 10 * 1024 * 1024,
      unlimited: false,
      startingDate: started,
      endingDate: ends,
      simSerial: '8933150319876543210F',
      // The GSMA form, so QrImageView renders a scannable code rather than an
      // error box. Not a real SM-DP+: scanning it fails at the operator, which
      // is the point.
      activation: LpaActivation.from(
        activationCode: r'LPA:1$smdp.example.com$FAKE-MATCHING-ID-1234',
      ),
    ),
    EsimPlan(
      id: -2,
      packName: 'One-off Turkey 5GB 15 day(s)',
      countryCodes: const ['TUR'],
      status: EsimStatus.active,
      dataValueKb: 5 * 1024 * 1024,
      unlimited: false,
      startingDate: now.subtract(const Duration(days: 11)),
      endingDate: now.add(const Duration(days: 4)),
      simSerial: '8933150312345678901F',
      activation: LpaActivation.from(
        activationCode: r'LPA:1$smdp.example.com$FAKE-MATCHING-ID-5678',
      ),
    ),
  ];
}

/// Usage keyed by plan id: one barely touched, one nearly gone.
///
/// 8.4 of 10 GB left is 16% used; 0.4 of 5 GB left is 92% used, which is the
/// "under 10% remaining" end. Both are decimals on purpose — `_n()` prints a
/// whole number without a decimal point and a fraction with one, and that
/// asymmetry is only visible with values of both kinds on screen at once.
Map<int, EsimUsage> fakeEsimUsage() => const {
      -1: EsimUsage(totalData: 10, remainingData: 8.4, unit: 'GB'),
      -2: EsimUsage(totalData: 5, remainingData: 0.4, unit: 'GB'),
    };
