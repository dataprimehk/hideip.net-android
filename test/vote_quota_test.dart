import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hideip_vpn/core/votes.dart';

/// A backend that states a cycle and accepts every vote.
http.Client _server({
  required int max,
  required String resets,
  Map<String, int> votes = const {},
  List<String> won = const [],
}) =>
    MockClient((req) async {
      if (req.method == 'GET') {
        return http.Response(
          json.encode({
            'votes': votes,
            'max': max,
            'resets': resets,
            'won': won,
          }),
          200,
        );
      }
      final body = json.decode(req.body) as Map<String, dynamic>;
      return http.Response(
        json.encode({'country': body['country'], 'votes': 1}),
        200,
      );
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    VoteService.instance.resetForTesting();
  });

  test('the quota is the server figure and it is spent by voting', () async {
    final svc = VoteService.instance;
    svc.clientOverride = _server(max: 3, resets: 'September 1');
    await svc.init();
    // init starts the first refresh without awaiting it.
    await pumpEventQueue();

    expect(svc.votesMax, 3);
    expect(svc.votesReset, 'September 1');
    expect(svc.votesLeft, 3);

    await svc.toggle('688');
    expect(svc.votesLeft, 2);
    await svc.toggle('076');
    await svc.toggle('356');
    expect(svc.votesLeft, 0);
    expect(svc.canVote, isFalse);

    // Spent means spent: a fourth country is not recorded at all.
    await svc.toggle('784');
    expect(svc.hasVoted('784'), isFalse);
    expect(svc.votesLeft, 0);
    await pumpEventQueue();
  });

  test('retracting a vote gives the allowance back', () async {
    final svc = VoteService.instance;
    svc.clientOverride = _server(max: 3, resets: 'September 1');
    await svc.init();
    // init starts the first refresh without awaiting it.
    await pumpEventQueue();

    await svc.toggle('688');
    await svc.toggle('076');
    expect(svc.votesLeft, 1);

    await svc.unvote('076');
    expect(svc.hasVoted('076'), isFalse);
    expect(svc.votesLeft, 2);

    // Retracting something never voted for is a no-op, not a refund.
    await svc.unvote('999');
    expect(svc.votesLeft, 2);
    await pumpEventQueue();
  });

  test('a vote from a finished cycle shows but spends nothing', () async {
    final svc = VoteService.instance;
    svc.clientOverride = _server(max: 3, resets: 'September 1');
    await svc.init();
    // init starts the first refresh without awaiting it.
    await pumpEventQueue();
    await svc.toggle('688');
    await svc.toggle('076');
    expect(svc.votesLeft, 1);

    // The cycle rolls over: same device, new allowance, old votes intact.
    svc.clientOverride = _server(max: 3, resets: 'October 1');
    await svc.refresh();

    expect(svc.votesReset, 'October 1');
    expect(svc.votesLeft, 3);
    expect(svc.hasVoted('688'), isTrue);
    expect(svc.hasVoted('076'), isTrue);

    await svc.toggle('356');
    expect(svc.votesLeft, 2);
    await pumpEventQueue();
  });

  test('with no server answer there is no quota and no block', () async {
    final svc = VoteService.instance;
    svc.clientOverride = MockClient((req) async => http.Response('', 503));
    await svc.init();
    // init starts the first refresh without awaiting it.
    await pumpEventQueue();

    expect(svc.votesMax, isNull);
    expect(svc.votesLeft, isNull);
    expect(svc.votesReset, isNull);
    expect(svc.canVote, isTrue);

    // A limit nobody stated is not enforced against the user.
    await svc.toggle('688');
    await svc.toggle('076');
    await svc.toggle('356');
    await svc.toggle('784');
    expect(svc.hasVoted('784'), isTrue);
    await pumpEventQueue();
  });

  test('winners come from the server and are never guessed', () async {
    final svc = VoteService.instance;
    svc.clientOverride = MockClient((req) async => http.Response('', 503));
    await svc.init();
    // init starts the first refresh without awaiting it.
    await pumpEventQueue();
    expect(svc.won, isEmpty);

    svc.clientOverride =
        _server(max: 3, resets: 'September 1', won: const ['784']);
    await svc.refresh();
    expect(svc.won, contains('784'));
  });
}
