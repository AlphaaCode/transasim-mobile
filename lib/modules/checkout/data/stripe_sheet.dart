import 'package:flutter/foundation.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import '../presentation/checkout_controllers.dart';

/// The only surface that ever sees a card.
///
/// §7.4: Stripe's PaymentSheet is the sole collection point. The app never
/// touches a PAN, a CVC or an expiry date, and so stays outside PCI scope.
/// This adapter exists so the controller depends on a function, not on the SDK
/// — which is what lets every branch of the money path be tested without a
/// payment sheet.
Future<SheetResult> presentStripeSheet({
  required String clientSecret,
  required String merchantName,
}) async {
  try {
    await Stripe.instance.initPaymentSheet(
      paymentSheetParameters: SetupPaymentSheetParameters(
        paymentIntentClientSecret: clientSecret,
        merchantDisplayName: merchantName,
      ),
    );
    await Stripe.instance.presentPaymentSheet();
    return SheetResult.completed;
  } on StripeException catch (e) {
    // A dismissal is NOT a failure, and the distinction is the whole point:
    // the old app posted a subscribe call after a cancel and reported it as a
    // failed attempt (§7.2, difference #4).
    if (e.error.code == FailureCode.Canceled) return SheetResult.cancelled;

    // The UI only ever shows the generic "declined" message (§7.2) — on
    // purpose, a user should not see a raw Stripe error. But that means this
    // debug line is the ONLY place the real reason survives. In particular,
    // a publishable/secret key mode mismatch (live key confirming a
    // test-mode PaymentIntent, or vice versa) surfaces here as Stripe's own
    // "similar object exists in test/live mode" text — without this log
    // there is no way to tell that apart from a genuine card decline.
    debugPrint('[checkout] Stripe payment sheet failed: '
        'code=${e.error.code} message=${e.error.message}');
    return SheetResult.failed;
  } catch (e) {
    debugPrint('[checkout] Stripe payment sheet failed with a non-Stripe '
        'error: $e');
    return SheetResult.failed;
  }
}
