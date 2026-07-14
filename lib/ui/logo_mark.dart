import 'package:flutter/material.dart';

import 'brand.dart';

/// hideip.net pill brand mark, ported from `brand-kit/LogoMark.tsx`.
///
/// Renders `102. ▪ ▪ ▪ .13.37`: the three blue squares stand in for the
/// hidden octets of an IP address. A bordered pill with mono octets around
/// three rounded accent squares. This is the brand's primary visual hook.
class LogoMark extends StatelessWidget {
  /// Pill height in logical pixels. Width follows the natural ratio.
  final double size;

  /// When true, shows the "hideip.net" wordmark to the right of the pill.
  final bool withWordmark;

  /// When true (and [withWordmark]), shows the "Browse Privately" tagline.
  final bool tagline;

  const LogoMark({
    super.key,
    this.size = 28,
    this.withWordmark = false,
    this.tagline = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.brand;
    final pill = CustomPaint(
      size: Size(_PillPainter.widthFor(size), size),
      painter: _PillPainter(
        foreground: t.foreground,
        accent: t.primary,
        card: t.card,
      ),
    );
    if (!withWordmark) return pill;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        pill,
        SizedBox(width: size * 0.32),
        Wordmark(size: size, tagline: tagline),
      ],
    );
  }
}

/// "hideip.net" with the .net in muted weight/color, plus optional tagline.
class Wordmark extends StatelessWidget {
  final double size;
  final bool tagline;
  const Wordmark({super.key, required this.size, this.tagline = false});

  @override
  Widget build(BuildContext context) {
    final t = context.brand;
    final wordPx = size * 0.98;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            style: TextStyle(
              fontFamily: Brand.displayFont,
              fontSize: wordPx,
              height: 1,
              letterSpacing: -wordPx * 0.035,
            ),
            children: [
              TextSpan(
                text: 'hideip',
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: t.foreground),
              ),
              TextSpan(
                text: '.net',
                style: TextStyle(
                    fontWeight: FontWeight.w500, color: t.mutedForeground),
              ),
            ],
          ),
        ),
        if (tagline) ...[
          SizedBox(height: size * 0.12),
          Text(
            'Browse Privately',
            style: TextStyle(
              fontFamily: Brand.displayFont,
              fontWeight: FontWeight.w500,
              fontSize: size * 0.4,
              color: t.primary,
            ),
          ),
        ],
      ],
    );
  }
}

class _PillPainter extends CustomPainter {
  final Color foreground;
  final Color accent;
  final Color card;

  // Octets framing the hidden squares. Matches the static LogoMark default.
  static const _left = '102.';
  static const _right = '.13.37';

  _PillPainter({
    required this.foreground,
    required this.accent,
    required this.card,
  });

  // --- Geometry, derived once from the pill height -------------------------
  // Keeping these in one place lets [widthFor] and [paint] agree exactly, so
  // the pill always wraps its measured content with no clipping.

  static double _dotSide(double h) => (h * 0.22).clamp(3.0, h);
  static double _dotGap(double h) => (h * 0.08).clamp(1.25, h);
  static double _textGap(double h) => (h * 0.12).clamp(2.0, h);
  static double _fontSize(double h) => (h * 0.56).clamp(7.0, h);
  static double _dotsTotalW(double h) => _dotSide(h) * 3 + _dotGap(h) * 2;

  /// Measures one octet at the pill's font size (mono, tabular figures).
  static double _measure(String text, double h) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: _textStyle(h, Colors.black)),
      textDirection: TextDirection.ltr,
    )..layout();
    return tp.width;
  }

  static TextStyle _textStyle(double h, Color color) => TextStyle(
        fontFamily: Brand.monoFont,
        fontWeight: FontWeight.w600,
        fontSize: _fontSize(h),
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// Exact pill width for a given height: side padding + left octet + gap +
  /// three squares + gap + right octet + side padding. No magic ratio.
  static double widthFor(double h) {
    final sidePad = h * 0.5; // half-height padding keeps the rounded caps clear
    return sidePad +
        _measure(_left, h) +
        _textGap(h) +
        _dotsTotalW(h) +
        _textGap(h) +
        _measure(_right, h) +
        sidePad;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final w = size.width;

    // Pill body
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(1, 1, w - 2, h - 2),
      Radius.circular((h - 2) / 2),
    );
    canvas.drawRRect(rrect, Paint()..color = card);
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = foreground.withValues(alpha: 0.78),
    );

    final dotSide = _dotSide(h);
    final dotRx = dotSide * 0.22;
    final dotGap = _dotGap(h);
    final textGap = _textGap(h);
    final dotsTotalW = _dotsTotalW(h);
    final centerY = h / 2;

    // Center the whole measured block horizontally inside the pill.
    final leftW = _measure(_left, h);
    final rightW = _measure(_right, h);
    final contentW = leftW + textGap + dotsTotalW + textGap + rightW;
    final blockStartX = (w - contentW) / 2;
    final dotsStartX = blockStartX + leftW + textGap;
    final dotY = centerY - dotSide / 2;

    // Three accent squares
    final dotPaint = Paint()..color = accent;
    for (var i = 0; i < 3; i++) {
      final x = dotsStartX + i * (dotSide + dotGap);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, dotY, dotSide, dotSide),
          Radius.circular(dotRx),
        ),
        dotPaint,
      );
    }

    // Left octet (right-aligned to the squares)
    _drawText(canvas, _left, h,
        anchorX: dotsStartX - textGap, centerY: centerY, alignEnd: true);
    // Right octet (left-aligned after the squares)
    _drawText(canvas, _right, h,
        anchorX: dotsStartX + dotsTotalW + textGap,
        centerY: centerY,
        alignEnd: false);
  }

  void _drawText(Canvas canvas, String text, double h,
      {required double anchorX,
      required double centerY,
      required bool alignEnd}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: _textStyle(h, foreground)),
      textDirection: TextDirection.ltr,
    )..layout();
    final x = alignEnd ? anchorX - tp.width : anchorX;
    tp.paint(canvas, Offset(x, centerY - tp.height / 2));
  }

  @override
  bool shouldRepaint(_PillPainter old) =>
      old.foreground != foreground || old.accent != accent || old.card != card;
}
