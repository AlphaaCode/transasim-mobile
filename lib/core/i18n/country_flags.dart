/// A destination's flag, from the code the catalogue already carries.
///
/// The catalogue speaks ISO 3166-1 **alpha-3** end to end — Store rows, a
/// pack's coverage list, `place_names.g.dart`'s search index, this project's
/// own fixtures (`DZA`, `AUT`, ...). The bundled flags are named alpha-3 too,
/// so for the common case there is no mapping at all: `FRA` is `FRA.svg`.
///
/// Alpha-2 is still accepted and converted, because an earlier version of this
/// file assumed alpha-2 throughout and running it against the real catalogue
/// was what proved that wrong — every call returned null.
///
/// The old app pulled every flag from `flagcdn.com` at runtime: an
/// uncontrolled third-party dependency in a commercial funnel (rebuild audit,
/// `country.dart:75,77`). Nothing here fetches. The artwork ships in the
/// bundle, which the pack-art renderer requires anyway.
library;

import 'country_codes.g.dart';
import 'country_flag_assets.g.dart';

const int _regionalIndicatorBase = 0x1F1E6; // Unicode regional indicator 'A'
const int _asciiA = 0x41;
const int _asciiZ = 0x5A;

/// alpha-2 -> alpha-3, derived from the generated table rather than typed out
/// again, so the two can never disagree.
final Map<String, String> _alpha2ToAlpha3 = <String, String>{
  for (final e in kAlpha3ToAlpha2.entries) e.value: e.key,
};

/// The bundled flag for a catalogue code, or `null` when there is none.
///
/// Callers fall back to their own glyph — the ISO letters on a tinted disc —
/// rather than this returning a placeholder, so a regional pseudo-code never
/// renders as somebody's flag.
String? countryFlagAsset(String code) {
  final a3 = countryAlpha3(code);
  if (a3 == null || !kFlagAssetCodes.contains(a3)) return null;
  return 'assets/pack_art/flags/$a3.svg';
}

/// The curated flag-map inset for a catalogue code, or `null` when there is
/// none — which is the ordinary case, not an error: the set covers 139 of the
/// catalogue's 200-odd destinations and the Store card draws without an inset
/// for the rest.
///
/// Asked as a constant for the same reason as [countryFlagAsset]: `Image.asset`
/// fails asynchronously on a missing file, which lands as a broken-image box
/// halfway down a scrolling list.
String? countryFlagMapAsset(String code) {
  final a3 = countryAlpha3(code);
  if (a3 == null || !kFlagMapCodes.contains(a3)) return null;
  if (_euFilledMaps.contains(a3)) return null;
  return 'assets/flag_maps/$a3.webp';
}

/// Six of the curated maps are filled with the EU flag instead of the
/// country's own — Austria drawn as a ring of gold stars on reflex blue, and
/// Belarus the same despite not being in the EU at all. Measured by colour
/// histogram, each is 92-97% EU reflex blue (#00339b).
///
/// Treated as absent rather than shipped wrong, so the card falls back to the
/// country's real flag. Delete a code from here once its artwork is replaced;
/// the file is already on disk and in [kFlagMapCodes], so that is the only
/// change needed.
const Set<String> _euFilledMaps = <String>{
  'ALA', // Aland Islands
  'AUT', // Austria
  'BGR', // Bulgaria
  'BLR', // Belarus
  'DNK', // Denmark
  'HRV', // Croatia
};

/// A catalogue code as upper-case alpha-3, or `null` for a regional/global
/// pack pseudo-code and anything else that is not a country.
String? countryAlpha3(String code) {
  final upper = code.trim().toUpperCase();
  return switch (upper.length) {
    3 => kAlpha3ToAlpha2.containsKey(upper) ? upper : null,
    2 => _alpha2ToAlpha3[upper],
    _ => null,
  };
}

/// The flag EMOJI for a code, for text contexts where an inline character is
/// the only thing that composes with a sentence. The cards all draw the real
/// artwork instead.
String? countryFlagEmoji(String code) {
  final alpha2 = _alpha2(code);
  if (alpha2 == null) return null;
  final a = alpha2.codeUnitAt(0);
  final b = alpha2.codeUnitAt(1);
  if (a < _asciiA || a > _asciiZ || b < _asciiA || b > _asciiZ) return null;
  return String.fromCharCodes(<int>[
    _regionalIndicatorBase + (a - _asciiA),
    _regionalIndicatorBase + (b - _asciiA),
  ]);
}

String? _alpha2(String code) {
  final upper = code.trim().toUpperCase();
  final alpha2 = switch (upper.length) {
    2 => upper,
    3 => kAlpha3ToAlpha2[upper],
    _ => null,
  };
  return alpha2 != null && alpha2.length == 2 ? alpha2 : null;
}
