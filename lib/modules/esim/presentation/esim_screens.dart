/// My eSIMs, and one eSIM's detail.
///
/// Layout from `My eSIMs - Sabily (Mobile)` (52:26) and `eSIM Tracking -
/// Sabily` (47:923). Colours resolved through the brand tokens, not the
/// literals those frames carry — 52:26 alone uses `#004d40`, `#003c3a` AND
/// `#015552` for what is one role (ARCHITECTURE-MOBILE.md §2.2.1).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/brand/brand_providers.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/session/session.dart';
import '../../../core/sync/pending_order_notice.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_button.dart';
import '../../../core/ui/app_card.dart';
import '../../../core/ui/app_skeleton.dart';
import '../../../core/ui/esim_help_sheet.dart';
import '../data/fake_esims.dart';
import '../domain/esim.dart';
import '../data/esim_install.dart';
import 'esim_controllers.dart';
import '../../../core/perf/perf_log.dart';

/// Refetches on focus and on resume, throttled — see [refreshEsimsIfStale].
///
/// ⚠️ The list used to be fetched once per session and never again, so an
/// eSIM bought or redeemed minutes earlier was simply absent until the app was
/// killed. A purchase now invalidates directly; this covers the rest: coming
/// back to the tab, and waking the phone while a profile finishes installing
/// on the server.
class MyEsimsScreen extends ConsumerStatefulWidget {
  const MyEsimsScreen({super.key});

  @override
  ConsumerState<MyEsimsScreen> createState() => _MyEsimsScreenState();
}

class _MyEsimsScreenState extends ConsumerState<MyEsimsScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // After the first frame: the screen paints from whatever is cached and the
    // refetch lands underneath, rather than holding the paint on a request.
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshIfStale());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshIfStale();
  }

  void _refreshIfStale() {
    if (!mounted) return;
    if (!ref.read(isSignedInProvider)) return;
    // Fire and forget: the provider's own loading state is the feedback, and
    // a failure here must not replace a list that is already on screen.
    unawaited(refreshEsimsIfStale(ref));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);
    // The fake list stands in for a session as well as for data: without this
    // a demo build would show "you are not signed in" and never reach the
    // providers at all. `kFakeEsimsAllowed` is const false in release, so this
    // reduces to the plain check there.
    final faking = kFakeEsimsAllowed && ref.watch(fakeEsimsProvider);
    final signedIn = ref.watch(isSignedInProvider) || faking;
    perfLog('esim.screen build signedIn=$signedIn');

    return Scaffold(
      backgroundColor: t.surface,
      appBar: AppBar(
        // Long-press the title to swap in two invented eSIMs, and again to go
        // back to the real list. Deliberately undiscoverable — it is for
        // looking at the screen on a device, not a feature — and compiled out
        // of release entirely.
        title: kFakeEsimsAllowed
            ? GestureDetector(
                onLongPress: () => _toggleFakeEsims(context, ref),
                child: Text(l10n.t('nav.esims')),
              )
            : Text(l10n.t('nav.esims')),
      ),
      body: SafeArea(
        child: !signedIn
            ? _SignedOut(l10n: l10n)
            : Column(
                children: [
                  // Above everything, including the empty state — which is
                  // exactly the screen someone reaches when the eSIM they
                  // paid for has not arrived.
                  const _StuckOrderCard(),
                  Expanded(child: _plans(context, l10n)),
                ],
              ),
      ),
    );
  }

  Widget _plans(BuildContext context, L10n l10n) =>
      ref.watch(esimPlansProvider).when(
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
                );
}

/// Flips [fakeEsimsProvider] and says which list is now on screen, because a
/// silent swap between two plausible lists is impossible to read.
void _toggleFakeEsims(BuildContext context, WidgetRef ref) {
  ref.read(fakeEsimsProvider.notifier).toggle();
  final now = ref.read(fakeEsimsProvider);
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(
      content: Text(now ? 'Demo eSIMs ON (not real)' : 'Demo eSIMs off — real list'),
      duration: const Duration(seconds: 2),
    ));
}

class _EsimList extends ConsumerWidget {
  final List<EsimPlan> plans;
  const _EsimList({required this.plans});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    WidgetsBinding.instance.addPostFrameCallback((_) => perfLog('esim.list painted ${plans.length} plans'));
    final l10n = ref.watch(l10nProvider);
    final s = ShopTokens.of(context);

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
                style: AppType.title.copyWith(color: s.display),
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
                    Text(
                        // The pack may not have resolved. The plan is still
                        // the user's, so it is named rather than blank.
                        plan.packName.isEmpty
                            ? l10n.t('esim.unknownPack')
                            : plan.packName,
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
                          : AppType.title.copyWith(color: ShopTokens.of(context).display),
                    ),
                    // Said plainly, with somewhere to go. An eSIM whose
                    // details would not load is not a reason to hide it.
                    if (plan.detailsUnavailable) ...[
                      const SizedBox(height: Gap.xs),
                      Text(
                        l10n.t('esim.detailsUnavailable', vars: {
                          'email': ref.watch(
                              brandConfigProvider.select((b) => b.support.email)),
                        }),
                        style: AppType.caption.copyWith(color: t.danger),
                      ),
                    ],
                  ],
                ),
              ),
              if (!expired) ...[
                const SizedBox(width: Gap.sm),
                _StatusPill(status: plan.status),
              ],
            ],
          ),
          ...usageSection(l10n, t, plan: plan, usage: usage),
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
    return formatKilobytes(l10n, kb.toDouble());
  }
}

