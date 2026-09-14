import '../../../core/network/api_client.dart';
import '../../../core/perf/perf_log.dart';
import '../../../core/result/result.dart';
import '../domain/esim.dart';

/// Talks to the JHipster backend. Routes read off the deployed JAR's constant
/// pool, not from the old client's call sites.
///
/// ⚠️ `GET /v1/sub-plans/subscriber/details` — the aggregate endpoint the
/// original S3 request asked for — DOES NOT EXIST. `SubPlanResourceExt`
/// exposes `/all`, `/esim-profile/{idEP}`, `/pack/{idPack}`, `/subscriber` and
/// `/subscriber/{idSub}` and nothing else. Calling `/subscriber/details` binds
/// `"details"` to the `Long` of `/subscriber/{idSub}`, so it answers **400,
/// not 404** — worth knowing before writing a fallback keyed on 404.
///
/// It is also unnecessary for the list: see [plans].
class EsimRepositoryImpl implements EsimRepository {
  final ApiClient _api;

  EsimRepositoryImpl(this._api);

  /// E1 — `GET /api/v1/sub-plans/subscriber`. ONE request for the whole list.
  ///
  /// `SubPlanDTO` nests `pack` and `esimProfile`, and those carry everything
  /// both screens need: name, countries, allowance, validity, status, serial,
  /// and the SM-DP+ address and matching id the LPA string is built from. The
  /// old app issued 16–21 sequential requests to render this, re-fetching data
  /// it had already been handed.
  @override
  Future<List<EsimPlan>> plans() async {
    final rows = _require(await _api.get<List<dynamic>>('/v1/sub-plans/subscriber'));
    final parseStart = perfNow;
    final out = <EsimPlan>[];
    for (final row in rows) {
      final plan = _parsePlan(row);
      // A malformed row is skipped, never fatal. The old app asserted its way
      // through parsing and one bad row emptied the screen
      // (`ANALYSE-EXISTANT.md` §2.2).
      if (plan != null) out.add(plan);
    }
    out.sort(_mostRelevantFirst);
    perfLog('esim.parse ${rows.length} rows -> ${out.length} plans ${perfNow - parseStart}ms');
    return out;
  }

  /// E2 — `GET /api/v1/subscribers/consumption?simSerial=…`.
  ///
  /// Per-eSIM because that is the only shape offered: the resource exposes
  /// `getConsumption(long)` and `getConsumptionForBookedEsim(String simSerial)`
  /// and no bulk variant. Backend request B9.
  ///
  /// Returns null rather than throwing: usage is an enrichment, and a card
  /// that renders without its bar is better than a list that fails because one
  /// consumption call did.
  @override
  Future<EsimUsage?> usage(EsimPlan plan) async {
    final serial = plan.simSerial;
    if (serial == null || serial.isEmpty) return null;

    final result = await _api.get<dynamic>(
      '/v1/subscribers/consumption',
      // `subPlanId` is the parameter the live backend REQUIRES: `simSerial`
      // alone is a 400 "Required request parameter 'subPlanId'". Sent together,
      // since the deployed method declares both.
      query: {'subPlanId': plan.id, 'simSerial': serial},
    );
    if (result is! Ok<dynamic>) return null;

    final body = result.value;
    if (body is! Map) return null;

    final total = _num(body['totalData']);
    // `rmainingData` is the DEPLOYED spelling — the typo is in the server's
    // own model, and backend request B7 asks for it to be emitted under both
    // names. Until it is, reading only the correct spelling reads nothing.
    final remaining = _num(body['rmainingData']) ?? _num(body['remainingData']);
    if (total == null || remaining == null) return null;

    return EsimUsage(
      totalData: total,
      remainingData: remaining,
      unit: body['unit']?.toString() ?? 'GB',
    );
  }

  EsimPlan? _parsePlan(Object? row) {
    if (row is! Map) return null;
    final id = row['id'];
    if (id is! num) return null;

    final pack = row['pack'] is Map ? (row['pack'] as Map) : const {};
    final profile = row['esimProfile'] is Map ? (row['esimProfile'] as Map) : const {};

    final name = pack['name']?.toString();
    if (name == null || name.isEmpty) return null;

    return EsimPlan(
      id: id.toInt(),
      packName: name,
      countryCodes: _countryCodes(pack['countries']),
      // The profile's status is what the SIM is doing; the plan's dates say
      // whether it still may.
      status: EsimStatus.parse(profile['status']?.toString()),
      dataValueKb: _num(pack['dataValue'])?.toInt(),
      unlimited: pack['unlimited'] == true,
      startingDate: _date(row['startingDate']),
      endingDate: _date(row['endingDate']),
      simSerial: profile['simSerial']?.toString(),
      activation: LpaActivation.from(
        activationCode: profile['activationCode']?.toString(),
        smdpAddress: profile['smdpAddress']?.toString(),
        matchingId: profile['matchingId']?.toString(),
      ),
    );
  }

  /// Active first, then anything still usable, then the dead ones — each group
  /// newest first. A user opening this screen is looking at the SIM they are
  /// travelling on, not the one from last year.
  static int _mostRelevantFirst(EsimPlan a, EsimPlan b) {
    int rank(EsimPlan p) => switch (p) {
          _ when p.status == EsimStatus.active && !p.isExpired => 0,
          _ when !p.isExpired => 1,
          _ => 2,
        };
    final byRank = rank(a).compareTo(rank(b));
    if (byRank != 0) return byRank;

    final aEnd = a.endingDate, bEnd = b.endingDate;
    if (aEnd == null && bEnd == null) return b.id.compareTo(a.id);
    if (aEnd == null) return 1;
    if (bEnd == null) return -1;
    return bEnd.compareTo(aEnd);
  }

  static List<String> _countryCodes(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((c) => c['code']?.toString())
        .whereType<String>()
        .toList(growable: false);
  }

  static double? _num(Object? v) => switch (v) {
        num n => n.toDouble(),
        String s => double.tryParse(s),
        _ => null,
      };

  static DateTime? _date(Object? v) =>
      v is String && v.isNotEmpty ? DateTime.tryParse(v)?.toLocal() : null;

  T _require<T>(Result<T> result) => switch (result) {
        Ok(:final value) => value,
        Err(:final error) => throw EsimFailure(error),
      };
}

/// Carries a typed [AppError] out of the repository so the controller can
/// translate it at the edge rather than surface an exception string.
class EsimFailure implements Exception {
  final AppError error;
  const EsimFailure(this.error);

  @override
  String toString() => 'EsimFailure(${error.code})';
}
