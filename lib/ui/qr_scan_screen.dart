import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';

import '../core/haptics.dart';
import 'brand.dart';
import 'strings.dart';

/// The live camera preview that decodes QR codes, with no chrome of its own
/// beyond the reader's torch and camera-flip buttons.
///
/// Backed by [flutter_zxing] (pure ZXing via FFI). Unlike ML Kit based
/// scanners it has no Google Play Services dependency, so it decodes on
/// GrapheneOS and other no-GMS devices exactly as on stock Android, which
/// matters for a privacy app whose users often run de-Googled ROMs.
///
/// It reports every decode it sees; whoever mounts it decides what a first
/// code means and when to stop listening.
class QrReader extends StatelessWidget {
  /// Called with the trimmed contents of each decoded code.
  final ValueChanged<String> onCode;

  /// Shows the reader's own torch and camera-flip buttons. They are the
  /// reader's because it owns the camera controller and knows whether the
  /// device has a torch at all.
  final bool showControls;

  final AlignmentGeometry controlsAlignment;
  final EdgeInsetsGeometry controlsPadding;

  const QrReader({
    super.key,
    required this.onCode,
    this.showControls = true,
    this.controlsAlignment = Alignment.bottomLeft,
    this.controlsPadding = const EdgeInsets.all(10),
  });

  void _onScan(Code code) {
    final raw = code.text;
    if (!code.isValid || raw == null || raw.trim().isEmpty) return;
    onCode(raw.trim());
  }

  @override
  Widget build(BuildContext context) {
    return ReaderWidget(
      codeFormat: Format.qrCode,
      onScan: _onScan,
      // Privacy: never reach into the photo library; links come from the
      // camera or paste, not the gallery.
      showGallery: false,
      showScannerOverlay: false,
      showFlashlight: showControls,
      showToggleCamera: showControls,
      actionButtonsAlignment: controlsAlignment,
      actionButtonsPadding: controlsPadding,
      flashOnIcon: const Icon(
        Icons.flashlight_on_outlined,
        color: Colors.white,
      ),
      flashOffIcon: const Icon(
        Icons.flashlight_off_outlined,
        color: Colors.white,
      ),
      toggleCameraIcon: const Icon(
        Icons.cameraswitch_outlined,
        color: Colors.white,
      ),
      scanDelaySuccess: const Duration(milliseconds: 600),
      actionButtonsBackgroundColor: Colors.black.withValues(alpha: 0.35),
      actionButtonsBackgroundBorderRadius: BorderRadius.circular(999),
      loading: const DecoratedBox(
        decoration: BoxDecoration(color: Colors.black),
        child: Center(child: CircularProgressIndicator(color: Colors.white)),
      ),
    );
  }
}

/// Full-screen QR scanner. Pops with the first decoded string, or null if the
/// user backs out.
///
/// The importer scans in an inline popup instead; this screen is what device
/// linking uses, where the scan is the whole task.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  bool _handled = false;

  void _onCode(String raw) {
    if (_handled) return;
    _handled = true;
    Haptics.success();
    Navigator.of(context).pop(raw);
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
        title: const Text(S.e7Title),
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          QrReader(onCode: _onCode),
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
              S.e9Hint,
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
