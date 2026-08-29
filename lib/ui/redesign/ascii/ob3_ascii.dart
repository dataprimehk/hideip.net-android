import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../brand.dart';
import '../hip.dart';
import 'ascii_core.dart';

/// The onboarding background: ASCII rain with a wave on every Next, and a
/// dotted globe that retreats on the choice screen.
///
/// A literal port of `design/onboarding-v3/ob3-ascii.js`. Every constant,
/// formula and threshold below is copied from it without rounding: the field
/// is seeded noise, so a value that is "close enough" produces a picture that
/// is visibly not the design and nothing anywhere says why.
///
/// Two things differ from the JavaScript, both forced by the platform:
///  * The hashes run through [imul32] / [u32] so the arithmetic wraps at 32
///    bits the way `Math.imul` does.
///  * The globe is five to six thousand dots per frame. Canvas2D draws them
///    one arc at a time; here they are bucketed by opacity and drawn with
///    [Canvas.drawRawPoints], which is the same picture in a few dozen calls.

// ---------------------------------------------------------------------------
// Pure field maths. Public so the port can be pinned by tests against values
// computed from the JavaScript.
// ---------------------------------------------------------------------------

/// Hermite interpolation between two edges, the GLSL/CSS `smoothstep`.
double ob3Smoothstep(double e0, double e1, double x) {
  var t = (x - e0) / (e1 - e0);
  t = t < 0 ? 0 : (t > 1 ? 1 : t);
  return t * t * (3 - 2 * t);
}

/// How strongly a cell participates: the field fades towards the middle so
/// the headline always has quiet ground under it. The ellipse is wider than
/// tall (`u / 0.85`, `v / 0.95`) because the text block is.
double ob3CenterMask(int x, int y, int cols, int rows) {
  final u = ((x + 0.5) / cols) * 2 - 1;
  final v = ((y + 0.5) / rows) * 2 - 1;
  final r = math.sqrt((u / 0.85) * (u / 0.85) + (v / 0.95) * (v / 0.95));
  return 0.28 + 0.72 * ob3Smoothstep(0.3, 0.9, r);
}

/// Grid width, fixed. The cell height and the row count follow from it.
const int kOb3Cols = 34;

/// The tallest field ever built, whatever the screen height.
const int kOb3MaxRows = 52;

/// Seed of the onboarding field.
const int kOb3Seed = 0x51AB1E17;

/// Rain level while the field is at rest.
const double kOb3Level = 0.55;

/// Fraction of cells that may ever light up, before the centre mask.
const double kOb3Spawn = 0.35;

/// The blue ramp the accented glyphs are tinted along, left to right.
const List<List<double>> kOb3GradStops = [
  [220, 85, 48],
  [220, 95, 62],
  [220, 100, 65],
  [210, 95, 62],
];

/// Equirectangular land mask, 80 columns by 39 rows: one column is 4.5
/// degrees of longitude, one row 3.6 degrees of latitude, from 84N down.
const double kOb3MapW = 80;
const double kOb3MapLatTop = 84;
const double kOb3MapLatSpan = 140.4;

const List<String> _kWorldMap = [
  '                    ####    ######                                              ',
  '               ### ####  ##########        ##                ##                 ',
  '            ### ######     #########                ###      ####               ',
  '   ###### ################# ########       ### ############ ########### ########',
  '   #######################  ###### ##      #### ################################',
  '   ################    #### ####   ##     ######################################',
  '   ################    ####  #           ##############################    ##   ',
  '          #########    ####           ## ### ##########################    #    ',
  '           ########    ######         ## ###############################        ',
  '            ##############              ################################        ',
  '            ##############              ##########   ################# ##       ',
  '            #############             ### ########   ################# #        ',
  '             ###########              ##     #####  ################# ##        ',
  '             ###########              #####     #################### ##         ',
  '              #########               ##############################            ',
  '               ####  #               ########### ####  #############            ',
  '               ####  ###            ############ ####  #############            ',
  '                ##### ##            ############# ##   ##### #### ##            ',
  '                  #### ##           ############# ##    ###  #### ##            ',
  '                   ###              ###############     ##    ###  #            ',
  '                     ######          ###############      #   ##   ##           ',
  '                      #######        ##############       #   ## ###            ',
  '                      #######             #########          ## ####            ',
  '                      ########            ########            ## ### ###        ',
  '                      ##########          #######              # #   ####       ',
  '                      ###########         #######              ###     ##       ',
  '                       #########           ######                 #  ####       ',
  '                       #########           ###### ##               ######       ',
  '                        ########           ###### ##             ########       ',
  '                        #######            #####  #              #########      ',
  '                        ######             #####                 ##########     ',
  '                        #####               ###                   #########     ',
  '                        #####               ###                   ###  ###      ',
  '                        ####                                          ####     #',
  '                        ###                                             #     ##',
  '                        ##                                              #    ## ',
  '                        ##                                                   #  ',
  '                        ##                                                      ',
  '                        ##                                                      ',
];

