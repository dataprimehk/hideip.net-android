import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:hideip_vpn/ui/redesign/ascii/ascii_core.dart';

/// The ASCII fields are seeded noise. If the arithmetic drifts by one bit the
/// picture drifts away from the design and nothing anywhere says so, which is
/// why the reference values below are pinned rather than recomputed.
///
/// Every expected number in this file was produced by running the original
/// `design/app-1_1_0/home-ascii.js` functions under Node and copying the
/// output verbatim.
void main() {
  group('hash32 matches the reference implementation', () {
    const reference = <int, int>{
      0: 0,
      1: 824515495,
      2: 1722258072,
      7: 148231923,
      42: 4147366645,
      1000: 4040455147,
      65535: 3392487869,
      0x51AB1E17: 677400739,
      0x7E11C0DE: 795074432,
      0xFFFFFFFF: 539527247,
    };

    test('ten pinned inputs', () {
      reference.forEach((input, expected) {
        expect(hash32(input), expected, reason: 'hash32($input)');
      });
    });

    test('stays inside 32 bits', () {
      for (final input in reference.keys) {
        expect(hash32(input), inInclusiveRange(0, 0xFFFFFFFF));
      }
    });
  });

  test('hash2 matches the reference implementation on the hero seed', () {
    // (x, y) -> hash2(x, y, 0x51AB1E17), the back layer's seed.
    const reference = <List<int>, int>{
      [0, 0]: 3716379797,
      [1, 0]: 1283844310,
      [0, 1]: 3176032918,
      [3, 5]: 12830861,
      [33, 19]: 1480142049,
      [12, 7]: 3445812847,
      [13, 4]: 3195968942,
      [7, 1]: 3025712724,
      [2, 2]: 2617383738,
      [34, 20]: 1171968600,
    };
    reference.forEach((cell, expected) {
      expect(hash2(cell[0], cell[1], 0x51AB1E17), expected,
          reason: 'hash2(${cell[0]}, ${cell[1]}, 0x51AB1E17)');
    });
  });

  group('mulberry32 matches the reference implementation', () {
    test('ten values from the hero seed', () {
      const expected = <double>[
        0.99284025491215289,
        0.47194839129224420,
        0.06751214759424329,
        0.48595276707783341,
        0.61813638033345342,
        0.99014689098112285,
        0.95755098364315927,
        0.24397228541783988,
        0.81414999463595450,
        0.17737412406131625,
      ];
      final rng = mulberry32(0x51AB1E17);
      for (var i = 0; i < expected.length; i++) {
        expect(rng(), closeTo(expected[i], 1e-15), reason: 'draw $i');
      }
    });

    test('first three values from four more seeds', () {
      const expected = <int, List<double>>{
        0: [0.26642920868471265, 0.00032974570058286, 0.22327202744781971],
        1: [0.62707394058816135, 0.00273572118021548, 0.52744703995995224],
        0x7E11C0DE: [
          0.87679483019746840,
          0.53412950877100229,
          0.51327748247422278,
        ],
        12345: [0.97972826776094735, 0.30675226449966431, 0.48420542152598500],
      };
      expected.forEach((seed, values) {
        final rng = mulberry32(seed);
        for (var i = 0; i < values.length; i++) {
          expect(rng(), closeTo(values[i], 1e-15), reason: 'seed $seed draw $i');
        }
      });
    });

    test('every draw is a fraction', () {
      final rng = mulberry32(7);
      for (var i = 0; i < 200; i++) {
        final v = rng();
        expect(v, greaterThanOrEqualTo(0));
        expect(v, lessThan(1));
      }
    });
  });

  group('glyph thresholds', () {
    // h01(h) is h / 2^32, so these pairs straddle each cut exactly.
    test('exposed', () {
      expect(glyphExposed(3006477107), '1'); // just under 0.70: a digit
      expect(glyphExposed(3006477108), '.');
      expect(glyphExposed(3650722201), '.'); // just under 0.85
      expect(glyphExposed(3650722202), '░');
      expect(glyphExposed(3865470566), '░'); // just under 0.90
      expect(glyphExposed(3865470567), '▒');
      expect(glyphExposed(4080218931), '▒'); // just under 0.95
      expect(glyphExposed(4080218932), ':');
    });

    test('exposed digits come from bits 8 and up', () {
      for (var d = 0; d < 10; d++) {
        expect(glyphExposed(d << 8), String.fromCharCode(48 + d));
      }
    });

    test('hidden', () {
      expect(glyphHidden(2147483647), '░'); // just under 0.50
      expect(glyphHidden(2147483648), '▒');
      expect(glyphHidden(3264175144), '▒'); // just under 0.76
      expect(glyphHidden(3264175145), '.');
      expect(glyphHidden(3865470566), '.'); // just under 0.90
      expect(glyphHidden(3865470567), '█');
    });
  });

  group('addresses stay inside the documentation ranges', () {
    test('docAddress is RFC 5737 or RFC 3849, never anything real', () {
      for (var seed = 0; seed < 300; seed++) {
        final addr = docAddress(mulberry32(seed));
        final documented = addr.startsWith('2001:db8:') ||
            kDocPrefixes.any(addr.startsWith);
        expect(documented, isTrue, reason: addr);
      }
    });

    test('maskedAddress is four groups of blocks', () {
      final addr = maskedAddress(mulberry32(0x51AB1E17));
      expect(addr.split('.'), hasLength(4));
      for (final group in addr.split('.')) {
        expect(group.length, inInclusiveRange(2, 3));
        expect(group.replaceAll('█', ''), isEmpty);
      }
    });
  });

  test('buildGradient walks the four stops across the columns', () {
    const stops = <List<double>>[
      [0, 100, 50],
      [90, 100, 50],
      [180, 100, 50],
      [270, 100, 50],
    ];
    final grad = buildGradient(34, stops);
    expect(grad, hasLength(34));
    // First and last columns land exactly on the first and last stop.
    expect(grad.first, buildGradient(1, stops).first);
    expect(grad.last.toARGB32(), isNot(grad.first.toARGB32()));
  });

  group('AsciiTicker', () {
    testWidgets('freezes six seconds after the last poke', (tester) async {
      var frames = 0;
      final ticker = AsciiTicker(
        vsync: const TestVSync(),
        onFrame: (_) => frames++,
      );
      addTearDown(ticker.dispose);

      ticker.poke();
      expect(ticker.isRunning, isTrue);

      await tester.pump();
      for (var i = 0; i < 80; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(ticker.isRunning, isFalse, reason: 'the idle window has passed');
      // Six seconds of frames, one per pump past the 83 ms throttle.
      expect(frames, inInclusiveRange(55, 70));

      final frozen = frames;
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(frames, frozen, reason: 'a frozen field draws nothing');

      // A change of state starts it again. The clock restarts with it, so
      // the first tick lands inside the throttle window and the second one
      // is the frame.
      ticker.poke();
      expect(ticker.isRunning, isTrue);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(frames, greaterThan(frozen));
      ticker.stop();
    });

    testWidgets('never freezes while continuous', (tester) async {
      var frames = 0;
      final ticker = AsciiTicker(
        vsync: const TestVSync(),
        onFrame: (_) => frames++,
      );
      addTearDown(ticker.dispose);

      ticker.continuous = true;
      ticker.poke();
      await tester.pump();
      for (var i = 0; i < 150; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(ticker.isRunning, isTrue, reason: 'transit must keep moving');
      expect(frames, greaterThan(120));
      ticker.stop();
    });

    testWidgets('reduced motion holds one still frame and no ticker',
        (tester) async {
      final times = <double>[];
      final ticker = AsciiTicker(
        vsync: const TestVSync(),
        onFrame: times.add,
        reducedMotion: true,
      );
      addTearDown(ticker.dispose);

      ticker.poke();
      expect(ticker.isRunning, isFalse);
      expect(times, [kStaticTimeMs]);

      ticker.continuous = true;
      await tester.pump(const Duration(milliseconds: 500));
      expect(ticker.isRunning, isFalse, reason: 'not even transit animates');
      expect(times, everyElement(kStaticTimeMs));
    });
  });

  test('AsciiParagraphCache reuses a laid-out glyph', () {
    final cache = AsciiParagraphCache(fontSize: 7.8);
    const white = Color(0xFFFFFFFF);
    final first = cache.paragraph('░', white, 0.5);
    expect(identical(cache.paragraph('░', white, 0.5), first), isTrue);
    expect(cache.length, 1);
    // Alpha is bucketed, so a hair of difference is the same entry.
    cache.paragraph('░', white, 0.505);
    expect(cache.length, 1);
    cache.paragraph('▒', white, 0.5);
    expect(cache.length, 2);
    cache.clear();
    expect(cache.length, 0);
  });
}
