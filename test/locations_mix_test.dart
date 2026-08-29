import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hideip_vpn/core/location.dart';
import 'package:hideip_vpn/core/proxy_profile.dart';
import 'package:hideip_vpn/state/app_state.dart';
import 'package:hideip_vpn/ui/redesign/locations_screen.dart';
import 'package:hideip_vpn/ui/strings.dart';

ProxyProfile _profile(String name, String host, {bool premium = false}) =>
    ProxyProfile(
      name: name,
      protocol: 'vless',
      server: host,
      port: 443,
      outbound: const {'type': 'vless'},
      premium: premium,
    );

Location _loc(String name, String host,
        {bool premium = false,
        bool locked = false,
        bool won = false,
        int index = 0}) =>
    Location.derive(_profile(name, host, premium: premium), index)
        .copyWith(locked: locked, won: won);

/// The list as the given mix renders it. Everything the three mixes disagree
/// about is a parameter, so one call per mix is a full comparison.
Widget _list({
  required Mix mix,
  required ManagedGroup group,
  List<Location> managed = const [],
  List<Location> locked = const [],
  List<Location> user = const [],
  bool subscribed = true,
  bool allLockedShown = false,
  Location? winner,
  bool advanced = false,
  void Function(Location)? onManage,
  VoidCallback? onShowAll,
}) {
  return MaterialApp(
    home: Scaffold(
      body: LocationsBody(
        mix: mix,
        advanced: advanced,
        subscribed: subscribed,
        showManagedSection: true,
        managedGroup: group,
        managed: managed,
        locked: locked,
        userLocations: user,
        allLockedShown: allLockedShown,
        winner: winner,
        selectedId: null,
        autoCity: 'Zurich',
        autoMs: 24,
        autoManaged: true,
        pingOf: (_) => 24,
        levelOf: (_) => 3,
        nameOf: (l) => l.city,
        subInfoOf: (_) => null,
        onBack: () {},
        onSelect: (_) {},
        onManage: onManage ?? (_) {},
        onLockedTap: (_, _) {},
        onShowAll: onShowAll ?? () {},
        onSeePlans: () {},
        onAdd: () {},
        onDismissWinner: () {},
        onWinner: (_) {},
      ),
    ),
  );
}

