import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';

import '../core/haptics.dart';
import 'brand.dart';

/// Full-screen QR scanner. Pops with the first decoded string (the raw share
/// link or subscription body), or null if the user backs out.
///
/// Backed by [flutter_zxing] (pure ZXing via FFI). Unlike ML Kit based
/// scanners it has no Google Play Services dependency, so it decodes on
/// GrapheneOS and other no-GMS devices exactly as on stock Android — which
/// matters for a privacy app whose users often run de-Googled ROMs.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  bool _handled = false;

  void _onScan(Code code) {
    if (_handled) return;
    final raw = code.text;
    if (!code.isValid || raw == null || raw.trim().isEmpty) return;
    _handled = true;
    Haptics.success();
    Navigator.of(context).pop(raw.trim());
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Scan QR code'),
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          ReaderWidget(
            codeFormat: Format.qrCode,
            onScan: _onScan,
            // Privacy: never reach into the photo library — links come from
            // the camera or paste, not the gallery.
            showGallery: false,
            showScannerOverlay: false,
            // Built-in torch + front/back toggle, tinted to the brand blue.
            showFlashlight: true,
            showToggleCamera: true,
            flashOnIcon: const Icon(Icons.flashlight_on_outlined,
                color: Colors.white),
            flashOffIcon: const Icon(Icons.flashlight_off_outlined,
                color: Colors.white),
            toggleCameraIcon:
                const Icon(Icons.cameraswitch_outlined, color: Colors.white),
            scanDelaySuccess: const Duration(milliseconds: 600),
            actionButtonsBackgroundColor: Colors.black.withValues(alpha: 0.35),
            loading: const DecoratedBox(
              decoration: BoxDecoration(color: Colors.black),
              child: Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
          ),
          // Brand reticle drawn on top of the live preview.
          IgnorePointer(
            child: CustomPaint(
              painter: _ReticlePainter(color: brand.primary),
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 48,
            child: Text(
              'Point the camera at a server QR code',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Draws a darkened frame with a transparent square reticle in the centre.
class _ReticlePainter extends CustomPainter {
  final Color color;
  _ReticlePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide * 0.66;
    final rect = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: side,
      height: side,
    );
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(20));

    // Dim everything except the reticle.
    final overlay = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(rrect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
        overlay, Paint()..color = Colors.black.withValues(alpha: 0.55));

    // Corner brackets in brand blue.
    final bracket = Paint()
      ..color = color
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const len = 28.0;
    void corner(Offset o, Offset hDir, Offset vDir) {
      canvas.drawLine(o, o + hDir * len, bracket);
      canvas.drawLine(o, o + vDir * len, bracket);
    }

    corner(rect.topLeft, const Offset(1, 0), const Offset(0, 1));
    corner(rect.topRight, const Offset(-1, 0), const Offset(0, 1));
    corner(rect.bottomLeft, const Offset(1, 0), const Offset(0, -1));
    corner(rect.bottomRight, const Offset(-1, 0), const Offset(0, -1));
  }

  @override
  bool shouldRepaint(covariant _ReticlePainter old) => old.color != color;
}
