/// Checkout. `Checkout - Sabily (Mobile)` (52:560).
///
/// The promo-code + payment-method variant, not the currency-dropdown one:
/// per-currency pricing waits on backend request B4, and a dropdown that
/// cannot change a price is a lie with a chevron on it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/brand/brand_providers.dart';
import '../../../core/commerce/money.dart';
import '../../../core/i18n/country_flags.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/flag_glyph.dart';
import '../../../core/ui/app_button.dart';
import '../../../core/ui/app_card.dart';
import '../../../core/ui/esim_help_sheet.dart';
import '../../../core/ui/app_text_field.dart';
import 'checkout_controllers.dart';

class CheckoutScreen extends ConsumerWidget {
  final PurchaseRequest request;
  const CheckoutScreen({super.key, required this.request});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);
    final state = ref.watch(checkoutControllerProvider);
    final canPay = ref.watch(canTakePaymentsProvider);

    ref.listen(checkoutControllerProvider, (_, next) {
      if (next is CheckoutDone && context.mounted) {
        context.goNamed('esims');
      }
    });

    final busy = state is CheckoutBusy;

    return PopScope(
      // A charge in flight cannot be backed out of. Not a spinner the user can
      // tap away from — the system back gesture is refused too, for as long as
      // money is moving.
      canPop: !busy,
      child: Scaffold(
        backgroundColor: t.surface,
        appBar: AppBar(
          title: Text(l10n.t('checkout.title')),
          automaticallyImplyLeading: !busy,
        ),
        body: SafeArea(
          child: Stack(
            children: [
              ListView(
                padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, 120),
                children: [
                  _OrderSummary(request: request),
                  const SizedBox(height: Gap.lg),
                  const _PaymentMethod(),
                  const SizedBox(height: Gap.xl),
                  const _SecurityBadge(),
                  if (state is CheckoutError) ...[
                    const SizedBox(height: Gap.lg),
                    _Banner(messageKey: state.messageKey, tone: t.danger),
                  ],
                  if (state is CheckoutAwaitingProvisioning) ...[
                    const SizedBox(height: Gap.lg),
                    _Banner(messageKey: 'checkout.awaitingProvisioning', tone: t.warning),
                  ],
                  if (!canPay) ...[
                    const SizedBox(height: Gap.lg),
                    _Banner(messageKey: 'checkout.unavailable', tone: t.warning),
                  ],
                ],
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: _ActionBar(
                  request: request,
                  enabled: canPay && !busy,
                  busy: busy,
                ),
              ),
              // The honest processing state: a full-surface, undismissable
              // cover for as long as the charge is in flight.
              if (busy) _Processing(stepKey: state.stepKey),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrderSummary extends ConsumerWidget {
  final PurchaseRequest request;
  const _OrderSummary({required this.request});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);
    final code = request.destinationCode;
    final flag = code == null ? null : countryFlagAsset(code);

    return AppCard(
      padding: const EdgeInsets.all(Gap.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.t('checkout.orderSummary'),
              style: AppType.title.copyWith(color: t.primary)),
          // Before paying, and small: someone unsure whether their phone can
          // take an eSIM should be able to check without leaving checkout.
          // It informs; it does not gate, warn or interrupt the purchase.
          const EsimHelpLink(),
          const SizedBox(height: Gap.md),
          Row(
            children: [
              Container(
                height: 64,
                width: 64,
                alignment: Alignment.center,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: t.accent,
                  borderRadius: BorderRadius.circular(Radii.chip),
                ),
                // The same destination the pack was bought for, real flag or
                // nothing (country_flags.dart) — a request with no
                // destinationCode (not every purchase path sets one yet)
                // falls back to the generic icon rather than guessing one.
                // Inset, not filling: the mint tile is the summary's own
                // shape and stays visible around the flag, the same way the
                // sim-card icon sits on it when there is no destination.
                child: flag != null
                    ? FlagBadge(flag, size: 44)
                    : Icon(Icons.sim_card_outlined, color: t.primary),
              ),
              const SizedBox(width: Gap.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(request.packName,
                        style: AppType.subtitleStrong.copyWith(color: t.ink),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    Text(request.summary,
                        style: AppType.label.copyWith(color: t.inkMuted)),
                  ],
                ),
              ),
              const SizedBox(width: Gap.md),
              Text(request.amount.format(l10n.language),
                  style: AppType.subtitleStrong.copyWith(color: t.primary)),
            ],
          ),
          const SizedBox(height: Gap.lg),
          Divider(height: 1, color: t.fieldBorder),
          const SizedBox(height: Gap.lg),
          const _PromoCode(),
          const SizedBox(height: Gap.lg),
          _Breakdown(amount: request.amount),
        ],
      ),
    );
  }
}

