import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hideip_vpn/state/app_state.dart';
import 'package:hideip_vpn/vpn_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In flutter_test no platform channels are registered, so every
/// VpnController call hits MissingPluginException, exactly like a platform
/// whose native VPN side does not exist yet (iOS before the PacketTunnel
/// port). These tests pin the graceful-degradation contract.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // Haptics go through SystemChannels.platform; give it a no-op handler so
    // unawaited feedback calls don't surface as unhandled test errors.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
  });

  test('status reports not-running instead of throwing', () async {
    final s = await VpnController.status();
    expect(s.running, isFalse);
    expect(s.error, isNull);
  });

  test('stats report zero instead of throwing', () async {
    final s = await VpnController.stats();
    expect(s.uplink, 0);
    expect(s.downlink, 0);
    expect(s.uplinkTotal, 0);
    expect(s.downlinkTotal, 0);
  });

  test('connect surfaces a clear unsupported-platform error', () async {
    final state = AppState();
    await state.addLink('trojan://pw@203.0.113.1:443#Test');
    await state.connect();
    expect(state.conn, ConnState.error);
    expect(state.error, 'VPN is not yet supported on this platform.');
  });
}
