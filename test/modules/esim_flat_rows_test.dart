/// The production row shape, which is FLAT.
///
/// ⚠️ THE DEFECT THESE TESTS EXIST TO PREVENT. `_parsePlan` returned null for
/// any row without `pack.name`, and production sends no `pack` object at all —
/// `GET /v1/sub-plans/subscriber` answers 150-180 bytes per row, which is
/// `{id, startingDate, endingDate, packId, productId, esimProfileId}`. So the
/// list was empty for every real customer while the screen said "No eSIM yet",
/// to people who had just paid.
///
/// The harness comes from `esim_test.dart`, which owns the request-counting
/// `FakeWire` — the request COUNT is the other half of this screen's contract
/// and both halves are asserted against the same fake.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:transasim_mobile/core/network/api_client.dart';
import 'package:transasim_mobile/modules/esim/data/esim_repository_impl.dart';
import 'package:transasim_mobile/modules/esim/domain/esim.dart';

import 'esim_test.dart' show FakeWire, repoOn, subPlan;

/// A row exactly as production sends it: ids and dates, nothing nested.
Map<String, dynamic> liveRow({
  int id = 1,
  int? packId = 3610,
  int? esimProfileId = 41751,
  String? starting = '2026-10-04T19:16:44Z',
  String? ending = '2026-11-04T19:16:44Z',
}) =>
    <String, dynamic>{
      'id': id,
      'startingDate': starting,
      'endingDate': ending,
      'packId': packId,
      'productId': null,
      'esimProfileId': esimProfileId,
    };

Map<String, dynamic> profileRow({
  int id = 41751,
  String status = 'ACTIVE',
  String? serial = '8944000000000041751',
  String? smdp = 'rsp.truphone.com',
  String? matchingId = 'ACT-41751-XYZ',
  String? activationCode,
}) =>
    <String, dynamic>{
      'id': id,
      'status': status,
      'simSerial': serial,
      'smdpAddress': smdp,
      'matchingId': matchingId,
      'activationCode': activationCode,
    };

Map<String, dynamic> packRow({int id = 3610, String name = 'Europe 10GB 30 days'}) =>
    <String, dynamic>{
      'id': id,
      'name': name,
      'dataValue': 10 * 1024 * 1024,
      'unlimited': false,
      'countries': [
        {'code': 'FRA', 'name': 'France'}
      ],
    };

