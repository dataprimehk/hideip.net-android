import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hideip_vpn/core/premium.dart';
import 'package:hideip_vpn/ui/redesign/hip.dart';
import 'package:hideip_vpn/ui/redesign/paywall_screen.dart';

const _trialEnds = 'Sep 5, 2026';

Widget _offer(
  PremiumPlan plan, {
  ValueChanged<PremiumPlan>? onPlan,
  int? locationCount,
  String? city,
  bool failed = false,
}) =>
    MaterialApp(
      home: Scaffold(
        backgroundColor: Hip.dark,
        body: PaywallOffer(
          yearly: PlanInfo.yearly,
          monthly: PlanInfo.monthly,
          plan: plan,
          onPlan: onPlan ?? (_) {},
          locationCount: locationCount,
          city: city,
          trialEnds: _trialEnds,
          storeName: 'App Store',
          failed: failed,
          onBuy: () {},
          onRestore: () {},
          onTerms: () {},
          onPrivacy: () {},
        ),
      ),
    );

void main() {
  group('the plan decides the offer', () {
    testWidgets('yearly starts with the free trial', (tester) async {
      await tester.pumpWidget(_offer(PremiumPlan.yearly));

      expect(find.text('Start 7-day free trial'), findsOneWidget);
      expect(find.text('Get Premium'), findsNothing);
      expect(find.textContaining(_trialEnds), findsOneWidget);
      expect(find.textContaining('Nothing is charged before'), findsOneWidget);
    });

    testWidgets('yearly restates the price per month', (tester) async {
      await tester.pumpWidget(_offer(PremiumPlan.yearly));

      expect(find.textContaining(r'$2.50'), findsOneWidget);
      expect(find.text(r'$29.99'), findsOneWidget);
    });

    testWidgets('monthly bills right away and says so', (tester) async {
      await tester.pumpWidget(_offer(PremiumPlan.monthly));

      expect(find.text('Get Premium'), findsOneWidget);
      expect(find.text('Start 7-day free trial'), findsNothing);
      expect(find.textContaining('The first charge happens right away'),
          findsOneWidget);
      expect(find.textContaining(_trialEnds), findsNothing);
    });

    testWidgets('the monthly plan never carries the yearly per-month figure',
        (tester) async {
      await tester.pumpWidget(_offer(PremiumPlan.monthly));

      expect(find.textContaining(r'$2.50'), findsNothing);
      expect(
          find.textContaining('The free trial comes with the yearly plan'),
          findsOneWidget);
    });

    testWidgets('a failed attempt retries without a new plan', (tester) async {
      await tester.pumpWidget(_offer(PremiumPlan.yearly, failed: true));

      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Start 7-day free trial'), findsNothing);
      expect(find.textContaining("you haven't been charged"), findsOneWidget);
    });

    test('the button label follows the plan, not the screen', () {
      expect(paywallCtaLabel(PlanInfo.yearly, failed: false),
          'Start 7-day free trial');
      expect(paywallCtaLabel(PlanInfo.monthly, failed: false), 'Get Premium');
      expect(paywallCtaLabel(PlanInfo.yearly, failed: true), 'Try again');
    });

    test('a localized price drops the per-month figure it cannot derive', () {
      final localized = PlanInfo.yearly.withPrice('27,99 EUR');
      expect(localized.perMonth, isNull);
      expect(localized.trial, isTrue);
      expect(localized.note, isNot(contains(r'$2.50')));
    });
  });

  group('what the offer promises', () {
    testWidgets('the first row carries the number of locations',
        (tester) async {
      await tester.pumpWidget(_offer(PremiumPlan.yearly, locationCount: 12));

      expect(find.text('All 12 hideip.net locations'), findsOneWidget);
    });

    testWidgets('without a catalog it counts nothing', (tester) async {
      await tester.pumpWidget(_offer(PremiumPlan.yearly));

      expect(find.text('All hideip.net locations'), findsOneWidget);
    });

    testWidgets('a locked row personalises the headline', (tester) async {
      await tester.pumpWidget(_offer(PremiumPlan.yearly, city: 'London'));

      expect(find.text('London is part of the plan.'), findsOneWidget);
      expect(find.text('Every location, one plan.'), findsNothing);
    });

    testWidgets('the plain headline is the default', (tester) async {
      await tester.pumpWidget(_offer(PremiumPlan.yearly));

      expect(find.text('Every location, one plan.'), findsOneWidget);
    });

    testWidgets('the segment offers the other plan', (tester) async {
      PremiumPlan? picked;
      await tester.pumpWidget(
          _offer(PremiumPlan.yearly, onPlan: (p) => picked = p));

      await tester.tap(find.text('Monthly'));
      expect(picked, PremiumPlan.monthly);
    });
  });
}
