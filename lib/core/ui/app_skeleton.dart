/// Loading states that keep the page's shape.
///
/// A spinner says "something is happening". A skeleton says "this is what is
/// arriving, and here is where it will be" — the layout does not jump when the
/// data lands, and at identical latency the screen reads as faster because
/// structure appears immediately instead of nothing.
///
/// One [AnimationController] per screen, not per block: a list of twelve
/// shimmering rows driven by twelve controllers is twelve tickers competing
/// for the same frame, which is how a loading state becomes the janky part.
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Drives every [AppSkeletonBox] beneath it from a single ticker.
class AppSkeleton extends StatefulWidget {
  final Widget child;

  const AppSkeleton({super.key, required this.child});

  @override
  State<AppSkeleton> createState() => _AppSkeletonState();
}

class _AppSkeletonState extends State<AppSkeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _ShimmerScope(
        animation: _controller,
        child: ExcludeSemantics(
          // A screen reader should hear the loading announcement once, not a
          // dozen empty boxes.
          child: Semantics(
            label: MaterialLocalizations.of(context).modalBarrierDismissLabel,
            liveRegion: true,
            child: widget.child,
          ),
        ),
      );
}

class _ShimmerScope extends InheritedWidget {
  final Animation<double> animation;

  const _ShimmerScope({required this.animation, required super.child});

  static Animation<double>? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ShimmerScope>()?.animation;

  @override
  bool updateShouldNotify(_ShimmerScope old) => old.animation != animation;
}

/// One placeholder block. Outside an [AppSkeleton] it renders flat and still,
/// which is the right thing in a golden or a widget test.
class AppSkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;
  final bool circle;

  const AppSkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.radius = Radii.chip,
    this.circle = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final animation = _ShimmerScope.maybeOf(context);

    final shape = circle
        ? BoxDecoration(shape: BoxShape.circle, color: t.hairline)
        : BoxDecoration(color: t.hairline, borderRadius: BorderRadius.circular(radius));

    final box = SizedBox(width: width, height: height);

    if (animation == null) {
      return DecoratedBox(decoration: shape, child: box);
    }

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        // A band of the brand's own surface sweeping across the placeholder.
        final t0 = animation.value * 2 - 1;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment(t0 - 0.6, 0),
            end: Alignment(t0 + 0.6, 0),
            colors: <Color>[
              t.hairline,
              Color.alphaBlend(t.card.withValues(alpha: 0.75), t.hairline),
              t.hairline,
            ],
            stops: const <double>[0, 0.5, 1],
          ).createShader(rect),
          child: DecoratedBox(decoration: shape, child: box),
        );
      },
    );
  }
}

/// The catalogue's loading state: the store list's own geometry, repeated.
///
/// Deliberately built from the same measurements as `DestinationTile` — a
/// skeleton whose rows are a different height than the real ones makes the
/// page jump at exactly the moment the user starts reading it.
class AppListSkeleton extends StatelessWidget {
  final int rows;
  final EdgeInsetsGeometry padding;

  /// Blocks above the list — a title, a search box.
  final List<Widget> header;

  const AppListSkeleton({
    super.key,
    this.rows = 7,
    this.padding = const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, Gap.xxl),
    this.header = const <Widget>[],
  });

  @override
  Widget build(BuildContext context) => AppSkeleton(
        child: ListView(
          padding: padding,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            ...header,
            for (var i = 0; i < rows; i++) ...[
              const _RowSkeleton(),
              const SizedBox(height: Gap.md),
            ],
          ],
        ),
      );
}

class _RowSkeleton extends StatelessWidget {
  const _RowSkeleton();

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(Gap.lg),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(Radii.control),
        border: Border.all(color: t.fieldBorder),
      ),
      child: const Row(
        children: [
          AppSkeletonBox(height: 44, width: 44, circle: true),
          SizedBox(width: Gap.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppSkeletonBox(height: 16, width: 120),
                SizedBox(height: Gap.sm),
                AppSkeletonBox(height: 12, width: 72),
              ],
            ),
          ),
          SizedBox(width: Gap.lg),
          AppSkeletonBox(height: 20, width: 64),
        ],
      ),
    );
  }
}
