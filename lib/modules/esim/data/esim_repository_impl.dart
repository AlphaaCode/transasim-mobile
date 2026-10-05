import 'package:flutter/foundation.dart';

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
class EsimRepositoryImpl implements EsimRepository {
  final ApiClient _api;

  /// Consults the catalogue the Store already holds before any network call.
  /// Null in tests and wherever the catalogue is not wired; the repository
  /// then goes straight to `/v1/packs/{id}`.
  final PackLookup? _packLookup;

  EsimRepositoryImpl(this._api, {PackLookup? packLookup}) : _packLookup = packLookup;

  /// E1 — `GET /api/v1/sub-plans/subscriber`, then only what that did not say.
  ///
  /// The row CAN nest `pack` and `esimProfile`, and when it does this is still
  /// exactly one request. Production does not: it answers 150-180 bytes per
  /// row, which is `{id, startingDate, endingDate, packId, productId,
  /// esimProfileId}` and nothing more. So the ids are joined —
  /// `/v1/esim-profiles/subscriber` ONCE for every profile, and the pack from
  /// the catalogue already in memory, falling back to `/v1/packs/{id}` for the
  /// few that are not in it. Distinct ids only, and all of them concurrently.
  @override
  Future<List<EsimPlan>> plans() async {
    final rows = _require(await _api.get<List<dynamic>>('/v1/sub-plans/subscriber'));
    final parseStart = perfNow;

    final parsed = <EsimRow>[];
    for (final row in rows) {
      final r = EsimRow.from(row);
      // Only a row with no id at all is unusable: there is nothing to show and
      // nothing to look up. Everything else is kept, however thin.
      if (r == null) {
        note(null, 'row is not an object with a numeric id');
        continue;
      }
      parsed.add(r);
    }

    final profiles = await _profilesFor(parsed);
    final packs = await _packsFor(parsed);

    final out = <EsimPlan>[];
    for (final r in parsed) {
      final profile = r.inlineProfile ??
          (r.esimProfileId == null ? null : profiles[r.esimProfileId]);
      final plan = r.toPlan(
        pack: r.inlinePack ?? (r.packId == null ? null : packs[r.packId]),
        profile: profile,
      );
      // The RAW string, before EsimStatus.parse flattens it. An unmapped value
      // becomes `unknown` and an unexpected one can become `expired`, and
      // neither is visible from the enum afterwards. Deliberately not the
      // serial itself: whether there IS one is the useful part.
      debugPrint(
        '[esim] plan ${plan.id}'
        " rawStatus='${profile?.status ?? ''}'"
        ' hasSerial=${plan.simSerial != null && plan.simSerial!.isNotEmpty}'
        ' end=${plan.endingDate?.toIso8601String() ?? ''}',
      );
      out.add(plan);
    }

    out.sort(_mostRelevantFirst);
    perfLog('esim.parse ${rows.length} rows -> ${out.length} plans ${perfNow - parseStart}ms');
    return out;
  }

  /// One request for every profile the rows named, or none when they all came
  /// nested. Failure is not fatal: the plans are listed without their serials.
  Future<Map<int, EsimProfileInfo>> _profilesFor(List<EsimRow> rows) async {
    final wanted = <int>{
      for (final r in rows)
        if (r.inlineProfile == null && r.esimProfileId != null) r.esimProfileId!,
    };
    if (wanted.isEmpty) return const <int, EsimProfileInfo>{};

    final result = await _api.get<List<dynamic>>('/v1/esim-profiles/subscriber');
    if (result is! Ok<List<dynamic>>) {
      note(null, 'esim-profiles/subscriber failed: ${result.errorOrNull?.code}');
      return const <int, EsimProfileInfo>{};
    }

    final out = <int, EsimProfileInfo>{};
    for (final raw in result.value) {
      if (raw is! Map) continue;
      final id = raw['id'];
      if (id is! num) continue;
      out[id.toInt()] = profileOf(raw);
    }
    return out;
  }

