/// My eSIMs, and one eSIM's detail.
///
/// Layout from `My eSIMs - Sabily (Mobile)` (52:26) and `eSIM Tracking -
/// Sabily` (47:923). Colours resolved through the brand tokens, not the
/// literals those frames carry — 52:26 alone uses `#004d40`, `#003c3a` AND
/// `#015552` for what is one role (ARCHITECTURE-MOBILE.md §2.2.1).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/brand/brand_providers.dart';
import '../../../core/session/session.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_button.dart';
import '../../../core/ui/app_card.dart';
import '../../../core/ui/app_skeleton.dart';
import '../domain/esim.dart';
import '../data/esim_install.dart';
import 'esim_controllers.dart';

class MyEsimsScreen extends ConsumerWidget {
  const MyEsimsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);
    final signedIn = ref.watch(isSignedInProvider);

    return Scaffold(
      backgroundColor: t.surface,
      appBar: AppBar(title: Text(l10n.t('nav.esims'))),
      body: SafeArea(
        child: !signedIn
            ? _SignedOut(l10n: l10n)
            : ref.watch(esimPlansProvider).when(
                  // Structure first. The list is one request, so this is brief
                  // — but a bare spinner still reads as "nothing is happening".
                  loading: () => const _EsimListSkeleton(),
                  error: (_, _) => StateMessageEsim(
                    icon: Icons.cloud_off,
                    title: l10n.t('error.network_unavailable'),
                    actionLabel: l10n.t('common.retry'),
                    onAction: () => ref.invalidate(esimPlansProvider),
                  ),
                  data: (plans) => plans.isEmpty
                      ? StateMessageEsim(
                          icon: Icons.sim_card_outlined,
                          title: l10n.t('esim.emptyTitle'),
                          body: l10n.t('esim.emptyBody'),
                          actionLabel: l10n.t('esim.browse'),
                          onAction: () => context.goNamed('store'),
                        )
                      : _EsimList(plans: plans),
                ),
      ),
    );
  }
}

class _EsimList extends ConsumerWidget {
  final List<EsimPlan> plans;
  const _EsimList({required this.plans});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);

    return RefreshIndicator(
      onRefresh: () => refreshEsims(ref),
      // Lazy from the start. A traveller accumulates eSIMs; the screen must not
      // build every card it has ever issued in order to show the top two.
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, Gap.md),
            sliver: SliverToBoxAdapter(
              child: Text(
                l10n.t('esim.activePlans'),
                style: AppType.title.copyWith(color: t.primary),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.xxl),
            sliver: SliverList.separated(
              itemCount: plans.length,
              separatorBuilder: (_, _) => const SizedBox(height: Gap.lg),
              itemBuilder: (context, i) => EsimCard(
                key: ValueKey<int>(plans[i].id),
                plan: plans[i],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One plan. Renders entirely from the list request; the usage bar appears
/// underneath when its own request lands, without moving anything else.
class EsimCard extends ConsumerWidget {
  final EsimPlan plan;
  const EsimCard({super.key, required this.plan});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);
    final expired = plan.isExpired;

    // Narrow: this card rebuilds when ITS usage arrives, not when a sibling's
    // does. With ten eSIMs a bare watch would rebuild all ten, ten times.
    final usage = ref.watch(esimUsageForProvider(plan.id));

    final card = AppCard(
      glow: !expired,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _IconChip(expired: expired),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(plan.packName,
                        style: AppType.label.copyWith(color: t.inkMuted),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: Gap.xs),
                    Text(
                      expired
                          ? l10n.t('esim.status.expired')
                          : _allowance(l10n, plan),
                      style: expired
                          ? AppType.body.copyWith(color: t.inkMuted)
                          : AppType.title.copyWith(color: t.primary),
                    ),
                  ],
                ),
              ),
              if (!expired) ...[
                const SizedBox(width: Gap.sm),
                _StatusPill(status: plan.status),
              ],
            ],
          ),
          if (usage != null) ...[
            const SizedBox(height: Gap.xl),
            _UsageBar(usage: usage),
          ],
          const SizedBox(height: Gap.lg),
          Divider(height: 1, color: t.fieldBorder),
          const SizedBox(height: Gap.lg),
          Row(
            children: [
              Expanded(child: _Footer(plan: plan, usage: usage, expired: expired)),
              const SizedBox(width: Gap.md),
              if (expired)
                AppLinkButton(
                  label: l10n.t('esim.repurchase'),
                  onPressed: () => context.goNamed('store'),
                )
              else
                _TopUpButton(plan: plan),
            ],
          ),
        ],
      ),
    );

    return Semantics(
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.control),
        onTap: () => context.pushNamed('esimDetail',
            pathParameters: {'id': '${plan.id}'}),
        // The expired card is dimmed as a whole, exactly as the frame draws it.
        child: Opacity(opacity: expired ? 0.8 : 1, child: card),
      ),
    );
  }

  static String _allowance(dynamic l10n, EsimPlan plan) {
    if (plan.unlimited) return l10n.t('catalog.unlimited') as String;
    final kb = plan.dataValueKb;
    if (kb == null) return '';
    final gb = kb / (1024 * 1024);
    final label = gb >= 1
        ? '${_trim(gb)} ${l10n.t('catalog.unit.gigabyte')}'
        : '${_trim(kb / 1024)} ${l10n.t('catalog.unit.megabyte')}';
    return label;
  }

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