/// The land dots, parsed once and kept for the life of the process.
///
/// Each `#` in the mask becomes four points (a 2 by 2 subsample), which is
/// what gives the coastlines their grain. The rotation is applied per frame
/// with an angle-addition identity, so the sine and cosine of every latitude
/// and longitude are taken here and never again.
class _LandPoints {
  final Float32List cosLat;
  final Float32List sinLat;
  final Float32List sinLon;
  final Float32List cosLon;
  final Float32List lat; // route endpoints are picked in spherical coordinates
  final Float32List lon;
  final int count;

  const _LandPoints({
    required this.cosLat,
    required this.sinLat,
    required this.sinLon,
    required this.cosLon,
    required this.lat,
    required this.lon,
    required this.count,
  });
}

_LandPoints? _landCache;

_LandPoints _worldPoints() {
  final cached = _landCache;
  if (cached != null) return cached;
  final mapRows = _kWorldMap.length;
  var n = 0;
  for (final row in _kWorldMap) {
    for (var c = 0; c < row.length; c++) {
      if (row.codeUnitAt(c) == 0x23) n += 4;
    }
  }
  final cosLat = Float32List(n);
  final sinLat = Float32List(n);
  final sinLon = Float32List(n);
  final cosLon = Float32List(n);
  final lat = Float32List(n);
  final lon = Float32List(n);
  var i = 0;
  for (var r = 0; r < mapRows; r++) {
    final row = _kWorldMap[r];
    for (var c = 0; c < row.length; c++) {
      if (row.codeUnitAt(c) != 0x23) continue;
      for (var sr = 0; sr < 2; sr++) {
        for (var sc = 0; sc < 2; sc++) {
          final la = (kOb3MapLatTop -
                  ((r + (sr + 0.5) / 2) / mapRows) * kOb3MapLatSpan) *
              math.pi /
              180;
          final lo = (-180 + ((c + (sc + 0.5) / 2) / kOb3MapW) * 360) *
              math.pi /
              180;
          cosLat[i] = math.cos(la);
          sinLat[i] = math.sin(la);
          sinLon[i] = math.sin(lo);
          cosLon[i] = math.cos(lo);
          lat[i] = la;
          lon[i] = lo;
          i++;
        }
      }
    }
  }
  return _landCache = _LandPoints(
    cosLat: cosLat,
    sinLat: sinLat,
    sinLon: sinLon,
    cosLon: cosLon,
    lat: lat,
    lon: lon,
    count: n,
  );
}

/// Points sorted into a fixed number of opacity buckets, so a frame of the
/// globe is a few [Canvas.drawRawPoints] calls instead of six thousand arcs.
/// The buffers are allocated once and refilled, never grown per frame.
class _PointBuckets {
  static const int count = 8;
  final List<Float32List> _xy;
  final Int32List _used = Int32List(count);

  _PointBuckets(int capacity)
      : _xy = List<Float32List>.generate(
            count, (_) => Float32List(capacity * 2),
            growable: false);

  void reset() => _used.fillRange(0, count, 0);

  void add(int bucket, double x, double y) {
    final buf = _xy[bucket];
    final n = _used[bucket];
    if (n * 2 + 1 >= buf.length) return;
    buf[n * 2] = x;
    buf[n * 2 + 1] = y;
    _used[bucket] = n + 1;
  }

  int lengthOf(int bucket) => _used[bucket];

  Float32List viewOf(int bucket) =>
      Float32List.sublistView(_xy[bucket], 0, _used[bucket] * 2);
}

// ---------------------------------------------------------------------------
// The glyph field.
// ---------------------------------------------------------------------------

