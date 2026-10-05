/// An order the customer has PAID for whose eSIM has not arrived.
///
/// The fact belongs to checkout; the place it has to be seen is My eSIMs —
/// which is where someone goes when the eSIM they bought is not there. Those
/// two modules may not import each other (rule L2), so the notice is declared
/// here and bound at the composition root, the same way `presentSheetProvider`
/// binds the payment sheet.
///
/// Both providers default to "nothing pending" so every test and every screen
/// works without the binding; `main_common.dart` overrides them.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the card needs to say, with no checkout types in it.
class PendingOrderNotice {
  /// Shown to the user and quoted to support — the Stripe payment intent, the
  /// one identifier that ties a charge to an order on both sides.
  final String reference;

  /// What was bought, when the record kept it. May be empty.
  final String packName;

  /// Retries are exhausted and the app has stopped trying on its own. The card
  /// still offers the button; it just no longer promises anything.
  final bool exhausted;

  const PendingOrderNotice({
    required this.reference,
    required this.packName,
    required this.exhausted,
  });
}

/// The order still outstanding, or null. Overridden at the composition root.
final pendingOrderNoticeProvider = Provider<PendingOrderNotice?>((ref) => null);

/// Runs finalisation again, answering whether the eSIM was provisioned.
///
/// Safe to call repeatedly: `/v1/subscriptions/card` finds the payment by its
/// Stripe intent and refuses one already `COMPLETED_AND_CONSUMED`, so a retry
/// cannot double-provision or double-charge. That server guarantee is what
/// makes a user-facing "Retry now" button acceptable at all.
typedef RetryPendingOrder = Future<bool> Function();

/// Null until bound, which is also what makes the card hide its button in a
/// build that has no checkout module.
final retryPendingOrderProvider = Provider<RetryPendingOrder?>((ref) => null);
