import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hideip_vpn/core/ui_prefs.dart';
import 'package:hideip_vpn/state/app_state.dart';

const _uuid = '11111111-1111-1111-1111-111111111111';

String _link(String host, String name) =>
    'vless://$_uuid@$host:443?security=none#$name';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the recents list', () {
    test('the same location twice is one entry, and it leads', () {
      var recents = UiPrefs.pushRecent(const [], 'a:443');
      recents = UiPrefs.pushRecent(recents, 'b:443');
      recents = UiPrefs.pushRecent(recents, 'a:443');
      expect(recents, ['a:443', 'b:443']);
    });

    test('it stops at eight, dropping the oldest', () {
      var recents = <String>[];
      for (var i = 0; i < 12; i++) {
        recents = UiPrefs.pushRecent(recents, 'h$i:443');
      }
      expect(recents.length, UiPrefs.maxRecents);
      expect(recents.first, 'h11:443');
      expect(recents.last, 'h4:443');
      expect(recents, isNot(contains('h3:443')));
    });

    test('picking a server remembers it, and picking it again does not '
        'stack a second copy', () async {
      final state = AppState();
      await state.addLink(_link('1.0.0.1', 'de-fra-01'));
      await state.addLink(_link('1.0.0.2', 'ch-zur-reality-03'));

      final locations = state.locations;
      await state.selectLocation(locations[0]);
      await state.selectLocation(locations[1]);
      await state.selectLocation(locations[0]);

      expect(state.prefs.recents, ['1.0.0.1:443', '1.0.0.2:443']);
    });

    test('Auto is not a pick and remembers nothing', () async {
      final state = AppState();
      await state.addLink(_link('1.0.0.1', 'de-fra-01'));
      await state.selectLocation(null);
      expect(state.prefs.recents, isEmpty);
    });
  });
}
