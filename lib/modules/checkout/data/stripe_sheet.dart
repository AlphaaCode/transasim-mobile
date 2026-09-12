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
    return e.error.code == FailureCode.Canceled
        ? SheetResult.cancelled
        : SheetResult.failed;
  } catch (_) {
    return SheetResult.failed;
  }
}
