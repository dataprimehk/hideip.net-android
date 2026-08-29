import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:permission_handler/permission_handler.dart';

/// What the system says about the camera for this app.
///
/// Three answers, not two, for the same reason notifications need three: the
/// QR popup shows its own pre-prompt only where nobody has been asked yet, and
/// a calm line with a way into system settings where the answer was no.
enum CamPerm {
  /// Never asked, or asked and dismissed without an answer. The pre-prompt
  /// goes here, and only here.
  ask,

  /// Allowed. The scanner may start.
  granted,

  /// Refused, or switched off in system settings later.
  denied,
}

/// The camera permission, kept to the three answers the QR popup can render.
class CameraPermission {
  CameraPermission._();

  /// Test hook: pretend the platform answered [statusOverride] without
  /// touching a plugin. Null restores the real lookup.
  @visibleForTesting
  static PermissionStatus? statusOverride;

  /// Reads the current state without prompting.
  ///
  /// Both platforms report "not asked yet" and "asked and refused once" as
  /// plain `denied`, so only a permanently denied or restricted answer is
  /// taken as a real no here. A refusal inside this session is remembered by
  /// the popup, which sees what [request] returned.
  static Future<CamPerm> status() async {
    final status = await _status();
    if (status == null) return CamPerm.ask;
    if (status.isGranted || status.isLimited) return CamPerm.granted;
    if (status.isPermanentlyDenied || status.isRestricted) {
      return CamPerm.denied;
    }
    return CamPerm.ask;
  }

  /// Puts the system dialog up. Only ever called from the pre-prompt, so the
  /// person has already read why the camera is wanted.
  static Future<CamPerm> request() async {
    try {
      final status = await Permission.camera.request();
      return status.isGranted || status.isLimited
          ? CamPerm.granted
          : CamPerm.denied;
    } on MissingPluginException {
      return CamPerm.denied;
    } catch (_) {
      return CamPerm.denied;
    }
  }

  /// Opens the app's page in system settings, for the denied state.
  static Future<void> openSettings() async {
    try {
      await openAppSettings();
    } on MissingPluginException {
      // No platform side: nothing to open.
    } catch (_) {
      // A settings page that will not open is not worth an error dialog.
    }
  }

  static Future<PermissionStatus?> _status() async {
    final override = statusOverride;
    if (override != null) return override;
    try {
      return await Permission.camera.status;
    } on MissingPluginException {
      return null;
    } catch (_) {
      return null;
    }
  }
}
