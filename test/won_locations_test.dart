import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hideip_vpn/core/cc_iso.dart';
import 'package:hideip_vpn/core/votes.dart';
import 'package:hideip_vpn/state/app_state.dart';

const _uuid = '11111111-1111-1111-1111-111111111111';

String _link(String host, String name) =>
    'vless://$_uuid@$host:443?security=none#$name';

/// A backend that names the countries whose vote already won a round.
http.Client _server(List<String> won) => MockClient((req) async {
      if (req.method == 'GET') {
        return http.Response(
          json.encode({
            'votes': const <String, int>{},
            'max': 3,
            'resets': 'September 1',
            'won': won,
          }),
          200,
        );
      }
      return http.Response('{}', 200);
    });

Future<AppState> _stateWithWinners(List<String> won) async {
  VoteService.instance.resetForTesting();
  VoteService.instance.clientOverride = _server(won);
  await VoteService.instance.init();
  // init starts the first refresh without awaiting it.
  await pumpEventQueue();

  final state = AppState();
  await state.addLink(_link('1.0.0.1', 'de-fra-01'));
  await state.addLink(_link('1.0.0.2', 'ch-zur-reality-03'));
  return state;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    VoteService.instance.resetForTesting();
  });

  tearDown(() => VoteService.instance.resetForTesting());

  group('country codes', () {
    test('the numeric id is the one the geometry and the backend use', () {
      expect(ccNumeric('DE'), '276');
      expect(ccNumeric('de'), '276', reason: 'case must not decide a match');
      expect(ccNumeric('AE'), '784');
    });

    test('a country outside the table simply has no id', () {
      expect(ccNumeric('ZZ'), isNull);
      expect(ccNumeric('··'), isNull);
    });
  });

  group('winner locations', () {
    test('a location in a country whose vote won carries the trophy',
        () async {
      final state = await _stateWithWinners(['276']); // Germany

      final won = {
        for (final l in state.locations) l.id: l.won,
      };
      expect(won, {'1.0.0.1:443': true, '1.0.0.2:443': false});
    });

    test('nothing won means no trophy anywhere', () async {
      final state = await _stateWithWinners(const []);
      expect(state.locations.every((l) => !l.won), isTrue);
    });

    test('a claimed win is over: the trophy does not come back', () async {
      final state = await _stateWithWinners(['276']);
      expect(state.locations.first.won, isTrue);

      // Connecting there is what writes the id; the effect on the list is
      // the same either way.
      await state.updatePrefs(
        state.prefs.copyWith(wonClaimed: {'1.0.0.1:443'}),
      );

      expect(state.locations.every((l) => !l.won), isTrue);
    });
  });
}
