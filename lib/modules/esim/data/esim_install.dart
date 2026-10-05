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
///   Android     a link to esimsetup.android.com, and NOTHING ELSE. See below.
///
/// ⚠️ ANDROID USED TO TRY `EuiccManager.downloadSubscription()` FIRST. It no
/// longer does, and the reason came from two devices rather than from docs:
///
///  - Galaxy A25, Android 16: `isEnabled` was FALSE, so the call was never
///    even reachable and every user got the "cannot install" toast.
///  - Galaxy S23 Ultra, Android 15: the call WAS made. The platform asked for
///    consent, the user granted it, the SM-DP+ was contacted and the profile
///    metadata downloaded — then `EuiccController` refused with "Caller does
///    not have carrier privilege in metadata". The profile's own GSMA access
///    rules name which certificates may install it, and this app's is not one.
///
/// That is a provisioning setting at the operator's SM-DP+, not something a
/// client can arrange. The link has no such problem because no app is in the
/// call chain at all: on the same S23 Ultra it ran GMS → Samsung's
/// `QrTransferActivity` → `finishAndLaunchEsimAddPlan`, no Knox restriction,
/// no refusal. One rung that works beats two where the first cannot.
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

/// What the platform says about this phone's eUICC. Informational only.
enum EsimHint {
  /// The device reports eSIM hardware.
  supported,

  /// The device reports none.
  unsupported,

  /// Not Android, no channel, or the platform errored. Never a guess.
  unknown,
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

  /// Android's own provisioning entry point.
  ///
  /// The LPA string goes in `carddata` RAW — not percent-encoded, unlike
  /// [appleSetupLink]. That is the format other providers publish, with `$`
  /// and `:` literal, so it is the form used here. Whether an encoded link
  /// would ALSO be accepted is untested; the byte-exact test below pins what
  /// is actually sent rather than asserting anything about the alternative.
  static Uri androidSetupLink(LpaActivation activation) => Uri.parse(
        'https://esimsetup.android.com/esim_qrcode_provisioning'
        '?carddata=${activation.code}',
      );

  static const MethodChannel _channel = MethodChannel('transasim/esim');

  /// Best-effort hand-off to the platform's own installer.
  static Future<EsimInstallOutcome> install(LpaActivation activation) async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final ok = await _open(appleSetupLink(activation), 'ios universal link');
      return ok ? EsimInstallOutcome.handedOff : EsimInstallOutcome.failed;
    }
    if (defaultTargetPlatform == TargetPlatform.android) return _installAndroid(activation);
    return EsimInstallOutcome.unsupported;
  }

  /// The setup link, and nothing else.
  ///
  /// The native channel is NOT asked to install: see the header. It is the one
  /// path the platform refuses for this app, and asking first only delayed the
  /// path that works.
  static Future<EsimInstallOutcome> _installAndroid(LpaActivation activation) async {
    final opened = await _open(androidSetupLink(activation), 'setup link');
    if (opened) return EsimInstallOutcome.handedOff;

    // The existing toast shows, with the QR still on screen behind it.
    debugPrint('[esim] setup link refused; nothing else to try');
    return EsimInstallOutcome.unsupported;
  }

  /// Whether this phone appears to have an eUICC at all.
  ///
  /// Two read-only facts from the platform, nothing more: it installs nothing
  /// and decides nothing. NOT WIRED INTO ANY SCREEN YET — it exists so the
  /// question "can this phone take an eSIM" can be answered from the device
  /// rather than from a help sheet, once there is a decision about how to say
  /// it without discouraging a purchase.
  ///
  /// [EsimHint.unknown] is the honest answer off Android, in a build with no
  /// channel, and on any error — never a guess.
  static Future<EsimHint> androidEsimHint() async {
    if (defaultTargetPlatform != TargetPlatform.android) return EsimHint.unknown;
    try {
      final hint = await _channel.invokeMapMethod<String, dynamic>('hint');
      if (hint == null) return EsimHint.unknown;
      final feature = hint['euiccFeature'];
      if (feature is! bool) return EsimHint.unknown;
      debugPrint('[esim] hint euiccFeature=$feature isEnabled=${hint['isEnabled']}');
      // The HARDWARE flag decides. `isEnabled` is about this app's access to
      // the API, which no longer has anything to do with whether the phone can
      // take an eSIM through the OS.
      return feature ? EsimHint.supported : EsimHint.unsupported;
    } on PlatformException catch (e) {
      debugPrint('[esim] hint threw PlatformException ${e.code}: ${e.message}');
      return EsimHint.unknown;
    } on MissingPluginException {
      debugPrint('[esim] hint unavailable: channel not registered');
      return EsimHint.unknown;
    }
  }

  /// `launchUrl` THROWS when no activity can handle the link, it is not just
  /// a false return. This is the one place that is caught: an install button
  /// is best effort and the QR is still on screen behind it, so nothing here
  /// is allowed to escape into the widget's handler.
  static Future<bool> _open(Uri uri, String what) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      debugPrint('[esim] $what ${ok ? 'opened' : 'refused'}');
      return ok;
    } on PlatformException catch (e) {
      debugPrint('[esim] $what threw PlatformException ${e.code}: ${e.message}');
      return false;
    } catch (e) {
      debugPrint('[esim] $what threw ${e.runtimeType}: $e');
      return false;
    }
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
