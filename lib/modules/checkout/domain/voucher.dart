/// Redeeming an agency-issued voucher.
///
/// Lives beside checkout because it is the same concern by a different means:
/// acquiring a pack and having an eSIM provisioned. It just does not involve
/// money — the agency already paid.
library;

/// What the backend says a voucher is.
///
/// Read off `VoucherStatus` in the deployed JAR: ACTIVE, CREATED, EXPIRED,
/// REDEEMED, REVOKED, SENT. Only some of those are usable, and that is the
/// whole point of this type existing.
enum VoucherStatus {
  /// Issued and not yet used.
  active,

  /// Created but not yet distributed. Still usable.
  created,

  /// Handed to a customer. Usable.
  sent,

  expired,

  /// Already used — by this person or another.
  redeemed,

  /// Cancelled by the agency.
  revoked,

  /// A value this build does not know. Treated as NOT usable: a voucher the
  /// app cannot vouch for must not be announced as valid.
  unknown;

  static VoucherStatus parse(String? raw) => switch (raw?.toUpperCase().trim()) {
        'ACTIVE' => VoucherStatus.active,
        'CREATED' => VoucherStatus.created,
        'SENT' => VoucherStatus.sent,
        'EXPIRED' => VoucherStatus.expired,
        'REDEEMED' => VoucherStatus.redeemed,
        'REVOKED' => VoucherStatus.revoked,
        _ => VoucherStatus.unknown,
      };

  bool get isUsable =>
      this == VoucherStatus.active ||
      this == VoucherStatus.created ||
      this == VoucherStatus.sent;

  /// The dictionary key explaining a refusal.
  String get refusalKey => switch (this) {
        VoucherStatus.expired => 'voucher.error.expired',
        VoucherStatus.redeemed => 'voucher.error.redeemed',
        VoucherStatus.revoked => 'voucher.error.revoked',
        _ => 'voucher.error.invalid',
      };
}

/// The verdict on one redemption attempt.
///
/// ⚠️ THE DEFECT THIS TYPE EXISTS TO PREVENT. The old client threw the server
/// response away and returned a hard-coded `Voucher(status: 'valid')`
/// (`voucher_client.dart:12-19`), so **every 2xx was announced to the user as a
/// valid voucher** — `ANALYSE-EXISTANT.md` §4.
///
/// Verified against the deployed JAR: a voucher that is missing, expired,
/// redeemed or revoked makes `VoucherServiceImplExt` throw
/// `BadRequestAlertException` or `EntityNotFoundException`, which JHipster maps
/// to 4xx. So on THIS build a 2xx does appear to mean success.
///
/// It is still not trusted on its own, for a reason that is in the contract
/// rather than in today's behaviour: `VoucherDTO` carries a `status` field
/// whose values include EXPIRED, REDEEMED and REVOKED, and the voucher subscribe
/// endpoints return a `ResponseEntity` able to carry that DTO. A 200 with a
/// rejection inside it is therefore REPRESENTABLE, and one backend change away
/// from being real. Reading the payload costs nothing and removes the whole
/// class of bug — where trusting the status code re-creates it the day the
/// server starts being polite about failures.
sealed class VoucherResult {
  const VoucherResult();
}

/// Accepted, and the payload agreed.
final class VoucherAccepted extends VoucherResult {
  /// What was redeemed, when the server said. Null when it did not say.
  final String? packName;
  const VoucherAccepted({this.packName});
}

/// The server answered, and the answer was no — whatever the status code was.
final class VoucherRejected extends VoucherResult {
  final String messageKey;
  const VoucherRejected(this.messageKey);
}

/// Reads a redemption response WITHOUT trusting the status code.
///
/// Returns null when the body carries no verdict either way, which the caller
/// resolves using the status code as a fallback — a 2xx with an opaque body is
/// the one case where there is nothing else to go on. `redeemVoucher`'s success
/// body on this build is exactly that: the fixed string
/// `{"data":"voucher redeemed successfully"}`, with no status field at all.
VoucherResult? readVoucherVerdict(Object? body) {
  if (body is! Map) return null;
  final map = body.cast<String, dynamic>();

  // A status anywhere the DTO might put it.
  final rawStatus = map['status'] ?? (map['voucher'] is Map ? (map['voucher'] as Map)['status'] : null);
  if (rawStatus is String) {
    final status = VoucherStatus.parse(rawStatus);
    return status.isUsable
        ? VoucherAccepted(packName: _packName(map))
        : VoucherRejected(status.refusalKey);
  }

  // JHipster's own error envelope, which can travel with any status.
  final serverError = map['message'] ?? map['error'] ?? map['title'];
  if (serverError is String && serverError.toLowerCase().contains('error')) {
    return const VoucherRejected('voucher.error.invalid');
  }

  // An explicit boolean, if a future version sends one.
  final valid = map['valid'] ?? map['isValid'];
  if (valid is bool) {
    return valid ? VoucherAccepted(packName: _packName(map)) : const VoucherRejected('voucher.error.invalid');
  }

  return null;
}

String? _packName(Map<String, dynamic> map) {
  final pack = map['pack'];
  if (pack is Map && pack['name'] is String) return pack['name'] as String;
  final direct = map['packName'];
  return direct is String ? direct : null;
}

/// A scanned or typed code, normalised.
///
/// A voucher QR may encode the bare token or a URL containing it. Both are
/// accepted, because a pilgrim holding a printed slip should not have to know
/// the difference.
String? normaliseVoucherCode(String raw) {
  var value = raw.trim();
  if (value.isEmpty) return null;

  // A URL: take the last non-empty path segment, or a `token`/`voucher` query.
  final uri = Uri.tryParse(value);
  if (uri != null && uri.hasScheme && (uri.hasAuthority || uri.pathSegments.isNotEmpty)) {
    final fromQuery = uri.queryParameters['token'] ?? uri.queryParameters['voucher'];
    if (fromQuery != null && fromQuery.trim().isNotEmpty) {
      value = fromQuery.trim();
    } else if (uri.pathSegments.isNotEmpty) {
      final last = uri.pathSegments.lastWhere((s) => s.trim().isNotEmpty, orElse: () => '');
      if (last.isNotEmpty) value = last;
    }
  }

  // Printed codes are read aloud and typed back in; spaces and dashes are how
  // people group them, not part of the token.
  value = value.replaceAll(RegExp(r'[\s ]'), '');
  return value.isEmpty ? null : value;
}

abstract class VoucherRepository {
  /// `POST /v1/subscriptions/voucher` with `{ voucherToken }`.
  ///
  /// Returns the verdict, never a bare success.
  Future<VoucherResult> redeem(String token);
}
