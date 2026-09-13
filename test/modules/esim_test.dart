import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transasim_mobile/core/network/api_client.dart';
import 'package:transasim_mobile/modules/esim/data/esim_install.dart';
import 'package:transasim_mobile/modules/esim/data/esim_repository_impl.dart';
import 'package:transasim_mobile/modules/esim/domain/esim.dart';

/// A dio that answers from memory and records what it was asked, so the
/// REQUEST COUNT is assertable — which is the point of this screen.
class FakeWire {
  final List<RequestOptions> sent = <RequestOptions>[];
  final Dio dio = Dio();

  /// path -> body
  final Map<String, Object?> routes;

  /// Held open until released, so overlap can be observed rather than assumed.
  final List<Completer<void>> gates = [];
  final bool gateConsumption;

  FakeWire(this.routes, {this.gateConsumption = false});

  void arm() {
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) async {
      sent.add(options);
      if (gateConsumption && options.path.contains('consumption')) {
        final gate = Completer<void>();
        gates.add(gate);
        await gate.future;
      }
      handler.resolve(Response<dynamic>(
        requestOptions: options,
        statusCode: 200,
        data: routes[options.path],
      ));
    }));
  }

  int get consumptionCalls =>
      sent.where((r) => r.path.contains('consumption')).length;
}

EsimRepositoryImpl repoOn(FakeWire wire) {
  final api = ApiClient(
    baseUrl: 'https://example.test/api',
    token: () => 'token',
    language: () => 'en',
    dio: wire.dio,
  );
  wire.arm();
  return EsimRepositoryImpl(api);
}

Map<String, dynamic> subPlan({
  int id = 1,
  String name = 'Saudi Arabia - Hajj Special',
  String status = 'ACTIVE',
  String? serial = '8996601234567890123',
  String? smdp = 'rsp.truphone.com',
  String? matchingId = 'ACT-CODE-XYZ-123',
  String? activationCode,
  String? ending = '2099-01-01T00:00:00Z',
  bool unlimited = false,
}) =>
    <String, dynamic>{
      'id': id,
      'startingDate': '2024-01-01T00:00:00Z',
      'endingDate': ending,
      'pack': {
        'name': name,
        'dataValue': 10 * 1024 * 1024,
        'unlimited': unlimited,
        'countries': [
          {'code': 'SA', 'name': 'Saudi Arabia'}
        ],
      },
      'esimProfile': {
        'status': status,
        'simSerial': serial,
        'smdpAddress': smdp,
        'matchingId': matchingId,
        'activationCode': activationCode,
      },
    };

