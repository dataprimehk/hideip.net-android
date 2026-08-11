import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hideip_vpn/core/async_gate.dart';

void main() {
  test('AsyncGate serializes the full fetch and commit transaction', () async {
    final gate = AsyncGate();
    final firstMayFinish = Completer<void>();
    final events = <String>[];

    final first = gate.run(() async {
      events.add('first fetch');
      await firstMayFinish.future;
      events.add('first commit');
    });
    final second = gate.run(() async {
      events.add('second fetch');
      events.add('second commit');
    });

    await Future<void>.delayed(Duration.zero);
    expect(events, ['first fetch']);
    firstMayFinish.complete();
    await Future.wait([first, second]);
    expect(events, [
      'first fetch',
      'first commit',
      'second fetch',
      'second commit',
    ]);
  });

  test('forEachBounded never exceeds its concurrency limit', () async {
    var active = 0;
    var peak = 0;
    await forEachBounded(
      List.generate(30, (index) => index),
      limit: 8,
      action: (_) async {
        active++;
        if (active > peak) peak = active;
        await Future<void>.delayed(const Duration(milliseconds: 2));
        active--;
      },
    );
    expect(peak, 8);
    expect(active, 0);
  });
}
