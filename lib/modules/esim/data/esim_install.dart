/// How an eSIM actually gets onto the phone.
///
/// In `data/`, not `domain/`: it drives a platform channel and a URL launcher,
/// and the domain layer holds no Flutter (rule L3). It is an outbound adapter
/// like the repository beside it — the thing it adapts is the OS rather than a
/// server.
///
/// THE CONSTRAINT THAT SHAPES THIS FILE: Apple's real programmatic install API,
/// `CTCellularPlanProvisioning.addPlan()`, requires the
/// `com.apple.CommCenter.fine-grained` carrier entitlement, which Apple grants
/// only to actual mobile network operators. A reseller does not qualify — and
/// the old app's own entitlement file was present but EMPTY, which is what an
/// unapproved request looks like after the fact.
///
/// So one-tap is a BEST-EFFORT LAYER ON TOP of the QR code, never the other way
/// round. The reliable path — the one the design itself draws, with "Scan QR
/// Code" and "Manual Activation Steps" side by side — is: show the QR, let the
/// user copy the string, and let them install from another device or by hand.
/// Everything below can fail without the user losing the ability to install.
///
///   iOS 17.4+   a Universal Link to esimsetup.apple.com hands the LPA string
///               to Apple's own install sheet. No restricted entitlement.
///   Android     `EuiccManager.downloadSubscription()` shows a system consent
///               dialog. No special entitlement either, but the device must
///               actually have an eUICC.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/esim.dart';

/// What happened when one-tap was attempted. The UI never treats a failure as
/// an error state — it just keeps the QR in front of the user.
enum EsimInstallOutcome {
  /// The OS took over. Whether the user completed it is not observable.
  handedOff,

  /// This device or platform cannot do it. Expected, not exceptional.
  unsupported,

  /// It was attempted and the OS refused.
  failed,
}

class EsimInstaller {
  /// Apple's own provisioning entry point, iOS 17.4+.
  ///
  /// The LPA string goes in `carddata` and MUST be percent-encoded: it
  /// contains `$` separators, which are legal in a query value but only
  /// unambiguous when encoded.
  static Uri appleSetupLink(LpaActivation activation) => Uri.parse(
        'https://esimsetup.apple.com/esim_qrcode_provisioning'
        '?carddata=${Uri.encodeComponent(activation.code)}',
      );

  static const MethodChannel _channel = MethodChannel('transasim/esim');

  /// Best-effort hand-off to the platform's own installer.
  static Future<EsimInstallOutcome> install(LpaActivation activation) async {
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final ok = await launchUrl(
          appleSetupLink(activation),
          mode: LaunchMode.externalApplication,
        );
        return ok ? EsimInstallOutcome.handedOff : EsimInstallOutcome.failed;
      }
      if (defaultTargetPlatform == TargetPlatform.android) {
        final ok = await _channel.invokeMethod<bool>('install', {
          'activationCode': activation.code,
        });
        return switch (ok) {
          true => EsimInstallOutcome.handedOff,
          false => EsimInstallOutcome.unsupported,
          _ => EsimInstallOutcome.failed,
        };
      }
    } on PlatformException {
      return EsimInstallOutcome.failed;
    } on MissingPluginException {
      // The channel is not registered in this build. Not a crash — the QR is
      // still on screen.
      return EsimInstallOutcome.unsupported;
    }
    return EsimInstallOutcome.unsupported;
  }

  /// Whether to offer the one-tap button at all. Cheap and synchronous: the
  /// real capability check happens on the platform side.
  ///
  /// `defaultTargetPlatform` rather than `dart:io`'s `Platform`: check L4 bans
  /// `dart:io` inside a module because it carries `HttpClient`, and the
  /// substitute is the better API regardless — it is defined on web, and a
  /// test can override it, which `Platform` cannot.
  static bool get isSupportedPlatform =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;

  static Future<void> copy(String value) =>
      Clipboard.setData(ClipboardData(text: value));
}