class _IconChip extends StatelessWidget {
  final bool expired;
  const _IconChip({required this.expired});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Container(
      height: 48,
      width: 48,
      decoration: BoxDecoration(shape: BoxShape.circle, color: t.hairline),
      child: Icon(
        expired ? Icons.flight_land_outlined : Icons.sim_card_outlined,
        size: 20,
        color: expired ? t.inkMuted : t.primary,
      ),
    );
  }
}

class _StatusPill extends ConsumerWidget {
  final EsimStatus status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTokens.of(context);
    final l10n = ref.watch(l10nProvider);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.xs),
      decoration: BoxDecoration(
        color: t.accent,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Text(
        l10n.t('esim.status.${status.name}'),
        style: AppType.label.copyWith(color: t.primary),
      ),
    );
  }
}

class _UsageBar extends ConsumerWidget {
  final EsimUsage usage;
  const _UsageBar({required this.usage});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTokens.of(context);
    final l10n = ref.watch(l10nProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(l10n.t('esim.dataUsage'), style: AppType.label.copyWith(color: t.inkMuted)),
            Text(
              '${_n(usage.usedData)} / ${_n(usage.totalData)} ${usage.unit}',
              style: AppType.labelStrong.copyWith(color: t.primary),
            ),
          ],
        ),
        const SizedBox(height: Gap.sm),
        ClipRRect(
          borderRadius: BorderRadius.circular(Radii.pill),
          child: LinearProgressIndicator(
            value: usage.fraction,
            minHeight: 8,
            backgroundColor: t.hairline,
            valueColor: AlwaysStoppedAnimation<Color>(t.primary),
          ),
        ),
      ],
    );
  }

  static String _n(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

/// "12 jours (24 oct.)" near the end, a bare date further out.
///
/// A countdown is how a traveller reads an expiry that matters this week. At
/// two years out it stops being information and starts being noise — the list
/// rendered "Expire dans 26704 jours" before this existed.
String _expiry(dynamic l10n, EsimPlan plan) {
  final end = plan.endingDate;
  if (end == null) return '—';
  final date = '${end.day} ${_month(l10n, end.month)} ${end.year}';

  final days = plan.daysRemaining;
  if (days == null || days > 90) return date;

  final counted = l10n.t(days == 1 ? 'catalog.dayOne' : 'catalog.dayMany',
      vars: {'count': '$days'}) as String;
  return '$counted ($date)';
}

String _month(dynamic l10n, int m) =>
    (l10n.t('month.${_monthKeys[m - 1]}') as String);

const List<String> _monthKeys = [
  'jan', 'feb', 'mar', 'apr', 'may', 'jun',
  'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
];

class _Footer extends ConsumerWidget {
  final EsimPlan plan;
  final EsimUsage? usage;
  final bool expired;

  const _Footer({required this.plan, required this.usage, required this.expired});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTokens.of(context);
    final l10n = ref.watch(l10nProvider);

    if (expired) {
      final u = usage;
      return Text(
        u == null
            ? l10n.t('esim.status.expired')
            : '${l10n.t('esim.used')} ${_UsageBar._n(u.usedData)} / '
                '${_UsageBar._n(u.totalData)} ${u.unit}',
        style: AppType.label.copyWith(color: t.inkMuted),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.t('esim.expiresIn'), style: AppType.label.copyWith(color: t.inkMuted)),
        Text(
          _expiry(l10n, plan),
          style: AppType.bodyStrong.copyWith(color: t.primary),
        ),
      ],
    );
  }
}

