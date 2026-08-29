import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

import '../ui/strings.dart';

/// What the system says about notifications for this app.
///
/// Three answers, not two. Both platforms report "not determined yet" and
/// "the user said no" the same way through the permission API, and the UI has
/// to tell them apart: the first gets a pre-prompt that explains why, the
/// second gets a calm line and a link into system settings. The difference is
/// carried by [UiPrefs.notifAsked], which this app writes the first time it
/// puts the system dialog up.
enum NotifPerm {
  /// Never asked. The pre-prompt goes here, and only here.
  ask,

  /// Allowed.
  granted,

  /// Asked and refused, or switched off in system settings later.
  denied,
}

/// The two things this app may ever notify about, and nothing else.
///
/// Android splits them into two channels so the user can silence one and keep
/// the other, which is the whole point of channels. The tunnel's own
/// foreground notification is a third, separate thing: it lives in the native
/// service on channel `hideip_vpn`, it is mandatory while a VPN runs, and it
/// is not managed from here.
class Notifications {
  Notifications._();

  /// Drop alerts: the tunnel went down without the user asking it to.
  static const String connectionChannelId = 'hideip_connection_alerts';

  /// Voting: a location the user voted for went live.
  static const String votingChannelId = 'hideip_voting_updates';

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  /// Test hook: pretend the platform answered [status] without touching a
  /// plugin. Null restores the real lookup.
  @visibleForTesting
  static PermissionStatus? statusOverride;

  /// Creates both channels and wires the plugin. Idempotent, cheap, and
  /// silent on a platform that has no notification side at all.
  ///
  /// It does not ask for permission: creating a channel is not a prompt, and
  /// the prompt only ever follows a pre-prompt the user agreed to.
  static Future<void> init() async {
    if (_ready) return;
    _ready = true;
    try {
      await _plugin.initialize(const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          // The prompt is ours to time, not the plugin's.
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ));
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android == null) return;
      await android.createNotificationChannel(const AndroidNotificationChannel(
        connectionChannelId,
        S.notifConnTitle,
        description: S.notifConnBody,
        importance: Importance.defaultImportance,
      ));
      await android.createNotificationChannel(const AndroidNotificationChannel(
        votingChannelId,
        S.notifVoteTitle,
        description: S.notifVoteBody,
        importance: Importance.defaultImportance,
      ));
    } on MissingPluginException {
      // No platform side (unit tests, an unsupported target): nothing to do.
    } catch (_) {
      // A channel that could not be created is not worth failing a launch for.
    }
  }

  /// The current permission, given whether this install has ever put the
  /// system dialog up ([asked], persisted in [UiPrefs.notifAsked]).
  static Future<NotifPerm> permission({required bool asked}) async {
    final status = await _status();
    if (status == null) return asked ? NotifPerm.denied : NotifPerm.ask;
    if (status.isGranted || status.isProvisional) return NotifPerm.granted;
    // Before the first prompt both platforms report "denied"; only our own
    // record can say whether anyone was ever actually asked.
    return asked ? NotifPerm.denied : NotifPerm.ask;
  }

  /// Puts the system dialog up. The caller writes [UiPrefs.notifAsked] after
  /// this returns, whatever the answer was: the dialog is offered once.
  static Future<NotifPerm> request() async {
    try {
      final status = await Permission.notification.request();
      return status.isGranted || status.isProvisional
          ? NotifPerm.granted
          : NotifPerm.denied;
    } on MissingPluginException {
      return NotifPerm.denied;
    } catch (_) {
      return NotifPerm.denied;
    }
  }

  /// Opens the app's page in system settings, for the denied state.
  static Future<void> openSettings() async {
    try {
      await openAppSettings();
    } on MissingPluginException {
      // ignore
    } catch (_) {
      // ignore
    }
  }

  static Future<PermissionStatus?> _status() async {
    final override = statusOverride;
    if (override != null) return override;
    try {
      return await Permission.notification.status;
    } on MissingPluginException {
      return null;
    } catch (_) {
      return null;
    }
  }
}