void main() {
  // The list is a lazy ListView: on a phone-sized test surface the sections
  // below the fold are never built, so the tree is inspected on a tall one.
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.views.first;
    view.physicalSize = const Size(1000, 4000);
    view.devicePixelRatio = 1;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
  });

  final ownZurich = _loc('ch-zur-reality-03', '198.51.100.10');
  final ownMilan = _loc('it-mil-01', '198.51.100.11', index: 1);
  final managedFrankfurt =
      _loc('de-fra-01', '203.0.113.10', premium: true, index: 2);
  final lockedLondon = _loc('gb-lon-01', '203.0.113.20',
      premium: true, locked: true, index: -1);

  group('the three mixes give three different trees', () {
    testWidgets('byo: locked rows and the strip, no tint, own servers visible',
        (tester) async {
      await tester.pumpWidget(_list(
        mix: Mix.byo,
        group: ManagedGroup.locked,
        subscribed: false,
        locked: [lockedLondon],
        user: [ownZurich],
      ));

      // The locked group sells by comparison: a real row with a real number.
      expect(find.text('London'), findsOneWidget);
      expect(find.text(S.lockedSub('United Kingdom', 24)), findsOneWidget);
      expect(find.text(S.d1StripTitle), findsOneWidget);
      expect(find.text(S.d1StripSub), findsOneWidget);

      // Nothing to tell apart yet, so no tint and no Speed mode bolt.
      expect(find.byIcon(Icons.bolt), findsNothing);
      expect(find.text(S.dYourServers.toUpperCase()), findsOneWidget);
      expect(find.text('Zurich'), findsOneWidget);
    });

    testWidgets('mixed: tinted group and the bolt on managed rows',
        (tester) async {
      await tester.pumpWidget(_list(
        mix: Mix.mixed,
        group: ManagedGroup.servers,
        managed: [managedFrankfurt],
        user: [ownZurich],
      ));

      expect(find.text(S.dYourServers.toUpperCase()), findsOneWidget);
      expect(find.text('Frankfurt'), findsOneWidget);
      // Speed mode applies to the hideip.net fleet only, so exactly one row
      // carries the bolt.
      expect(find.byIcon(Icons.bolt), findsOneWidget);
      // Auto names where its pick comes from once there is a mix.
      expect(find.text(S.autoSub('Zurich', 24, managed: true)), findsOneWidget);
      // Subscribed: the plan is not sold again under the group.
      expect(find.text(S.d1StripTitle), findsNothing);
    });

    testWidgets('hip: no Your servers, no tint, no brand badge',
        (tester) async {
      await tester.pumpWidget(_list(
        mix: Mix.hip,
        group: ManagedGroup.servers,
        managed: [managedFrankfurt],
      ));

      expect(find.text(S.dYourServers.toUpperCase()), findsNothing);
      expect(find.text(S.dNoServers), findsNothing);
      expect(find.byIcon(Icons.bolt), findsNothing);
      expect(find.text('hideip.net'), findsNothing);
      // Auto drops the origin suffix: there is no other origin to name.
      expect(find.text(S.autoSub('Zurich', 24)), findsOneWidget);
    });
  });

  testWidgets('a long locked catalog shows three rows until Show all',
      (tester) async {
    final many = [
      for (var i = 0; i < 7; i++)
        _loc('gb-lon-0$i', '203.0.113.$i',
            premium: true, locked: true, index: -1),
    ];
    var expanded = false;

    await tester.pumpWidget(_list(
      mix: Mix.byo,
      group: ManagedGroup.locked,
      subscribed: false,
      locked: many,
      onShowAll: () => expanded = true,
    ));

    expect(find.text('London'), findsNWidgets(3));
    expect(find.text(S.d2ShowAll(7)), findsOneWidget);

    await tester.tap(find.text(S.d2ShowAll(7)));
    expect(expanded, isTrue);

    await tester.pumpWidget(_list(
      mix: Mix.byo,
      group: ManagedGroup.locked,
      subscribed: false,
      locked: many,
      allLockedShown: true,
    ));
    expect(find.text('London'), findsNWidgets(7));
    expect(find.text(S.d2ShowAll(7)), findsNothing);
  });

  testWidgets('a short catalog is never truncated', (tester) async {
    final few = [
      for (var i = 0; i < 4; i++)
        _loc('gb-lon-0$i', '203.0.113.$i',
            premium: true, locked: true, index: -1),
    ];
    await tester.pumpWidget(_list(
      mix: Mix.byo,
      group: ManagedGroup.locked,
      subscribed: false,
      locked: few,
    ));
    expect(find.text('London'), findsNWidgets(4));
    expect(find.text(S.d2ShowAll(4)), findsNothing);
  });

  group('the chevron into manage', () {
    testWidgets('opens from a user row in Simple view', (tester) async {
      Location? opened;
      await tester.pumpWidget(_list(
        mix: Mix.mixed,
        group: ManagedGroup.servers,
        managed: [managedFrankfurt],
        user: [ownZurich, ownMilan],
        onManage: (l) => opened = l,
      ));

      // Two user rows, no managed one: managed servers stay closed in Simple.
      expect(find.bySemanticsLabel(S.dManage), findsNWidgets(2));
      await tester.tap(find.bySemanticsLabel(S.dManage).first);
      expect(opened?.city, 'Zurich');
    });

    testWidgets('opens managed rows too in Advanced view', (tester) async {
      await tester.pumpWidget(_list(
        mix: Mix.mixed,
        group: ManagedGroup.servers,
        managed: [managedFrankfurt],
        user: [ownZurich],
        advanced: true,
      ));
      expect(find.bySemanticsLabel(S.dManage), findsNWidgets(2));
      // Advanced swaps subtitles for the mono chain.
      expect(find.text(S.tunnelChain('vless', '198.51.100.10:443')),
          findsOneWidget);
    });
  });

  testWidgets('the winner card names the location and offers the plan',
      (tester) async {
    await tester.pumpWidget(_list(
      mix: Mix.byo,
      group: ManagedGroup.locked,
      subscribed: false,
      locked: [lockedLondon],
      winner: lockedLondon,
    ));

    expect(find.text(S.d6Title('London')), findsOneWidget);
    expect(find.text(S.d6Sub), findsOneWidget);
    expect(find.text(S.aSeePlans), findsOneWidget);
    expect(find.text(S.tConnect), findsNothing);
  });

  testWidgets('a winner already on the device offers Connect', (tester) async {
    final wonMilan = _loc('it-mil-01', '198.51.100.11', won: true, index: 1);
    await tester.pumpWidget(_list(
      mix: Mix.mixed,
      group: ManagedGroup.servers,
      managed: [managedFrankfurt],
      user: [wonMilan],
      winner: wonMilan,
    ));

    expect(find.text(S.tConnect), findsOneWidget);
    expect(find.text(S.aSeePlans), findsNothing);
    // The row wears the trophy until the first connect there.
    expect(find.text(S.badgeVoted), findsOneWidget);
  });
}
