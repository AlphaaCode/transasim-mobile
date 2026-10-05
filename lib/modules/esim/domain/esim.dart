/// eSIM domain. No Flutter, no HTTP — rule L3.
library;

/// What the backend says an eSIM profile is doing.
///
/// The wire carries free-form strings; everything outside this file reasons
/// about the enum. An unrecognised value becomes [unknown] rather than an
/// exception: a new server-side status must not empty the user's list.
enum EsimStatus {
  /// Bought, profile issued, not yet installed on a device.
  ready,

  /// Installed and usable.
  active,

  /// Past its end date, or consumed.
  expired,

  /// Cancelled, suspended, or anything else.
  unknown;

  static EsimStatus parse(String? raw) => switch (raw?.toUpperCase().trim()) {
        'ACTIVE' || 'ENABLED' || 'IN_USE' => EsimStatus.active,
        'RELEASED' || 'AVAILABLE' || 'ALLOCATED' || 'DOWNLOADED' => EsimStatus.ready,
        'EXPIRED' || 'TERMINATED' || 'DELETED' || 'DISABLED' => EsimStatus.expired,
        _ => EsimStatus.unknown,
      };

}

/// The GSMA activation string, and the two parts it is built from.
///
/// `LPA:1$<smdpAddress>$<matchingId>` is the SGP.22 standard. It is what a QR
/// code encodes, what a user types into iOS's "Enter Details Manually", and
/// what both platforms' one-tap paths take as their payload — so it is built
/// in exactly one place and never re-assembled at a call site.
class LpaActivation {
  final String smdpAddress;
  final String matchingId;

  /// The full string, as it must appear in a QR code.
  final String code;

  const LpaActivation({
    required this.smdpAddress,
    required this.matchingId,
    required this.code,
  });

  /// Prefers a server-supplied complete string over re-deriving one.
  ///
  /// `EsimProfileDTO` carries `activationCode` ALONGSIDE `smdpAddress` and
  /// `matchingId`, and in the design's own sample that field is already the
  /// whole `LPA:1$rsp.truphone.com$ACT-CODE-XYZ-123`. When the server has
  /// spelled it out, that spelling wins — re-deriving would silently drop any
  /// optional SGP.22 field the backend chose to include.
  static LpaActivation? from({
    String? activationCode,
    String? smdpAddress,
    String? matchingId,
  }) {
    final supplied = activationCode?.trim();
    if (supplied != null && supplied.toUpperCase().startsWith('LPA:')) {
      final parts = supplied.split(r'$');
      return LpaActivation(
        smdpAddress: parts.length > 1 ? parts[1] : (smdpAddress ?? ''),
        matchingId: parts.length > 2 ? parts[2] : (matchingId ?? ''),
        code: supplied,
      );
    }

    final host = smdpAddress?.trim();
    // The matching id may arrive under either name.
    final id = (matchingId?.trim().isNotEmpty ?? false) ? matchingId!.trim() : supplied;
    if (host == null || host.isEmpty || id == null || id.isEmpty) return null;

    return LpaActivation(
      smdpAddress: host,
      matchingId: id,
      // Exactly the GSMA form. No spaces, no trailing '$', literal dollars.
      code: 'LPA:1\$$host\$$id',
    );
  }
}

/// What a plan needs to know about its pack, from whichever source had it.
///
/// The row may carry the pack inline, the catalogue may already hold it, or it
/// may have to be fetched. All three produce this, so the plan is built from
/// one shape and the parser is not written three times.
class EsimPackInfo {
  final String name;
  final List<String> countryCodes;

  /// Total allowance in kilobytes; null when unlimited or unstated.
  final int? dataValueKb;
  final bool unlimited;

  const EsimPackInfo({
    required this.name,
    this.countryCodes = const <String>[],
    this.dataValueKb,
    this.unlimited = false,
  });
}

/// The eSIM profile's half of a plan — status, serial and the activation data.
class EsimProfileInfo {
  final String? status;
  final String? simSerial;
  final String? smdpAddress;
  final String? matchingId;
  final String? activationCode;

  const EsimProfileInfo({
    this.status,
    this.simSerial,
    this.smdpAddress,
    this.matchingId,
    this.activationCode,
  });
}

/// Resolves a pack the subscriber's row only named by id, WITHOUT going to the
/// network — the catalogue the Store already loaded.
///
/// Returns null when that catalogue has not been loaded or does not hold the
/// pack, which sends the repository to `/v1/packs/{id}` instead. Injected
/// rather than imported: `modules/esim` may not depend on `modules/catalog`
/// (rule L2), so the composition root binds the two.
typedef PackLookup = Future<EsimPackInfo?> Function(int packId);

/// One purchased plan, as the list and the detail screen need it.
///
/// ⚠️ The row is NOT reliably nested. `SubPlanDTO` CAN carry `pack` and
/// `esimProfile` as objects, and the staging data did — but production answers
/// `/v1/sub-plans/subscriber` in 150-180 bytes per row, which is a flat record
/// of ids and dates and nothing else. A parser that required `pack.name`
/// therefore dropped every row every real customer had, and the screen read as
/// "no eSIM yet" to people who had just paid. Both shapes are accepted now,
/// and an unresolvable row is still SHOWN — see [detailsUnavailable].
class EsimPlan {
  final int id;
  final String packName;
  final List<String> countryCodes;
  final EsimStatus status;

