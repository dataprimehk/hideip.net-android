import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../hip.dart';
import '../mark.dart' show MarkState;
import 'ascii_core.dart';

/// Which field the hero draws. `modeFor(state)` in
/// `design/app-1_1_0/home-ascii.js`: connected is hidden, connecting and
/// disconnecting are transit, everything else is exposed.
enum HeroAsciiMode { exposed, transit, hidden }

/// The mode [state] belongs to, and with it the palette and the glyph set.
HeroAsciiMode heroAsciiModeFor(MarkState state) => switch (state) {
      MarkState.connected => HeroAsciiMode.hidden,
      MarkState.connecting || MarkState.disconnecting => HeroAsciiMode.transit,
      MarkState.disconnected => HeroAsciiMode.exposed,
    };

/// The accent ramp per mode, four HSL stops interpolated across the columns.
/// Red while the address is out in the open, blue in transit, green once the
/// field is redacted: the same three colours the rest of Home speaks in.
const Map<HeroAsciiMode, List<List<double>>> _grads = {
  HeroAsciiMode.exposed: [
    [6, 78, 58],
    [10, 84, 62],
    [4, 86, 64],
    [16, 80, 60],
  ],
  HeroAsciiMode.transit: [
    [220, 85, 48],
    [220, 95, 62],
    [220, 100, 65],
    [210, 95, 62],
  ],
  HeroAsciiMode.hidden: [
    [152, 55, 44],
    [152, 62, 50],
    [160, 65, 52],
    [146, 60, 48],
  ],
};

/// Ambient level per mode: the hidden field is quiet, transit is busy.
const Map<HeroAsciiMode, double> _levels = {
  HeroAsciiMode.exposed: 0.60,
  HeroAsciiMode.transit: 0.75,
  HeroAsciiMode.hidden: 0.40,
};

/// Columns in each layer. The back layer is the fine grid that carries the
/// addresses; the front layer is coarse, sparse and blurred, and draws no
/// addresses at all, so the two read as depth rather than as one busy field.
const int _colsBack = 34;
const int _colsFront = 13;

const int _seedBack = 0x51AB1E17;
const int _seedFront = 0x7E11C0DE;

/// The tail the wave keeps fading over after the front has left the grid.
const double _waveTailMs = 250;

/// The ASCII field behind the home status card.
///
/// A literal port of `design/app-1_1_0/home-ascii.js`. [state] drives the mode
/// and the one-shot wave (left to right on connect, right to left on
/// disconnect); [front] selects the sparser, larger foreground layer that sits
/// over the card.
///
/// The engine paints at 12 fps and freezes six seconds after the last change
/// of state, except in transit, which never stops on its own. Backgrounding
/// the app stops it; coming back starts it again. When the user asked for less
/// motion it paints exactly one frame and holds no ticker.
class HeroAscii extends StatefulWidget {
  final MarkState state;
  final bool front;

  const HeroAscii({super.key, required this.state, this.front = false});

  @override
  State<HeroAscii> createState() => _HeroAsciiState();
}