/// The rain grid: characters, their intensity, and whether each one is tinted
/// along the blue ramp. Rebuilt only when the paint size changes.
class _Ob3Field {
  int cols = 0;
  int rows = 0;
  double cellW = 0;
  double cellH = 0;
  double ambient = 1;
  double _w = -1;
  double _h = -1;

  List<String> chars = const <String>[];
  Float32List inten = Float32List(0);
  Uint8List accent = Uint8List(0);
  List<ui.Color> grad = const <ui.Color>[];
  AsciiParagraphCache? cache;
  _PointBuckets? buckets;

  void resize(double w, double h) {
    if (w == _w && h == _h) return;
    _w = w;
    _h = h;
    cols = kOb3Cols;
    cellW = w / cols;
    cellH = cellW * 1.4;
    final r = (h / cellH).ceil();
    rows = r < 1 ? 1 : (r > kOb3MaxRows ? kOb3MaxRows : r);
    final n = cols * rows;
    chars = List<String>.filled(n, '');
    inten = Float32List(n);
    accent = Uint8List(n);
    grad = buildGradient(cols, kOb3GradStops);
    cache?.clear();
    cache = AsciiParagraphCache(
        fontSize: (cellW * 0.72 * 10).round() / 10, fontWeight: 500);
  }

  void _put(int x, int y, String ch, double v, bool acc) {
    if (x < 0 || y < 0 || x >= cols || y >= rows) return;
    final i = y * cols + x;
    chars[i] = ch;
    inten[i] = v > 1 ? 1 : v;
    accent[i] = acc ? 1 : 0;
  }

