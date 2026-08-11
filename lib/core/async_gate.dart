import 'dart:async';

/// FIFO gate for refreshes whose fetch and commit must be one transaction.
class AsyncGate {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() action) {
    final previous = _tail;
    final released = Completer<void>();
    _tail = released.future;
    return () async {
      await previous;
      try {
        return await action();
      } finally {
        released.complete();
      }
    }();
  }
}

/// Runs at most [limit] asynchronous operations at once.
Future<void> forEachBounded<T>(
  Iterable<T> values, {
  required int limit,
  required Future<void> Function(T value) action,
}) async {
  if (limit < 1) throw ArgumentError.value(limit, 'limit');
  final iterator = values.iterator;

  Future<void> worker() async {
    while (iterator.moveNext()) {
      await action(iterator.current);
    }
  }

  final count = values.length < limit ? values.length : limit;
  await Future.wait(List.generate(count, (_) => worker()));
}