/// Top-up. The button and the route exist; the flow does not.
///
/// Deliberate, and the same shape the wallet uses: backend request B5 (a
/// top-up endpoint) is NOT built. Nothing in the API accepts a top-up, so a
/// working flow here would be a button wired to an endpoint that does not
/// exist — which is how the old app shipped Google and Apple sign-in.
class _TopUpButton extends ConsumerWidget {
  final EsimPlan plan;
  const _TopUpButton({required this.plan});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    return AppButton(
      label: l10n.t('esim.topUp'),
      tone: AppButtonTone.cta,
      onPressed: () => showComingSoon(context, ref),
    );
  }
}

Future<void> showComingSoon(BuildContext context, WidgetRef ref) {
  final l10n = ref.read(l10nProvider);
  final t = AppTokens.of(context);
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: t.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.control)),
    ),
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(Gap.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule, size: 40, color: t.primary),
            const SizedBox(height: Gap.lg),
            Text(l10n.t('wallet.comingSoon'),
                style: AppType.heading.copyWith(color: t.primary)),
            const SizedBox(height: Gap.sm),
            Text(l10n.t('wallet.comingSoonBody'),
                style: AppType.body.copyWith(color: t.inkMuted),
                textAlign: TextAlign.center),
            const SizedBox(height: Gap.xl),
            AppButton(
              label: l10n.t('common.close'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SignedOut extends StatelessWidget {
  final dynamic l10n;
  const _SignedOut({required this.l10n});

  @override
  Widget build(BuildContext context) => StateMessageEsim(
        icon: Icons.person_outline,
        title: l10n.t('account.signedOutTitle') as String,
        body: l10n.t('account.signedOutBody') as String,
        actionLabel: l10n.t('account.signIn') as String,
        onAction: () => context.pushNamed('welcome'),
      );
}

class StateMessageEsim extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? body;
  final String? actionLabel;
  final VoidCallback? onAction;

  const StateMessageEsim({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Gap.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: t.inkMuted),
            const SizedBox(height: Gap.lg),
            Text(title,
                style: AppType.heading.copyWith(color: t.primary),
                textAlign: TextAlign.center),
            if (body != null) ...[
              const SizedBox(height: Gap.sm),
              Text(body!,
                  style: AppType.body.copyWith(color: t.inkMuted),
                  textAlign: TextAlign.center),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: Gap.xl),
              AppButton(label: actionLabel!, onPressed: onAction),
            ],
          ],
        ),
      ),
    );
  }
}

/// The list's own geometry while it loads.
class _EsimListSkeleton extends StatelessWidget {
  const _EsimListSkeleton();

  @override
  Widget build(BuildContext context) => const AppSkeleton(
        child: Padding(
          padding: EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, Gap.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppSkeletonBox(height: 32, width: 180),
              SizedBox(height: Gap.lg),
              _CardSkeleton(),
              SizedBox(height: Gap.lg),
              _CardSkeleton(),
            ],
          ),
        ),
      );
}

class _CardSkeleton extends StatelessWidget {
  const _CardSkeleton();

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(Gap.xl),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(Radii.control),
        boxShadow: Shadows.card,
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppSkeletonBox(height: 48, width: 48, circle: true),
              SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppSkeletonBox(height: 14, width: 150),
                    SizedBox(height: Gap.sm),
                    AppSkeletonBox(height: 24, width: 90),
                  ],
                ),
              ),
              AppSkeletonBox(height: 24, width: 64, radius: Radii.pill),
            ],
          ),
          SizedBox(height: Gap.xl),
          AppSkeletonBox(height: 8, radius: Radii.pill),
          SizedBox(height: Gap.xl),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              AppSkeletonBox(height: 36, width: 120),
              AppSkeletonBox(height: 44, width: 110),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Detail
// ---------------------------------------------------------------------------