  void _drawAmbient(double t, double level) {
    final spawn = kOb3Spawn * ambient;
    final narrow = cols <= 32 ? 0.75 : 1.0;
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        final m = ob3CenterMask(x, y, cols, rows) * narrow;
        final hh = hash2(x, y, kOb3Seed);
        final gate = spawn * m;
        if (h01(hh) >= (gate > 0.9 ? 0.9 : gate)) continue;
        final period = 1800 + h01(hash32(u32(hh ^ 0xA5))) * 4200;
        final cyc = t / period + h01(hash32(u32(hh ^ 0x3C)));
        final f = cyc - cyc.floorToDouble();
        final tri = f < 0.5 ? f * 2 : 2 - f * 2;
        var v = tri * tri * 1.4 - 0.4;
        if (v <= 0) continue;
        v *= m * level * 0.16;
        if (v <= 0.02) continue;
        _put(x, y, glyphExposed(hash2(x, y, u32(kOb3Seed ^ (cyc * 3).floor()))),
            v, false);
      }
    }
  }

  void _drawFragments(double t) {
    final raw = (cols * rows / 260).round();
    final fragments = raw < 3 ? 3 : (raw > 8 ? 8 : raw);
    for (var s = 0; s < fragments; s++) {
      final cd = 8000 + h01(hash2(s, 0, kOb3Seed)) * 5000;
      final off = h01(hash2(s, 1, kOb3Seed)) * cd;
      final k = ((t + off) / cd).floor();
      final local = (t + off) - k * cd;
      final rng = mulberry32(u32(kOb3Seed ^ hash2(s, k, 0x51)));
      final addr = docAddress(rng);
      final row = (rng() * rows).floor();
      final edgeRow = row < rows * 0.12 || row > rows * 0.82;
      if (!edgeRow && cols <= 32) continue;
      final spanRaw = (cols * 0.30).floor() - addr.length;
      final span = spanRaw < 1 ? 1 : spanRaw;
      int col;
      if (edgeRow) {
        final room = cols - addr.length;
        col = (rng() * (room < 1 ? 1 : room)).floor();
      } else {
        // The branch is chosen with its own draw, then the column with the
        // next one: the order of calls is part of the sequence.
        final pick = rng();
        col = pick < 0.5
            ? (rng() * span).floor()
            : (cols * 0.70).floor() + (rng() * span).floor();
      }
      if (col > cols - addr.length) col = cols - addr.length;
      if (col < 0) col = 0;
      final fm =
          0.45 + 0.55 * ob3CenterMask(col + (addr.length >> 1), row, cols, rows);
      final typeDur = addr.length * 45.0;
      final visEnd = typeDur + 1400;
      final groups = List<int>.filled(addr.length, 0);
      var g = 0;
      for (var i = 0; i < addr.length; i++) {
        groups[i] = g;
        final ch = addr[i];
        if (ch == '.' || ch == ':') g++;
      }
      final redactEnd = visEnd + (g + 1) * 140 + 4 * 65;
      final holdEnd = redactEnd + 1000;
      final dissEnd = holdEnd + 600;
      for (var c = 0; c < addr.length; c++) {
        String? ch;
        var v = 0.0;
        var acc = false;
        if (local < typeDur) {
          final born = c * 45.0;
          if (local < born) continue;
          if (local - born < 90) {
            ch = glyphExposed(hash2(c, k, u32(kOb3Seed ^ 0x77)));
            acc = true;
          } else {
            ch = addr[c];
          }
          v = 0.30 * fm;
        } else if (local < visEnd) {
          ch = addr[c];
          v = 0.32 * fm;
        } else if (local < redactEnd) {
          final step = ((local - (visEnd + groups[c] * 140)) / 65).floor();
          if (step < 0) {
            ch = addr[c];
            v = 0.32 * fm;
          } else if (step < 4) {
            ch = kBlocks[step];
            v = 0.42 * fm;
            acc = true;
          } else {
            ch = '█';
            v = 0.24 * fm;
          }
        } else if (local < holdEnd) {
          ch = '█';
          v = 0.22 * fm;
        } else if (local < dissEnd) {
          final p = (local - holdEnd) / 600;
          final drop = (p * 4).floor();
          ch = kBlocks[3 - (drop > 3 ? 3 : drop)];
          v = 0.22 * fm * (1 - p);
        } else {
          continue;
        }
        if (v > 0.03) _put(col + c, row, ch, v, acc);
      }
    }
  }

  /// One sweep left to right on every Next. Returns how much extra rain the
  /// front is still pulling behind it (0 to 1).
  double _drawWaveOnce(double t, double waveStart) {
    if (waveStart < 0) return 0;
    final lt = t - waveStart;
    if (lt < 0 || lt > kWaveMs + 250) return 0;
    final front =
        ((lt < kWaveMs ? lt : kWaveMs) / kWaveMs) * (cols + 12) - 4;
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        final d = front - x;
        if (d < 0 || d > 10) continue;
        final m = ob3CenterMask(x, y, cols, rows);
        final boost = math.exp(-d / 4) * m;
        if (boost < 0.04) continue;
        final i = y * cols + x;
        final lit = inten[i] + boost * 0.6;
        inten[i] = lit > 1 ? 1 : lit;
        if (chars[i].isNotEmpty) {
          if (chars[i] != '█') {
            final step = (d / 3).floor();
            chars[i] = kBlocks[3 - (step > 3 ? 3 : step)];
          }
        } else if (boost > 0.2) {
          final step = (boost * 4).floor();
          chars[i] = kBlocks[step > 3 ? 3 : step];
        }
        if (d < 2 && inten[i] > 0.10) accent[i] = 1;
      }
    }
    if (lt < 600) return 1;
    final tail = 1 - (lt - 600) / 400;
    return tail < 0 ? 0 : tail;
  }

  void render(double t, double waveStart) {
    final n = cols * rows;
    for (var i = 0; i < n; i++) {
      chars[i] = '';
      inten[i] = 0;
      accent[i] = 0;
    }
    _drawAmbient(t, kOb3Level);
    _drawFragments(t);
    final act = _drawWaveOnce(t, waveStart);
    if (act > 0) _drawAmbient(t, 0.3 * act);
  }

  void dispose() {
    cache?.clear();
    cache = null;
  }
}

/// Everything a frame needs that changes between frames. Held apart from the
/// widget so a repaint never rebuilds the tree.
class _Ob3Data {
  double t = 0;
  double waveStart = -1;
  double gA = 1;
  double gTarget = 1;
}

// ---------------------------------------------------------------------------
// The widget.
// ---------------------------------------------------------------------------

/// Handle the onboarding screen holds: it triggers the wave on Next and pulls
/// the globe back on the choice screen.
class Ob3AsciiController extends ChangeNotifier {
  int _wave = 0;
  bool _globe = true;

  int get waveSeq => _wave;
  bool get globe => _globe;

  /// Starts one sweep. Ignored while the user asked for less motion, the same
  /// way the prototype ignores it.
  void wave() {
    _wave++;
    notifyListeners();
  }

  void setGlobe(bool on) {
    if (_globe == on) return;
    _globe = on;
    notifyListeners();
  }
}

