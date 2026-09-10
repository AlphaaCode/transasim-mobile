import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../brand/brand_config.dart';
import '../result/result.dart';

/// The single contract the core knows about. ARCHITECTURE-MOBILE.md §4.1.
///
/// The core knows no module; modules do not know each other. A module needing
/// another goes through a contract exposed by the core. That is what makes a
/// module genuinely removable — and therefore what makes a flag genuinely
/// honest.
abstract class AppModule {
  const AppModule();

  /// Stable identifier. Doubles as the key in `features` for optional modules.
  String get id;

  /// Is this module active for this brand?
  bool isEnabled(BrandConfig config);

  /// Routes. NOT REGISTERED when the module is inactive — this is half of what
  /// makes the flag honest (§4.2).
  List<RouteBase> routes(BrandConfig config);

  /// Main navigation entries. May be empty.
  List<NavEntry> navEntries(BrandConfig config);

  // NOTE — deviation from ARCHITECTURE-MOBILE.md §4.1, flagged deliberately.
  //
  // The spec's contract carries a fifth member, `List<Override> providers(...)`.
  // It is not implemented, for two reasons:
  //
  //   1. Riverpod 3.4.3 does not export `Override` from its public API
  //      (`riverpod.dart` exports a `show` list that omits it), so the return
  //      type is not nameable outside the package.
  //   2. It is not needed. The spec's justification was "a disabled module
  //      installs no providers". Riverpod providers are lazy: one that is never
  //      read is never created. A disabled module's routes are not registered
  //      and its use cases are guarded, so nothing reads them, so nothing is
  //      instantiated. The property the spec wanted holds without the member.
  //
  // If a module later needs a genuinely scoped override, this comes back —
  // with a named type from whatever Riverpod exposes then.
}

/// A bottom-navigation destination contributed by a module.
///
/// The tab set is per-brand by construction: ARCHITECTURE-MOBILE.md §5.7 noted
/// the white-label template has three tabs while Sabily has four. That is a
/// configuration outcome, not a special case.
class NavEntry {
  final String moduleId;
  final String path;

  /// Dictionary key, never a literal. Resolved through [L10n] at render time.
  final String labelKey;
  final IconData icon;

  const NavEntry({
    required this.moduleId,
    required this.path,
    required this.labelKey,
    required this.icon,
  });
}

/// The active module set for a brand.
class ModuleRegistry {
  final List<AppModule> all;
  final BrandConfig config;

  const ModuleRegistry({required this.all, required this.config});

  List<AppModule> get active => all.where((m) => m.isEnabled(config)).toList();

  bool isActive(String moduleId) => active.any((m) => m.id == moduleId);

  List<RouteBase> get routes => [for (final m in active) ...m.routes(config)];

  List<NavEntry> get navEntries => [for (final m in active) ...m.navEntries(config)];

  /// The entry guard — the OTHER half of the mechanism (§4.2).
  ///
  /// Not registering a route is not enough: the deep link, the named
  /// navigation and the network call all still exist in the binary. Every use
  /// case in an optional module starts with this.
  ///
  /// This is the exact equivalent of the web socle's `assertB2b()`, and it is
  /// the lesson the old app failed: `FEATURE_CREDIT_CARD` hid one of four
  /// entry points and closed none of the routes
  /// (`ANALYSE-EXISTANT.md` §4.10).
  Result<T> guard<T>(String moduleId, T Function() body) {
    if (!isActive(moduleId)) return Err<T>(FeatureUnavailable(moduleId));
    return Ok<T>(body());
  }
}