  /// Total allowance in kilobytes, or null when the pack is unlimited.
  final int? dataValueKb;
  final bool unlimited;

  final DateTime? startingDate;
  final DateTime? endingDate;

  /// The printed serial, shown as ICCID on the detail screen.
  final String? simSerial;

  /// Null when the profile has not been issued yet — the install section is
  /// hidden rather than shown broken.
  final LpaActivation? activation;

  /// The row arrived, but its pack or its profile could not be resolved.
  ///
  /// The plan is still listed: the user paid for it and it exists. The card
  /// says the details are unavailable and points at support, which is a far
  /// better answer than an empty screen — the defect this whole shape exists
  /// to prevent.
  final bool detailsUnavailable;

  const EsimPlan({
    required this.id,
    required this.packName,
    required this.countryCodes,
    required this.status,
    required this.dataValueKb,
    required this.unlimited,
    required this.startingDate,
    required this.endingDate,
    required this.simSerial,
    required this.activation,
    this.detailsUnavailable = false,
  });

  /// Whole days remaining, floored at zero. Null when there is no end date.
  int? get daysRemaining {
    final end = endingDate;
    if (end == null) return null;
    final days = end.difference(DateTime.now()).inDays;
    return days < 0 ? 0 : days;
  }

  /// Expired by status OR by date. The server's status is authoritative when
  /// it says expired, but a plan whose end date has passed while the status
  /// lags must not be offered as active.
  bool get isExpired =>
      status == EsimStatus.expired || (daysRemaining != null && daysRemaining == 0 && !unlimited);

  bool get canInstall => activation != null && !isExpired;
}

/// Kilobytes in one of [unit], or null when the unit is not recognised.
///
/// Kilobytes is the base because that is what the catalogue already speaks:
/// `Pack.dataValue` and [EsimPlan.dataValueKb] are kilobytes, so a usage line
/// converted here is directly comparable with the allowance line above it.
///
/// ⚠️ The server's unit is NOT verified against production. It has only ever
/// been seen in a debug fixture, so this accepts the spellings a JHipster
/// backend and a French-speaking operator plausibly send — including `Mo`/`Go`,
/// which are the French forms — and returns null for anything else rather than
/// assuming. A wrong assumption here renders "10485760 GB".
double? kilobytesPerUnit(String? unit) {
  final u = unit?.trim().toUpperCase();
  if (u == null || u.isEmpty) return null;
  return switch (u) {
    'B' || 'BYTE' || 'BYTES' || 'O' || 'OCTET' || 'OCTETS' => 1 / 1024,
    'K' || 'KB' || 'KO' || 'KIB' || 'KILOBYTE' || 'KILOBYTES' => 1,
    'M' || 'MB' || 'MO' || 'MIB' || 'MEGABYTE' || 'MEGABYTES' => 1024,
    'G' || 'GB' || 'GO' || 'GIB' || 'GIGABYTE' || 'GIGABYTES' => 1024 * 1024,
    _ => null,
  };
}

/// Consumption for one eSIM.
///
/// Fetched separately and per-eSIM, because that is the only shape the backend
/// offers — `getConsumption(long)` and `getConsumptionForBookedEsim(String)`.
/// Backend request B9 asks for a bulk form.
class EsimUsage {
  /// Allowance and remainder in the unit the server chose.
  final double totalData;
  final double remainingData;

  /// EXACTLY what the server sent, empty when it sent nothing.
  ///
  /// ⚠️ This used to default to `'GB'` when the field was absent, which is a
  /// guess presented as a fact: the same numbers would read as gigabytes
  /// whatever they were. An absent unit is now absent, and the UI shows the
  /// raw numbers with no unit rather than inventing one.
  final String unit;

  const EsimUsage({
    required this.totalData,
    required this.remainingData,
    required this.unit,
  });

  double get usedData {
    final used = totalData - remainingData;
    return used < 0 ? 0 : used;
  }

  /// 0..1. Zero when the total is zero, rather than NaN.
  double get fraction {
    if (totalData <= 0) return 0;
    final f = usedData / totalData;
    return f.clamp(0, 1).toDouble();
  }

  /// Whether [unit] is one this build can convert. When false the numbers are
  /// still shown — with the server's own unit text — but never reformatted.
  bool get hasKnownUnit => kilobytesPerUnit(unit) != null;

  double? get totalKilobytes => _kb(totalData);
  double? get usedKilobytes => _kb(usedData);
  double? get remainingKilobytes => _kb(remainingData);

  double? _kb(double value) {
    final per = kilobytesPerUnit(unit);
    return per == null ? null : value * per;
  }

  /// Whether a progress bar means anything. An unlimited pack has no
  /// denominator, and a zero or negative total would be a divide by zero.
  bool get hasMeasurableTotal => totalData > 0;
}

abstract class EsimRepository {
  /// ONE request. `SubPlanDTO` already nests the pack and the eSIM profile.
  Future<List<EsimPlan>> plans();

  /// Usage for a single plan. Callers fetch these CONCURRENTLY — never in a
  /// loop with an await inside it, which is how the old app reached 16–21
  /// sequential requests to paint one screen.
  Future<EsimUsage?> usage(EsimPlan plan);
}
