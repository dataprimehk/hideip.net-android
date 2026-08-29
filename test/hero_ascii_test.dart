import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hideip_vpn/ui/redesign/ascii/hero_ascii.dart';
import 'package:hideip_vpn/ui/redesign/ascii/hero_glow.dart';
import 'package:hideip_vpn/ui/redesign/hip.dart';
import 'package:hideip_vpn/ui/redesign/mark.dart' show MarkState;

/// The hero band under test: the size it has on Home.
Widget _host(Widget child) => Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(width: 340, height: 132, child: child),
      ),
    );

void main() {
  tearDown(() => Hip.reducedMotion = false);

  group('heroAsciiModeFor', () {
    test('maps every connection state to a field', () {
      expect(heroAsciiModeFor(MarkState.disconnected), HeroAsciiMode.exposed);
      expect(heroAsciiModeFor(MarkState.connecting), HeroAsciiMode.transit);
      expect(heroAsciiModeFor(MarkState.disconnecting), HeroAsciiMode.transit);
      expect(heroAsciiModeFor(MarkState.connected), HeroAsciiMode.hidden);
    });
  });

  testWidgets('the field freezes once the idle window has passed',
      (tester) async {
    await tester.pumpWidget(
      _host(const HeroAscii(state: MarkState.disconnected)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.hasScheduledFrame, isTrue);

    // Six seconds of animation and then a still canvas: pumpAndSettle only
    // returns because the engine stops itself.
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('transit never freezes on its own', (tester) async {
    await tester.pumpWidget(
      _host(const HeroAscii(state: MarkState.connecting)),
    );
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.binding.hasScheduledFrame, isTrue,
        reason: 'the wave has to keep moving while connecting');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a change of state wakes a frozen field', (tester) async {
    await tester.pumpWidget(
      _host(const HeroAscii(state: MarkState.disconnected)),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(tester.binding.hasScheduledFrame, isFalse);

    await tester.pumpWidget(
      _host(const HeroAscii(state: MarkState.connected)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('reduced motion paints one still frame and holds no ticker',
      (tester) async {
    Hip.reducedMotion = true;
    await tester.pumpWidget(
      _host(const HeroAscii(state: MarkState.connecting)),
    );
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse,
        reason: 'not even transit animates when motion is reduced');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the reduced-motion frame is one fixed frame, not the clock',
      (tester) async {
    Hip.reducedMotion = true;
    await tester.pumpWidget(
      _host(const HeroAscii(state: MarkState.disconnected)),
    );
    await tester.pump();
    final paint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byType(HeroAscii),
        matching: find.byType(CustomPaint),
      ),
    );
    final first = _CountingCanvas();
    paint.painter!.paint(first, const Size(340, 132));
    await tester.pump(const Duration(seconds: 3));
    final second = _CountingCanvas();
    paint.painter!.paint(second, const Size(340, 132));
    expect(second.paragraphs, first.paragraphs);
    expect(first.paragraphs, greaterThan(5));
  });

  testWidgets('the front layer mounts alongside the back one', (tester) async {
    await tester.pumpWidget(
      _host(
        const Stack(
          children: [
            Positioned.fill(child: HeroAscii(state: MarkState.connected)),
            Positioned.fill(
              child: HeroAscii(state: MarkState.connected, front: true),
            ),
          ],
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(HeroAscii), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
  });

  testWidgets('a zero-height box paints nothing and does not throw',
      (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 340,
            height: 0,
            child: const HeroAscii(state: MarkState.disconnected),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
  });

  testWidgets('every mode actually draws glyphs', (tester) async {
    for (final state in MarkState.values) {
      await tester.pumpWidget(_host(HeroAscii(state: state)));
      await tester.pump(const Duration(milliseconds: 100));
      final paint = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byType(HeroAscii),
          matching: find.byType(CustomPaint),
        ),
      );
      final canvas = _CountingCanvas();
      paint.painter!.paint(canvas, const Size(340, 132));
      expect(canvas.paragraphs, greaterThan(5), reason: 'field for $state');
      await tester.pumpWidget(const SizedBox());
    }
  });

  group('HeroGlow', () {
    testWidgets('drifts, and takes the colour of the state', (tester) async {
      await tester.pumpWidget(_host(const HeroGlow(state: MarkState.connected)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.hasScheduledFrame, isTrue);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(
        _host(const HeroGlow(state: MarkState.disconnected)),
      );
      await tester.pump(const Duration(milliseconds: 900));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('holds still when motion is reduced', (tester) async {
      Hip.reducedMotion = true;
      await tester.pumpWidget(
        _host(const HeroGlow(state: MarkState.connecting, offline: true)),
      );
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
    });
  });
}

/// Counts the glyphs a painter lays down, so the engine can be checked
/// without a golden file.
class _CountingCanvas implements Canvas {
  int paragraphs = 0;

  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) => paragraphs++;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
