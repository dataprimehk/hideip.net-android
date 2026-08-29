import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hideip_vpn/state/app_state.dart';
import 'package:hideip_vpn/ui/redesign/detail_screen.dart';

const _uuid = '11111111-1111-1111-1111-111111111111';

Future<AppState> _oneServer() async {
  final state = AppState();
  await state.addLink(
      'vless://$_uuid@1.0.0.2:443?security=none#ch-zur-reality-03');
  return state;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a server with no name of its own reads as the parsed one', () async {
    final state = await _oneServer();
    expect(serverLabel(state.locations.first), 'Zurich');
  });

  test('renaming wins over the parsed name and keeps the provider one',
      () async {
    final state = await _oneServer();
    await state.renameServer(0, '  Home  ');

    final loc = state.locations.first;
    expect(loc.profile.customName, 'Home', reason: 'the name is trimmed');
    expect(serverLabel(loc), 'Home');
    expect(loc.rawName, 'ch-zur-reality-03',
        reason: 'renaming must never lose where the server came from');
  });

  test('an empty name falls back to the parsed one', () async {
    final state = await _oneServer();
    await state.renameServer(0, 'Home');
    await state.renameServer(0, '   ');
    expect(state.locations.first.profile.customName, isNull);
    expect(serverLabel(state.locations.first), 'Zurich');
  });

  test('a position that is not there renames nothing', () async {
    final state = await _oneServer();
    await state.renameServer(7, 'Home');
    expect(state.locations.first.profile.customName, isNull);
  });
}
