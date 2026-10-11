/// The animated logo, played as the app's first moment on screen.
///
/// The native splash cannot play video on either platform — it stays static
/// and instant. This takes over after it: the same cream ground, then the
/// brand's animation, then the app.
///
/// Two styles, chosen by `intro.style` in brand.json and never by a brand's
/// name: [IntroStyle.video] plays the brand's file, [IntroStyle.logoHold]
/// holds the brand's mark while the app warms up.
///
/// It must never be a second wait between launch and something usable:
///  - on every launch (a cold start: returning from the background is not one);
///  - the app builds and loads underneath while it plays;
///  - a tap anywhere skips it;
///  - if the video is not playing within [_startDeadline], or fails, or the
///    system asks for reduced motion, it is skipped outright;
///  - it plays muted, whether the file has a soundtrack (Acorn's carries a
///    silent AAC track) or none at all (Sabily's);
///  - the hold has a hard cap, so a dead backend cannot freeze the launch.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../brand/brand_config.dart';
import '../brand/brand_providers.dart';
import '../theme/app_theme.dart';

const _startDeadline = Duration(milliseconds: 1500);
const _fadeOut = Duration(milliseconds: 280);

/// Whether the work the app starts at launch has settled.
///
/// Core cannot see a module (rule L1), and the catalogue prefetch lives in
/// one. `main_common.dart` binds this to the controller [_PrefetchCatalog]
/// already started — it is OBSERVED here, never triggered, so there is still
/// exactly one request at launch.
///
/// The default is `true`: anything that has not bound it (a test, a harness)
/// is "ready", so the hold reduces to its minimum rather than its cap.
final appWarmupSettledProvider = Provider<bool>((ref) => true);

/// True until the intro has played (or been skipped) in this launch.
///
/// Nothing is persisted: a fresh process plays it again. The brand is READ, not
/// watched, so a background config refresh that rebuilds the brand provider
/// cannot restart the animation in the middle of a session.
class IntroController extends Notifier<bool> {
  @override
  bool build() {
    final brand = ref.read(brandConfigProvider);
    return switch (brand.intro.style) {
      // A video style with no file is a config error, not a runtime one; the
      // guard is here only so a half-written brand cannot crash the launch.
      IntroStyle.video => brand.logo.intro != null,
      IntroStyle.logoHold => true,
    };
  }

  void finish() => state = false;
}

final introProvider = NotifierProvider<IntroController, bool>(IntroController.new);

/// Completes once the intro is over, or at once when there is none. The
/// onboarding tour waits on this so it never opens under the video. Listens to
/// the provider rather than holding a completer, so it survives the provider
/// rebuilding (a background brand refresh) mid-intro.
Future<void> untilIntroDone(WidgetRef ref) {
  if (!ref.read(introProvider)) return Future<void>.value();
  final done = Completer<void>();
  late final ProviderSubscription<bool> sub;
  sub = ref.listenManual<bool>(introProvider, (_, pending) {
    if (!pending && !done.isCompleted) {
      done.complete();
      sub.close();
    }
  });
  return done.future;
}

/// Wraps the app. While the intro is pending it paints over it; otherwise it is
/// the app, untouched.
class IntroGate extends ConsumerWidget {
  final Widget child;
  const IntroGate({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(introProvider);
    return Stack(
      children: [
        child,
        if (pending)
          Positioned.fill(
            child: switch (ref.read(brandConfigProvider).intro.style) {
              IntroStyle.video => const _Intro(),
              IntroStyle.logoHold => const _LogoHold(),
            },
          ),
      ],
    );
  }
}

class _Intro extends ConsumerStatefulWidget {
  const _Intro();

  @override
  ConsumerState<_Intro> createState() => _IntroState();
}

class _IntroState extends ConsumerState<_Intro> {
  VideoPlayerController? _video;
  Timer? _deadline;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (!mounted) return;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _leave(fade: false);
      return;
    }