/// Kilobytes as "3 GB" / "500 MB", in the brand's own unit words.
///
/// The allowance line and the usage line go through THIS, so a plan whose
/// allowance reads "500 MB" cannot have a usage line reading "0.49 GB".
String formatKilobytes(dynamic l10n, double kb) {
  final gb = kb / (1024 * 1024);
  return gb >= 1
      ? '${trimNumber(gb)} ${l10n.t('catalog.unit.gigabyte')}'
      : '${trimNumber(kb / 1024)} ${l10n.t('catalog.unit.megabyte')}';
}

String trimNumber(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

/// What to put where the usage bar goes, for a given plan.
///
/// Three outcomes, and the middle one is the point:
///
///  - usage with a real total → the bar, even at 0 used. A `ready` plan that
///    the server says has used 0 of 500 MB has REAL data; drawing it at zero
///    is reporting, not inventing.
///  - no usage, and the plan is not `ready` → one muted line saying so. An
///    active plan with no numbers is a gap worth admitting; a fake bar or a
///    hard-coded 0 would be a lie about someone's allowance.
///  - no usage on a `ready` plan, or an unlimited/zero total → nothing. A
///    profile not yet installed has nothing to report, and an unlimited pack
///    has no denominator to draw.
List<Widget> usageSection(
  dynamic l10n,
  AppTokens t, {
  required EsimPlan plan,
  required EsimUsage? usage,
}) {
  if (usage != null && usage.hasMeasurableTotal) {
    return <Widget>[
      const SizedBox(height: Gap.xl),
      _UsageBar(usage: usage),
    ];
  }
  if (usage == null && plan.status != EsimStatus.ready) {
    return <Widget>[
      const SizedBox(height: Gap.md),
      Text(
        l10n.t('esim.usageUnavailable'),
        style: AppType.caption.copyWith(color: t.inkMuted),
      ),
    ];
  }
  return const <Widget>[];
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
        color: expired ? t.inkMuted : ShopTokens.of(context).fill,
      ),
    );
  }
}

class _StatusPill extends ConsumerWidget {
  final EsimStatus status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ShopTokens.of(context);
    final l10n = ref.watch(l10nProvider);
    final edge = s.badgeBorder;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.xs),
      decoration: BoxDecoration(
        color: s.badge,
        borderRadius: BorderRadius.circular(Radii.pill),
        border: edge == null ? null : Border.all(color: edge),
      ),
      child: Text(
        l10n.t('esim.status.${status.name}'),
        style: AppType.label.copyWith(color: s.onBadge),
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
              _label(l10n, usage),
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
            valueColor: AlwaysStoppedAnimation<Color>(
              usageBarColor(t, ShopTokens.of(context), usage.fraction),
            ),
          ),
        ),
      ],
    );
  }

  /// "2.5 GB / 10 GB" when the unit is one we know, otherwise the server's own
  /// numbers and its own unit text, untouched.
  ///
  /// ⚠️ Reformatting an unrecognised unit is how "10485760 GB" happens. When
  /// in doubt this repeats what the server said rather than converting it.
  static String _label(dynamic l10n, EsimUsage usage) {
    final used = usage.usedKilobytes;
    final total = usage.totalKilobytes;
    if (used != null && total != null) {
      return '${formatKilobytes(l10n, used)} / ${formatKilobytes(l10n, total)}';
    }
    final raw = '${trimNumber(usage.usedData)} / ${trimNumber(usage.totalData)}';
    return usage.unit.isEmpty ? raw : '$raw ${usage.unit}';
  }
}