class _PromoCode extends ConsumerStatefulWidget {
  const _PromoCode();

  @override
  ConsumerState<_PromoCode> createState() => _PromoCodeState();
}

class _PromoCodeState extends ConsumerState<_PromoCode> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: AppTextField(
            label: l10n.t('checkout.promoCode'),
            controller: _controller,
            textInputAction: TextInputAction.done,
          ),
        ),
        const SizedBox(width: Gap.sm),
        Padding(
          padding: const EdgeInsets.only(bottom: 0),
          child: SizedBox(
            height: kAppFieldHeight,
            child: Material(
              color: t.primary,
              borderRadius: BorderRadius.circular(Radii.chip),
              child: InkWell(
                borderRadius: BorderRadius.circular(Radii.chip),
                onTap: () {
                  ref.read(promoCodeProvider.notifier).apply(_controller.text);
                  // There is no endpoint that prices a code before purchase —
                  // the backend takes a voucherToken at subscribe time and
                  // exposes no "validate" route. Saying so is honest; showing a
                  // computed discount would not be. Backend request B10.
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.t('checkout.promoUnavailable'))),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
                  child: Center(
                    child: Text(l10n.t('checkout.apply'),
                        style: AppType.labelStrong.copyWith(color: t.onPrimary)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Breakdown extends ConsumerWidget {
  final Money amount;
  const _Breakdown({required this.amount});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);

    Widget row(String label, String value, {bool strong = false}) => Padding(
          padding: const EdgeInsets.only(bottom: Gap.sm),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: strong
                      ? AppType.subtitleStrong.copyWith(color: t.primary)
                      : AppType.body.copyWith(color: t.inkMuted)),
              Text(value,
                  style: strong
                      ? AppType.subtitleStrong.copyWith(color: t.primary)
                      : AppType.body.copyWith(color: t.inkMuted)),
            ],
          ),
        );

    return Column(
      children: [
        row(l10n.t('checkout.subtotal'), amount.format(l10n.language)),
        const SizedBox(height: Gap.sm),
        Divider(height: 1, color: t.fieldBorder),
        const SizedBox(height: Gap.md),
        // No discount line: nothing can currently produce one, and a permanent
        // "-0.00" is furniture pretending to be information.
        row(l10n.t('checkout.total'), amount.format(l10n.language), strong: true),
      ],
    );
  }
}

/// The methods this brand can actually offer.
///
/// The frame draws Apple Pay and Card as radio options. A wallet needs
/// `merchantIdentifier` and `merchantCountryCode`, and Sabily sets neither — so
/// for this brand there is exactly one method, and a radio group of one is
/// furniture. It renders as a statement instead, and becomes a choice the day
/// a brand configures a wallet.
class _PaymentMethod extends ConsumerWidget {
  const _PaymentMethod();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);
    final wallet = ref.watch(
      brandConfigProvider.select((b) => b.mobile.merchantIdentifier != null),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.t('checkout.paymentMethod'),
            style: AppType.title.copyWith(color: t.primary)),
        const SizedBox(height: Gap.md),
        _MethodRow(
          icon: Icons.credit_card,
          labelKey: 'checkout.method.card',
          selected: true,
          // Stripe's own sheet is the only collection surface; the app never
          // touches a PAN, a CVC or an expiry, and stays out of PCI scope.
          // §7.4 — the one thing the old app did right, kept as-is.
          subtitleKey: 'checkout.method.cardBody',
        ),
        if (wallet) ...[
          const SizedBox(height: Gap.md),
          const _MethodRow(
            icon: Icons.account_balance_wallet_outlined,
            labelKey: 'checkout.method.wallet',
            selected: false,
          ),
        ],
      ],
    );
  }
}