/// One eSIM: its plan details, and how to get it onto the phone.
///
/// Install layout follows `eSIM Tracking` (47:923), which draws "Scan QR Code"
/// and "Manual Activation Steps" side by side and NO one-tap button. That is
/// also the technically correct emphasis — see [EsimInstaller].
class EsimDetailScreen extends ConsumerWidget {
  final int id;
  const EsimDetailScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);
    final plan = ref.watch(esimPlanProvider(id));

    if (plan == null) {
      return Scaffold(
        backgroundColor: t.surface,
        appBar: AppBar(),
        body: StateMessageEsim(
          icon: Icons.sim_card_alert_outlined,
          title: l10n.t('esim.missing'),
          actionLabel: l10n.t('common.close'),
          onAction: () => context.pop(),
        ),
      );
    }

    final usage = ref.watch(esimUsageForProvider(id));

    return Scaffold(
      backgroundColor: t.surface,
      appBar: AppBar(title: Text(plan.packName, style: AppType.heading.copyWith(color: t.primary))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, Gap.xxl),
          children: [
            if (usage != null) ...[
              AppCard(glow: true, child: _UsageBar(usage: usage)),
              const SizedBox(height: Gap.lg),
            ],
            _DetailsCard(plan: plan),
            if (plan.canInstall) ...[
              const SizedBox(height: Gap.lg),
              _InstallCard(plan: plan),
            ],
            const SizedBox(height: Gap.lg),
            AppButton(
              label: l10n.t('esim.topUp'),
              tone: AppButtonTone.cta,
              onPressed: () => showComingSoon(context, ref),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailsCard extends ConsumerWidget {
  final EsimPlan plan;
  const _DetailsCard({required this.plan});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.t('esim.planDetails'),
              style: AppType.heading.copyWith(color: AppTokens.of(context).primary)),
          const SizedBox(height: Gap.lg),
          if (plan.simSerial != null)
            _Row(label: l10n.t('esim.iccid'), value: plan.simSerial!),
          if (plan.startingDate != null)
            _Row(label: l10n.t('esim.startDate'), value: _d(plan.startingDate!)),
          if (plan.endingDate != null)
            _Row(label: l10n.t('esim.expiryDate'), value: _d(plan.endingDate!)),
        ],
      ),
    );
  }

  static String _d(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: AppType.label.copyWith(color: t.inkMuted))),
          const SizedBox(width: Gap.md),
          Flexible(
            child: Text(value,
                style: AppType.bodyStrong.copyWith(color: t.ink), textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }
}

/// QR first, everything else after.
class _InstallCard extends ConsumerWidget {
  final EsimPlan plan;
  const _InstallCard({required this.plan});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);
    final activation = plan.activation!;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.t('esim.installTitle'),
              style: AppType.heading.copyWith(color: t.primary)),
          const SizedBox(height: Gap.sm),
          Text(l10n.t('esim.installBody'),
              style: AppType.body.copyWith(color: t.inkMuted)),
          const SizedBox(height: Gap.xl),
          Center(
            child: Container(
              padding: const EdgeInsets.all(Gap.lg),
              decoration: BoxDecoration(
                color: t.card,
                borderRadius: BorderRadius.circular(Radii.chip),
                border: Border.all(color: t.fieldBorder),
              ),
              child: QrImageView(
                data: activation.code,
                size: 200,
                // Black on white, always. A QR tinted to the brand is a QR
                // some scanners refuse — contrast is the specification here,
                // not a style choice. The values live in the theme because
                // that is where colour literals live (check C2); they are the
                // only ones there that no brand can change.
                backgroundColor: t.qrBackground,
                eyeStyle: QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: t.qrForeground,
                ),
                dataModuleStyle: QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: t.qrForeground,
                ),
              ),
            ),
          ),
          const SizedBox(height: Gap.xl),
          Text(l10n.t('esim.manualTitle'),
              style: AppType.labelStrong.copyWith(color: t.primary)),
          const SizedBox(height: Gap.md),
          _CopyRow(label: l10n.t('esim.smdp'), value: activation.smdpAddress),
          _CopyRow(label: l10n.t('esim.activationCode'), value: activation.code),
          const SizedBox(height: Gap.lg),
          // Best effort, and last. If it does nothing the QR above still works.
          if (EsimInstaller.isSupportedPlatform)
            AppButton(
              label: l10n.t('esim.installNow'),
              icon: Icons.download_outlined,
              onPressed: () async {
                final outcome = await EsimInstaller.install(activation);
                if (!context.mounted) return;
                if (outcome != EsimInstallOutcome.handedOff) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.t('esim.installUnavailable'))),
                  );
                }
              },
            ),
        ],
      ),
    );
  }
}

class _CopyRow extends ConsumerWidget {
  final String label;
  final String value;
  const _CopyRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTokens.of(context);
    final l10n = ref.watch(l10nProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppType.label.copyWith(color: t.inkMuted)),
          const SizedBox(height: Gap.xs),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  value,
                  style: AppType.body.copyWith(color: t.ink),
                  maxLines: 2,
                ),
              ),
              IconButton(
                tooltip: l10n.t('esim.copy'),
                icon: Icon(Icons.copy_outlined, size: 18, color: t.primary),
                onPressed: () async {
                  await EsimInstaller.copy(value);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.t('esim.copied'))),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
