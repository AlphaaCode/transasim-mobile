/// The data-usage bar: which plans get asked, and what the numbers mean.
///
/// ⚠️ TWO DEFECTS THESE TESTS EXIST TO PREVENT.
///
/// 1. Usage was only fetched when `status == active`. A plan the server reports
///    as RELEASED / AVAILABLE / DOWNLOADED parses as `ready`, so no request was
///    ever sent and a real customer's "ready to install" card had no bar. The
///    only bars anyone had seen came from the debug demo fixtures.
/// 2. A missing `unit` defaulted to `'GB'`. That is a guess presented as a
///    fact: a server answering in kilobytes would have rendered "10485760 GB".
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transasim_mobile/core/session/session.dart';
import 'package:transasim_mobile/core/sync/entitlements.dart';
import 'package:transasim_mobile/modules/esim/domain/esim.dart';
import 'package:transasim_mobile/modules/esim/presentation/esim_controllers.dart';

EsimPlan plan({
  int id = 1,
  EsimStatus status = EsimStatus.ready,
  String? serial = '8944000000000041751',
  DateTime? ending,
  bool unlimited = false,
}) =>
    EsimPlan(
      id: id,
      packName: 'Europe 10GB',
      countryCodes: const <String>['FRA'],
      status: status,
      dataValueKb: 10 * 1024 * 1024,
      unlimited: unlimited,
      startingDate: DateTime(2026, 10, 1),
      endingDate: ending ?? DateTime(2099),
      simSerial: serial,
      activation: null,
    );

EsimUsage usage(double total, double remaining, String unit) =>
    EsimUsage(totalData: total, remainingData: remaining, unit: unit);

/// Records which plans were asked about.
class SpyRepo implements EsimRepository {
  SpyRepo(this._plans, {this.answer});

  final List<EsimPlan> _plans;
  final EsimUsage? answer;

  int planCalls = 0;
  final List<int> asked = <int>[];

  @override
  Future<List<EsimPlan>> plans() async {
    planCalls++;
    return _plans;
  }

  @override
  Future<EsimUsage?> usage(EsimPlan p) async {
    asked.add(p.id);
    return answer;
  }
}