class _MethodRow extends ConsumerWidget {
  final IconData icon;
  final String labelKey;
  final String? subtitleKey;
  final bool selected;

  const _MethodRow({
    required this.icon,
    required this.labelKey,
    required this.selected,
    this.subtitleKey,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);

    return Container(
      padding: const EdgeInsets.all(Gap.lg),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(Radii.control),
        border: Border.all(color: selected ? t.primary : t.fieldBorder, width: selected ? 2 : 1),
        boxShadow: Shadows.field,
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: t.primary),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.t(labelKey), style: AppType.subtitle.copyWith(color: t.ink)),
                if (subtitleKey != null)
                  Text(l10n.t(subtitleKey!),
                      style: AppType.caption.copyWith(color: t.inkMuted)),
              ],
            ),
          ),
          if (selected) Icon(Icons.check_circle, size: 20, color: t.success),
        ],
      ),
    );
  }
}

class _SecurityBadge extends ConsumerWidget {
  const _SecurityBadge();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTokens.of(context);
    return Opacity(
      opacity: 0.8,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_outline, size: 14, color: t.inkMuted),
          const SizedBox(width: Gap.sm),
          Flexible(
            child: Text(ref.watch(l10nProvider).t('checkout.secure'),
                style: AppType.label.copyWith(color: t.inkMuted),
                textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }
}

class _Banner extends ConsumerWidget {
  final String messageKey;
  final Color tone;
  const _Banner({required this.messageKey, required this.tone});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
        padding: const EdgeInsets.all(Gap.md),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(Radii.chip),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: tone, size: 18),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: Text(ref.watch(l10nProvider).t(messageKey),
                  style: AppType.labelStrong.copyWith(color: tone)),
            ),
          ],
        ),
      );
}

/// The fixed bottom bar the frame draws, carrying the total on the button.
class _ActionBar extends ConsumerWidget {
  final PurchaseRequest request;
  final bool enabled;
  final bool busy;

  const _ActionBar({required this.request, required this.enabled, required this.busy});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Gap.lg),
      // The page's own ground, not a white sheet: the canvas wants no seam
      // under the footer, just the button's own shadow lifting it.
      color: t.surface,
      child: SafeArea(
        top: false,
        child: AppButton(
          label: l10n.t('checkout.pay', vars: {'amount': request.amount.format(l10n.language)}),
          icon: Icons.account_balance_wallet_outlined,
          // The one loud action on a calm screen — the same yellow as Home's
          // "Scan your voucher", which is what `cta` means in this palette.
          tone: AppButtonTone.cta,
          busy: busy,
          onPressed:
              enabled ? () => ref.read(checkoutControllerProvider.notifier).pay(request) : null,
        ),
      ),
    );
  }
}

/// A charge in flight, stated plainly and impossible to dismiss.
class _Processing extends ConsumerWidget {
  final String stepKey;
  const _Processing({required this.stepKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTokens.of(context);
    final l10n = ref.watch(l10nProvider);

    return Positioned.fill(
      child: AbsorbPointer(
        child: ColoredBox(
          color: t.surface.withValues(alpha: 0.94),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(Gap.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: t.primary),
                  const SizedBox(height: Gap.xl),
                  Text(l10n.t(stepKey),
                      style: AppType.heading.copyWith(color: t.primary),
                      textAlign: TextAlign.center),
                  const SizedBox(height: Gap.sm),
                  Text(l10n.t('checkout.doNotClose'),
                      style: AppType.body.copyWith(color: t.inkMuted),
                      textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
