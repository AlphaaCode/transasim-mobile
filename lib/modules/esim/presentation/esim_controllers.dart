/// Widget -> controller -> repository. No widget touches a repository.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/network_providers.dart';
import '../../../core/perf/perf_log.dart';
import '../../../core/session/session.dart';
import '../data/esim_repository_impl.dart';
import '../domain/esim.dart';

final esimRepositoryProvider = Provider<EsimRepository>(
  (ref) => EsimRepositoryImpl(ref.watch(apiClientProvider)),
);

/// The list. ONE request, and the screen can paint from it alone.
///
/// Scoped to the session for the same reason `profileProvider` is: a list of
/// one person's eSIMs must not survive into the next person's session. That
/// bug shipped once already, in the account module.
final esimPlansProvider = FutureProvider<List<EsimPlan>>((ref) {
  ref.watch(bearerTokenProvider);
  return perfTime('esim.plans total', ref.watch(esimRepositoryProvider).plans);
});

/// Usage for every plan that can still consume data, fetched CONCURRENTLY.
///
/// This is the whole N+1 answer, and the shape matters more than the count:
///
///  - the list does NOT await this. It paints from [esimPlansProvider], and
///    usage fills in underneath. Time to first meaningful paint is one request
///    regardless of how many eSIMs the user owns;
///  - the requests go out together via `Future.wait`, not in a loop with an
///    await inside it. N eSIMs cost one round trip of latency, not N;
///  - expired plans are skipped entirely. Nothing consumes data after it
///    expires, so asking is a request per dead eSIM for an answer that cannot
///    change.
///
/// The old app issued 16–21 SEQUENTIAL requests to render this screen
/// (`ANALYSE-EXISTANT.md`). Backend request B9 asks for a bulk endpoint, which
/// would make this one request too; until it exists, this is the honest
/// best shape.
final esimUsageProvider = FutureProvider<Map<int, EsimUsage>>((ref) async {
  final plans = await ref.watch(esimPlansProvider.future);
  final live = plans.where((p) => p.status.usesData && !p.isExpired).toList();
  if (live.isEmpty) return const <int, EsimUsage>{};

  final repo = ref.watch(esimRepositoryProvider);
  final results = await perfTime(
    'esim.usage ${live.length} concurrent',
    () => Future.wait(live.map(repo.usage)),
  );

  return <int, EsimUsage>{
    for (var i = 0; i < live.length; i++)
      if (results[i] != null) live[i].id: results[i]!,
  };
});

/// One plan by id, read from the list already in hand rather than re-fetched.
///
/// `.select` so the detail screen rebuilds when ITS plan changes and not when
/// any other plan in the list does.
final esimPlanProvider = Provider.family<EsimPlan?, int>((ref, id) {
  final plans = ref.watch(esimPlansProvider.select((async) => async.value));
  if (plans == null) return null;
  for (final p in plans) {
    if (p.id == id) return p;
  }
  return null;
});

/// Usage for one plan, again narrowed so a sibling's arrival does not rebuild
/// this card.
final esimUsageForProvider = Provider.family<EsimUsage?, int>(
  (ref, id) => ref.watch(esimUsageProvider.select((async) => async.value?[id])),
);

/// Pull-to-refresh: both the list and the usage that hangs off it.
Future<void> refreshEsims(WidgetRef ref) async {
  ref.invalidate(esimPlansProvider);
  await ref.read(esimPlansProvider.future);
}
