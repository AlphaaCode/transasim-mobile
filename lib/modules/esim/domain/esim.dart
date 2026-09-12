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

  /// Whether usage is worth fetching. Nothing consumes data after it expires,
  /// so asking costs a request per dead eSIM for an answer that cannot change.
  bool get usesData => this == EsimStatus.active;
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

/// One purchased plan, as the list and the detail screen need it.
///
/// Everything here comes from a SINGLE `GET /v1/sub-plans/subscriber`:
/// `SubPlanDTO` nests `pack` and `esimProfile`, so the list needs no follow-up
/// request to render. See ARCHITECTURE-MOBILE.md §13.2.1.
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

/// Consumption for one eSIM.
///
/// Fetched separately and per-eSIM, because that is the only shape the backend
/// offers — `getConsumption(long)` and `getConsumptionForBookedEsim(String)`.
/// Backend request B9 asks for a bulk form.
class EsimUsage {
  /// Allowance and remainder in the unit the server chose.
  final double totalData;
  final double remainingData;
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
}

abstract class EsimRepository {
  /// ONE request. `SubPlanDTO` already nests the pack and the eSIM profile.
  Future<List<EsimPlan>> plans();

  /// Usage for a single plan. Callers fetch these CONCURRENTLY — never in a
  /// loop with an await inside it, which is how the old app reached 16–21
  /// sequential requests to paint one screen.
  Future<EsimUsage?> usage(EsimPlan plan);
}