class _HeroAsciiState extends State<HeroAscii>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final _HeroEngine _engine;
  late final AsciiTicker _ticker;
  final _Repaint _repaint = _Repaint();

  @override
  void initState() {
    super.initState();
    _engine = _HeroEngine(
      front: widget.front,
      mode: heroAsciiModeFor(widget.state),
      reducedMotion: Hip.reducedMotion,
    );
    _ticker = AsciiTicker(
      vsync: this,
      reducedMotion: Hip.reducedMotion,
      onFrame: (_) {
        // The engine keeps its own wall clock. The ticker's elapsed time
        // restarts from zero on every start, and the field has to carry on
        // where it left off rather than jump back to the opening frame.
        _repaint.ping();
      },
    );
    _ticker.continuous = _engine.mode == HeroAsciiMode.transit;
    WidgetsBinding.instance.addObserver(this);
    _ticker.poke();
  }

  @override
  void didUpdateWidget(HeroAscii oldWidget) {
    super.didUpdateWidget(oldWidget);
    final mode = heroAsciiModeFor(widget.state);
    if (mode == _engine.mode) return;
    _engine.mode = mode;
    _ticker.continuous = mode == HeroAsciiMode.transit;
    if (mode == HeroAsciiMode.transit && !Hip.reducedMotion) {
      _engine.waveDir = widget.state == MarkState.disconnecting ? -1 : 1;
      _engine.waveStart = _engine.timeMs;
    }
    _ticker.poke();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The web engine stops on `visibilitychange`. Same contract here: a field
    // nobody can see is a field nobody should pay for.
    if (state == AppLifecycleState.resumed) {
      _ticker.poke();
    } else {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _repaint.dispose();
    _engine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_engine.reducedMotion != Hip.reducedMotion) {
      // The engine has to know before the ticker does: the ticker paints the
      // still frame on the spot, and it has to be the settled one.
      _engine.reducedMotion = Hip.reducedMotion;
      _ticker.reducedMotion = Hip.reducedMotion;
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth.isFinite ? constraints.maxWidth : 0.0;
        final h = constraints.maxHeight.isFinite ? constraints.maxHeight : 0.0;
        if (w <= 0 || h <= 0) return const SizedBox.expand();
        if (_engine.resize(w, h)) {
          // Poking from inside layout would start a ticker mid-frame; the
          // next frame is soon enough for a grid that has just changed size.
          SchedulerBinding.instance.addPostFrameCallback((_) {
            if (mounted) _ticker.poke();
          });
        }
        Widget field = RepaintBoundary(
          child: CustomPaint(
            size: Size(w, h),
            isComplex: true,
            painter: _HeroAsciiPainter(_engine, _repaint),
          ),
        );
        // The band fades out at both edges so it never ends in a hard line.
        field = ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => _maskGradient.createShader(rect),
          child: field,
        );
        if (widget.front) {
          field = Opacity(
            opacity: 0.6,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 0.8, sigmaY: 0.8),
              child: field,
            ),
          );
        }
        return SizedBox.expand(child: field);
      },
    );
  }

  LinearGradient get _maskGradient => widget.front
      ? const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0x00000000),
            Color(0xFF000000),
            Color(0xFF000000),
            Color(0x00000000),
            Color(0x00000000),
          ],
          stops: [0, 0.24, 0.52, 0.80, 1],
        )
      : const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0x00000000),
            Color(0xFF000000),
            Color(0xFF000000),
            Color(0x00000000),
          ],
          stops: [0, 0.16, 0.84, 1],
        );
}

/// A repaint signal with no value: the painter reads the engine's own clock,
/// so all this has to do is say "now".
class _Repaint extends ChangeNotifier {
  void ping() => notifyListeners();
}

/// The grid, the clock and the frame buffers.
///
/// Held by the state and read by the painter, so a resize reallocates once
/// instead of once per frame.
class _HeroEngine {
  final bool front;
  final int seed;
  final double ambient;
  final double gain;
  final int cols;

  HeroAsciiMode mode;
  double waveStart = -1;
  int waveDir = 1;
  bool reducedMotion;

  final Stopwatch _clock = Stopwatch()..start();

  double width = 0;
  double height = 0;
  int rows = 0;
  double cellW = 0;
  double cellH = 0;

  List<String> chars = const [];
  Float32List inten = Float32List(0);
  Uint8List accent = Uint8List(0);

  AsciiParagraphCache? cache;
  Map<HeroAsciiMode, List<ui.Color>> grads = const {};

  _HeroEngine({
    required this.front,
    required this.mode,
    this.reducedMotion = false,
  })  : seed = front ? _seedFront : _seedBack,
        ambient = front ? 1.5 : 1.0,
        gain = front ? 1.9 : 1.0,
        cols = front ? _colsFront : _colsBack;

  /// The engine's own wall clock, frozen on one settled frame when the user
  /// asked for less motion.
  double get timeMs =>
      reducedMotion ? kStaticTimeMs : _clock.elapsedMicroseconds / 1000.0;

  bool get ready => rows > 0 && cache != null;

  /// Rebuilds the grid for a new box. Returns true when anything changed.
  bool resize(double w, double h) {
    if (w == width && h == height && ready) return false;
    width = w;
    height = h;
    cellW = w / cols;
    cellH = cellW * 1.4;
    rows = math.max(4, (h / cellH).ceil());
    final n = cols * rows;
    chars = List<String>.filled(n, '');
    inten = Float32List(n);
    accent = Uint8List(n);
    cache?.clear();
    cache = AsciiParagraphCache(
      fontSize: (cellW * 0.72 * 10).round() / 10,
    );
    grads = {
      for (final m in HeroAsciiMode.values) m: buildGradient(cols, _grads[m]!),
    };
    return true;
  }

  void dispose() {
    cache?.clear();
    _clock.stop();
  }

  void _put(int x, int y, String ch, double v, bool acc) {
    if (x < 0 || y < 0 || x >= cols || y >= rows) return;
    final i = y * cols + x;
    chars[i] = ch;
    inten[i] = v > 1 ? 1 : v;
    accent[i] = acc ? 1 : 0;
  }

