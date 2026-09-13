/// Coach marks: a bubble pointing at a real widget on the real screen.
///
/// Not screenshots and not a mock-up. Each mark names a [GlobalKey] already
/// attached to the live widget; the overlay asks that widget's render box where
/// it is, scrolls it into view if a list hides it, cuts a hole in the scrim
/// around exactly those bounds, and anchors the bubble beside it. Rotate the
/// phone and it measures again.
///
/// Hand-built rather than a package: it is one overlay and one painter, it
/// takes its colours from the brand tokens like everything else, and it follows
/// the reading direction the rest of the app already does.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_button.dart';

class CoachMark {
  final GlobalKey target;
  final String title;
  final String body;

  const CoachMark({
    required this.target,
    required this.title,
    required this.body,
  });
}

enum CoachMarkOutcome { finished, skipped }

class CoachMarkLabels {
  final String next;
  final String done;
  final String skip;

  const CoachMarkLabels({
    required this.next,
    required this.done,
    required this.skip,
  });
}

/// Shows [marks] one after another over the current screen.
///
/// A mark whose widget is not on screen is passed over rather than pointed at
/// empty space. [onShown] fires as each mark actually appears, so progress can
/// be saved step by step: an app killed mid-tour does not repeat what was seen.
Future<CoachMarkOutcome> showCoachMarks(
  BuildContext context, {
  required List<CoachMark> marks,
  required CoachMarkLabels labels,
  void Function(int index)? onShown,
}) {
  final completer = Completer<CoachMarkOutcome>();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _CoachOverlay(
      marks: marks,
      labels: labels,
      onShown: onShown,
      onClose: (outcome) {
        entry.remove();
        if (!completer.isCompleted) completer.complete(outcome);
      },
    ),
  );
  Overlay.of(context, rootOverlay: true).insert(entry);
  return completer.future;
}

class _CoachOverlay extends StatefulWidget {
  final List<CoachMark> marks;
  final CoachMarkLabels labels;
  final void Function(int index)? onShown;
  final ValueChanged<CoachMarkOutcome> onClose;

  const _CoachOverlay({
    required this.marks,
    required this.labels,
    required this.onShown,
    required this.onClose,
  });

  @override
  State<_CoachOverlay> createState() => _CoachOverlayState();
}

class _CoachOverlayState extends State<_CoachOverlay>
    with WidgetsBindingObserver {
  int _index = -1;
  Rect? _hole;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _goTo(0);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The screen changed size (rotation, keyboard): measure the target again.
  @override
  void didChangeMetrics() =>
      WidgetsBinding.instance.addPostFrameCallback((_) => _measure(_index));

  Future<void> _goTo(int index) async {
    for (var i = index; i < widget.marks.length; i++) {
      final targetContext = widget.marks[i].target.currentContext;
      if (targetContext == null) continue;
      await Scrollable.ensureVisible(
        targetContext,
        alignment: 0.4,
        duration: const Duration(milliseconds: 250),
      );
      if (!mounted || _closed) return;
      if (_measure(i)) {
        widget.onShown?.call(i);
        return;
      }
    }
    _close(CoachMarkOutcome.finished);
  }

  /// Puts the hole over mark [i]'s widget. False when it cannot be measured.
  bool _measure(int i) {
    if (i < 0 || i >= widget.marks.length || !mounted) return false;
    final target = widget.marks[i].target.currentContext?.findRenderObject();
    final overlay = context.findRenderObject();
    if (target is! RenderBox || !target.hasSize || !target.attached) {
      return false;
    }
    if (overlay is! RenderBox || !overlay.hasSize) return false;
    final topLeft = target.localToGlobal(Offset.zero, ancestor: overlay);
    setState(() {
      _index = i;
      _hole = (topLeft & target.size).inflate(6);
    });
    return true;
  }

  void _close(CoachMarkOutcome outcome) {
    if (_closed) return;
    _closed = true;
    widget.onClose(outcome);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final hole = _hole;
    final last = _index == widget.marks.length - 1;

    final overlay = Material(
      type: MaterialType.transparency,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          return Stack(
            children: [
              // Swallows taps: the tour ends by its own buttons, never by a
              // stray touch that also pressed something underneath.
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: CustomPaint(
                    painter: _ScrimPainter(
                      hole: hole,
                      scrim: t.primary.withValues(alpha: 0.78),
                      ring: t.cta,
                    ),
                  ),
                ),
              ),
              if (hole != null && _index >= 0)
                _Bubble(
                  hole: hole,
                  screen: size,
                  mark: widget.marks[_index],
                  step: _index + 1,
                  steps: widget.marks.length,
                  primaryLabel: last ? widget.labels.done : widget.labels.next,
                  skipLabel: last ? null : widget.labels.skip,
                  onPrimary: () => last
                      ? _close(CoachMarkOutcome.finished)
                      : _goTo(_index + 1),
                  onSkip: () => _close(CoachMarkOutcome.skipped),
                ),
            ],
          );
        },
      ),
    );

    // Back means "not now", not "leave the screen underneath". Only where a
    // Router dispatches the back button, which the app always has.
    if (Router.maybeOf(context)?.backButtonDispatcher == null) return overlay;
    return BackButtonListener(
      onBackButtonPressed: () async {
        _close(CoachMarkOutcome.skipped);
        return true;
      },
      child: overlay,
    );
  }
}

