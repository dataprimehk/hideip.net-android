import 'package:flutter/services.dart';

/// Thin Dart wrapper over the native VPN MethodChannel.
class VpnController {
  static const _channel = MethodChannel('net.hideip.vpn/control');

  /// Requests VPN consent from the OS if needed. Returns true when allowed.
  static Future<bool> prepare() async {
    final ok = await _channel.invokeMethod<bool>('prepare');
    return ok ?? false;
  }

  /// Whether the OS already holds a VPN configuration for this app, i.e.
  /// whether [prepare] would return immediately instead of putting the system
  /// consent dialog up.
  ///
  /// This is what lets the app tell "never asked" apart from "asked and
  /// refused", which is the difference between showing a one-off explanation
  /// and showing a declined state. It asks and never grants: on Android it is
  /// `VpnService.prepare(context) == null`, which reads the existing consent
  /// without raising anything.
  ///
  /// False is the safe answer everywhere it cannot be determined (an iOS build
  /// before the PacketTunnel port, a platform with no native side): the
  /// explanation is then shown once, and the persisted record stops it from
  /// ever appearing again.
  static Future<bool> isPrepared() async {
    try {
      return await _channel.invokeMethod<bool>('isPrepared') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Starts the sing-box tunnel with the given config JSON. [label] is shown in
  /// the foreground notification (the server name).
  static Future<bool> start(String configJson, {String? label}) async {
    final ok = await _channel.invokeMethod<bool>(
        'start', {'config': configJson, 'label': label});
    return ok ?? false;
  }

  /// Stops the tunnel.
  static Future<void> stop() async {
    await _channel.invokeMethod('stop');
  }

  /// Polls native status: {running: bool, error: String?}.
  /// Platforms without a native side (iOS until the PacketTunnel port lands)
  /// report a plain "not running" instead of throwing, so the status poll and
  /// the cold-start reconcile stay quiet there.
  static Future<VpnStatus> status() async {
    final Map<String, dynamic>? res;
    try {
      res = await _channel.invokeMapMethod<String, dynamic>('status');
    } on MissingPluginException {
      return const VpnStatus(running: false);
    }
    return VpnStatus(
      running: res?['running'] as bool? ?? false,
      error: res?['error'] as String?,
      alwaysOn: res?['alwaysOn'] as bool? ?? false,
      lockdown: res?['lockdown'] as bool? ?? false,
    );
  }

  /// Records the user's in-app choice for Always-on support. When enabled, the
  /// native service reconnects the last used server if Android's Always-on VPN
  /// starts it; when disabled it refuses system-initiated starts. Android only;
  /// a no-op elsewhere.
  static Future<void> setAlwaysOn(bool enabled) async {
    try {
      await _channel.invokeMethod('setAlwaysOn', {'enabled': enabled});
    } on MissingPluginException {
      // No native side (or not Android): nothing to record.
    } on PlatformException {
      // iOS side has no such method; ignore.
    }
  }

  /// Records the user's kill switch choice natively. Android: the service
  /// reads it when the core dies unexpectedly and reconnects instead of
  /// tearing the TUN down. iOS: arms/disarms on-demand rules on the profile
  /// (the system redials whenever a network is available).
  static Future<void> setKillSwitch(bool enabled) async {
    try {
      await _channel.invokeMethod('setKillSwitch', {'enabled': enabled});
    } on MissingPluginException {
      // No native side: nothing to record.
    } on PlatformException {
      // ignore
    }
  }

  /// Opens the system VPN settings screen (where Android's Always-on VPN
  /// toggle lives). Android only; a no-op elsewhere.
  static Future<void> openVpnSettings() async {
    try {
      await _channel.invokeMethod('openVpnSettings');
    } on MissingPluginException {
      // ignore
    } on PlatformException {
      // ignore
    }
  }

  /// Polls live traffic counters. Rates are bytes/second, totals cumulative
  /// bytes for the session. All zero when disconnected.
  static Future<VpnStats> stats() async {
    final Map<String, dynamic>? res;
    try {
      res = await _channel.invokeMapMethod<String, dynamic>('stats');
    } on MissingPluginException {
      return VpnStats.zero;
    }
    int v(String k) => (res?[k] as num?)?.toInt() ?? 0;
    return VpnStats(
      uplink: v('uplink'),
      downlink: v('downlink'),
      uplinkTotal: v('uplinkTotal'),
      downlinkTotal: v('downlinkTotal'),
    );
  }
}

class VpnStatus {
  final bool running;
  final String? error;

  /// Whether Android's system Always-on VPN is enabled for this app (read
  /// live from system settings). Always false on other platforms.
  final bool alwaysOn;

  /// Whether "Block connections without VPN" (lockdown) accompanies it.
  final bool lockdown;
  const VpnStatus(
      {required this.running,
      this.error,
      this.alwaysOn = false,
      this.lockdown = false});
}

class VpnStats {
  final int uplink; // bytes/sec
  final int downlink; // bytes/sec
  final int uplinkTotal; // bytes
  final int downlinkTotal; // bytes
  const VpnStats({
    required this.uplink,
    required this.downlink,
    required this.uplinkTotal,
    required this.downlinkTotal,
  });

  static const zero = VpnStats(
      uplink: 0, downlink: 0, uplinkTotal: 0, downlinkTotal: 0);
}
