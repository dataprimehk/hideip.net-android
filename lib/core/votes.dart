import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Anonymous location voting: tapping a country without an exit node casts a
/// vote for where to build next. No account, no identifiers; the request body
/// is just the country code (see docs/voting-api.md for the full contract).
///
/// Backend contract:
///   GET  {endpoint}
///     -> 200 {"votes": {"RS": 141, ...}, "max": 3, "resets": "2026-09-01",
///             "won": ["784"]}
///   POST {endpoint} {"country":"RS","vote":true}  -> 200 {"country":"RS","votes":142}
///
/// The service is fully usable before the backend exists: a vote lands in
/// local storage immediately and queues for sync, and vote counts only render
/// once the server has answered at least once (no invented numbers). The same
/// rule covers the quota: with no answer yet there is no "N of M left" on
/// screen, and voting is not blocked by a limit nobody has stated.
class VoteService extends ChangeNotifier {
  VoteService._();
  static final VoteService instance = VoteService._();

  /// Planned endpoint on the site; not live yet. Every network failure is
  /// silent and retried on the next refresh.
  static const endpoint = 'https://hideip.net/api/votes';

  static const _kMine = 'votes_mine_v1';
  static const _kMineCycles = 'votes_mine_cycles_v1';
  static const _kPending = 'votes_pending_v1';
  static const _kCounts = 'votes_counts_v1';
  static const _kCycle = 'votes_cycle_v1';
  static const _kMax = 'votes_max_v1';

  SharedPreferences? _prefs;

  /// Every country this install voted for, mapped to the cycle it was cast
  /// in. The cycle is the reset date the server was announcing at the time.
  /// A vote from a finished cycle still shows as cast; it just no longer
  /// spends anything, which is the whole reason the cycle is stored per vote
  /// rather than as one global counter.
  final Map<String, String> _mine = {};
  final Map<String, bool> _pending = {};
  Map<String, int>? _counts; // null until the server has ever answered
  final Set<String> _won = {};
  String? _cycle; // the current reset date, as the server states it
  int? _max; // votes per cycle, null until the server has said
  bool _refreshing = false;

  /// Test hook: inject an http client; null uses a fresh default client.
  @visibleForTesting
  http.Client? clientOverride;

  /// The map's "tap a country to vote" hint stays up until the first vote is
  /// cast; retracting every vote brings it back. Derived, not a stored flag,
  /// so it self-corrects across installs and upgrades.
  bool get hintDismissed => _mine.isNotEmpty;
  bool hasVoted(String cc) => _mine.containsKey(cc);

  /// How many votes this cycle allows, or null while the server has not said.
  int? get votesMax => _max;

  /// When the allowance resets, as the server states it, or null while it has
  /// not said. Rendered verbatim; the client never formats a date it invented.
  String? get votesReset => _cycle;

  /// Votes still available this cycle, or null while the quota is unknown.
  int? get votesLeft {
    final max = _max;
    if (max == null) return null;
    final left = max - _spentThisCycle;
    return left < 0 ? 0 : left;
  }

  /// Whether another country may be voted for right now.
  bool get canVote {
    final left = votesLeft;
    return left == null || left > 0;
  }

  int get _spentThisCycle =>
      _mine.values.where((cycle) => cycle == (_cycle ?? '')).length;

  /// Countries whose vote already won a round and went live. Used for the
  /// trophy on the map pin and the winner card in Locations.
  Set<String> get won => Set.unmodifiable(_won);

  /// The count to render for [cc], or null when the server total is unknown
  /// (the UI omits the number rather than inventing one). A queued local vote
  /// is reflected on top of the last known server total.
  int? displayCount(String cc) {
    final base = _counts?[cc];
    if (base == null) return null;
    final queued = _pending[cc];
    if (queued == null) return base;
    return queued ? base + 1 : (base > 0 ? base - 1 : 0);
  }

  /// The countries this install has voted for, in any cycle.
  Set<String> get mine => Set.unmodifiable(_mine.keys.toSet());

  /// Top voted countries as (code, count), highest first. Empty until the
  /// server has answered at least once, for the same reason [displayCount]
  /// returns null: the UI never invents numbers.
  List<(String, int)> leaderboard([int limit = 5]) {
    final counts = _counts;
    if (counts == null) return const [];
    final entries = <(String, int)>[
      for (final cc in {...counts.keys, ..._pending.keys})
        if (displayCount(cc) case final n? when n > 0) (cc, n),
    ];
    entries.sort((a, b) {
      final byCount = b.$2.compareTo(a.$2);
      return byCount != 0 ? byCount : a.$1.compareTo(b.$1);
    });
    return entries.take(limit).toList();
  }

  /// Test hook: forget everything held in memory so the next [init] reloads
  /// from a fresh [SharedPreferences] mock. The service is a singleton, so
  /// without this one test's votes are the next test's starting state.
  @visibleForTesting
  void resetForTesting() {
    _prefs = null;
    _mine.clear();
    _pending.clear();
    _counts = null;
    _won.clear();
    _cycle = null;
    _max = null;
    _refreshing = false;
    clientOverride = null;
  }

