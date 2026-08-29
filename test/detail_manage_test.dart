import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hideip_vpn/ui/redesign/detail_screen.dart';
import 'package:hideip_vpn/ui/redesign/hip_sheet.dart';
import 'package:hideip_vpn/ui/strings.dart';

Widget _section({
  required String name,
  String rawName = 'ch-zur-reality-03',
  bool fromSubscription = false,
  RefreshState refresh = RefreshState.idle,
  int refreshed = 0,
  DateTime? lastUpdated,
  void Function(String)? onRename,
  VoidCallback? onRefresh,
}) {
  return MaterialApp(
    home: Scaffold(
      body: ManageServerSection(
        name: name,
        rawName: rawName,
        fromSubscription: fromSubscription,
        refresh: refresh,
        refreshedServers: refreshed,
        lastUpdated: lastUpdated,
        onRename: onRename ?? (_) {},
        onRefresh: onRefresh,
      ),
    ),
  );
}

void main() {
  group('rename', () {
    testWidgets('changes the name shown and keeps the raw one', (tester) async {
      String? renamed;
      await tester.pumpWidget(_section(
        name: 'Zurich',
        onRename: (v) => renamed = v,
      ));

      expect(find.text(S.gThisServer.toUpperCase()), findsOneWidget);
      expect(find.text(S.gNameSub('Zurich', 'ch-zur-reality-03')),
          findsOneWidget);

      await tester.tap(find.text(S.gName));
      await tester.pumpAndSettle();

      // The field opens on the current name, ready to be replaced.
      expect(find.widgetWithText(TextField, 'Zurich'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Home');
      await tester.tap(find.text(S.gSave));
      await tester.pumpAndSettle();

      expect(renamed, 'Home');

      // What the user renamed it to leads; the provider's name stays quoted
      // underneath, so nothing is lost by renaming.
      await tester.pumpWidget(_section(name: 'Home'));
      expect(find.text(S.gNameSub('Home', 'ch-zur-reality-03')), findsOneWidget);
      expect(
          find.textContaining('ch-zur-reality-03'), findsOneWidget);
    });

    testWidgets('an empty field keeps the name it had', (tester) async {
      String? renamed;
      await tester.pumpWidget(
          _section(name: 'Zurich', onRename: (v) => renamed = v));

      await tester.tap(find.text(S.gName));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.text(S.gSave));
      await tester.pumpAndSettle();

      expect(renamed, 'Zurich');
    });
  });

  group('source and subscription', () {
    testWidgets('a single link says it does not update on its own',
        (tester) async {
      await tester.pumpWidget(_section(name: 'Zurich'));
      expect(find.text(S.gSource), findsOneWidget);
      expect(find.text(S.gSourceSub), findsOneWidget);
      expect(find.text(S.gSubscription), findsNothing);
    });

    testWidgets('a failed refresh names what still works', (tester) async {
      await tester.pumpWidget(_section(
        name: 'Zurich',
        fromSubscription: true,
        refresh: RefreshState.error,
      ));

      expect(find.text(S.gSubscription), findsOneWidget);
      expect(
        find.text('The subscription could not be reached. The servers already '
            'on this device keep working.'),
        findsOneWidget,
      );
      expect(find.text(S.gRefreshError), findsOneWidget);
    });

    testWidgets('the other three refresh states each have their line',
        (tester) async {
      await tester.pumpWidget(_section(
        name: 'Zurich',
        fromSubscription: true,
        lastUpdated: DateTime.now().subtract(const Duration(hours: 2)),
        onRefresh: () {},
      ));
      expect(find.text(S.gRefreshIdle(S.gAgoHours(2))), findsOneWidget);

      await tester.pumpWidget(_section(
        name: 'Zurich',
        fromSubscription: true,
        refresh: RefreshState.busy,
      ));
      expect(find.text(S.gRefreshBusy), findsOneWidget);

      await tester.pumpWidget(_section(
        name: 'Zurich',
        fromSubscription: true,
        refresh: RefreshState.done,
        refreshed: 1,
      ));
      expect(find.text('Updated just now. 1 server.'), findsOneWidget);
    });

    testWidgets('a refresh in flight cannot be started again', (tester) async {
      var calls = 0;
      await tester.pumpWidget(_section(
        name: 'Zurich',
        fromSubscription: true,
        refresh: RefreshState.busy,
        onRefresh: () => calls++,
      ));
      await tester.tap(find.text(S.gSubscription));
      await tester.pump();
      expect(calls, 0);
    });
  });

  group('remove', () {
    testWidgets('opens a sheet that says what keeps working', (tester) async {
      var removed = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showHipSheet<bool>(
                context,
                children: removeServerSheet(
                  name: 'Milan',
                  onCancel: () => Navigator.of(context).pop(false),
                  onRemove: () => Navigator.of(context).pop(true),
                ),
              ).then((v) => removed = v ?? false),
              child: const Text(S.gRemove),
            ),
          ),
        ),
      ));

      await tester.tap(find.text(S.gRemove));
      await tester.pumpAndSettle();

      expect(find.text('Remove Milan?'), findsOneWidget);
      expect(
        find.text('The server is removed from this device. The link from your '
            'provider keeps working, so it can be added again at any time.'),
        findsOneWidget,
      );
      expect(find.text(S.aCancel), findsOneWidget);

      await tester.tap(find.text(S.aRemove));
      await tester.pumpAndSettle();
      expect(removed, isTrue);
    });

    testWidgets('cancelling removes nothing', (tester) async {
      bool? removed;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showHipSheet<bool>(
                context,
                children: removeServerSheet(
                  name: 'Milan',
                  onCancel: () => Navigator.of(context).pop(false),
                  onRemove: () => Navigator.of(context).pop(true),
                ),
              ).then((v) => removed = v),
              child: const Text(S.gRemove),
            ),
          ),
        ),
      ));

      await tester.tap(find.text(S.gRemove));
      await tester.pumpAndSettle();
      await tester.tap(find.text(S.aCancel));
      await tester.pumpAndSettle();
      expect(removed, isFalse);
    });

    test('removing the selected server falls back to Auto', () {
      // The server the user explicitly picked is gone: Auto is the honest
      // answer, not whichever server now sits first in the list.
      expect(
        removalFallsBackToAuto(
            autoSelect: false, selectedIndex: 2, removedIndex: 2),
        isTrue,
      );
      // Removing any other server leaves the selection where it was.
      expect(
        removalFallsBackToAuto(
            autoSelect: false, selectedIndex: 2, removedIndex: 1),
        isFalse,
      );
      // Already on Auto: nothing to fall back from.
      expect(
        removalFallsBackToAuto(
            autoSelect: true, selectedIndex: 2, removedIndex: 2),
        isFalse,
      );
    });
  });
}