/// The onboarding background. Paints at 12 fps through [AsciiTicker], and
/// freezes to a single frame when the user asked for less motion: with
/// `disableAnimations` on, no ticker is ever created.
class Ob3Ascii extends StatefulWidget {
  final Ob3AsciiController controller;
  const Ob3Ascii({super.key, required this.controller});

  @override
  State<Ob3Ascii> createState() => _Ob3AsciiState();
}

class _Ob3AsciiState extends State<Ob3Ascii>
    with SingleTickerProviderStateMixin {
  final _Ob3Field _field = _Ob3Field();
  final _Ob3Data _data = _Ob3Data();
  final ValueNotifier<int> _repaint = ValueNotifier<int>(0);
  AsciiTicker? _ticker;
  int _seenWave = 0;
  bool _reduced = false;
  bool _started = false;

  /// Visible for tests: whether a ticker exists at all.
  bool get hasTicker => _ticker != null;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onController);
    _seenWave = widget.controller.waveSeq;
    _data.gTarget = widget.controller.globe ? 1 : 0;
    _data.gA = _data.gTarget;
  }

  @override
  void didUpdateWidget(Ob3Ascii old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onController);
      widget.controller.addListener(_onController);
      _seenWave = widget.controller.waveSeq;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.disableAnimationsOf(context) || Hip.reducedMotion;
    if (_started && reduced == _reduced) return;
    _started = true;
    _reduced = reduced;
    _sync();
  }

  void _sync() {
    if (_reduced) {
      _ticker?.stop();
      _frame(kStaticTimeMs);
      return;
    }
    final ticker = _ticker ??= AsciiTicker(vsync: this, onFrame: _frame);
    // Onboarding is a screen someone is looking at while they read; the field
    // never idles out from under them the way the home hero does.
    ticker.continuous = true;
    ticker.poke();
  }

  void _frame(double t) {
    _data.t = t;
    _data.gA += (_data.gTarget - _data.gA) * 0.18;
    if ((_data.gTarget - _data.gA).abs() < 0.02) _data.gA = _data.gTarget;
    _repaint.value++;
  }

  void _onController() {
    final controller = widget.controller;
    if (controller.waveSeq != _seenWave) {
      _seenWave = controller.waveSeq;
      if (!_reduced) _data.waveStart = _data.t;
    }
    final target = controller.globe ? 1.0 : 0.0;
    if (_data.gTarget != target) {
      _data.gTarget = target;
      if (_reduced) _data.gA = target;
    }
    if (_reduced) {
      _frame(kStaticTimeMs);
    } else {
      _ticker?.poke();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onController);
    _ticker?.dispose();
    _repaint.dispose();
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _Ob3Painter(field: _field, data: _data, repaint: _repaint),
        size: Size.infinite,
      ),
    );
  }
}

class _Ob3Painter extends CustomPainter {
  final _Ob3Field field;
  final _Ob3Data data;

