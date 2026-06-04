import 'package:flutter/services.dart';

/// Thin Dart wrapper over the native VPN MethodChannel.
class VpnController {
  static const _channel = MethodChannel('net.hideip.vpn/control');

  /// Requests VPN consent from the OS if needed. Returns true when allowed.
  static Future<bool> prepare() async {
    final ok = await _channel.invokeMethod<bool>('prepare');
    return ok ?? false;
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
  static Future<VpnStatus> status() async {
    final res = await _channel.invokeMapMethod<String, dynamic>('status');
    return VpnStatus(
      running: res?['running'] as bool? ?? false,
      error: res?['error'] as String?,
    );
  }

  /// Polls live traffic counters. Rates are bytes/second, totals cumulative
  /// bytes for the session. All zero when disconnected.
  static Future<VpnStats> stats() async {
    final res = await _channel.invokeMapMethod<String, dynamic>('stats');
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
  const VpnStatus({required this.running, this.error});
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