/// How much is left, as a colour: the brand's own fill while there is plenty,
/// then amber, then red.
///
/// Takes the SAME [usedFraction] that sets the bar's width, and derives
/// everything from it. The old app computed a second consumption figure for
/// the colour, and the two could disagree — a bar drawn nearly full while
/// painted healthy. One number, two uses.
///
/// The thresholds are on what REMAINS, which is what a traveller is actually
/// asking. Semantic colours come from [AppTokens], where `danger`, `warning`
/// and `success` already live and are already used elsewhere; a brand does not
/// get to restyle "you are nearly out of data" (§2.3).
Color usageBarColor(AppTokens t, ShopTokens shop, double usedFraction) {
  // Compared on the USED side, though the thresholds are written in terms of
  // what remains. `1 - usedFraction` looks more readable and is wrong at the
  // boundary: a plan with exactly a fifth left computes 0.19999999999999996
  // and paints red. The subtraction is the only source of that error, so it
  // is not performed.
  if (usedFraction > 0.8) return t.danger; // under 20% left
  if (usedFraction > 0.5) return t.warning; // under 50% left
  return shop.fill;
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
        // Same converted-or-raw rule as the bar, so an expired card cannot
        // report different numbers from a live one.
        u == null
            ? l10n.t('esim.status.expired')
            : '${l10n.t('esim.used')} ${_UsageBar._label(l10n, u)}',
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
      tone: AppButtonTone.shop,
      // The Store, exactly as the expired card's "buy again" link already
      // does. Topping up IS buying another pack here; a "coming soon" sheet
      // on a button the user pressed to spend money was the wrong answer.
      onPressed: () => context.goNamed('store'),
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
            // The same rule as the card, so the two screens never disagree
            // about whether this plan has usage.
            if (usage != null && usage.hasMeasurableTotal) ...[
              AppCard(glow: true, child: _UsageBar(usage: usage)),
              const SizedBox(height: Gap.lg),
            ] else if (usage == null && plan.status != EsimStatus.ready) ...[
              AppCard(
                child: Text(
                  l10n.t('esim.usageUnavailable'),
                  style: AppType.caption.copyWith(color: t.inkMuted),
                ),
              ),
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
              onPressed: () => context.goNamed('store'),
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
          if (EsimInstaller.isSupportedPlatform) ...[
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
            const SizedBox(height: Gap.sm),
            // ⚠️ The hand-off can succeed and STILL appear to do nothing. On
            // one device the OS opened its own installer and Samsung's
            // telephony UI then closed it with "Add eSIM not allowed by
            // policy" — in its own process, where this app cannot see it. So
            // the line says what to do instead, and deliberately claims NO
            // cause: we genuinely do not know which of several it was.
            InkWell(
              onTap: () => showEsimHelpSheet(context),
              borderRadius: BorderRadius.circular(Radii.chip),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Gap.xs),
                child: Text(
                  l10n.t('esim.installHint'),
                  style: AppType.caption.copyWith(color: t.inkMuted),
                ),
              ),
            ),
          ],
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


/// "Payment received, finishing your eSIM."
///
/// Shown whenever an order is still on disk: the customer has been charged and
/// the eSIM is not here. Saying so, with the reference and a way out, is the
/// whole point — the alternative is an empty list and a charge on a statement.
///
/// Reads [pendingOrderNoticeProvider] rather than checkout's own types: this
/// module may not import that one (rule L2), so the composition root binds it.
class _StuckOrderCard extends ConsumerStatefulWidget {
  const _StuckOrderCard();

  @override
  ConsumerState<_StuckOrderCard> createState() => _StuckOrderCardState();
}

class _StuckOrderCardState extends ConsumerState<_StuckOrderCard> {
  bool _retrying = false;

  Future<void> _retry() async {
    final retry = ref.read(retryPendingOrderProvider);
    if (retry == null || _retrying) return;
    setState(() => _retrying = true);
    try {
      // Safe to press repeatedly: the backend refuses a payment already
      // COMPLETED_AND_CONSUMED, so this cannot double-provision or re-charge.
      final done = await retry();
      if (done) ref.invalidate(esimPlansProvider);
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final notice = ref.watch(pendingOrderNoticeProvider);
    if (notice == null) return const SizedBox.shrink();

    final l10n = ref.watch(l10nProvider);
    final t = AppTokens.of(context);
    final email = ref.watch(brandConfigProvider.select((b) => b.support.email));

    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, 0),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.hourglass_bottom, color: t.primary, size: 20),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Text(
                    l10n.t('esim.stuck.title'),
                    style: AppType.heading.copyWith(color: t.primary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Gap.sm),
            Text(
              notice.packName.isEmpty
                  ? l10n.t('esim.stuck.body')
                  : '${notice.packName} — ${l10n.t('esim.stuck.body')}',
              style: AppType.body.copyWith(color: t.inkMuted),
            ),
            const SizedBox(height: Gap.sm),
            // Quoted to support, so a human can find the charge in Stripe.
            SelectableText(
              l10n.t('esim.stuck.reference', vars: {'ref': notice.reference}),
              style: AppType.caption.copyWith(color: t.inkMuted),
            ),
            const SizedBox(height: Gap.lg),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: _retrying
                        ? l10n.t('esim.stuck.retrying')
                        : l10n.t('common.retry'),
                    busy: _retrying,
                    onPressed: ref.read(retryPendingOrderProvider) == null
                        ? null
                        : _retry,
                  ),
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: AppButton(
                    label: l10n.t('support.contact'),
                    tone: AppButtonTone.onDark,
                    onPressed: () => _mailto(email, notice.reference),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Opens the mail app with the reference already in the subject, because the
  /// one thing support needs is the thing a worried customer forgets to copy.
  void _mailto(String email, String reference) {
    final uri = Uri(
      scheme: 'mailto',
      path: email,
      queryParameters: <String, String>{'subject': reference},
    );
    unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
  }
}