  _Ob3Painter({
    required this.field,
    required this.data,
    required Listenable repaint,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    field.resize(size.width, size.height);
    field.render(data.t, data.waveStart);
    _paintField(canvas);
    _paintGlobe(canvas, size);
  }

  void _paintField(Canvas canvas) {
    final cache = field.cache;
    if (cache == null) return;
    final half = cache.cellWidth / 2;
    for (var y = 0; y < field.rows; y++) {
      for (var x = 0; x < field.cols; x++) {
        final i = y * field.cols + x;
        final v = field.inten[i];
        final ch = field.chars[i];
        if (v < 0.03 || ch.isEmpty) continue;
        final ui.Color color;
        final double alpha;
        if (field.accent[i] != 0) {
          color = field.grad[x];
          final a = v * 1.25;
          alpha = a > 0.95 ? 0.95 : a;
        } else {
          color = const Color(0xFFFFFFFF);
          alpha = v > 0.9 ? 0.9 : v;
        }
        final paragraph = cache.paragraph(ch, color, alpha);
        canvas.drawParagraph(
          paragraph,
          Offset((x + 0.5) * field.cellW - half,
              (y + 0.5) * field.cellH - paragraph.height / 2),
        );
      }
    }
  }

  /// The globe, in pixels rather than in the glyph grid: 34 columns is far too
  /// coarse for coastlines. Same dotted look, drawn straight onto the canvas.
  void _paintGlobe(Canvas canvas, Size size) {
    final gA = data.gA;
    if (gA <= 0.02) return;
    final t = data.t;
    final pts = _worldPoints();
    final buckets = field.buckets ??= _PointBuckets(pts.count);
    final cx = size.width * 0.5;
    final cy = size.height * 0.29;
    final r = math.min(size.width * 0.36, 150.0);
    if (r <= 0) return;
    final rot = t * 0.014 * math.pi / 180;
    final breathe = (0.80 + 0.20 * math.sin(t / 9000 * 2 * math.pi)) * gA;

    // The rain fades out under the disc so the planet stands on quiet ground.
    canvas.drawCircle(
      Offset(cx, cy),
      r * 1.18,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(cx, cy),
          r * 1.18,
          const [Color(0xF00B0E14), Color(0xF00B0E14), Color(0x000B0E14)],
          const [0.0, 0.82, 1.0],
        ),
    );

    final dots = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Ocean: a sparse lattice so the disc reads as a body.
    final stepPx = math.max(10.0, r / 11);
    buckets.reset();
    for (var oy = cy - r; oy <= cy + r; oy += stepPx) {
      for (var ox = cx - r; ox <= cx + r; ox += stepPx) {
        final du = (ox - cx) / r;
        final dv = (oy - cy) / r;
        final dd = du * du + dv * dv;
        if (dd > 0.9) continue;
        final s = math.sqrt(1 - dd);
        buckets.add((s * 7).round().clamp(0, 7), ox, oy);
      }
    }
    for (var b = 0; b < _PointBuckets.count; b++) {
      if (buckets.lengthOf(b) == 0) continue;
      dots
        ..color = Colors.white
            .withValues(alpha: ((0.055 + 0.05 * (b / 7)) * breathe).clamp(0, 1))
        ..strokeWidth = 2;
      canvas.drawRawPoints(ui.PointMode.points, buckets.viewOf(b), dots);
    }

    // Land: brighter and larger towards the viewer, which is the terminator.
    final cosRot = math.cos(rot);
    final sinRot = math.sin(rot);
    buckets.reset();
    for (var p = 0; p < pts.count; p++) {
      final cl = pts.cosLat[p];
      final sinL = pts.sinLon[p] * cosRot + pts.cosLon[p] * sinRot;
      final cosL = pts.cosLon[p] * cosRot - pts.sinLon[p] * sinRot;
      final z3 = cl * cosL;
      if (z3 <= 0.05) continue;
      buckets.add(
        (z3 * 7).round().clamp(0, 7),
        cx + cl * sinL * r * 0.97,
        cy - pts.sinLat[p] * r * 0.97,
      );
    }
    for (var b = 0; b < _PointBuckets.count; b++) {
      if (buckets.lengthOf(b) == 0) continue;
      final z = b / 7;
      dots
        ..color = Colors.white
            .withValues(alpha: ((0.15 + 0.4 * z) * breathe).clamp(0, 1))
        ..strokeWidth = 2 * (0.55 + 0.95 * z);
      canvas.drawRawPoints(ui.PointMode.points, buckets.viewOf(b), dots);
    }

    // Rim: a dotted blue edge drawn over the horizon.
    final rim = (r * 0.85).round();
    buckets.reset();
    for (var a = 0; a < rim; a++) {
      final th = a / rim * 2 * math.pi;
      final s = math.sin(th);
      buckets.add(
        (((s + 1) / 2) * 7).round().clamp(0, 7),
        cx + math.cos(th) * r * 1.05,
        cy + s * r * 1.05,
      );
    }
    for (var b = 0; b < _PointBuckets.count; b++) {
      if (buckets.lengthOf(b) == 0) continue;
      dots
        ..color = Brand.hsl(214 + 10 * ((b / 7) * 2 - 1), 95, 63,
            (0.4 * breathe).clamp(0, 1))
        ..strokeWidth = 2.5;
      canvas.drawRawPoints(ui.PointMode.points, buckets.viewOf(b), dots);
    }

    _paintRoutes(canvas, pts, cx, cy, r, rot, gA, t);
  }

