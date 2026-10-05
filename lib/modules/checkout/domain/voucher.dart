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

  // An eSIM activation string is a VALID URI — scheme `lpa`, the rest its
  // path — so the URL branch below would strip `LPA:1$` off and hand the
  // remainder to the backend as a voucher token. Returned intact instead, so
  // the caller can recognise it and say what it is.
  if (looksLikeEsimActivationCode(value)) return value;

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
  // people group them, not part of the token. The old class was whitespace
  // plus a non-breaking space — which is whitespace again — and so it never
  // stripped a dash: a slip printed ABCD-1234 went to the server with the
  // dash in it and came back refused, and retyping it by hand did not help
  // because the manual field normalises through here too.
  //
  // The class below is what a printed slip and an OCR pass actually produce:
  // the ASCII hyphen, the Unicode dash range, and the minus sign.
  value = value.replaceAll(RegExp(r'[\s\u00A0\-\u2010-\u2015\u2212]'), '');
  // Tokens are issued upper-case; a phone keyboard offers lower-case first.
  return value.isEmpty ? null : value.toUpperCase();
}

/// Whether this is an eSIM activation string rather than a voucher token.
///
/// People point the voucher scanner at the QR on the eSIM install screen, and
/// at the QR a previous purchase e-mailed them. Both encode `LPA:1$...`, which
/// the backend has no idea what to do with — it answers a generic refusal and
/// the user is told their voucher is not valid, which is true and useless.
///
/// Caught here, before any request: this costs nothing and can say what the
/// thing in front of the camera actually is.
bool looksLikeEsimActivationCode(String value) =>
    value.trim().toUpperCase().startsWith(r'LPA:1$');

/// Maps the backend's own refusal key to the reason shown on screen.
///
/// ⚠️ Read the caveat in [VoucherRepository] first: `subscribeViaVoucher`
/// catches EVERY exception — unknown code, used, expired, AND a provisioning
/// failure on a perfectly valid voucher — and rethrows them as one
/// `error.voucher_subscription_failed`. So the generic key must STAY generic:
/// telling someone holding a paid slip that it "is not valid" when
/// provisioning failed is how the slip ends up in a bin.
///
/// EXACT keys only. An earlier version matched substrings like "used" and
/// "redeem" anywhere in the key or the message, which is how
/// `error.voucher_subscription_failed` — the one key that means "we do not
/// know why" — would have been read as a definite verdict the moment the
/// backend reworded its message to mention a used voucher. A key the server
/// did not send is not a diagnosis.
String voucherRefusalKey(String? serverKey) {
  final key = serverKey?.trim().toLowerCase();
  if (key == null || key.isEmpty) return 'voucher.error.notRedeemed';

  return switch (key) {
    // Deliberately neutral: this backend uses "not available" for a voucher it
    // will not serve, without saying which of the reasons applies.
    'error.voucher_not_available' => 'voucher.error.notAvailable',
    'error.voucher_not_found' ||
    'error.voucher_unknown' ||
    'error.voucher_invalid' =>
      'voucher.error.invalid',
    'error.voucher_expired' => 'voucher.error.expired',
    'error.voucher_revoked' || 'error.voucher_cancelled' => 'voucher.error.revoked',
    'error.voucher_redeemed' || 'error.voucher_already_redeemed' => 'voucher.error.redeemed',
    // Including `error.voucher_subscription_failed`, which names no cause.
    _ => 'voucher.error.notRedeemed',
  };
}

/// Whether a scanned code may be submitted right now.
///
/// ⚠️ THE DEFECT THIS EXISTS TO PREVENT. The screen set one `_handled` flag
/// and cleared it the instant a refusal arrived — but the camera never
/// stopped, so it re-read the same slip on the next frame and submitted again,
/// which was refused again, which cleared the flag again. Measured in
/// production: ~110 identical `POST /v1/subscriptions/voucher` in 9 seconds off
/// a single voucher. A refusal that re-arms the scanner is a loop, not a retry.
///
/// Four rules, and all four are load-bearing: one request in flight at a time,
/// the same code not twice inside [window], nothing at all once a code has been
/// taken, and re-arming only when the USER asks for it.
class ScanGate {
  /// Long enough to cover the camera holding one slip in frame across many
  /// frames, short enough not to block a deliberate second attempt.
  static const window = Duration(seconds: 5);

  String? _lastCode;
  DateTime? _lastAt;
  bool _inFlight = false;
  bool _scanning = true;

  /// Whether the camera should be running at all.
  bool get scanning => _scanning;

  /// Whether a redemption is open. The manual button reads this too, so typing
  /// cannot race the camera.
  bool get inFlight => _inFlight;

  /// True at most once per code per [window], and never while busy.
  ///
  /// Records the attempt when it says yes, so a caller cannot forget to.
  bool accept(String code, DateTime now) {
    if (!_scanning || _inFlight) return false;
    final last = _lastAt;
    if (_lastCode == code && last != null && now.difference(last) < window) {
      return false;
    }
    _lastCode = code;
    _lastAt = now;
    _inFlight = true;
    // One read is one attempt. The camera stays off until "scan again".
    _scanning = false;
    return true;
  }

  /// The request finished, whatever it answered. Deliberately does NOT restart
  /// the camera — that is the whole fix.
  void settle() => _inFlight = false;

  /// The user asked for another go. Forgets the last code too, so the SAME
  /// slip can be retried on purpose.
  void rearm() {
    _inFlight = false;
    _scanning = true;
    _lastCode = null;
    _lastAt = null;
  }
}

abstract class VoucherRepository {
  /// `POST /v1/subscriptions/voucher` with `{ voucherToken }`.
  ///
  /// Returns the verdict, never a bare success.
  Future<VoucherResult> redeem(String token);
}