void main() {
  group('a flat row renders', () {
    test('the live row gets a pack name and a working activation QR', () async {
      // This fixture is a real row, copied verbatim from the production
      // response. Nothing about it is nested.
      final wire = FakeWire({
        '/v1/sub-plans/subscriber': [
          {
            'id': 1,
            'startingDate': '2026-10-04T19:16:44Z',
            'endingDate': '2026-11-04T19:16:44Z',
            'packId': 3610,
            'productId': null,
            'esimProfileId': 41751,
          },
        ],
        '/v1/esim-profiles/subscriber': [profileRow(id: 41751)],
        '/v1/packs/3610': packRow(id: 3610, name: 'Europe 10GB 30 days'),
      });

      final plans = await repoOn(wire).plans();

      expect(plans, hasLength(1), reason: 'the row the customer paid for');
      final plan = plans.single;
      expect(plan.id, 1);
      expect(plan.packName, 'Europe 10GB 30 days');
      expect(plan.detailsUnavailable, isFalse);

      // The profile joined on esimProfileId, and the QR is the GSMA string
      // a phone's camera will actually accept.
      expect(plan.simSerial, '8944000000000041751');
      expect(plan.status, EsimStatus.active);
      expect(plan.activation, isNotNull);
      expect(plan.activation!.code, r'LPA:1$rsp.truphone.com$ACT-41751-XYZ');
      expect(plan.activation!.smdpAddress, 'rsp.truphone.com');
      expect(plan.activation!.matchingId, 'ACT-41751-XYZ');
      expect(plan.canInstall, isTrue, reason: 'the QR is scannable, not decorative');

      // And the dates survived the join.
      expect(plan.startingDate, isNotNull);
      expect(plan.endingDate, isNotNull);
    });

    test('a server-supplied LPA string wins over re-deriving one', () async {
      final wire = FakeWire({
        '/v1/sub-plans/subscriber': [liveRow()],
        '/v1/esim-profiles/subscriber': [
          profileRow(activationCode: r'LPA:1$rsp.example.com$FULL-CODE'),
        ],
        '/v1/packs/3610': packRow(),
      });
      final plan = (await repoOn(wire).plans()).single;
      expect(plan.activation!.code, r'LPA:1$rsp.example.com$FULL-CODE');
    });
  });

  group('the join is one request per endpoint, not one per row', () {
    test('three rows share a single profiles call and two pack calls', () async {
      final wire = FakeWire({
        '/v1/sub-plans/subscriber': [
          liveRow(id: 1, esimProfileId: 41751, packId: 3610),
          liveRow(id: 2, esimProfileId: 41752, packId: 3610),
          liveRow(id: 3, esimProfileId: 41753, packId: 3611),
        ],
        '/v1/esim-profiles/subscriber': [
          profileRow(id: 41751, serial: 'A'),
          profileRow(id: 41752, serial: 'B'),
          profileRow(id: 41753, serial: 'C'),
        ],
        '/v1/packs/3610': packRow(id: 3610, name: 'Europe'),
        '/v1/packs/3611': packRow(id: 3611, name: 'Turkey'),
      });

      final plans = await repoOn(wire).plans();

      expect(plans, hasLength(3));
      expect(plans.map((p) => p.simSerial).toSet(), <String>{'A', 'B', 'C'});
      expect(
        wire.sent.where((r) => r.path.contains('esim-profiles')).length,
        1,
        reason: 'one join for the whole list',
      );
      // Two DISTINCT packs across three rows, so two calls — not three.
      expect(wire.sent.where((r) => r.path.startsWith('/v1/packs/')).length, 2);
    });

    test('a nested row still costs exactly one request', () async {
      // The staging shape must not regress into making follow-up calls.
      final wire = FakeWire({
        '/v1/sub-plans/subscriber': [subPlan(id: 1), subPlan(id: 2)],
      });
      final plans = await repoOn(wire).plans();
      expect(plans, hasLength(2));
      expect(wire.sent.length, 1, reason: 'nothing to join, so nothing is asked');
    });

    test('flat and nested rows in one response both render', () async {
      final wire = FakeWire({
        '/v1/sub-plans/subscriber': [
          subPlan(id: 1, name: 'Nested Pack'),
          liveRow(id: 2, packId: 3610, esimProfileId: 41751),
        ],
        '/v1/esim-profiles/subscriber': [profileRow(id: 41751)],
        '/v1/packs/3610': packRow(name: 'Flat Pack'),
      });

      final plans = await repoOn(wire).plans();

      expect(plans.map((p) => p.packName).toSet(), <String>{'Nested Pack', 'Flat Pack'});
      expect(plans.any((p) => p.detailsUnavailable), isFalse);
      // The nested row contributed nothing to the join.
      expect(wire.sent.where((r) => r.path.startsWith('/v1/packs/')).length, 1);
    });
  });

  group('an unresolvable row is shown, never swallowed', () {
    test('a pack that cannot be fetched still lists the plan', () async {
      // `/v1/packs/3610` is absent from the wire, so the body comes back null
      // and the pack stays unresolved.
      final wire = FakeWire({
        '/v1/sub-plans/subscriber': [liveRow()],
        '/v1/esim-profiles/subscriber': [profileRow()],
      });
      final plans = await repoOn(wire).plans();

      expect(plans, hasLength(1), reason: 'the user paid for it, so it is listed');
      expect(plans.single.detailsUnavailable, isTrue);
      expect(plans.single.packName, isEmpty, reason: 'the card supplies the placeholder');
      // The profile still joined, so a missing pack does not cost the QR.
      expect(plans.single.simSerial, isNotNull);
      expect(plans.single.activation, isNotNull);
    });

    test('a profile that cannot be joined still lists the plan', () async {
      final wire = FakeWire({
        '/v1/sub-plans/subscriber': [liveRow()],
        '/v1/esim-profiles/subscriber': <dynamic>[],
        '/v1/packs/3610': packRow(),
      });
      final plans = await repoOn(wire).plans();

      expect(plans, hasLength(1));
      expect(plans.single.packName, 'Europe 10GB 30 days');
      expect(plans.single.detailsUnavailable, isTrue);
      expect(plans.single.activation, isNull, reason: 'nothing to install yet');
    });
  });

  group('the catalogue is consulted before the network', () {
    test('a pack the Store already holds costs no request', () async {
      final wire = FakeWire({
        '/v1/sub-plans/subscriber': [liveRow()],
        '/v1/esim-profiles/subscriber': [profileRow()],
      });
      final api = ApiClient(
        baseUrl: 'https://example.test/api',
        token: () => 'token',
        language: () => 'en',
        dio: wire.dio,
      );
      wire.arm();
      final repo = EsimRepositoryImpl(
        api,
        packLookup: (id) async => id == 3610
            ? const EsimPackInfo(name: 'From the catalogue', countryCodes: <String>['FRA'])
            : null,
      );

      final plan = (await repo.plans()).single;
      expect(plan.packName, 'From the catalogue');
      expect(plan.detailsUnavailable, isFalse);
      expect(wire.sent.where((r) => r.path.startsWith('/v1/packs/')), isEmpty,
          reason: 'the Store already had it');
    });

    test('a pack the catalogue does not hold falls back to the endpoint', () async {
      final wire = FakeWire({
        '/v1/sub-plans/subscriber': [liveRow(packId: 9999)],
        '/v1/esim-profiles/subscriber': [profileRow()],
        '/v1/packs/9999': packRow(id: 9999, name: 'Fetched'),
      });
      final api = ApiClient(
        baseUrl: 'https://example.test/api',
        token: () => 'token',
        language: () => 'en',
        dio: wire.dio,
      );
      wire.arm();
      final repo = EsimRepositoryImpl(api, packLookup: (_) async => null);

      final plan = (await repo.plans()).single;
      expect(plan.packName, 'Fetched');
      expect(wire.sent.where((r) => r.path.startsWith('/v1/packs/')).length, 1);
    });
  });
}
