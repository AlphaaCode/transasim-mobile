/// The two `dart:ui` types the brand schema touches, for code that runs with
/// no Flutter engine.
///
/// Studio (tool/studio) validates a brand with `BrandConfig.parse` on the plain
/// Dart VM, so its form and the app enforce exactly one set of rules
/// (docs/STUDIO-SPEC.md §3). That VM has no `dart:ui`, so `brand_config.dart`
/// and `i18n/locales.dart` reach these two types through a conditional import:
/// Flutter's own by default, this file `if (dart.library.mirrors)` — the plain
/// VM has `dart:mirrors`, Flutter never does, so the app never sees this file.
///
/// Not the obvious `if (dart.library.ui)`: the analyzer resolves that one to
/// its fallback, then type-checks the whole app against these stubs (41
/// errors). test/studio/studio_test.dart fails if a plain Flutter import
/// creeps back into anything Studio loads.
library;

/// Stand-in for `dart:ui`'s Color: the 32-bit ARGB value and nothing else.
class Color {
  const Color(this._argb);

  final int _argb;

  int toARGB32() => _argb;
}

/// Stand-in for `dart:ui`'s TextDirection.
enum TextDirection { rtl, ltr }
