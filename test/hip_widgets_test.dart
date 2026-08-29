import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hideip_vpn/core/location.dart';
import 'package:hideip_vpn/core/proxy_profile.dart';
import 'package:hideip_vpn/ui/brand.dart';
import 'package:hideip_vpn/ui/redesign/hip.dart';
import 'package:hideip_vpn/ui/redesign/locked_row.dart';
import 'package:hideip_vpn/ui/redesign/paywall_screen.dart';

Widget _host(Widget child, {Color background = Colors.white}) =>
    MaterialApp(home: Scaffold(backgroundColor: background, body: child));

Location _location({bool won = false}) => Location(
      profile: const ProxyProfile(
        name: 'de-fra-01',
        protocol: 'vless',
        server: '10.0.0.1',
        port: 443,
        outbound: {'type': 'vless'},
        premium: true,
      ),
      index: 0,
      city: 'Frankfurt',
      country: 'Germany',
      cc: 'DE',
      locked: true,
      won: won,
    );

/// The single box a [HipCta] paints itself into.
BoxDecoration _ctaBox(WidgetTester tester) => tester
    .widget<Container>(find.descendant(
        of: find.byType(HipCta), matching: find.byType(Container)))
    .decoration! as BoxDecoration;

TextStyle _ctaLabel(WidgetTester tester) => tester
    .widget<Text>(
        find.descendant(of: find.byType(HipCta), matching: find.byType(Text)))
    .style!;

void main() {
  setUp(() {
    Hip.dm = false;
    Hip.reducedMotion = false;
  });

  group('the onboarding ghost button', () {
    testWidgets('wears the ob3 fill, rim and label', (tester) async {
      await tester.pumpWidget(_host(
          const HipCta('Explore the app first', obGhost: true),
          background: Hip.dark));

      final box = _ctaBox(tester);
      expect(box.color, Colors.white.withValues(alpha: .07));
      final border = box.border! as Border;
      expect(border.top.color, Colors.white.withValues(alpha: .17));
      expect(border.top.width, 1.5);
      expect(_ctaLabel(tester).color, Colors.white.withValues(alpha: .88));
    });

    testWidgets('the older dark ghost is untouched by it', (tester) async {
      await tester.pumpWidget(_host(
          const HipCta('Not now', ghost: true, darkGhost: true),
          background: Hip.dark));

      final box = _ctaBox(tester);
      expect(box.color, Colors.white.withValues(alpha: .09));
      expect(box.border, isNull);
      expect(_ctaLabel(tester).color, Colors.white);
    });

    testWidgets('a danger ghost stays red on the dark panel', (tester) async {
      await tester.pumpWidget(_host(
          const HipCta('Disconnect', ghost: true, darkGhost: true, danger: true),
          background: Hip.dark));

      expect(_ctaLabel(tester).color, Brand.hsl(4, 85, 70));
    });
  });

  group('a list row subtitle built from spans', () {
    testWidgets('wins over the plain subtitle', (tester) async {
      await tester.pumpWidget(_host(HipListRow(
        title: 'Premium',
        subtitle: 'plain sentence',
        subtitleSpan: TextSpan(children: [
          TextSpan(text: 'Free trial; ends ', style: Hip.sans(400, 14)),
          TextSpan(text: 'Sep 5, 2026', style: Hip.mono(600, 12.5)),
        ]),
      )));

      expect(find.text('plain sentence'), findsNothing);
      expect(find.text('Free trial; ends Sep 5, 2026'), findsOneWidget);
    });

    testWidgets('keeps the mono run mono and the sentence in the body face',
        (tester) async {
      await tester.pumpWidget(_host(HipListRow(
        title: 'Premium',
        subtitleSpan: TextSpan(children: [
          TextSpan(text: 'Free trial; ends ', style: Hip.sans(400, 14)),
          TextSpan(text: 'Sep 5, 2026', style: Hip.mono(600, 12.5)),
        ]),
      )));

      final rich = tester.widget<Text>(find.text('Free trial; ends Sep 5, 2026'));
      final runs = (rich.textSpan! as TextSpan).children!.cast<TextSpan>();
      expect(runs.first.style!.fontFamily, Brand.bodyFont);
      expect(runs.last.text, 'Sep 5, 2026');
      expect(runs.last.style!.fontFamily, Brand.monoFont);
    });

    testWidgets('a row with neither draws no subtitle at all', (tester) async {
      await tester.pumpWidget(_host(const HipListRow(title: 'Premium')));

      expect(find.byType(Text), findsOneWidget);
    });
  });

  group('the voted badge', () {
    testWidgets('is amber, not the blue the rest of Premium uses',
        (tester) async {
      await tester.pumpWidget(_host(LockedRow(
          location: _location(won: true), from: LockedFrom.homeRow)));

      final badge = tester.widget<HipBadge>(find.byType(HipBadge));
      expect(badge.bg, Brand.hsl(42, 92, 52, .16));
      expect(badge.fg, Brand.hsl(38, 85, 38));
      expect(badge.icon, Icons.emoji_events_outlined);
    });

    testWidgets('lightens its label in dark mode', (tester) async {
      Hip.dm = true;
      await tester.pumpWidget(_host(LockedRow(
          location: _location(won: true), from: LockedFrom.homeRow)));

      expect(tester.widget<HipBadge>(find.byType(HipBadge)).fg,
          Brand.hsl(42, 92, 66));
    });

    testWidgets('a location nobody voted for carries no badge',
        (tester) async {
      await tester.pumpWidget(
          _host(LockedRow(location: _location(), from: LockedFrom.homeRow)));

      expect(find.byType(HipBadge), findsNothing);
    });
  });

  testWidgets('the padlock is the deep blue, not a muted gray',
      (tester) async {
    await tester.pumpWidget(
        _host(LockedRow(location: _location(), from: LockedFrom.homeRow)));

    expect(tester.widget<Icon>(find.byIcon(Icons.lock_outline)).color,
        Hip.blueDeep);
    expect(Hip.blueDeep, isNot(Hip.muted2));
  });

  group('the unlocked locations deal themselves in', () {
    Widget rows() => _host(
          Column(children: const [
            UnlockIn(index: 0, child: Text('Frankfurt')),
            UnlockIn(index: 1, child: Text('Amsterdam')),
          ]),
          background: Hip.dark,
        );

    double opacityOf(WidgetTester tester, String label) => tester
        .widget<Opacity>(find.ancestor(
            of: find.text(label), matching: find.byType(Opacity)))
        .opacity;

    testWidgets('the second row lags the first, then both settle',
        (tester) async {
      await tester.pumpWidget(rows());

      // Nothing has moved yet: the first row waits out its 250 ms.
      expect(opacityOf(tester, 'Frankfurt'), 0);
      expect(opacityOf(tester, 'Amsterdam'), 0);

      // 400 ms in, the first row is on its way and the second has not begun
      // (it waits 250 + 160).
      await tester.pump(const Duration(milliseconds: 400));
      expect(opacityOf(tester, 'Frankfurt'), greaterThan(0));
      expect(opacityOf(tester, 'Amsterdam'), 0);

      await tester.pump(const Duration(milliseconds: 1200));
      expect(opacityOf(tester, 'Frankfurt'), 1);
      expect(opacityOf(tester, 'Amsterdam'), 1);
    });

    testWidgets('reduce motion puts every row in place at once',
        (tester) async {
      Hip.reducedMotion = true;
      await tester.pumpWidget(rows());

      expect(opacityOf(tester, 'Frankfurt'), 1);
      expect(opacityOf(tester, 'Amsterdam'), 1);
    });
  });
}
