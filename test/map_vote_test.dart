import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hideip_vpn/core/location.dart';
import 'package:hideip_vpn/core/notifications.dart';
import 'package:hideip_vpn/core/proxy_profile.dart';
import 'package:hideip_vpn/core/votes.dart';
import 'package:hideip_vpn/ui/redesign/worldmap.dart';
import 'package:hideip_vpn/ui/strings.dart';

Location _loc(String name, {bool premium = false}) => Location.derive(
      ProxyProfile(
        name: name,
        protocol: 'vless',
        server: '198.51.100.24',
        port: 443,
        outbound: const {'type': 'vless'},
        premium: premium,
      ),
      0,
    );

/// A backend that states a cycle and accepts every vote.
http.Client _server({required int max, required String resets}) =>
    MockClient((req) async {
      if (req.method == 'GET') {
        return http.Response(
          json.encode({'votes': const {}, 'max': max, 'resets': resets}),
          200,
        );
      }
      final body = json.decode(req.body) as Map<String, dynamic>;
      return http.Response(
        json.encode({'country': body['country'], 'votes': 1}),
        200,
      );
    });

Widget _panel({
  String country = 'France',
  int? count,
  bool voted = false,
  int? votesLeft = 2,
  int? votesMax = 3,
  String? resetDate = 'September 1',
  NotifPerm? notifPerm,
  VoidCallback? onVote,
  VoidCallback? onUnvote,
}) =>
    MaterialApp(
      home: Scaffold(
        body: VotePanel(
          countryName: country,
          count: count,
          voted: voted,
          votesLeft: votesLeft,
          votesMax: votesMax,
          resetDate: resetDate,
          notifPerm: notifPerm,
          onVote: onVote ?? () {},
          onUnvote: onUnvote ?? () {},
          onClose: () {},
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    VoteService.instance.resetForTesting();
    votePrimer.resetForTesting();
  });

  group('what blocks a vote', () {
    test('a server the user imported never speaks for its country', () {
      expect(managedCountryIds([_loc('par-home-relay')]), isEmpty);
    });

    test('a hideip.net location in the country does block it', () {
      expect(
        managedCountryIds([_loc('fr-par-reality-01', premium: true)]),
        contains('250'), // ISO 3166 numeric for France
      );
    });

    test('one managed country does not silence the others', () {
      final ids = managedCountryIds([
        _loc('de-fra-reality-01', premium: true),
        _loc('par-home-relay'),
        _loc('zur-vps'),
      ]);
      expect(ids, {'276'});
    });
  });

  group('vote panel', () {
    testWidgets('the allowance is on screen and Vote works', (tester) async {
      var votes = 0;
      await tester.pumpWidget(_panel(count: 41, onVote: () => votes++));
      await tester.pumpAndSettle();

      expect(find.text(S.c2LeftThisRound(2, 3)), findsOneWidget);
      expect(find.text(S.c2Count(41), findRichText: true), findsOneWidget);
      expect(find.text(S.c3Remove), findsNothing);

      await tester.tap(find.text(S.c2Vote));
      expect(votes, 1);
    });

    testWidgets('a spent allowance says so and refuses the tap',
        (tester) async {
      var votes = 0;
      await tester.pumpWidget(_panel(votesLeft: 0, onVote: () => votes++));
      await tester.pumpAndSettle();

      expect(find.text(S.c2NoVotes), findsOneWidget);
      expect(find.text(S.c2Vote), findsNothing);
      expect(
          find.text(S.c2Resets('September 1'), findRichText: true), findsOneWidget);

      await tester.tap(find.text(S.c2NoVotes));
      expect(votes, 0);
    });

    testWidgets('a voted country offers a separate Remove vote',
        (tester) async {
      var removed = 0;
      var votes = 0;
      await tester.pumpWidget(_panel(
        voted: true,
        votesLeft: 1,
        onVote: () => votes++,
        onUnvote: () => removed++,
      ));
      await tester.pumpAndSettle();

      expect(find.text(S.c3Voted), findsOneWidget);
      await tester.tap(find.text(S.c3Voted));
      expect(votes, 0, reason: 'the Voted button is a state, not an action');

      await tester.tap(find.text(S.c3Remove));
      expect(removed, 1);
    });

    testWidgets('the thanks line says only what the app can deliver',
        (tester) async {
      await tester
          .pumpWidget(_panel(voted: true, notifPerm: NotifPerm.granted));
      await tester.pumpAndSettle();
      expect(find.text(S.c3ThanksSoon('France')), findsOneWidget);

      await tester.pumpWidget(_panel(voted: true, notifPerm: NotifPerm.denied));
      await tester.pumpAndSettle();
      expect(find.text(S.c3ThanksOff), findsOneWidget);

      await tester.pumpWidget(_panel(voted: true, notifPerm: NotifPerm.ask));
      await tester.pumpAndSettle();
      expect(find.text(S.c3Thanks), findsOneWidget);
    });

    testWidgets('an unknown total is left out rather than invented',
        (tester) async {
      await tester.pumpWidget(_panel(count: null));
      await tester.pumpAndSettle();
      expect(find.text(S.c2Count(0), findRichText: true), findsNothing);
      expect(find.text(S.c2Anon), findsOneWidget);
    });
  });

  group('the map hint', () {
    testWidgets('invites first, then carries the allowance alone',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: VoteHint(invite: true, votesLeft: 3, votesMax: 3)),
      ));
      await tester.pumpAndSettle();
      expect(find.text(S.c1Hint), findsOneWidget);
      expect(find.text(S.c1HintLeft(3, 3)), findsOneWidget);

      await tester.pumpWidget(const MaterialApp(
        home:
            Scaffold(body: VoteHint(invite: false, votesLeft: 2, votesMax: 3)),
      ));
      await tester.pumpAndSettle();
      expect(find.text(S.c1Hint), findsNothing);
      expect(find.text(S.c1VotesLeft(2, 3)), findsOneWidget);
    });

    testWidgets('with no quota stated there is nothing to promise',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: VoteHint(invite: false)),
      ));
      await tester.pumpAndSettle();
      expect(find.text(S.c1Hint), findsNothing);
      expect(find.byIcon(Icons.public), findsNothing);
    });
  });

  group('the notification pre-prompt', () {
    test('never before a vote, once after the first one', () {
      final gate = VotePrimerGate();
      expect(
        gate.due(firstOfCycle: false, perm: NotifPerm.ask),
        isFalse,
        reason: 'a second vote is not the moment to ask',
      );
      expect(gate.due(firstOfCycle: true, perm: NotifPerm.ask), isTrue);
      expect(
        gate.due(firstOfCycle: true, perm: NotifPerm.ask),
        isFalse,
        reason: 'the explanation is offered once',
      );
    });

    test('an answered permission is not asked again', () {
      expect(
        VotePrimerGate().due(firstOfCycle: true, perm: NotifPerm.granted),
        isFalse,
      );
      expect(
        VotePrimerGate().due(firstOfCycle: true, perm: NotifPerm.denied),
        isFalse,
      );
    });
  });

  test('the quota the panel shows is the one the service enforces', () async {
    final svc = VoteService.instance;
    svc.clientOverride = _server(max: 2, resets: 'September 1');
    await svc.init();
    // init starts the first refresh without awaiting it.
    await pumpEventQueue();

    expect(svc.votesLeft, 2);
    await svc.toggle('250');
    await svc.toggle('276');
    expect(svc.votesLeft, 0);
    expect(svc.canVote, isFalse);

    // The panel would show "No votes left"; the service backs that up.
    await svc.toggle('784');
    expect(svc.hasVoted('784'), isFalse);

    await svc.unvote('250');
    expect(svc.votesLeft, 1);
    await pumpEventQueue();
  });
}
