import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../brand.dart';
import '../hip.dart';
import '../mark.dart' show MarkState;

/// The light under the hero: two soft ellipses that drift and take the colour
/// of the connection.
///
/// `.hero-glow` in `design/app-1_1_0/app.css`. It sits behind the status card
/// and above the ASCII field, and it is the one thing on Home that says what
/// the state is without words: red while the address is exposed, blue in
/// transit, green once the tunnel is up, neutral grey with no network.
///
/// The caller positions it. In the design it hangs a little outside the hero
/// on both sides and below it, and is 78 logical pixels tall.
class HeroGlow extends StatefulWidget {
  final MarkState state;

  /// No network: the glow goes neutral rather than alarming. Being offline is
  /// not the same as being exposed, and it should not look like it.
  final bool offline;

  const HeroGlow({super.key, required this.state, this.offline = false});

  @override
  State<HeroGlow> createState() => _HeroGlowState();
}

/// Roughly 20 fps. The drift takes seven and a half seconds to cross, so
/// nothing is lost by not painting two blurred ellipses sixty times a second.
const int _glowThrottleMs = 50;

/// The colour cross-fade when the state changes (`transition .7s ease`).
const Duration _tintMs = Duration(milliseconds: 700);

/// The one-shot swell on a change of state (`gmorph`), and where it peaks.
const double _pulseMs = 900;
const double _pulsePeak = 0.35;

class _HeroGlowState extends State<HeroGlow>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker;
  final _GlowPaintState _paint = _GlowPaintState();
  Duration _lastDraw = Duration.zero;

  @override
  void initState() {
    super.initState();
    _paint.setTint(_tintFor(widget.state, widget.offline), animate: false);
    _ticker = createTicker(_onTick);
    WidgetsBinding.instance.addObserver(this);
    if (!Hip.reducedMotion) _ticker.start();
  }

  @override
  void didUpdateWidget(HeroGlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    final tint = _tintFor(widget.state, widget.offline);
    if (tint == _paint.target) return;
    _paint.setTint(tint, animate: !Hip.reducedMotion);
    if (Hip.reducedMotion) _paint.ping();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (Hip.reducedMotion) return;
    if (state == AppLifecycleState.resumed) {
      if (!_ticker.isActive) _ticker.start();
    } else {
      _ticker.stop();
    }
  }

  void _onTick(Duration elapsed) {
    if ((elapsed - _lastDraw).inMilliseconds < _glowThrottleMs) return;
    _lastDraw = elapsed;
    _paint.ping();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _paint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = Hip.reducedMotion;
    if (reduced && _ticker.isActive) _ticker.stop();
    if (!reduced && !_ticker.isActive) _ticker.start();
    _paint.reducedMotion = reduced;
    return RepaintBoundary(
      child: CustomPaint(
        painter: _HeroGlowPainter(_paint),
        size: Size.infinite,
      ),
    );
  }
}

/// The four tints, straight out of `app.css`.
Color _tintFor(MarkState state, bool offline) {
  if (offline) return Brand.hsl(220, 8, 36);
  return switch (state) {
    MarkState.connecting || MarkState.disconnecting => Brand.hsl(220, 95, 58),
    MarkState.connected => Brand.hsl(152, 60, 46),
    MarkState.disconnected => Brand.hsl(4, 78, 56),
  };
}

/// Clock, tint cross-fade and pulse. Shared between the state and the painter
/// so a repaint costs no allocation.
class _GlowPaintState extends ChangeNotifier {
  final Stopwatch _clock = Stopwatch()..start();

  Color _from = const Color(0x00000000);
  Color target = const Color(0x00000000);
  double _tintStart = 0;
  double _pulseStart = -1;
  bool reducedMotion = false;

  double get timeMs => _clock.elapsedMicroseconds / 1000.0;

  void ping() => notifyListeners();

  void setTint(Color tint, {required bool animate}) {
    _from = animate ? color : tint;
    target = tint;
    _tintStart = timeMs;
    if (animate) _pulseStart = timeMs;
  }

  /// The tint mid-cross-fade.
  Color get color {
    final d = _tintMs.inMilliseconds.toDouble();
    final p = d <= 0 ? 1.0 : ((timeMs - _tintStart) / d).clamp(0.0, 1.0);
    if (p >= 1) return target;
    return Color.lerp(_from, target, Curves.ease.transform(p)) ?? target;
  }

  /// How far into the swell the glow is, 0 at rest and 1 at the peak.
  double get pulse {
    if (_pulseStart < 0 || reducedMotion) return 0;
    final p = (timeMs - _pulseStart) / _pulseMs;
    if (p < 0 || p >= 1) return 0;
    return p < _pulsePeak
        ? p / _pulsePeak
        : 1 - (p - _pulsePeak) / (1 - _pulsePeak);
  }

  @override
  void dispose() {
    _clock.stop();
    super.dispose();
  }
}

class _HeroGlowPainter extends CustomPainter {
  final _GlowPaintState state;

  _HeroGlowPainter(this.state) : super(repaint: state);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final w = size.width;
    final h = size.height;
    // Frozen on the resting frame when the user asked for less motion.
    final t = state.reducedMotion ? 0.0 : state.timeMs;
    final tint = state.color;
    final pulse = state.pulse;

    // `.hero-glow::before`: the wide one on the left.
    _blob(
      canvas: canvas,
      rect: Rect.fromLTWH(0.10 * w, h - 2 - 62, 0.52 * w, 62),
      tint: tint,
      opacity: 0.24,
      pulse: pulse,
      dx: 10 * math.sin(2 * math.pi * t / 7500),
      dy: 3.4 * math.sin(2 * math.pi * t / 7500),
      scale: 1 + 0.07 * math.sin(2 * math.pi * t / 7500),
    );
    // `.hero-glow::after`: the smaller one on the right, drifting the other
    // way on a longer period so the two never line up.
    _blob(
      canvas: canvas,
      rect: Rect.fromLTWH(w - 0.08 * w - 0.40 * w, h + 2 - 52, 0.40 * w, 52),
      tint: tint,
      opacity: 0.18,
      pulse: pulse,
      dx: -8 * math.sin(2 * math.pi * t / 9500),
      dy: -3.5 * math.sin(2 * math.pi * t / 9500),
      scale: 1 + 0.07 * math.sin(2 * math.pi * t / 9500),
    );
  }

  void _blob({
    required Canvas canvas,
    required Rect rect,
    required Color tint,
    required double opacity,
    required double pulse,
    required double dx,
    required double dy,
    required double scale,
  }) {
    final s = scale * (1 + 0.09 * pulse);
    final center = rect.center.translate(dx, dy);
    final oval = Rect.fromCenter(
      center: center,
      width: rect.width * s,
      height: rect.height * s,
    );
    final paint = Paint()
      // `filter: blur(26px)`: a Gaussian whose deviation is the CSS radius.
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 26)
      ..color = tint.withValues(
        alpha: (opacity * (1 + 0.75 * pulse)).clamp(0.0, 1.0),
      );
    canvas.drawOval(oval, paint);
  }

  @override
  bool shouldRepaint(_HeroGlowPainter oldDelegate) =>
      oldDelegate.state != state;
}
