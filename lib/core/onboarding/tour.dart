/// The first-run tour: a few coach marks on the actions that matter, shown
/// where the user meets them, once.
///
/// Four marks and no more — scan a voucher, type its code, browse the store,
/// find your eSIMs. The people using this are travellers with a voucher in hand,
/// not people who came to learn an app.
///
/// Once means once per device: a mark shown is recorded as it appears, the tour
/// is done when every mark has been seen, and "Skip" (or back) anywhere ends
/// all of it. Nothing here is forced to the end.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../brand/brand_providers.dart';
import '../storage/preferences.dart';
import 'intro.dart';
import '../ui/app_coach_mark.dart';

/// Every mark in the tour. The tour is complete when all have been seen.
abstract final class TourStep {
  static const scanVoucher = 'home.scan';
  static const store = 'nav.store';
  static const esims = 'nav.esims';
  static const enterCode = 'voucher.code';

  static const all = [scanVoucher, store, esims, enterCode];
}

class TourProgress {
  final bool done;
  final Set<String> seen;
  const TourProgress({required this.done, required this.seen});
}

class TourController extends Notifier<TourProgress> {
  static const _doneKey = 'tour.done';
  static const _seenKey = 'tour.seen';

  @override
  TourProgress build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return TourProgress(
      done: prefs.getBool(_doneKey) ?? false,
      seen: {...?prefs.getStringList(_seenKey)},
    );
  }

  bool isPending(String step) => !state.done && !state.seen.contains(step);

  void markSeen(String step) {
    final seen = {...state.seen, step};
    _save(TourProgress(done: TourStep.all.every(seen.contains), seen: seen));
  }

  void dismiss() => _save(TourProgress(done: true, seen: state.seen));

  void _save(TourProgress next) {
    final prefs = ref.read(sharedPreferencesProvider);
    prefs.setBool(_doneKey, next.done);
    prefs.setStringList(_seenKey, next.seen.toList());
    state = next;
  }
}

final tourProvider = NotifierProvider<TourController, TourProgress>(TourController.new);

/// The key a navigation tab carries, by its label key, so a screen can point
/// at a tab the shell owns.
final navAnchorProvider = Provider.family<GlobalKey, String>(
  (ref, labelKey) => GlobalKey(debugLabel: 'nav:$labelKey'),
);

bool _running = false;

/// Shows the marks from [marks] still pending, recording each as it appears.
///
/// A mark whose widget is not on screen right now (a module this brand does
/// not ship, say) is left pending, not counted as seen.
Future<void> runTour(
  BuildContext context,
  WidgetRef ref,
  List<(String step, CoachMark mark)> marks,
) async {
  if (_running || !context.mounted) return;
  // Never under the logo animation: wait for it, then look again.
  await untilIntroDone(ref);
  if (!context.mounted) return;
  // Only over the screen the user is actually looking at.
  if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;

  final tour = ref.read(tourProvider.notifier);
  final pending = [
    for (final (step, mark) in marks)
      if (tour.isPending(step) && mark.target.currentContext != null) (step, mark),
  ];
  if (pending.isEmpty) return;

  final l10n = ref.read(l10nProvider);
  _running = true;
  try {
    final outcome = await showCoachMarks(
      context,
      marks: [for (final (_, mark) in pending) mark],
      labels: CoachMarkLabels(
        next: l10n.t('tour.next'),
        done: l10n.t('tour.done'),
        skip: l10n.t('tour.skip'),
      ),
      onShown: (i) => tour.markSeen(pending[i].$1),
    );
    if (outcome == CoachMarkOutcome.skipped) tour.dismiss();
  } finally {
    _running = false;
  }
}
