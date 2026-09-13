/// Narrowing one destination's packs by what each pack already says about
/// itself: how long it lasts, and how much data it carries.
///
/// Client-side, over the list already fetched — a destination has tens of
/// packs, not thousands, so there is nothing to page and no round-trip to make.
///
/// Network generation (4G/5G) is NOT here: none of the 966 live packs carries
/// it, in any field, name or product id. A filter needs the data first.
library;

import 'catalog.dart';

/// The distinct durations among [packs], shortest first.
List<Validity> durationOptions(List<Pack> packs) {
  final byKey = <String, Validity>{
    for (final p in packs)
      if (p.validity.isKnown) _durationKey(p.validity): p.validity,
  };
  return byKey.values.toList()..sort((a, b) => a.approximateDays.compareTo(b.approximateDays));
}

/// The distinct data amounts among [packs], smallest first, unlimited last.
List<DataAllowance> dataOptions(List<Pack> packs) {
  final byKey = <String, DataAllowance>{
    for (final p in packs)
      if (p.data.unlimited || (p.data.kilobytes ?? 0) > 0) _dataKey(p.data): p.data,
  };
  return byKey.values.toList()
    ..sort((a, b) {
      if (a.unlimited != b.unlimited) return a.unlimited ? 1 : -1;
      return (a.kilobytes ?? 0).compareTo(b.kilobytes ?? 0);
    });
}

/// [packs] matching both selections. A null selection is "all".
List<Pack> filterPacks(List<Pack> packs, {Validity? duration, DataAllowance? data}) => [
      for (final p in packs)
        if ((duration == null || _durationKey(p.validity) == _durationKey(duration)) &&
            (data == null || _dataKey(p.data) == _dataKey(data)))
          p,
    ];

bool sameDuration(Validity? a, Validity? b) =>
    a == null || b == null ? a == b : _durationKey(a) == _durationKey(b);

bool sameData(DataAllowance? a, DataAllowance? b) =>
    a == null || b == null ? a == b : _dataKey(a) == _dataKey(b);

String _durationKey(Validity v) => '${v.amount} ${v.kind.name}';

String _dataKey(DataAllowance d) => d.unlimited ? 'unlimited' : '${d.kilobytes}';
