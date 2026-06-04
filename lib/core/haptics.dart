import 'package:flutter/services.dart';

/// Thin wrapper over [HapticFeedback] so the rest of the app expresses intent
/// ("a server was selected", "we connected") rather than raw vibration calls.
/// Each method is best-effort: on devices/platforms without a vibrator the
/// platform call is a no-op, so callers never need to guard.
class Haptics {
  /// Light tick for routine selections (pick a server, toggle a control).
  static void selection() => HapticFeedback.selectionClick();

  /// Confirming press for a primary action (tap Connect / Disconnect / Import).
  static void tap() => HapticFeedback.lightImpact();

  /// Success landing — the tunnel came up.
  static void success() => HapticFeedback.mediumImpact();

  /// Something failed (connect error, parse error).
  static void error() => HapticFeedback.heavyImpact();
}
