/// The animated logo, played as the app's first moment on screen.
///
/// The native splash cannot play video on either platform — it stays static
/// and instant. This takes over after it: the same cream ground, then the
/// brand's animation, then the app.
///
/// It must never be a second wait between launch and something usable:
///  - on every launch (a cold start: returning from the background is not one);
///  - the app builds and loads underneath while it plays;
///  - a tap anywhere skips it;
///  - if the video is not playing within [_startDeadline], or fails, or the
///    system asks for reduced motion, it is skipped outright;
///  - it plays muted — the file's soundtrack is not bundled at all.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../brand/brand_providers.dart';
import '../theme/app_theme.dart';

const _startDeadline = Duration(milliseconds: 1500);
const _fadeOut = Duration(milliseconds: 280);

/// True until the intro has played (or been skipped) in this launch.
///
/// Nothing is persisted: a fresh process plays it again. The brand is READ, not
/// watched, so a background config refresh that rebuilds the brand provider
/// cannot restart the animation in the middle of a session.
class IntroController extends Notifier<bool> {
  @override
  bool build() => ref.read(brandConfigProvider).logo.intro != null;

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
        if (pending) const Positioned.fill(child: _Intro()),
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
          // The brand's surface, as the native splash paints it, so the hand
          // over from the OS is seamless whether or not a frame is ready yet.
          child: ColoredBox(
            color: t.surface,
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