  /// Slow, sparse blinking across the whole grid. Every cell has its own
  /// period and phase out of the seed, so the field never repeats visibly.
  void _drawAmbient(double t, double level) {
    final spawn = 0.30 * ambient;
    final hidden = mode == HeroAsciiMode.hidden;
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        final hh = hash2(x, y, seed);
        if (h01(hh) >= spawn) continue;
        final period = 1800 + h01(hash32(u32(hh ^ 0xA5))) * 4200;
        final cyc = t / period + h01(hash32(u32(hh ^ 0x3C)));
        final f = cyc - cyc.floorToDouble();
        final tri = f < 0.5 ? f * 2 : 2 - f * 2;
        var v = tri * tri * 1.4 - 0.4;
        if (v <= 0) continue;
        v *= level * 0.16;
        if (v <= 0.02) continue;
        final gh = hash2(x, y, seed ^ (cyc * 3).floor());
        _put(x, y, hidden ? glyphHidden(gh) : glyphExposed(gh), v, false);
      }
    }
  }

  /// Four address fragments on their own cycles. Exposed types them out and
  /// lets them stand; transit redacts them group by group into blocks; hidden
  /// shows them already redacted.
  void _drawFragments(double t) {
    const f = 4;
    for (var s = 0; s < f; s++) {
      final cd = mode == HeroAsciiMode.transit
          ? 3400 + h01(hash2(s, 0, seed)) * 1600
          : 6200 + h01(hash2(s, 0, seed)) * 4600;
      final off = h01(hash2(s, 1, seed)) * cd;
      final k = ((t + off) / cd).floor();
      final local = (t + off) - k * cd;
      final rng = mulberry32(u32(seed ^ hash2(s, k, 0x51)));
      final addr = mode == HeroAsciiMode.hidden
          ? maskedAddress(rng)
          : docAddress(rng);
      final row = (rng() * rows).floor();
      var col = (rng() * math.max(1, cols - addr.length)).floor();
      if (col > cols - addr.length) col = cols - addr.length;
      if (col < 0) col = 0;

      if (mode == HeroAsciiMode.hidden) {
        // Already redacted: it fades in, stands, and fades out.
        const tIn = 500.0, hold = 2300.0, outD = 700.0;
        final a = local < tIn
            ? local / tIn
            : local < tIn + hold
                ? 1.0
                : local < tIn + hold + outD
                    ? 1 - (local - tIn - hold) / outD
                    : 0.0;
        if (a <= 0.03) continue;
        for (var c = 0; c < addr.length; c++) {
          final acc = addr[c] == '█';
          _put(col + c, row, addr[c], (acc ? 0.30 : 0.18) * a, acc);
        }
      } else if (mode == HeroAsciiMode.exposed) {
        // The address types itself out and stays legible. Nothing hides it:
        // that is the point of the state.
        final typeDur = addr.length * 45.0;
        final visEnd = typeDur + 2200;
        final dissEnd = visEnd + 650;
        for (var c = 0; c < addr.length; c++) {
          String? ch;
          var v = 0.0;
          var acc = false;
          if (local < typeDur) {
            final born = c * 45.0;
            if (local < born) continue;
            if (local - born < 90) {
              ch = glyphExposed(hash2(c, k, seed ^ 0x77));
              acc = true;
            } else {
              ch = addr[c];
            }
            v = 0.30;
          } else if (local < visEnd) {
            ch = addr[c];
            v = 0.32;
          } else if (local < dissEnd) {
            final p = (local - visEnd) / 650;
            ch = p < 0.5 ? addr[c] : glyphExposed(hash2(c, k + 1, seed));
            v = 0.32 * (1 - p);
          } else {
            continue;
          }
          if (v > 0.03) _put(col + c, row, ch, v, acc);
        }
      } else {
        // Transit runs the full cycle: typed out, then redacted group by
        // group into solid blocks, then let go.
        final tD = addr.length * 40.0;
        final vE = tD + 700;
        final groups = <int>[];
        var g = 0;
        for (var i = 0; i < addr.length; i++) {
          groups.add(g);
          if (addr[i] == '.' || addr[i] == ':') g++;
        }
        final rE = vE + (g + 1) * 120 + 4 * 60;
        final hE = rE + 800, dE = hE + 500;
        for (var c = 0; c < addr.length; c++) {
          String? ch;
          var v = 0.0;
          var acc = false;
          if (local < tD) {
            final born = c * 40.0;
            if (local < born) continue;
            if (local - born < 80) {
              ch = glyphExposed(hash2(c, k, seed ^ 0x77));
              acc = true;
            } else {
              ch = addr[c];
            }
            v = 0.30;
          } else if (local < vE) {
            ch = addr[c];
            v = 0.32;
          } else if (local < rE) {
            final step = ((local - (vE + groups[c] * 120)) / 60).floor();
            if (step < 0) {
              ch = addr[c];
              v = 0.32;
            } else if (step < 4) {
              ch = kBlocks[step];
              v = 0.42;
              acc = true;
            } else {
              ch = '█';
              v = 0.24;
            }
          } else if (local < hE) {
            ch = '█';
            v = 0.22;
          } else if (local < dE) {
            final p = (local - hE) / 500;
            ch = kBlocks[3 - math.min(3, (p * 4).floor())];
            v = 0.22 * (1 - p);
          } else {
            continue;
          }
          if (v > 0.03) _put(col + c, row, ch, v, acc);
        }
      }
    }
  }

  /// The one-shot sweep on a change of state. Direction 1 is connect, left to
  /// right, glyphs redacting into blocks behind the front; direction -1 is
  /// disconnect, right to left, blocks falling back apart into digits.
  /// Returns how much ambient the wave is still stirring up.
  double _drawWaveOnce(double t) {
    if (waveStart < 0) return 0;
    final lt = t - waveStart;
    if (lt < 0 || lt > kWaveMs + _waveTailMs) return 0;
    var frontX = (math.min(lt, kWaveMs) / kWaveMs) * (cols + 12) - 4;
    if (waveDir < 0) frontX = cols - frontX;
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        final d = waveDir > 0 ? frontX - x : x - frontX;
        if (d < 0 || d > 10) continue;
        final boost = math.exp(-d / 4);
        if (boost < 0.04) continue;
        final i = y * cols + x;
        final lit = inten[i] + boost * 0.6;
        inten[i] = lit > 1 ? 1 : lit;
        if (waveDir > 0) {
          if (chars[i].isNotEmpty) {
            if (chars[i] != '█') {
              chars[i] = kBlocks[3 - math.min(3, (d / 3).floor())];
            }
          } else if (boost > 0.2) {
            chars[i] = kBlocks[math.min(3, (boost * 4).floor())];
          }
        } else {
          final dg = hash2(x, y, seed ^ (t / 90).floor());
          if (chars[i].isNotEmpty) {
            if (kBlocks.contains(chars[i])) {
              chars[i] = d < 2
                  ? kBlocks[math.max(0, 2 - d.floor())]
                  : glyphExposed(dg);
            }
          } else if (boost > 0.2) {
            chars[i] = glyphExposed(dg);
          }
        }
        if (d < 2 && inten[i] > 0.10) accent[i] = 1;
      }
    }
    return lt < 600 ? 1 : math.max(0, 1 - (lt - 600) / 400);
  }

  /// One frame into the buffers.
  void renderFrame(double t) {
    final n = cols * rows;
    for (var i = 0; i < n; i++) {
      chars[i] = '';
      inten[i] = 0;
      accent[i] = 0;
    }
    _drawAmbient(t, _levels[mode]!);
    if (!front) _drawFragments(t);
    final act = _drawWaveOnce(t);
    if (act > 0) _drawAmbient(t, 0.3 * act);
  }
}

