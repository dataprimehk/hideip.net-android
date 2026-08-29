import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';

import '../../brand.dart';

/// Shared core of the two ASCII engines: the home hero (`home-ascii.js`) and
/// onboarding v3 (`ob3-ascii.js`).
///
/// Everything here is a literal port of the JavaScript, and it has to stay
/// literal. Both engines are seeded noise: one wrong bit in the hash and the
/// picture drifts away from the design with nothing in the console to say so.
///
/// The one place Dart cannot copy JavaScript verbatim is the arithmetic.
/// `Math.imul` is a 32-bit multiply that wraps; Dart's `*` is a 64-bit
/// multiply on the VM and a double multiply on the web, and neither wraps.
/// So every multiply in a hash goes through [imul32] and every intermediate
/// value is masked back to 32 bits with [u32].

/// Mask for the low 32 bits.
const int _mask32 = 0xFFFFFFFF;

/// JavaScript `x >>> 0`: the value as an unsigned 32-bit integer.
int u32(int x) => x & _mask32;

/// JavaScript `Math.imul(a, b)`: a 32-bit multiply that wraps.
///
/// The 16-bit split is the standard polyfill. Each partial product stays well
/// inside the range a double represents exactly, which is what makes this
/// correct on the web as well as on the VM.
int imul32(int a, int b) {
  a = u32(a);
  b = u32(b);
  final ah = (a >> 16) & 0xFFFF;
  final al = a & 0xFFFF;
  final bh = (b >> 16) & 0xFFFF;
  final bl = b & 0xFFFF;
  return u32(al * bl + u32((((ah * bl + al * bh) & 0xFFFF) << 16)));
}

/// 32-bit integer hash (the `hash32` of both engines).
int hash32(int x) {
  x = u32(x);
  x = u32(x ^ (x >> 16));
  x = imul32(x, 0x045d9f3b);
  x = u32(x ^ (x >> 16));
  x = imul32(x, 0x045d9f3b);
  return u32(x ^ (x >> 16));
}

/// Hash of a grid cell: `hash2(x, y, seed)`.
int hash2(int a, int b, int seed) =>
    hash32(u32(imul32(a, 0x9E3779B1) ^ hash32(u32(b + seed))));

/// A hash as a fraction in [0, 1).
double h01(int h) => u32(h) / 4294967296.0;

/// The `mulberry32` PRNG. Returns a closure that yields the next double in
/// [0, 1) on each call, exactly like the JavaScript one.
double Function() mulberry32(int seed) {
  var a = u32(seed);
  return () {
    a = u32(a + 0x6D2B79F5);
    var t = a;
    t = imul32(t ^ (t >> 15), t | 1);
    t = u32(t ^ u32(t + imul32(t ^ (t >> 7), t | 61)));
    return u32(t ^ (t >> 14)) / 4294967296.0;
  };
}

/// The four shading blocks, lightest to solid.
const List<String> kBlocks = ['░', '▒', '▓', '█'];

/// Glyph for an exposed cell: mostly digits, because what leaks is addresses.
String glyphExposed(int h) {
  final v = h01(h);
  if (v < 0.70) return String.fromCharCode(48 + ((u32(h) >> 8) % 10));
  if (v < 0.85) return '.';
  if (v < 0.90) return '░';
  if (v < 0.95) return '▒';
  return ':';
}

/// Glyph for a hidden cell: mostly blocks, because what is left is redaction.
String glyphHidden(int h) {
  final v = h01(h);
  if (v < 0.50) return '░';
  if (v < 0.76) return '▒';
  if (v < 0.90) return '.';
  return '█';
}

/// The documentation address ranges the engines draw. RFC 5737 and RFC 3849
/// only: nothing on screen is ever a real address.
const List<String> kDocPrefixes = ['192.0.2.', '198.51.100.', '203.0.113.'];

/// One address from the documentation ranges, or an RFC 3849 IPv6 prefix on
/// roughly one draw in seven.
String docAddress(double Function() rng) {
  if (rng() < 0.15) {
    const hex = '0123456789abcdef';
    var tail = '';
    final n = 2 + (rng() * 3).floor();
    for (var i = 0; i < n; i++) {
      tail += hex[(rng() * 16).floor()];
    }
    return '2001:db8:$tail';
  }
  return '${kDocPrefixes[(rng() * 3).floor()]}${1 + (rng() * 254).floor()}';
}

/// The same address already redacted into blocks.
String maskedAddress(double Function() rng) {
  final b = StringBuffer();
  for (var g = 0; g < 4; g++) {
    final n = 2 + (rng() * 2).floor();
    for (var i = 0; i < n; i++) {
      b.write('█');
    }
    if (g < 3) b.write('.');
  }
  return b.toString();
}

/// Interpolates [stops] (HSL triples, four of them) across [cols] columns.
/// The JavaScript builds CSS colour strings; here it builds [ui.Color]s
/// through the brand's own `hsl()` so the palette stays one definition.
List<ui.Color> buildGradient(int cols, List<List<double>> stops) {
  final res = <ui.Color>[];
  for (var x = 0; x < cols; x++) {
    final g = cols > 1 ? (x / (cols - 1)) * 3 : 0.0;
    final i = g.floor() < 2 ? g.floor() : 2;
    final f = g - i;
    final a = stops[i];
    final b = stops[i + 1];
    res.add(Brand.hsl(
      a[0] + (b[0] - a[0]) * f,
      a[1] + (b[1] - a[1]) * f,
      a[2] + (b[2] - a[2]) * f,
    ));
  }
  return res;
}

