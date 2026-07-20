import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../brand.dart';

/// Connection states the mark can express (mirrors the `state` attribute of
/// the `<hideip-mark>` web component in the design).
enum MarkState { disconnected, connecting, connected, disconnecting }

/// The living four-octet brand mark.
///
/// The metaphor: squares OPEN with scrambling digits = your real IP is
/// exposed; squares REDACTED (solid) = you are hidden. Connecting redacts
/// them left-to-right behind a scan line; connected absorbs the 4th octet so
/// the three-square logo remains, breathing, with orbiting particles.
/// Disconnecting re-exposes right-to-left.
class HideipMark extends StatefulWidget {
  final MarkState state;

  /// Square size in logical pixels; every other dimension scales off this.
  final double unit;

  /// True when drawn on the dark hero/onboarding surface.
  final bool darkSurface;

  const HideipMark({
    super.key,
    required this.state,
    this.unit = 52,
    this.darkSurface = false,
  });

  @override
  State<HideipMark> createState() => _HideipMarkState();
}

class _HideipMarkState extends State<HideipMark>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _rng = math.Random();

  double _now = 0; // seconds since widget mount
  double _stateAt = 0; // _now when widget.state last changed
  late List<String> _octets;

  double _nextDigitTick = 0;

  @override
  void initState() {
    super.initState();
    _octets = List.generate(4, (_) => _rollOctet());
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didUpdateWidget(covariant HideipMark old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state) {
      _stateAt = _now;
      // A fresh scramble makes the transition read as "live".
      _octets = List.generate(4, (_) => _rollOctet());
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  String _rollOctet() => _rng.nextInt(256).toString().padLeft(3, '0');

  void _onTick(Duration elapsed) {
    _now = elapsed.inMicroseconds / 1e6;
    // Digit scramble cadence: calm single-octet ticks when exposed, frantic
    // full re-rolls while the scan line works, frozen when hidden.
    final s = widget.state;
    if (s != MarkState.connected && _now >= _nextDigitTick) {
      if (s == MarkState.disconnected) {
        _octets[_rng.nextInt(4)] = _rollOctet();
        _nextDigitTick = _now + .43;
      } else {
        for (var i = 0; i < 4; i++) {
          _octets[i] = _rollOctet();
        }
        _nextDigitTick = _now + .07;
      }
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.unit;
    return CustomPaint(
      size: Size(u * 4 + u * .2 * 3 + u * 2.2, u * 3.4),
      painter: _MarkPainter(
        state: widget.state,
        u: u,
        dark: widget.darkSurface,
        now: _now,
        sinceChange: _now - _stateAt,
        octets: _octets,
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  final MarkState state;
  final double u;
  final bool dark;
  final double now; // absolute clock, for endless loops
  final double sinceChange; // time in current state, for transitions
  final List<String> octets;

  _MarkPainter({
    required this.state,
    required this.u,
    required this.dark,
    required this.now,
    required this.sinceChange,
    required this.octets,
  });

  // Per-square delays lifted from mark.js keyframe delays.
  static const _lockDelays = [.24, .64, 1.05, 1.45];
  static const _exposeDelays = [.64, .46, .28, .10];

  double get gap => u * .2;
  double get rad => u * .22;

  Color get _accent {
    switch (state) {
      case MarkState.disconnected:
        return dark ? Brand.hsl(4, 78, 60) : Brand.hsl(4, 72, 52);
      case MarkState.connecting:
      case MarkState.disconnecting:
        return dark ? Brand.hsl(220, 95, 62) : Brand.hsl(220, 95, 55);
      case MarkState.connected:
        return dark ? Brand.hsl(152, 60, 48) : Brand.hsl(152, 60, 42);
    }
  }

  Color get _accentSoft {
    switch (state) {
      case MarkState.disconnected:
        return Brand.hsl(4, 72, 52, .14);
      case MarkState.connecting:
      case MarkState.disconnecting:
        return Brand.hsl(220, 95, 55, .26);
      case MarkState.connected:
        return Brand.hsl(152, 60, 42, .30);
    }
  }

  static double _clamp01(double v) => v.clamp(0.0, 1.0);

  /// 0→1→0 hump, for pop/pulse envelopes.
  static double _hump(double p) => math.sin(math.pi * _clamp01(p));

  /// Smooth 0..1..0 oscillation with [period] seconds and [phase] offset.
  double _breath(double period, [double phase = 0]) =>
      .5 - .5 * math.cos(2 * math.pi * ((now - phase) % period) / period);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final connected = state == MarkState.connected;

    // --- connected-layout progress (mark recenters, 4th octet absorbed) ----
    double absorbP = 0; // 0 = four squares, 1 = three-square logo
    if (connected) {
      absorbP = Curves.easeInOutCubic
          .transform(_clamp01((sinceChange - .55) / .6));
    } else if (state == MarkState.disconnecting) {
      // Leaving connected: the 4th square pops back instantly enough.
      absorbP = 1 - Curves.easeOutCubic.transform(_clamp01(sinceChange / .5));
    }

    final markShift = (u + gap) / 2 * absorbP;
    // Gentle bob while connected.
    final bob = connected ? -u * .03 * _breath(4.6) : 0.0;

    final w4 = u * 4 + gap * 3;
    final baseY = center.dy - u / 2 + bob;

    // --- aura ---------------------------------------------------------------
    double auraOpacity;
    double auraScale;
    switch (state) {
      case MarkState.disconnected:
        auraOpacity = .55;
        auraScale = .9 + .06 * _breath(3.2);
        break;
      case MarkState.connecting:
      case MarkState.disconnecting:
        auraOpacity = .9;
        auraScale = .95;
        break;
      case MarkState.connected:
        auraOpacity = .85 + .15 * _breath(4.6);
        auraScale = .96 + .12 * _breath(4.6);
        break;
    }
    final auraR = u * 1.7 * auraScale;
    final auraPaint = Paint()
      ..shader = RadialGradient(colors: [
        _accentSoft.withValues(alpha: _accentSoft.a * auraOpacity),
        _accentSoft.withValues(alpha: 0),
      ], stops: const [0, .68])
          .createShader(Rect.fromCircle(center: center, radius: auraR));
    canvas.drawCircle(center, auraR, auraPaint);

    // --- squares ------------------------------------------------------------
    final squareBg =
        dark ? Colors.white.withValues(alpha: .07) : Brand.hsl(220, 24, 93);
    final inkColor = dark ? Brand.hsl(0, 0, 96) : Brand.hsl(0, 0, 24);

    for (var i = 0; i < 4; i++) {
      var x = center.dx - w4 / 2 + i * (u + gap) + markShift;
      var y = baseY;
      var scale = 1.0;
      var squareOpacity = 1.0;

      if (i == 3) {
        // Signature moment: absorbed into the neighbouring square.
        x += -(u + gap) * absorbP;
        scale = 1 - (1 - .38) * absorbP;
        if (connected) {
          squareOpacity = 1 - _clamp01((sinceChange - .82) / .3);
        }
        if (squareOpacity <= 0) continue;
      }

      // Lock pop (connecting) / unlock dip (disconnecting).
      if (state == MarkState.connecting) {
        final p = _hump((sinceChange - _lockDelays[i]) / .34);
        y -= u * .06 * p;
        scale *= 1 + .07 * p;
      } else if (state == MarkState.disconnecting) {
        final p = _hump((sinceChange - _exposeDelays[i]) / .3);
        scale *= 1 - .045 * p;
      }
      // Gulp: the 3rd square swallows the 4th.
      if (connected && i == 2) {
        final p = _hump((sinceChange - .95) / .5);
        scale *= 1 + .12 * p;
      }

      final s = u * scale;
      final rect = Rect.fromCenter(
          center: Offset(x + u / 2, y + u / 2), width: s, height: s);
      final rrect = RRect.fromRectAndRadius(rect, Radius.circular(rad * scale));

      // Soft drop shadow (accent-tinted when connected).
      final shadowPaint = Paint()
        ..color = connected
            ? _accentSoft.withValues(alpha: _accentSoft.a * squareOpacity)
            : Brand.hsl(220, 60, 8, .28 * squareOpacity)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, u * .08);
      canvas.drawRRect(rrect.shift(Offset(0, u * .06)), shadowPaint);

      canvas.drawRRect(
          rrect,
          Paint()
            ..color =
                squareBg.withValues(alpha: squareBg.a * squareOpacity));

      // Digits (under the fill).
      final fillP = _fillProgress(i);
      if (fillP < 1) {
        _paintDigits(canvas, rect, octets[i], scale,
            inkColor.withValues(alpha: .92 * squareOpacity));
      }

      // Redaction fill.
      if (fillP > 0) {
        canvas.save();
        canvas.clipRRect(rrect);
        Rect fillRect;
        if (state == MarkState.disconnected && i == 3) {
          // Vertical tease: reveals downward, then slides out downward.
          final ph = (now % 5.2) / 5.2;
          if (ph < .54) {
            fillRect = Rect.fromLTWH(
                rect.left, rect.top, rect.width, rect.height * fillP);
          } else {
            fillRect = Rect.fromLTWH(rect.left, rect.top + rect.height * (1 - fillP),
                rect.width, rect.height * fillP);
          }
        } else {
          // Horizontal wipe anchored left (locks L→R, lifts R→L).
          fillRect = Rect.fromLTWH(
              rect.left, rect.top, rect.width * fillP, rect.height);
        }
        canvas.drawRect(
            fillRect,
            Paint()
              ..color =
                  _accent.withValues(alpha: squareOpacity));
        canvas.restore();
      }

      // Accent border; pulses as a warning while exposed, gone when hidden.
      double borderOpacity;
      if (connected) {
        borderOpacity = .62 * (1 - _clamp01(sinceChange / .4));
      } else if (state == MarkState.disconnected) {
        borderOpacity = .34 + .46 * _breath(3.2, .18 * i);
      } else {
        borderOpacity = .62;
      }
      if (borderOpacity > 0) {
        canvas.drawRRect(
            rrect.deflate(1),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = _accent.withValues(
                  alpha: borderOpacity * squareOpacity));
      }
    }

    // --- scan line ----------------------------------------------------------
    double? scanX;
    if (state == MarkState.connecting) {
      final p = _clamp01((sinceChange - .1) / 1.55);
      if (p > 0 && p < 1) scanX = center.dx - w4 / 2 + w4 * p + markShift;
    } else if (state == MarkState.disconnecting) {
      final p = _clamp01((sinceChange - .05) / .7);
      if (p > 0 && p < 1) scanX = center.dx + w4 / 2 - w4 * p;
    }
    if (scanX != null) {
      final top = baseY - u * .28;
      final bottom = baseY + u * 1.28;
      final glow = Paint()
        ..color = _accent.withValues(alpha: .55)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, u * .14);
      canvas.drawLine(Offset(scanX, top), Offset(scanX, bottom), glow..strokeWidth = 4);
      final beam = Paint()
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _accent.withValues(alpha: 0),
            _accent,
            _accent,
            _accent.withValues(alpha: 0),
          ],
          stops: const [0, .22, .78, 1],
        ).createShader(Rect.fromLTRB(scanX - 2, top, scanX + 2, bottom));
      canvas.drawLine(Offset(scanX, top), Offset(scanX, bottom), beam);
    }

    // --- orbiting particles (connected) -------------------------------------
    if (connected) {
      final orbitOpacity = _clamp01(sinceChange / .5);
      final dotR = u * .12 / 2;
      final orbits = [
        (radius: u * 1.5, period: 9.0, reverse: false, start: -90.0, op: 1.0, sc: 1.0),
        (radius: u * 1.85, period: 13.0, reverse: true, start: -90.0, op: .7, sc: .8),
        (radius: u * 1.25, period: 7.0, reverse: false, start: 60.0, op: .55, sc: .7),
      ];
      for (final o in orbits) {
        var angle = 2 * math.pi * ((now % o.period) / o.period);
        if (o.reverse) angle = -angle;
        angle += o.start * math.pi / 180;
        final pos = center + Offset(math.cos(angle), math.sin(angle)) * o.radius;
        final alpha = o.op * orbitOpacity;
        canvas.drawCircle(
            pos,
            dotR * o.sc * 2.2,
            Paint()
              ..color = _accent.withValues(alpha: .35 * alpha)
              ..maskFilter = MaskFilter.blur(BlurStyle.normal, u * .09));
        canvas.drawCircle(pos, dotR * o.sc,
            Paint()..color = _accent.withValues(alpha: alpha));
      }
    }
  }

  /// How much of square [i] is redacted right now (0 open .. 1 solid).
  double _fillProgress(int i) {
    switch (state) {
      case MarkState.connecting:
        return _clamp01((sinceChange - _lockDelays[i]) / .3);
      case MarkState.connected:
        return 1;
      case MarkState.disconnecting:
        return 1 - _clamp01((sinceChange - _exposeDelays[i]) / .26);
      case MarkState.disconnected:
        if (i != 3) return 0;
        // Tease cycle: 0..46% hidden, 46..54% wipe in, 54..82% held,
        // 82..92% wipe out, rest hidden.
        final ph = (now % 5.2) / 5.2;
        if (ph < .46) return 0;
        if (ph < .54) return Curves.easeInOut.transform((ph - .46) / .08);
        if (ph < .82) return 1;
        if (ph < .92) return 1 - Curves.easeInOut.transform((ph - .82) / .10);
        return 0;
    }
  }

  void _paintDigits(
      Canvas canvas, Rect rect, String octet, double scale, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: octet,
        style: TextStyle(
          fontFamily: Brand.monoFont,
          fontVariations: const [FontVariation('wght', 700)],
          fontFeatures: const [FontFeature.tabularFigures()],
          fontSize: u * .34 * scale,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
        canvas,
        rect.center -
            Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _MarkPainter old) => true;
}