class _HeroAsciiPainter extends CustomPainter {
  final _HeroEngine engine;

  _HeroAsciiPainter(this.engine, Listenable repaint) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final cache = engine.cache;
    if (!engine.ready || cache == null) return;
    engine.renderFrame(engine.timeMs);
    final gradCols = engine.grads[engine.mode]!;
    final gain = engine.gain;
    final halfCell = cache.cellWidth / 2;
    for (var y = 0; y < engine.rows; y++) {
      for (var x = 0; x < engine.cols; x++) {
        final i = y * engine.cols + x;
        final v = engine.inten[i];
        final ch = engine.chars[i];
        if (v < 0.03 || ch.isEmpty) continue;
        final ui.Color color;
        final double alpha;
        if (engine.accent[i] != 0) {
          color = gradCols[x];
          final a = v * 1.25 * gain;
          alpha = a > 0.95 ? 0.95 : a;
        } else {
          color = const Color(0xFFFFFFFF);
          final a = v * gain;
          alpha = a > 0.9 ? 0.9 : a;
        }
        final para = cache.paragraph(ch, color, alpha);
        canvas.drawParagraph(
          para,
          Offset(
            (x + 0.5) * engine.cellW - halfCell,
            (y + 0.5) * engine.cellH - para.height / 2,
          ),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_HeroAsciiPainter oldDelegate) =>
      oldDelegate.engine != engine;
}