/// The frame both engines freeze on when the user asked for less motion: one
/// still image from a point where the field is settled (`STATIC_T`).
const double kStaticTimeMs = 5200;

/// One wave sweep, and how long a fragment cycle runs.
const double kWaveMs = 750;

/// The paced clock both ASCII engines run on.
///
/// Two things it does that a bare [Ticker] does not:
///  * **Throttle.** The field is redrawn at most every [throttleMs] (12 fps).
///    Drawing faster costs battery and looks no different: the glyphs are a
///    coarse grid and the eye reads them as text, not as motion.
///  * **Freeze.** [idleMs] after the last [poke] the ticker stops itself and
///    the canvas keeps its last frame. Home is a screen people leave open, so
///    an ambient field that never stops is an ambient field that always
///    drains. [continuous] holds it open for the one mode that must keep
///    moving (the transit wave).
class AsciiTicker {
  /// 12 fps, the rate both engines were designed at.
  static const int throttleMs = 83;

  /// How long the field keeps moving after the last change of state.
  static const int idleMs = 6000;

  final void Function(double timeMs) onFrame;
  late final Ticker _ticker;

  Duration _lastDraw = Duration.zero;
  Duration _activeSince = Duration.zero;
  bool _continuous = false;
  bool _reducedMotion = false;

  AsciiTicker({
    required TickerProvider vsync,
    required this.onFrame,
    bool reducedMotion = false,
  }) {
    _reducedMotion = reducedMotion;
    _ticker = vsync.createTicker(_onTick);
  }

  bool get isRunning => _ticker.isActive;

  /// True while the engine is in a mode that must never freeze.
  bool get continuous => _continuous;
  set continuous(bool value) {
    if (_continuous == value) return;
    _continuous = value;
    if (value) poke();
  }

  /// Whether the user asked for less motion. While true the ticker never
  /// runs; [poke] paints the single frozen frame at [kStaticTimeMs] instead.
  bool get reducedMotion => _reducedMotion;
  set reducedMotion(bool value) {
    if (_reducedMotion == value) return;
    _reducedMotion = value;
    if (value) {
      _ticker.stop();
      onFrame(kStaticTimeMs);
    } else {
      poke();
    }
  }

  void _onTick(Duration elapsed) {
    if ((elapsed - _lastDraw).inMilliseconds < throttleMs) return;
    _lastDraw = elapsed;
    onFrame(elapsed.inMicroseconds / 1000.0);
    if (!_continuous &&
        (elapsed - _activeSince).inMilliseconds > idleMs) {
      _ticker.stop();
    }
  }

  /// Marks activity (a state change, coming back to the foreground, a
  /// resize) and starts the clock if it is not already running.
  void poke() {
    if (_reducedMotion) {
      onFrame(kStaticTimeMs);
      return;
    }
    _activeSince = _ticker.isActive ? _lastDraw : Duration.zero;
    if (!_ticker.isActive) {
      _lastDraw = Duration.zero;
      _ticker.start();
    }
  }

  void stop() => _ticker.stop();

  void dispose() {
    _ticker.stop();
    _ticker.dispose();
  }
}

/// Laid-out glyphs, cached by (glyph, colour, alpha bucket).
///
/// The hero field is roughly 34 by 20 cells and the globe reaches five to six
/// thousand points, so laying a paragraph out per cell per frame is the one
/// thing that would make this expensive. Every cell in a frame draws one of
/// six glyphs in one of a few dozen colours at one of [alphaBuckets] opacity
/// steps, so the whole frame comes out of a cache of a few hundred entries.
class AsciiParagraphCache {
  /// How finely alpha is quantised. Eight steps is below what the eye
  /// resolves on a glyph this small.
  static const int alphaBuckets = 8;

  final double fontSize;
  final String fontFamily;
  final int fontWeight;
  final Map<int, ui.Paragraph> _cache = {};

  AsciiParagraphCache({
    required this.fontSize,
    this.fontFamily = Brand.monoFont,
    this.fontWeight = 500,
  });

  /// The width every cached paragraph is laid out at. Each one is centred in
  /// this box, so a caller draws a cell by painting at
  /// `Offset(centerX - cellWidth / 2, centerY - paragraph.height / 2)`.
  double get cellWidth => fontSize * 2;

  /// The paragraph for [glyph] in [color] at [alpha] (0 to 1), laid out once
  /// and reused. Alpha is snapped to the nearest bucket.
  ui.Paragraph paragraph(String glyph, ui.Color color, double alpha) {
    final bucket = (alpha.clamp(0.0, 1.0) * alphaBuckets).round();
    final key = Object.hash(glyph, color.toARGB32(), bucket);
    final hit = _cache[key];
    if (hit != null) return hit;
    final shade = color.withValues(alpha: bucket / alphaBuckets);
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
      fontFamily: fontFamily,
      fontSize: fontSize,
      textAlign: ui.TextAlign.center,
    ))
      ..pushStyle(ui.TextStyle(
        color: shade,
        fontFamily: fontFamily,
        fontSize: fontSize,
        fontVariations: [ui.FontVariation('wght', fontWeight.toDouble())],
      ))
      ..addText(glyph);
    final paragraph = builder.build()
      ..layout(ui.ParagraphConstraints(width: cellWidth));
    _cache[key] = paragraph;
    return paragraph;
  }

  /// Drops every laid-out glyph. Called when the cell size changes, since
  /// every entry was laid out at the old font size.
  void clear() => _cache.clear();

  int get length => _cache.length;
}
