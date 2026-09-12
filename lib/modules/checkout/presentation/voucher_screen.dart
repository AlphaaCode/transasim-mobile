/// Redeeming a voucher: camera first, typing always.
///
/// The manual field is NOT an error-state fallback. A pilgrim arrives with a
/// paper slip that has been folded, photocopied and carried through an airport;
/// some of those will never scan. Typing is a first-class way in, visible from
/// the start — the same shape as eSIM installation, where the QR is primary and
/// the copyable code sits under it rather than appearing after a failure.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/brand/brand_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_button.dart';
import '../../../core/ui/app_card.dart';
import '../../../core/ui/app_text_field.dart';
import '../domain/voucher.dart';
import 'voucher_controllers.dart';

class VoucherScreen extends ConsumerStatefulWidget {
  const VoucherScreen({super.key});

  @override
  ConsumerState<VoucherScreen> createState() => _VoucherScreenState();
}

class _VoucherScreenState extends ConsumerState<VoucherScreen> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode, BarcodeFormat.code128, BarcodeFormat.dataMatrix],
  );
  final _manual = TextEditingController();

  /// Set once a code is in flight, so a camera that keeps firing cannot submit
  /// the same voucher twice while the first attempt is still open.
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    _manual.dispose();
    super.dispose();
  }

  void _submit(String raw) {
    final code = normaliseVoucherCode(raw);
    if (code == null || _handled) return;
    setState(() => _handled = true);
    ref.read(voucherControllerProvider.notifier).redeem(code);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);
    final state = ref.watch(voucherControllerProvider);

    ref.listen(voucherControllerProvider, (_, next) {
      // A refusal re-arms the camera; the user can try another slip without
      // leaving the screen.
      if (next is VoucherFailed) setState(() => _handled = false);
    });

    if (state is VoucherSucceeded) return _Success(packName: state.packName);

    return Scaffold(
      backgroundColor: t.surface,
      appBar: AppBar(title: Text(l10n.t('voucher.title'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, Gap.xxl),
          children: [
            Text(l10n.t('voucher.subtitle'),
                style: AppType.body.copyWith(color: t.inkMuted)),
            const SizedBox(height: Gap.lg),
            _Viewfinder(controller: _controller, onCode: _submit, paused: _handled),
            const SizedBox(height: Gap.lg),
            if (state is VoucherFailed) ...[
              _Refusal(messageKey: state.messageKey),
              const SizedBox(height: Gap.lg),
            ],
            // Always here. Not behind a failure, not behind a disclosure arrow.
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.t('voucher.manualTitle'),
                      style: AppType.heading.copyWith(color: t.primary)),
                  const SizedBox(height: Gap.sm),
                  Text(l10n.t('voucher.manualBody'),
                      style: AppType.body.copyWith(color: t.inkMuted)),
                  const SizedBox(height: Gap.lg),
                  AppTextField(
                    label: l10n.t('voucher.code'),
                    controller: _manual,
                    textInputAction: TextInputAction.done,
                    onChanged: (_) {
                      if (state is VoucherFailed) {
                        ref.read(voucherControllerProvider.notifier).reset();
                      }
                    },
                  ),
                  const SizedBox(height: Gap.lg),
                  AppButton(
                    label: l10n.t('voucher.redeem'),
                    busy: state is VoucherChecking,
                    onPressed: () => _submit(_manual.text),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Viewfinder extends ConsumerWidget {
  final MobileScannerController controller;
  final ValueChanged<String> onCode;
  final bool paused;

  const _Viewfinder({required this.controller, required this.onCode, required this.paused});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTokens.of(context);
    final l10n = ref.watch(l10nProvider);

    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.control),
      child: SizedBox(
        height: 280,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: t.primary),
            MobileScanner(
              controller: controller,
              onDetect: (capture) {
                for (final barcode in capture.barcodes) {
                  final value = barcode.rawValue;
                  if (value != null && value.trim().isNotEmpty) {
                    onCode(value);
                    return;
                  }
                }
              },
              // A camera that cannot start is not an error state — the field
              // below still works, and saying so beats an empty black box.
              errorBuilder: (context, error) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(Gap.xl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.no_photography_outlined, color: t.onPrimary, size: 32),
                      const SizedBox(height: Gap.md),
                      Text(l10n.t('voucher.cameraUnavailable'),
                          style: AppType.body.copyWith(color: t.onPrimary),
                          textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ),
            ),
            IgnorePointer(child: CustomPaint(painter: _ReticlePainter(color: t.accent))),
            if (paused)
              ColoredBox(
                color: t.primary.withValues(alpha: 0.7),
                child: Center(child: CircularProgressIndicator(color: t.onPrimary)),
              ),
          ],
        ),
      ),
    );
  }
}

/// Four corner marks. Enough to say "point it here" without hiding the frame.
class _ReticlePainter extends CustomPainter {
  final Color color;
  const _ReticlePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide * 0.62;
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: side,
      height: side,
    );
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    const arm = 26.0;
    for (final (corner, dx, dy) in <(Offset, double, double)>[
      (rect.topLeft, 1, 1),
      (rect.topRight, -1, 1),
      (rect.bottomLeft, 1, -1),
      (rect.bottomRight, -1, -1),
    ]) {
      canvas
        ..drawLine(corner, corner.translate(arm * dx, 0), paint)
        ..drawLine(corner, corner.translate(0, arm * dy), paint);
    }
  }

  @override
  bool shouldRepaint(_ReticlePainter old) => old.color != color;
}

class _Refusal extends ConsumerWidget {
  final String messageKey;
  const _Refusal({required this.messageKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: t.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(Radii.chip),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: t.danger, size: 18),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Text(ref.watch(l10nProvider).t(messageKey),
                style: AppType.labelStrong.copyWith(color: t.danger)),
          ),
        ],
      ),
    );
  }
}

class _Success extends ConsumerWidget {
  final String? packName;
  const _Success({required this.packName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);

    return Scaffold(
      backgroundColor: t.surface,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(Gap.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_outline, size: 64, color: t.primary),
                const SizedBox(height: Gap.xl),
                Text(l10n.t('voucher.successTitle'),
                    style: AppType.hero.copyWith(color: t.primary),
                    textAlign: TextAlign.center),
                const SizedBox(height: Gap.sm),
                Text(
                  packName == null
                      ? l10n.t('voucher.successBody')
                      : l10n.t('voucher.successBodyNamed', vars: {'pack': packName!}),
                  style: AppType.body.copyWith(color: t.inkMuted),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: Gap.xxl),
                AppButton(
                  label: l10n.t('voucher.seeEsims'),
                  onPressed: () {
                    ref.read(voucherControllerProvider.notifier).reset();
                    context.goNamed('esims');
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
