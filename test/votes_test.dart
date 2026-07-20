import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hideip_vpn/core/votes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('vote is stored locally and queued when the backend is unreachable',
      () async {
    final svc = VoteService.instance;
    svc.clientOverride = MockClient((req) async => http.Response('', 503));
    await svc.init();

    expect(svc.hasVoted('688'), isFalse);
    await svc.toggle('688');
    expect(svc.hasVoted('688'), isTrue);
    // No server contact ever: no number to show, but the vote is not lost.
    expect(svc.displayCount('688'), isNull);
    // Same rule for the leaderboard; the local vote shows through `mine`.
    expect(svc.leaderboard(), isEmpty);
    expect(svc.mine, contains('688'));

    await svc.toggle('688');
    expect(svc.hasVoted('688'), isFalse);
  });

  test('counts come from the server and queued votes adjust them', () async {
    final svc = VoteService.instance;
    var posted = false;
    svc.clientOverride = MockClient((req) async {
      if (req.method == 'GET') {
        return http.Response(json.encode({'votes': {'076': 141}}), 200);
      }
      posted = true;
      final body = json.decode(req.body) as Map<String, dynamic>;
      expect(body['country'], '076');
      expect(body['vote'], true);
      return http.Response(json.encode({'country': '076', 'votes': 142}), 200);
    });
    await svc.init();
    // init kicks off its own refresh; let it settle before asserting.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await svc.refresh();
    expect(svc.displayCount('076'), 141);

    await svc.toggle('076');
    // Give the async sync a beat to run.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(posted, isTrue);
    expect(svc.displayCount('076'), 142);
    expect(svc.hasVoted('076'), isTrue);
  });

  test('leaderboard sorts by count with the country code as tie-break',
      () async {
    final svc = VoteService.instance;
    svc.clientOverride = MockClient((req) async => http.Response(
        json.encode({
          'votes': {'076': 10, '688': 25, '356': 25, '392': 3, '752': 0}
        }),
        200));
    await svc.refresh();

    expect(svc.leaderboard(3), [('356', 25), ('688', 25), ('076', 10)]);
    // Zero-count entries never make the board; the limit is respected.
    expect(svc.leaderboard(), [
      ('356', 25),
      ('688', 25),
      ('076', 10),
      ('392', 3),
    ]);
  });
}