  /// Three lanes of great-circle hops on an offset beat: each lights up,
  /// holds, then fades.
  void _paintRoutes(Canvas canvas, _LandPoints pts, double cx, double cy,
      double r, double rot, double gA, double t) {
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final mid = <double>[];
    final ends = <double>[];
    for (var lane = 0; lane < 3; lane++) {
      final period = 6400 + lane * 1100;
      final tt = t + lane * 2700;
      final rk = (tt / period).floor();
      final rlocal = tt - rk * period;
      double alpha;
      if (rlocal < 2100) {
        alpha = 1;
      } else if (rlocal < 2900) {
        alpha = 1 - (rlocal - 2100) / 800;
      } else {
        continue;
      }
      alpha *= gA * (lane == 0 ? 1 : 0.75);
      final rng = mulberry32(u32(kOb3Seed ^ hash2(rk, 7 + lane * 13, 0x1F)));
      final ai = (rng() * pts.count).floor();
      final aLat = pts.lat[ai];
      final aLon = pts.lon[ai];
      var bi = -1;
      for (var tries = 0; tries < 12; tries++) {
        final ci = (rng() * pts.count).floor();
        final dot = math.sin(aLat) * math.sin(pts.lat[ci]) +
            math.cos(aLat) * math.cos(pts.lat[ci]) * math.cos(aLon - pts.lon[ci]);
        if (dot < 0.5) {
          bi = ci;
          break;
        }
      }
      if (bi < 0) continue;
      final bLat = pts.lat[bi];
      final bLon = pts.lon[bi];
      final prog = rlocal / 1200 < 1 ? rlocal / 1200 : 1.0;
      const ns = 30;
      final avx = math.cos(aLat) * math.cos(aLon);
      final avy = math.sin(aLat);
      final avz = math.cos(aLat) * math.sin(aLon);
      final bvx = math.cos(bLat) * math.cos(bLon);
      final bvy = math.sin(bLat);
      final bvz = math.cos(bLat) * math.sin(bLon);
      final ang = math.acos(
          (avx * bvx + avy * bvy + avz * bvz).clamp(-1.0, 1.0));
      final sinAng = math.sin(ang);
      if (sinAng < 1e-4) continue;
      final last = (ns * prog).floor();
      mid.clear();
      ends.clear();
      for (var s = 0; s <= last; s++) {
        final f = s / ns;
        final w1 = math.sin((1 - f) * ang) / sinAng;
        final w2 = math.sin(f * ang) / sinAng;
        final vx = avx * w1 + bvx * w2;
        final vy = avy * w1 + bvy * w2;
        final vz = avz * w1 + bvz * w2;
        final lonP = math.atan2(vz, vx) + rot;
        final latP = math.asin(vy.clamp(-1.0, 1.0));
        final rz3 = math.cos(latP) * math.cos(lonP);
        if (rz3 <= 0.05) continue;
        final px = cx + math.cos(latP) * math.sin(lonP) * r * 0.97;
        final py = cy - math.sin(latP) * r * 0.97;
        if (s == 0 || s == last) {
          ends..add(px)..add(py);
        } else {
          mid..add(px)..add(py);
        }
      }
      if (mid.isNotEmpty) {
        line
          ..color = Brand.hsl(216, 95, 64, (0.5 * alpha).clamp(0, 1))
          ..strokeWidth = 2.8;
        canvas.drawRawPoints(
            ui.PointMode.points, Float32List.fromList(mid), line);
      }
      if (ends.isNotEmpty) {
        line
          ..color = Brand.hsl(216, 95, 64, (0.8 * alpha).clamp(0, 1))
          ..strokeWidth = 5.2;
        canvas.drawRawPoints(
            ui.PointMode.points, Float32List.fromList(ends), line);
      }
      // A pulse on the destination once the route closes.
      if (rlocal > 1200 && rlocal < 2300) {
        final lonB = bLon + rot;
        final bz = math.cos(bLat) * math.cos(lonB);
        if (bz > 0.05) {
          final pp = (rlocal - 1200) / 1100;
          line
            ..color =
                Brand.hsl(216, 95, 64, (0.5 * (1 - pp) * alpha).clamp(0, 1))
            ..strokeWidth = 1
            ..strokeCap = StrokeCap.butt;
          canvas.drawCircle(
            Offset(cx + math.cos(bLat) * math.sin(lonB) * r * 0.97,
                cy - math.sin(bLat) * r * 0.97),
            3 + pp * 9,
            line,
          );
          line.strokeCap = StrokeCap.round;
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _Ob3Painter old) =>
      old.field != field || old.data != data;
}