    final brand = ref.read(brandConfigProvider);
    final video = VideoPlayerController.asset(brand.assetPath(brand.logo.intro!));
    _video = video;
    _deadline = Timer(_startDeadline, () {
      if (!video.value.isPlaying) _leave(fade: false);
    });
    try {
      await video.initialize();
      if (!mounted || _leaving) return;
      await video.setVolume(0);
      video.addListener(_onTick);
      await video.play();
      if (mounted) setState(() {});
    } catch (_) {
      _leave(fade: false);
    }
  }

  void _onTick() {
    final v = _video!.value;
    if (v.hasError) {
      _leave(fade: false);
    } else if (v.isCompleted || (v.isInitialized && v.position >= v.duration && !v.isPlaying)) {
      _leave();
    }
  }

  Future<void> _leave({bool fade = true}) async {
    if (_leaving) return;
    _leaving = true;
    _deadline?.cancel();
    if (fade && mounted) {
      setState(() {});
      await Future<void>.delayed(_fadeOut);
    }
    if (mounted) ref.read(introProvider.notifier).finish();
  }

  @override
  void dispose() {
    _deadline?.cancel();
    _video?.removeListener(_onTick);
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final l10n = ref.watch(l10nProvider);
    // Read, not watched, for the reason given on IntroController.
    final ground = ref.read(brandConfigProvider).logo.introBackground ?? t.surface;
    final video = _video;
    final ready = video != null && video.value.isInitialized;

    return AnimatedOpacity(
      opacity: _leaving ? 0 : 1,
      duration: _fadeOut,
      child: Semantics(
        button: true,
        label: l10n.t('intro.skip'),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _leave,
          // The video's own edge colour, which is also what the native splash
          // paints, so the hand over from the OS is seamless whether or not a
          // frame is ready yet — and so a 9:16 animation on a taller screen is
          // bordered by its own black, not by a brand colour.
          child: ColoredBox(
            color: ground,
            child: ready
                ? Center(
                    child: AspectRatio(
                      aspectRatio: video.value.aspectRatio,
                      child: VideoPlayer(video),
                    ),
                  )
                : const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

/// The brand's mark, held on its launch colour until the app is ready.
///
/// Not a timed splash and not a spinner. It ends when BOTH are true:
///
///  1. [BrandIntro.logoHoldMin] has passed — so a warm launch does not flash
///     the logo for 80 ms, which reads as a glitch rather than an opening;
///  2. [appWarmupSettledProvider] is true — the catalogue prefetch the app
///     already starts has come back, with data OR with an error.
///
/// And it ends REGARDLESS at [BrandIntro.logoHoldMax]. That cap is the whole
/// reason this is safe to put in front of a network call: with the backend
/// down, settling never happens, and without the cap the user would hold a
/// logo forever. Past it the hold leaves anyway and the screen underneath —
/// already built — shows its own loading or error state, which is the thing
/// actually designed to explain a dead backend.
///
/// No spinner and no progress bar, deliberately: there is nothing truthful to
/// report. The prefetch has no progress, and a bar that is not measuring
/// anything is a lie told at 60 fps.
class _LogoHold extends ConsumerStatefulWidget {
  const _LogoHold();

  @override
  ConsumerState<_LogoHold> createState() => _LogoHoldState();
}

class _LogoHoldState extends ConsumerState<_LogoHold> {
  bool _minPassed = false;
  bool _leaving = false;
  Timer? _min;
  Timer? _cap;

  @override
  void initState() {
    super.initState();
    final intro = ref.read(brandConfigProvider).intro;
    _min = Timer(intro.logoHoldMin, () {
      _minPassed = true;
      _releaseIfReady();
    });
    _cap = Timer(intro.logoHoldMax, () => _leave());
  }

  /// Only ever called where both conditions are already known; the cap is a
  /// separate path because it ignores them.
  void _releaseIfReady() {
    if (_minPassed && ref.read(appWarmupSettledProvider)) _leave();
  }

  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    _min?.cancel();
    _cap?.cancel();
    if (mounted) {
      setState(() {});
      await Future<void>.delayed(_fadeOut);
    }
    if (mounted) ref.read(introProvider.notifier).finish();
  }

  @override
  void dispose() {
    _min?.cancel();
    _cap?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Watched, so the hold leaves the moment the prefetch settles rather than
    // on the next timer tick.
    if (ref.watch(appWarmupSettledProvider) && _minPassed && !_leaving) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _leave());
    }

    final t = AppTokens.of(context);
    final l10n = ref.watch(l10nProvider);
    // Read, not watched, for the reason given on IntroController.
    final brand = ref.read(brandConfigProvider);
    final ground = brand.logo.introBackground ?? t.surface;

    // Reduced motion keeps the hold and drops its exit fade: the hold is
    // covering startup work, not decorating it, so removing the animation is
    // the right answer and removing the hold is not.
    final instant = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    // Sized to land the mark exactly where the native splash already drew it,
    // so the hand over is the same image at the same size and not a jump.
    //
    // MEASURED, not derived: a 420 dpi device was filmed through a cold start
    // and the mark's ink measured in both phases. Android 12+ draws the 432 px
    // brand_mark drawable into a canvas that comes out at 144 dp — NOT the
    // 120 dp a reading of the "240 dp canvas, 25% inset" rule predicts, and
    // the first version of this was wrong by exactly that. brand_mark's ink
    // fills that canvas top to bottom, so the native ink is 144 dp tall;
    // logo-mark.png's ink is 0.8796 of its own canvas, so 144 / 0.8796 =
    // 163.7 reproduces it. Both files are cut from the same master, so the
    // widths agree independently: 144 x 0.8704 / 0.7639 = 164.1.
    //
    // A FIXED dp, like the platform's own, not a fraction of the screen: the
    // native icon does not grow with the display and neither may this.
    const side = 164.0;

    return Semantics(
      button: true,
      label: l10n.t('intro.skip'),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _leave,
        // The same colour the native launch window paints, so the hand over
        // from the OS has nothing to flash between.
        child: ColoredBox(
          color: ground,
          child: AnimatedOpacity(
            // Opaque on the FIRST frame, deliberately. A fade in from zero
            // was specified and was wrong on a device: the native splash
            // hands over with this same mark already at full opacity, so
            // fading it up made it blink out for a frame and swim back. The
            // ground is already the right black, so arriving opaque is not a
            // cut — it is the native splash continuing, which is the whole
            // point. Only the exit fades.
            opacity: _leaving ? 0 : 1,
            duration: instant ? Duration.zero : _fadeOut,
            curve: Curves.easeOut,
            child: Center(
              child: Image.asset(
                brand.assetPath(brand.logo.mark),
                width: side,
                height: side,
                fit: BoxFit.contain,
                // A missing mark must not leave a blank hold: the ground is
                // still correct and the app still arrives behind it.
                errorBuilder: (_, _, _) => SizedBox(width: side, height: side),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