void main() {
  group('the list is ONE request', () {
    // The old app issued 16–21 sequential requests to render this screen.
    // `SubPlanDTO` nests `pack` and `esimProfile`, so none of them were needed.
    test('rendering the whole list costs a single call', () async {
      final wire = FakeWire({
        '/v1/sub-plans/subscriber': [
          subPlan(id: 1),
          subPlan(id: 2, name: 'Turkey - Essential'),
          subPlan(id: 3, name: 'Spain - Weekender'),
        ],
      });
      final plans = await repoOn(wire).plans();

      expect(plans.length, 3);
      expect(wire.sent.length, 1, reason: 'one request renders any number of eSIMs');
      // And it carried everything, with no follow-up.
      expect(plans.first.packName, isNotEmpty);
      expect(plans.first.activation, isNotNull);
      expect(plans.first.simSerial, isNotNull);
    });

    test('a malformed row is skipped, never fatal', () async {
      final wire = FakeWire({
        '/v1/sub-plans/subscriber': [
          subPlan(id: 1),
          {'id': 2},
          'not a plan',
          null,
          {'pack': {'name': 'no id'}},
        ],
      });
      final plans = await repoOn(wire).plans();
      expect(plans.map((p) => p.id), <int>[1]);
    });

    test('active plans sort above expired ones', () async {
      final wire = FakeWire({
        '/v1/sub-plans/subscriber': [
          subPlan(id: 1, status: 'EXPIRED', ending: '2020-01-01T00:00:00Z'),
          subPlan(id: 2, status: 'ACTIVE'),
        ],
      });
      final plans = await repoOn(wire).plans();
      expect(plans.first.id, 2, reason: 'the SIM being travelled on comes first');
    });
  });

  group('usage is fetched concurrently, and only where it can change', () {
    test('expired plans are not asked about at all', () async {
      final wire = FakeWire({
        '/v1/sub-plans/subscriber': [
          subPlan(id: 1, status: 'ACTIVE'),
          subPlan(id: 2, status: 'EXPIRED', ending: '2020-01-01T00:00:00Z'),
        ],
        '/v1/subscribers/consumption': {
          'totalData': 10.0,
          'rmainingData': 6.0,
          'unit': 'GB',
        },
      });
      final repo = repoOn(wire);
      final plans = await repo.plans();

      // The controller's rule, asserted at the level it is decided.
      final live = plans.where((p) => p.status.usesData && !p.isExpired).toList();
      expect(live.length, 1);
      await Future.wait(live.map(repo.usage));
      expect(wire.consumptionCalls, 1,
          reason: 'nothing consumes data after it expires');
    });

    test('the requests overlap instead of queueing', () async {
      // The actual N+1 claim. Sequential awaits would leave the later calls
      // unsent while the first is still open.
      final wire = FakeWire(
        {
          '/v1/sub-plans/subscriber': [
            subPlan(id: 1),
            subPlan(id: 2, serial: 'B'),
            subPlan(id: 3, serial: 'C'),
          ],
          '/v1/subscribers/consumption': {
            'totalData': 10.0,
            'rmainingData': 6.0,
            'unit': 'GB',
          },
        },
        gateConsumption: true,
      );
      final repo = repoOn(wire);
      final plans = await repo.plans();

      final pending = Future.wait(plans.map(repo.usage));
      // A real pause, not one microtask: dio's interceptor chain takes several
      // event-loop turns to reach the recorder. Too short a wait would make
      // this pass for the wrong reason on a sequential implementation too.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(wire.consumptionCalls, 3,
          reason: 'all three are in flight before any has answered');

      for (final g in wire.gates) {
        g.complete();
      }
      await pending;
    });

    test("the server's own typo is what gets read", () async {
      // `ConsumptionsModel` spells it `rmainingData`. Reading only the correct
      // spelling reads nothing at all until backend request B7 lands.
      final wire = FakeWire({
        '/v1/sub-plans/subscriber': [subPlan()],
        '/v1/subscribers/consumption': {
          'totalData': 10.0,
          'rmainingData': 2.5,
          'unit': 'GB',
        },
      });
      final repo = repoOn(wire);
      final plan = (await repo.plans()).first;
      final usage = await repo.usage(plan);

      // Live: without subPlanId the endpoint is a 400, whatever else is sent.
      expect(wire.sent.last.queryParameters['subPlanId'], plan.id);
      expect(usage, isNotNull);
      expect(usage!.remainingData, 2.5);
      expect(usage.usedData, 7.5);
      expect(usage.fraction, closeTo(0.75, 0.001));
    });

    test('a failed consumption call costs the card its bar, not the screen',
        () async {
      final wire = FakeWire({'/v1/sub-plans/subscriber': [subPlan()]});
      final repo = repoOn(wire);
      // No consumption route registered -> body is null.
      expect(await repo.usage((await repo.plans()).first), isNull);
    });
  });

  group('the LPA string is the GSMA one', () {
    test(r'built as LPA:1$smdp$matchingId, exactly', () {
      final a = LpaActivation.from(
        smdpAddress: 'rsp.truphone.com',
        matchingId: 'ACT-CODE-XYZ-123',
      );
      expect(a, isNotNull);
      expect(a!.code, r'LPA:1$rsp.truphone.com$ACT-CODE-XYZ-123');
    });

    test('a server-supplied complete string wins over re-deriving one', () {
      // EsimProfileDTO carries activationCode ALONGSIDE the parts, and in the
      // design's own sample that field is already the whole string.
      // Re-deriving would drop any optional SGP.22 field the server included.
      final a = LpaActivation.from(
        activationCode: r'LPA:1$rsp.truphone.com$ACT-CODE-XYZ-123$1$',
        smdpAddress: 'ignored.example',
        matchingId: 'IGNORED',
      );
      expect(a!.code, r'LPA:1$rsp.truphone.com$ACT-CODE-XYZ-123$1$');
      expect(a.smdpAddress, 'rsp.truphone.com');
    });

    test('a bare code with separate parts is still assembled', () {
      final a = LpaActivation.from(
        activationCode: 'ACT-ONLY',
        smdpAddress: 'rsp.example.com',
      );
      expect(a!.code, r'LPA:1$rsp.example.com$ACT-ONLY');
    });

    test('a profile with no SM-DP+ yields nothing rather than a broken code', () {
      // The install section is hidden, not shown broken.
      expect(LpaActivation.from(matchingId: 'X'), isNull);
      expect(LpaActivation.from(smdpAddress: 'rsp.example.com'), isNull);
      expect(LpaActivation.from(), isNull);
    });

    test('a plan without activation cannot offer install', () async {
      final wire = FakeWire({
        '/v1/sub-plans/subscriber': [subPlan(smdp: null, matchingId: null)],
      });
      final plan = (await repoOn(wire).plans()).first;
      expect(plan.activation, isNull);
      expect(plan.canInstall, isFalse);
    });
  });

  group("Apple's link carries the code intact", () {
    test('the LPA string is percent-encoded into carddata', () {
      // The dollars are legal in a query value but only unambiguous encoded.
      final a = LpaActivation.from(
        smdpAddress: 'rsp.truphone.com',
        matchingId: 'ACT-CODE-XYZ-123',
      )!;
      final uri = EsimInstaller.appleSetupLink(a);

      expect(uri.host, 'esimsetup.apple.com');
      expect(uri.path, '/esim_qrcode_provisioning');
      expect(uri.queryParameters['carddata'], a.code,
          reason: 'what Apple receives must be byte-identical to the QR');
      expect(uri.toString(), contains('%24'), reason: 'the \$ separators are encoded');
    });
  });

  group('status and expiry', () {
    test('an unknown server status does not empty the list', () {
      expect(EsimStatus.parse('SOMETHING_NEW'), EsimStatus.unknown);
      expect(EsimStatus.parse(null), EsimStatus.unknown);
    });

    test('a past end date is expired even when the status still says active',
        () async {
      final wire = FakeWire({
        '/v1/sub-plans/subscriber': [
          subPlan(status: 'ACTIVE', ending: '2020-01-01T00:00:00Z'),
        ],
      });
      final plan = (await repoOn(wire).plans()).first;
      expect(plan.isExpired, isTrue, reason: 'a lagging status must not sell a dead SIM');
      expect(plan.canInstall, isFalse);
    });

    test('an unlimited plan is not expired merely for having no days left',
        () async {
      final wire = FakeWire({
        '/v1/sub-plans/subscriber': [
          subPlan(status: 'ACTIVE', unlimited: true, ending: null),
        ],
      });
      final plan = (await repoOn(wire).plans()).first;
      expect(plan.isExpired, isFalse);
      expect(plan.daysRemaining, isNull);
    });
  });
}