  /// The catalogue first, then one `/v1/packs/{id}` per pack it did not hold —
  /// distinct ids, all in flight together.
  Future<Map<int, EsimPackInfo>> _packsFor(List<EsimRow> rows) async {
    final wanted = <int>{
      for (final r in rows)
        if (r.inlinePack == null && r.packId != null) r.packId!,
    };
    if (wanted.isEmpty) return const <int, EsimPackInfo>{};

    final out = <int, EsimPackInfo>{};
    final lookup = _packLookup;
    if (lookup != null) {
      for (final id in wanted) {
        final hit = await lookup(id);
        if (hit != null) out[id] = hit;
      }
    }

    final missing = wanted.where((id) => !out.containsKey(id)).toList();
    if (missing.isEmpty) return out;

    final fetched = await Future.wait(missing.map(_fetchPack));
    for (var i = 0; i < missing.length; i++) {
      final pack = fetched[i];
      if (pack != null) {
        out[missing[i]] = pack;
      } else {
        note(null, 'pack ${missing[i]} could not be fetched');
      }
    }
    return out;
  }

  Future<EsimPackInfo?> _fetchPack(int id) async {
    final result = await _api.get<dynamic>('/v1/packs/$id');
    if (result is! Ok<dynamic>) return null;
    final body = result.value;
    return body is Map ? packOf(body) : null;
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
    if (serial == null || serial.isEmpty) {
      _noteUsage(plan.id, ok: false, http: 'no-serial');
      return null;
    }

    final result = await _api.get<dynamic>(
      '/v1/subscribers/consumption',
      // `subPlanId` is the parameter the live backend REQUIRES: `simSerial`
      // alone is a 400 "Required request parameter 'subPlanId'". Sent together,
      // since the deployed method declares both.
      query: {'subPlanId': plan.id, 'simSerial': serial},
    );
    if (result is! Ok<dynamic>) {
      final error = result.errorOrNull;
      _noteUsage(
        plan.id,
        ok: false,
        http: error is HttpFailure ? '${error.status}' : (error?.code ?? 'error'),
      );
      return null;
    }

    final body = result.value;
    if (body is! Map) {
      _noteUsage(plan.id, ok: false, http: '200', shape: body.runtimeType.toString());
      return null;
    }

    final total = _num(body['totalData']);
    // `rmainingData` is the DEPLOYED spelling — the typo is in the server's
    // own model, and backend request B7 asks for it to be emitted under both
    // names. Until it is, reading only the correct spelling reads nothing.
    final remaining = _num(body['rmainingData']) ?? _num(body['remainingData']);

    _noteUsage(
      plan.id,
      ok: total != null && remaining != null,
      http: '200',
      total: body['totalData'],
      remaining: body['rmainingData'] ?? body['remainingData'],
      unit: body['unit'],
      // NAMES only. The values could be anything, including a serial.
      keys: body.keys.map((k) => '$k').toList()..sort(),
    );

    if (total == null || remaining == null) return null;

    return EsimUsage(
      totalData: total,
      remainingData: remaining,
      // Empty, not 'GB'. See EsimUsage.unit: defaulting here presented a
      // guess as a fact.
      unit: body['unit']?.toString() ?? '',
    );
  }