  Future<void> init() async {
    if (_prefs != null) {
      unawaited(refresh());
      return;
    }
    final p = _prefs = await SharedPreferences.getInstance();
    _cycle = p.getString(_kCycle);
    _max = p.getInt(_kMax);
    _mine.clear();
    final rawCycles = p.getString(_kMineCycles);
    if (rawCycles != null) {
      try {
        (json.decode(rawCycles) as Map<String, dynamic>)
            .forEach((k, v) => _mine[k] = v as String);
      } catch (_) {}
    } else {
      // Upgrade from the flat list: those votes were cast under whatever
      // cycle is current, so they spend from it like any other.
      for (final cc in p.getStringList(_kMine) ?? const <String>[]) {
        _mine[cc] = _cycle ?? '';
      }
    }
    _pending.clear();
    final rawPending = p.getString(_kPending);
    if (rawPending != null) {
      try {
        (json.decode(rawPending) as Map<String, dynamic>)
            .forEach((k, v) => _pending[k] = v == true);
      } catch (_) {}
    }
    final rawCounts = p.getString(_kCounts);
    if (rawCounts != null) {
      try {
        _counts = (json.decode(rawCounts) as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, (v as num).toInt()));
      } catch (_) {}
    }
    notifyListeners();
    unawaited(refresh());
  }

  /// Casts or retracts the vote for [cc]. Local state flips immediately; the
  /// server sync runs in the background and survives restarts via the queue.
  /// Retracts the vote for [cc], the separate action the vote panel offers
  /// once a country is voted for. A no-op when there is no vote to retract.
  Future<void> unvote(String cc) async {
    if (!_mine.containsKey(cc)) return;
    await toggle(cc);
  }

  Future<void> toggle(String cc) async {
    final voting = !_mine.containsKey(cc);
    // The quota only stops new votes. Retracting always works, and it is what
    // gives a vote back: three picks is a budget, not three taps.
    if (voting && !canVote) return;
    if (voting) {
      _mine[cc] = _cycle ?? '';
    } else {
      _mine.remove(cc);
    }
    // A queued opposite action cancels out instead of stacking.
    if (_pending[cc] == !voting) {
      _pending.remove(cc);
    } else {
      _pending[cc] = voting;
    }
    await _persist();
    notifyListeners();
    unawaited(_sync());
  }

  /// Pulls fresh totals and drains the pending queue. Safe to call anytime.
  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final client = clientOverride ?? http.Client();
      try {
        final res = await client
            .get(Uri.parse(endpoint))
            .timeout(const Duration(seconds: 6));
        if (res.statusCode == 200) {
          final body = json.decode(res.body) as Map<String, dynamic>;
          _counts = (body['votes'] as Map<String, dynamic>)
              .map((k, v) => MapEntry(k, (v as num).toInt()));
          final max = body['max'];
          if (max is num) _max = max.toInt();
          final resets = body['resets'];
          if (resets is String && resets.isNotEmpty) _cycle = resets;
          final won = body['won'];
          if (won is List) {
            _won
              ..clear()
              ..addAll(won.whereType<String>());
          }
          await _persist();
          notifyListeners();
        }
      } finally {
        if (clientOverride == null) client.close();
      }
      await _sync();
    } catch (_) {
      // Backend absent or unreachable: keep cached state, retry next time.
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _sync() async {
    if (_pending.isEmpty) return;
    final client = clientOverride ?? http.Client();
    try {
      for (final cc in _pending.keys.toList()) {
        // Two votes in quick succession start two drains, each over its own
        // snapshot of the queue. Whichever gets there first removes the entry,
        // so the other has to find it gone rather than assert on it.
        final vote = _pending[cc];
        if (vote == null) continue;
        try {
          final res = await client
              .post(Uri.parse(endpoint),
                  headers: {'content-type': 'application/json'},
                  body: json.encode({'country': cc, 'vote': vote}))
              .timeout(const Duration(seconds: 6));
          if (res.statusCode == 200) {
            _pending.remove(cc);
            try {
              final body = json.decode(res.body) as Map<String, dynamic>;
              (_counts ??= {})[cc] = (body['votes'] as num).toInt();
            } catch (_) {}
            await _persist();
            notifyListeners();
          } else {
            break; // server unhappy; keep the queue and stop hammering
          }
        } on Exception {
          break; // offline / endpoint not live yet; the queue persists
        }
      }
    } finally {
      if (clientOverride == null) client.close();
    }
  }

  Future<void> _persist() async {
    final p = _prefs;
    if (p == null) return;
    await p.setStringList(_kMine, _mine.keys.toList());
    await p.setString(_kMineCycles, json.encode(_mine));
    await p.setString(_kPending, json.encode(_pending));
    final c = _counts;
    if (c != null) await p.setString(_kCounts, json.encode(c));
    final cycle = _cycle;
    if (cycle != null) await p.setString(_kCycle, cycle);
    final max = _max;
    if (max != null) await p.setInt(_kMax, max);
  }
}
