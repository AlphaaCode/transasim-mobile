/// The pack-card background as a widget, with the caching the art needs.
///
/// Rendering is not cheap — a zone map draws 236 countries' outlines through a
/// projection — so a finished frame is kept as a `ui.Image`, keyed by exactly
/// the things that change it: the brand's three colours, the sorted coverage,
/// and the destination being viewed. A list scrolling past forty packs
/// therefore paints each distinct background once.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_svg/flutter_svg.dart';

import 'geo_data.dart';
import 'pack_art_painter.dart';
import 'pack_palette.dart';

/// Decoded flags, keyed alpha-3. Small enough to keep all 250.
final Map<String, PackFlag> _flagCache = <String, PackFlag>{};
final Map<String, Future<PackFlag?>> _flagLoading = <String, Future<PackFlag?>>{};

Future<PackFlag?> _loadFlag(String code) {
  final hit = _flagCache[code];
  if (hit != null) return Future.value(hit);
  return _flagLoading.putIfAbsent(code, () async {
    try {
      final raw = await rootBundle.loadString('assets/pack_art/flags/$code.svg');
      final info = await vg.loadPicture(SvgStringLoader(raw), null);
      final flag = PackFlag(info.picture, info.size);
      _flagCache[code] = flag;
      return flag;
    } catch (_) {
      // A missing or unparseable flag is not fatal: the art draws the
      // silhouette in the highlight colour instead.
      return null;
    } finally {
      _flagLoading.remove(code);
    }
  });
}

/// A rendered background, kept by cache key.
///
/// Bounded and least-recently-used: a catalogue has a few hundred distinct
/// backgrounds and each is a 400x225 image, which is not something to hold
/// without a ceiling.
class _ArtCache {
  static const int _max = 60;
  static final LinkedHashMap<String, ui.Image> _entries = LinkedHashMap<String, ui.Image>();

  static ui.Image? get(String key) {
    final hit = _entries.remove(key);
    if (hit != null) _entries[key] = hit; // most recently used
    return hit;
  }

  static void put(String key, ui.Image image) {
    _entries[key] = image;
    while (_entries.length > _max) {
      final oldest = _entries.keys.first;
      _entries.remove(oldest)?.dispose();
    }
  }
}

/// The background behind a destination or pack card.
///
/// [codes] is the pack's own coverage; a single code renders that country,
/// several render a zone or the globe. [current] is the destination being
/// viewed, which a zone highlights and the globe turns toward.
class PackArt extends StatefulWidget {
  final List<String> codes;
  final String? current;
  final Color primary;
  final Color accent;
  final Color cta;

  const PackArt({
    super.key,
    required this.codes,
    required this.primary,
    required this.accent,
    required this.cta,
    this.current,
  });

  @override
  State<PackArt> createState() => _PackArtState();
}

class _PackArtState extends State<PackArt> {
  ui.Image? _image;
  String? _key;

  @override
  void initState() {
    super.initState();
    _render();
  }

  @override
  void didUpdateWidget(PackArt old) {
    super.didUpdateWidget(old);
    if (_cacheKey() != _key) _render();
  }

  String _cacheKey() {
    final sorted = [...{...widget.codes}]..sort();
    return '${widget.primary.toARGB32()}|${widget.accent.toARGB32()}|'
        '${widget.cta.toARGB32()}|${sorted.join(",")}|${widget.current ?? ""}';
  }

  Future<void> _render() async {
    final key = _cacheKey();
    _key = key;

    final cached = _ArtCache.get(key);
    if (cached != null) {
      if (mounted) setState(() => _image = cached);
      return;
    }

    final geo = await GeoData.load();
    final unique = <String>{...widget.codes}.toList();

    // Only the flags this frame can actually show: one for a country card, at
    // most the three largest for a zone. Loading 38 flags for a Europe pack
    // would cost far more than the drawing.
    final wanted = <String>{};
    if (unique.length <= 1) {
      wanted.add(unique.isNotEmpty ? unique.first : (widget.current ?? ''));
    } else {
      final known = [for (final c in unique) if (geo.countries.containsKey(c)) c]
        ..sort((a, b) => geo.countries[b]!.area.compareTo(geo.countries[a]!.area));
      if (widget.current != null && known.contains(widget.current)) {
        wanted.add(widget.current!);
      }
      wanted.addAll(known.take(6)); // a few spare: some get rejected by framing
    }
    final flags = <String, PackFlag>{};
    for (final code in wanted) {
      if (code.isEmpty) continue;
      final f = await _loadFlag(code);
      if (f != null) flags[code] = f;
    }

    if (!mounted || _key != key) return;

    final painter = PackArtPainter(
      palette: PackPalette.of(widget.primary, widget.accent, widget.cta),
      geo: geo,
      codes: unique,
      current: widget.current,
      flags: flags,
    );
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), const Size(kArtWidth, kArtHeight));
    final image = await recorder
        .endRecording()
        .toImage(kArtWidth.round(), kArtHeight.round());

    if (!mounted || _key != key) {
      image.dispose();
      return;
    }
    _ArtCache.put(key, image);
    setState(() => _image = image);
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) {
      // Nothing to show yet: the card's own surface, not a flash of white.
      return const SizedBox.expand();
    }
    return SizedBox.expand(
      child: RawImage(image: image, fit: BoxFit.cover, filterQuality: FilterQuality.medium),
    );
  }
}
