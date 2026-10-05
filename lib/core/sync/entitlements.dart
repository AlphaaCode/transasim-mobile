/// "What the user owns has changed" — the one fact checkout, vouchers and the
/// eSIM list all need to agree on.
///
/// It lives in `core/` because the modules that raise it and the module that
/// reacts to it may not import each other (rule L2): checkout and the voucher
/// screen bump it, the eSIM list watches it. Core imports no module, so the
/// dependency only ever points inward.
///
/// ⚠️ THE DEFECT THIS EXISTS TO PREVENT. `esimPlansProvider` is a
/// `FutureProvider` kept alive for the session, so it ran its request once and
/// never again. A customer who bought a pack, or redeemed a voucher, was
/// returned to a list rendered BEFORE the purchase — and it stayed that way
/// until the app was killed. The eSIM they had just paid for was simply not
/// there, and pull-to-refresh was the only way to find it.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A monotonic "something changed" counter other providers can watch.
///
/// A counter rather than a stream or a broadcast: a provider that watches it
/// re-runs on any change, late subscribers see the current value instead of
/// missing an event that already fired, and it is trivially assertable. Used
/// for the entitlements signal below and, in checkout, to make the pending
/// order reactive without the store and its reader watching each other.
class RevisionCounter extends Notifier<int> {
  @override
  int build() {
    // Nothing watches this between a purchase and the next visit to the eSIM
    // tab. Without keepAlive, Riverpod 3 would dispose it in that gap and the
    // bump would be forgotten — which is the bug it is here to fix.
    ref.keepAlive();
    return 0;
  }

  /// Call AFTER the server has confirmed. Bumping on an optimistic local
  /// change would refetch a list the backend has not written yet.
  void bump() => state = state + 1;
}

/// Incremented whenever a purchase or a redemption lands.
final entitlementsRevisionProvider =
    NotifierProvider<RevisionCounter, int>(RevisionCounter.new);

/// Whether a focus- or resume-triggered refetch is worth making yet.
///
/// Returning to the tab and waking the phone both ask, and a traveller does
/// both constantly — in and out of an app while a profile installs. Without a
/// floor that is a request per glance, on a screen whose list costs a join.
/// A purchase does not wait for it: that path invalidates directly.
class RefreshThrottle {
  /// Short enough that a list is never visibly stale, long enough that
  /// flicking between tabs is free.
  static const window = Duration(seconds: 30);

  DateTime? _last;

  /// True at most once per [window]. Records the time when it says yes, so
  /// the caller cannot forget to.
  bool allow(DateTime now) {
    final last = _last;
    if (last != null && now.difference(last) < window) return false;
    mark(now);
    return true;
  }

  /// Records a fetch that happened WITHOUT asking — the list's own first load,
  /// a pull-to-refresh, a refetch after a purchase.
  ///
  /// ⚠️ Without this, opening My eSIMs cost TWO requests: the provider loaded
  /// the list, and then the screen's first-frame focus check found an unused
  /// throttle, allowed itself, and invalidated the list it had just loaded.
  /// A fetch is a fetch whoever started it.
  void mark(DateTime now) => _last = now;

  /// Forgets the last refresh, so the next ask is allowed. For a sign-out, or
  /// anything else that makes the previous answer meaningless.
  void reset() => _last = null;
}
