import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../state/app_state.dart';
import 'brand.dart';

/// The animated connection mark on the home screen.
///
/// Drawn natively (CustomPaint) so the brand pill mark — the three squares that
/// stand for hidden IP octets — stays readable in every state. The earlier
/// Lottie export filled the whole disc with a solid green blob that swallowed
/// the squares; this keeps them as the hero element.
///
///   disconnected -> grey outlined squares, slow breathing
///   connecting   -> squares fill blue left to right, a sweeping arc
///   connected    -> blue squares, soft pulsing halo + expanding ripple
///   error        -> treated like disconnected
class ConnectionMark extends StatefulWidget {
  final ConnState state;
  final double size;
  const ConnectionMark({super.key, required this.state, this.size = 160});

  @override
  State<ConnectionMark> createState() => _ConnectionMarkState();
}

class _ConnectionMarkState extends State<ConnectionMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.brand;
    final connected = widget.state == ConnState.connected;
    final connecting = widget.state == ConnState.connecting;
    final accent = connected || connecting ? t.primary : t.mutedForeground;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          painter: _MarkPainter(
            t: _c.value,
            accent: accent,
            connected: connected,
            connecting: connecting,
            squareFill: t.background,
          ),
        ),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  final double t; // 0..1 loop phase
  final Color accent;
  final bool connected;
  final bool connecting;
  final Color squareFill;

  _MarkPainter({
    required this.t,
    required this.accent,
    required this.connected,
    required this.connecting,
    required this.squareFill,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;

    // Gentle breathing scale (subtle, never overwhelming).
    final breathe = 1 + 0.02 * math.sin(t * 2 * math.pi);

    // Connected: an expanding ripple ring + a soft halo.
    if (connected) {
      final ripple = t; // 0..1
      final rippleR = r * (0.55 + ripple * 0.5);
      final rippleOpacity = (1 - ripple) * 0.5;
      canvas.drawCircle(
        c,
        rippleR,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = accent.withValues(alpha: rippleOpacity),
      );
      // Soft halo behind the squares.
      canvas.drawCircle(
        c,
        r * 0.62,
        Paint()
          ..color = accent.withValues(alpha: 0.10 + 0.04 * math.sin(t * 2 * math.pi)),
      );
    }

    // Connecting: a sweeping arc around the squares.
    if (connecting) {
      final sweep = math.pi * 1.4;
      final start = t * 2 * math.pi;
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r * 0.74),
        start,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = accent.withValues(alpha: 0.8),
      );
    }

    // The pill mark: three rounded squares in a row (hidden octets).
    final sq = r * 0.30 * (connected ? breathe : 1);
    final gap = sq * 0.42;
    final totalW = sq * 3 + gap * 2;
    final startX = c.dx - totalW / 2;
    final y = c.dy - sq / 2;

    final radius = Radius.circular(sq * 0.26);
    for (var i = 0; i < 3; i++) {
      final rect = Rect.fromLTWH(startX + i * (sq + gap), y, sq, sq);
      final rrect = RRect.fromRectAndRadius(rect, radius);

      if (connected) {
        // Filled accent squares (the connected, "on" look).
        canvas.drawRRect(rrect, Paint()..color = accent);
      } else if (connecting) {
        // Fill in left to right as the connection establishes.
        final fillProgress = ((t * 3) - i).clamp(0.0, 1.0);
        canvas.drawRRect(
          rrect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..color = accent.withValues(alpha: 0.8),
        );
        if (fillProgress > 0) {
          canvas.drawRRect(
            rrect,
            Paint()..color = accent.withValues(alpha: fillProgress),
          );
        }
      } else {
        // Disconnected: grey outline, slow breathing opacity.
        final pulse = 0.55 + 0.25 * (0.5 + 0.5 * math.sin(t * 2 * math.pi));
        canvas.drawRRect(
          rrect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..color = accent.withValues(alpha: pulse),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.t != t ||
      old.accent != accent ||
      old.connected != connected ||
      old.connecting != connecting;
}
