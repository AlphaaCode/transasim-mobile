/// The Android install path, and the exact link it uses.
///
/// ⚠️ WHAT THESE TESTS PIN, and why the native rung is gone. Measured on two
/// devices: on a Galaxy A25 `EuiccManager.isEnabled` was false, so
/// `downloadSubscription` was never reachable and every user got the "cannot
/// install" toast. On a Galaxy S23 Ultra it WAS reachable, the user consented,
/// the profile metadata downloaded — and the platform then refused with
/// "Caller does not have carrier privilege in metadata", because the profile's
/// GSMA access rules do not name this app's certificate.
///
/// The link has no such problem: no app is in the call chain. So the channel is
/// never asked to install, and a test below holds that line.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:transasim_mobile/modules/esim/data/esim_install.dart';
import 'package:transasim_mobile/modules/esim/domain/esim.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

const activation = LpaActivation(
  smdpAddress: 'rsp.truphone.com',
  matchingId: 'ACT-CODE-XYZ-123',
  code: r'LPA:1$rsp.truphone.com$ACT-CODE-XYZ-123',
);

/// Records what was launched and answers a fixed verdict.
class FakeLauncher extends UrlLauncherPlatform with MockPlatformInterfaceMixin {
  FakeLauncher({this.opens = true, this.throws});

  final bool opens;

  /// What `launchUrl` throws instead of answering. Real: it throws when no
  /// activity can handle the link, rather than returning false.
  final Object? throws;

  final List<String> launched = <String>[];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    final boom = throws;
    if (boom != null) throw boom;
    return opens;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the Android setup link is byte-exact', () {
    test('carddata carries the LPA string RAW', () {
      // This is the format other providers publish, separators literal.
      // Whether an encoded link would also work is untested — what is pinned
      // here is the exact string the app sends, so it cannot drift silently.
      expect(
        EsimInstaller.androidSetupLink(activation).toString(),
        'https://esimsetup.android.com/esim_qrcode_provisioning'
        r'?carddata=LPA:1$rsp.truphone.com$ACT-CODE-XYZ-123',
      );
    });

    test(r'neither $ nor : is percent-encoded', () {
      final link = EsimInstaller.androidSetupLink(activation).toString();
      expect(link, isNot(contains('%24')), reason: r'$ stays literal');
      expect(link, isNot(contains('%3A')), reason: ': stays literal');
    });

    test('Apple is encoded, and the two deliberately differ', () {
      expect(EsimInstaller.appleSetupLink(activation).toString(), contains('%24'));
    });
  });

  group('the link is the only Android path', () {
    late List<MethodCall> channelCalls;

    /// Records every channel call. If `install` ever appears here again, the
    /// rung that the platform refuses has come back.
    void watchChannel() {
      channelCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('transasim/esim'),
              (call) async {
        channelCalls.add(call);
        return null;
      });
    }

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      watchChannel();
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('transasim/esim'), null);
    });

    test('the link is opened, and it is the first thing tried', () async {
      final launcher = FakeLauncher();
      UrlLauncherPlatform.instance = launcher;

      expect(await EsimInstaller.install(activation), EsimInstallOutcome.handedOff);
      expect(launcher.launched.single,
          EsimInstaller.androidSetupLink(activation).toString());
    });

    test('the native channel is NEVER asked to install', () async {
      // The whole point of the change. `downloadSubscription` is refused for
      // this app at the profile's access rules, so asking only delays the path
      // that works.
      UrlLauncherPlatform.instance = FakeLauncher();

      await EsimInstaller.install(activation);

      expect(channelCalls.where((c) => c.method == 'install'), isEmpty);
      expect(channelCalls, isEmpty, reason: 'installing touches no channel at all');
    });

    test('a refused link gives the outcome that shows the toast', () async {
      UrlLauncherPlatform.instance = FakeLauncher(opens: false);

      expect(await EsimInstaller.install(activation), EsimInstallOutcome.unsupported);
    });
  });

  group('the device hint is informational and never guesses', () {
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('transasim/esim'), null);
    });

    void stubHint(Object? reply) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('transasim/esim'),
              (call) async {
        if (reply is Exception) throw reply;
        return reply;
      });
    }

    test('eUICC hardware present reads as supported', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      stubHint(<String, dynamic>{'euiccFeature': true, 'isEnabled': true});
      expect(await EsimInstaller.androidEsimHint(), EsimHint.supported);
    });

    test('isEnabled false does NOT make a phone unsupported', () async {
      // The A25 answers exactly this. `isEnabled` is about this app's access
      // to an API we no longer call; the phone still takes an eSIM via the OS.
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      stubHint(<String, dynamic>{'euiccFeature': true, 'isEnabled': false});
      expect(await EsimInstaller.androidEsimHint(), EsimHint.supported);
    });

    test('no eUICC hardware reads as unsupported', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      stubHint(<String, dynamic>{'euiccFeature': false, 'isEnabled': false});
      expect(await EsimInstaller.androidEsimHint(), EsimHint.unsupported);
    });

    test('anything unclear is unknown, never a guess', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      stubHint(null);
      expect(await EsimInstaller.androidEsimHint(), EsimHint.unknown);

      stubHint(<String, dynamic>{'isEnabled': true});
      expect(await EsimInstaller.androidEsimHint(), EsimHint.unknown);

      stubHint(PlatformException(code: 'boom'));
      expect(await EsimInstaller.androidEsimHint(), EsimHint.unknown);

      stubHint(MissingPluginException('none'));
      expect(await EsimInstaller.androidEsimHint(), EsimHint.unknown);
    });

    test('off Android it is unknown without touching the channel', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      var called = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('transasim/esim'),
              (_) async {
        called = true;
        return null;
      });

      expect(await EsimInstaller.androidEsimHint(), EsimHint.unknown);
      expect(called, isFalse);
    });
  });

  group('a launcher that throws does not reach the button', () {
    // `launchUrl` throws when nothing can handle the link. The refactor to a
    // two-rung ladder dropped the old try/catch, which would have let that
    // escape into the widget's onPressed and surface as a red screen instead
    // of the toast.

    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('the Android link rung swallows a PlatformException', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final launcher = FakeLauncher(
        throws: PlatformException(code: 'ACTIVITY_NOT_FOUND', message: 'none'),
      );
      UrlLauncherPlatform.instance = launcher;

      await expectLater(
        EsimInstaller.install(activation),
        completion(EsimInstallOutcome.unsupported),
      );
      expect(launcher.launched, hasLength(1), reason: 'it was tried');
    });

    test('the Android link rung swallows any other exception', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      UrlLauncherPlatform.instance = FakeLauncher(throws: StateError('boom'));

      await expectLater(
        EsimInstaller.install(activation),
        completion(EsimInstallOutcome.unsupported),
      );
    });

    test('the iOS rung swallows one too', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      UrlLauncherPlatform.instance = FakeLauncher(
        throws: PlatformException(code: 'ACTIVITY_NOT_FOUND', message: 'none'),
      );

      await expectLater(
        EsimInstaller.install(activation),
        completion(EsimInstallOutcome.failed),
      );
    });

    test('iOS still hands off when the link opens', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final launcher = FakeLauncher();
      UrlLauncherPlatform.instance = launcher;

      expect(await EsimInstaller.install(activation), EsimInstallOutcome.handedOff);
      expect(launcher.launched.single,
          EsimInstaller.appleSetupLink(activation).toString());
    });
  });

}