class _Bubble extends StatelessWidget {
  final Rect hole;
  final Size screen;
  final CoachMark mark;
  final int step;
  final int steps;
  final String primaryLabel;
  final String? skipLabel;
  final VoidCallback onPrimary;
  final VoidCallback onSkip;

  const _Bubble({
    required this.hole,
    required this.screen,
    required this.mark,
    required this.step,
    required this.steps,
    required this.primaryLabel,
    required this.skipLabel,
    required this.onPrimary,
    required this.onSkip,
  });

  static const double _arrow = 10;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final padding = MediaQuery.paddingOf(context);
    // Below the target when there is more room below, above otherwise: a tab
    // bar at the foot of the screen gets its bubble over it.
    final below = screen.height - hole.bottom > hole.top;
    final arrowX = hole.center.dx.clamp(
      Gap.lg + 24,
      screen.width - Gap.lg - 24,
    );

    final card = Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.all(Gap.lg),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(Radii.card),
          boxShadow: Shadows.card,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              mark.title,
              style: AppType.subtitleStrong.copyWith(color: t.primary),
            ),
            const SizedBox(height: Gap.xs),
            Text(mark.body, style: AppType.body.copyWith(color: t.inkMuted)),
            const SizedBox(height: Gap.lg),
            AppButton(label: primaryLabel, onPressed: onPrimary),
            // A fixed height, so the last step (no Skip) keeps the same footing.
            if (steps > 1 || skipLabel != null)
              SizedBox(
                height: 48,
                child: Row(
                  children: [
                    if (steps > 1)
                      Text(
                        '$step / $steps',
                        style: AppType.caption.copyWith(color: t.inkMuted),
                      ),
                    const Spacer(),
                    if (skipLabel != null)
                      AppLinkButton(label: skipLabel!, onPressed: onSkip),
                  ],
                ),
              ),
          ],
        ),
      ),
    );

    final arrow = CustomPaint(
      size: const Size(2 * _arrow, _arrow),
      painter: _ArrowPainter(color: t.card, pointsUp: below),
    );

    return Positioned(
      left: Gap.lg,
      right: Gap.lg,
      top: below ? hole.bottom + Gap.sm : null,
      bottom: below ? null : screen.height - hole.top + Gap.sm,
      child: Padding(
        padding: EdgeInsets.only(
          top: below ? 0 : padding.top,
          bottom: below ? padding.bottom : 0,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (below) _ArrowSlot(x: arrowX - Gap.lg, child: arrow),
            Align(child: card),
            if (!below) _ArrowSlot(x: arrowX - Gap.lg, child: arrow),
          ],
        ),
      ),
    );
  }
}

/// Places the arrow so its tip sits under the target's centre.
class _ArrowSlot extends StatelessWidget {
  final double x;
  final Widget child;
  const _ArrowSlot({required this.x, required this.child});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: _Bubble._arrow,
    child: Stack(
      clipBehavior: Clip.none,
      children: [Positioned(left: x - _Bubble._arrow, child: child)],
    ),
  );
}

class _ScrimPainter extends CustomPainter {
  final Rect? hole;
  final Color scrim;
  final Color ring;

  const _ScrimPainter({
    required this.hole,
    required this.scrim,
    required this.ring,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final everything = Path()..addRect(Offset.zero & size);
    final h = hole;
    if (h == null) {
      canvas.drawPath(everything, Paint()..color = scrim);
      return;
    }
    final cutout = RRect.fromRectAndRadius(
      h,
      const Radius.circular(Radii.control),
    );
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        everything,
        Path()..addRRect(cutout),
      ),
      Paint()..color = scrim,
    );
    canvas.drawRRect(
      cutout,
      Paint()
        ..color = ring
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_ScrimPainter old) =>
      old.hole != hole || old.scrim != scrim || old.ring != ring;
}

class _ArrowPainter extends CustomPainter {
  final Color color;
  final bool pointsUp;
  const _ArrowPainter({required this.color, required this.pointsUp});

  @override
  void paint(Canvas canvas, Size size) {
    final path = pointsUp
        ? (Path()
            ..moveTo(0, size.height)
            ..lineTo(size.width / 2, 0)
            ..lineTo(size.width, size.height))
        : (Path()
            ..moveTo(0, 0)
            ..lineTo(size.width / 2, size.height)
            ..lineTo(size.width, 0));
    canvas.drawPath(path..close(), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_ArrowPainter old) =>
      old.color != color || old.pointsUp != pointsUp;
}