  /// One line per consumption call, whatever happened.
  ///
  /// ⚠️ Every failure path above used to `return null` in silence, so a plan
  /// with no bar looked identical whether the request 404'd, answered a shape
  /// we did not expect, or simply omitted a field. Raw values, not parsed
  /// ones: the question is what the SERVER said.
  static void _noteUsage(
    int planId, {
    required bool ok,
    required String http,
    Object? total,
    Object? remaining,
    Object? unit,
    String? shape,
    List<String>? keys,
  }) {
    final extra = <String>[
      if (shape != null) 'body=$shape',
      if (keys != null) 'keys=${keys.join(',')}',
    ].join(' ');
    debugPrint(
      '[esim] usage plan $planId ok=$ok http=$http'
      ' total=${total ?? ''} remaining=${remaining ?? ''} unit=${unit ?? ''}'
      '${extra.isEmpty ? '' : ' $extra'}',
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

  static double? _num(Object? v) => switch (v) {
        num n => n.toDouble(),
        String s => double.tryParse(s),
        _ => null,
      };

  T _require<T>(Result<T> result) => switch (result) {
        Ok(:final value) => value,
        Err(:final error) => throw EsimFailure(error),
      };
}

/// The wire shape of a pack, from a nested object or from `/v1/packs/{id}`.
EsimPackInfo packOf(Map<dynamic, dynamic> pack) => EsimPackInfo(
      name: pack['name']?.toString() ?? '',
      countryCodes: _countryCodes(pack['countries']),
      dataValueKb: _numOf(pack['dataValue'])?.toInt(),
      unlimited: pack['unlimited'] == true,
    );

/// The wire shape of an eSIM profile, nested or from `/v1/esim-profiles/…`.
EsimProfileInfo profileOf(Map<dynamic, dynamic> p) => EsimProfileInfo(
      status: p['status']?.toString(),
      simSerial: p['simSerial']?.toString(),
      smdpAddress: p['smdpAddress']?.toString(),
      matchingId: p['matchingId']?.toString(),
      activationCode: p['activationCode']?.toString(),
    );

/// Why a row is thin, in EVERY build.
///
/// `perfLog` is silent in release, and release is exactly where this was
/// needed: the list was empty for real customers and the only evidence was a
/// screenshot. `debugPrint` keeps printing in a release build.
void note(int? rowId, String reason) =>
    debugPrint('[esim] row ${rowId ?? "?"}: $reason');

List<String> _countryCodes(Object? raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((c) => c['code']?.toString())
      .whereType<String>()
      .toList(growable: false);
}

double? _numOf(Object? v) => switch (v) {
      num n => n.toDouble(),
      String s => double.tryParse(s),
      _ => null,
    };

/// One `/v1/sub-plans/subscriber` row, before anything has been joined to it.
///
/// Holds whatever the row itself carried — which on production is four ids and
/// two dates — and the inline objects when staging-shaped data supplies them.
class EsimRow {
  final int id;
  final DateTime? startingDate;
  final DateTime? endingDate;
  final int? packId;
  final int? esimProfileId;
  final EsimPackInfo? inlinePack;
  final EsimProfileInfo? inlineProfile;

  const EsimRow({
    required this.id,
    required this.startingDate,
    required this.endingDate,
    required this.packId,
    required this.esimProfileId,
    required this.inlinePack,
    required this.inlineProfile,
  });

  static EsimRow? from(Object? row) {
    if (row is! Map) return null;
    final id = row['id'];
    if (id is! num) return null;

    final pack = row['pack'];
    final profile = row['esimProfile'];
    // A nested object counts only when it actually says something. The live
    // rows send neither; a staging row sends both.
    final name = pack is Map ? pack['name']?.toString() : null;
    final inlinePack = name != null && name.isNotEmpty ? packOf(pack! as Map) : null;
    final inlineProfile = profile is Map ? profileOf(profile) : null;

    return EsimRow(
      id: id.toInt(),
      startingDate: _date(row['startingDate']),
      endingDate: _date(row['endingDate']),
      packId: _id(row['packId']) ?? (pack is Map ? _id(pack['id']) : null),
      esimProfileId: _id(row['esimProfileId']) ?? (profile is Map ? _id(profile['id']) : null),
      inlinePack: inlinePack,
      inlineProfile: inlineProfile,
    );
  }

  /// Builds the plan from whatever was resolved. NEVER returns null: a row the
  /// server sent is a plan the user owns, and dropping it is the bug.
  EsimPlan toPlan({required EsimPackInfo? pack, required EsimProfileInfo? profile}) {
    if (pack == null) {
      note(id, 'pack ${packId ?? "unknown"} unresolved; listing without details');
    }
    if (profile == null) {
      note(id, 'profile ${esimProfileId ?? "unknown"} unresolved; listing without activation');
    }

    return EsimPlan(
      id: id,
      // Empty, not a sentence: the card knows to show its own "details
      // unavailable" line and the brand's support address with it.
      packName: pack?.name ?? '',
      countryCodes: pack?.countryCodes ?? const <String>[],
      // The profile's status is what the SIM is doing; the plan's dates say
      // whether it still may.
      status: EsimStatus.parse(profile?.status),
      dataValueKb: pack?.dataValueKb,
      unlimited: pack?.unlimited ?? false,
      startingDate: startingDate,
      endingDate: endingDate,
      simSerial: profile?.simSerial,
      activation: LpaActivation.from(
        activationCode: profile?.activationCode,
        smdpAddress: profile?.smdpAddress,
        matchingId: profile?.matchingId,
      ),
      detailsUnavailable: pack == null || profile == null,
    );
  }

  static int? _id(Object? v) => switch (v) {
        num n => n.toInt(),
        String s => int.tryParse(s),
        _ => null,
      };

  static DateTime? _date(Object? v) =>
      v is String && v.isNotEmpty ? DateTime.tryParse(v)?.toLocal() : null;
}

/// Carries a typed [AppError] out of the repository so the controller can
/// translate it at the edge rather than surface an exception string.
class EsimFailure implements Exception {
  final AppError error;
  const EsimFailure(this.error);

  @override
  String toString() => 'EsimFailure(${error.code})';
}