ProviderContainer containerOn(SpyRepo repo) {
  final c = ProviderContainer(overrides: [
    bearerTokenProvider.overrideWithValue('token'),
    esimRepositoryProvider.overrideWithValue(repo),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('which plans are asked about', () {
    test('a READY plan is asked — the whole point of the change', () async {
      final repo = SpyRepo([plan(id: 1, status: EsimStatus.ready)]);
      final c = containerOn(repo);

      await c.read(esimUsageProvider.future);

      expect(repo.asked, <int>[1],
          reason: 'a ready plan the server has numbers for must get a bar');
    });

    test('active and unknown are asked too', () async {
      final repo = SpyRepo([
        plan(id: 1, status: EsimStatus.active),
        plan(id: 2, status: EsimStatus.unknown),
      ]);
      final c = containerOn(repo);

      await c.read(esimUsageProvider.future);

      expect(repo.asked..sort(), <int>[1, 2]);
    });

    test('an expired plan is still skipped', () async {
      // Nothing consumes data after it expires, so asking is a request per
      // dead eSIM for an answer that cannot change.
      final repo = SpyRepo([
        plan(id: 1, status: EsimStatus.active),
        plan(id: 2, status: EsimStatus.expired, ending: DateTime(2020)),
      ]);
      final c = containerOn(repo);

      await c.read(esimUsageProvider.future);

      expect(repo.asked, <int>[1]);
    });

    test('a plan with no serial is skipped: there is nothing to ask with',
        () async {
      final repo = SpyRepo([
        plan(id: 1, serial: null),
        plan(id: 2, serial: ''),
        plan(id: 3),
      ]);
      final c = containerOn(repo);

      await c.read(esimUsageProvider.future);

      expect(repo.asked, <int>[3]);
    });

    test('one request per qualifying plan, and no polling', () async {
      final repo = SpyRepo([plan(id: 1), plan(id: 2), plan(id: 3)]);
      final c = containerOn(repo);

      await c.read(esimUsageProvider.future);
      await c.read(esimUsageProvider.future);

      expect(repo.asked.length, 3, reason: 'reading twice does not re-ask');
    });
  });

  group('usage refreshes whenever the list does', () {
    test('invalidating the list produces a new usage fetch', () async {
      final repo = SpyRepo([plan(id: 1)], answer: usage(10, 6, 'GB'));
      final c = containerOn(repo);

      await c.read(esimUsageProvider.future);
      expect(repo.asked, <int>[1]);

      // Pull-to-refresh, and the focus/resume path, both do exactly this.
      c.invalidate(esimPlansProvider);
      await c.read(esimUsageProvider.future);

      expect(repo.asked, <int>[1, 1], reason: 'usage follows the list');
      expect(repo.planCalls, 2);
    });

    test('a purchase or voucher refetches usage too', () async {
      final repo = SpyRepo([plan(id: 1)], answer: usage(10, 6, 'GB'));
      final c = containerOn(repo);

      await c.read(esimUsageProvider.future);
      expect(repo.asked.length, 1);

      c.read(entitlementsRevisionProvider.notifier).bump();
      await c.read(esimUsageProvider.future);

      expect(repo.asked.length, 2);
    });
  });

  group('the unit is read, never assumed', () {
    test('the units a backend plausibly sends all convert', () {
      expect(kilobytesPerUnit('GB'), 1024 * 1024);
      expect(kilobytesPerUnit('gb'), 1024 * 1024);
      expect(kilobytesPerUnit('Go'), 1024 * 1024); // French
      expect(kilobytesPerUnit('MB'), 1024);
      expect(kilobytesPerUnit('Mo'), 1024);
      expect(kilobytesPerUnit('KB'), 1);
      expect(kilobytesPerUnit('Ko'), 1);
      expect(kilobytesPerUnit('B'), 1 / 1024);
      expect(kilobytesPerUnit('bytes'), 1 / 1024);
    });

    test('an unknown or absent unit converts to nothing, not to GB', () {
      // The defect: `?? 'GB'` made every unitless answer read as gigabytes.
      expect(kilobytesPerUnit(null), isNull);
      expect(kilobytesPerUnit(''), isNull);
      expect(kilobytesPerUnit('  '), isNull);
      expect(kilobytesPerUnit('blocks'), isNull);
      expect(usage(10, 6, '').hasKnownUnit, isFalse);
      expect(usage(10, 6, 'blocks').totalKilobytes, isNull);
    });

    test('a GB answer converts', () {
      final u = usage(10, 6, 'GB');
      expect(u.totalKilobytes, 10 * 1024 * 1024);
      expect(u.usedKilobytes, 4 * 1024 * 1024);
    });

    test('an MB answer converts', () {
      final u = usage(500, 500, 'MB');
      expect(u.totalKilobytes, 500 * 1024);
      expect(u.usedKilobytes, 0, reason: '0 used is real data, not absence');
    });

    test('a KB answer converts, and does not become gigabytes', () {
      final u = usage(10485760, 5242880, 'KB');
      expect(u.totalKilobytes, 10485760);
      // 10 GB expressed in KB. Under the old default this rendered as
      // "10485760 GB".
      expect(u.totalKilobytes! / (1024 * 1024), 10);
    });
  });

  group('no NaN, no divide by zero', () {
    test('a zero total gives a zero fraction and no bar', () {
      final u = usage(0, 0, 'GB');
      expect(u.fraction, 0);
      expect(u.fraction.isNaN, isFalse);
      expect(u.hasMeasurableTotal, isFalse);
    });

    test('a negative total is not measurable either', () {
      final u = usage(-1, 0, 'GB');
      expect(u.hasMeasurableTotal, isFalse);
      expect(u.fraction, 0);
    });

    test('remaining above total clamps instead of going negative', () {
      final u = usage(10, 12, 'GB');
      expect(u.usedData, 0);
      expect(u.fraction, 0);
    });

    test('an over-consumed plan clamps at one', () {
      final u = usage(10, -2, 'GB');
      expect(u.fraction, 1);
    });

    test('an unlimited plan is asked about but draws no bar', () async {
      // It still has a serial and has not expired, so the request is made —
      // "used X" is worth showing. There is simply no denominator to draw.
      final repo = SpyRepo(
        [plan(id: 1, unlimited: true)],
        answer: usage(0, 0, 'GB'),
      );
      final c = containerOn(repo);

      await c.read(esimUsageProvider.future);

      expect(repo.asked, <int>[1]);
      expect(usage(0, 0, 'GB').hasMeasurableTotal, isFalse);
    });
  });
}
