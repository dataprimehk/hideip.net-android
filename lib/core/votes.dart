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
///   GET  {endpoint}                       -> 200 {"votes": {"RS": 141, ...}}
///   POST {endpoint} {"country":"RS","vote":true}  -> 200 {"country":"RS","votes":142}
///
/// The service is fully usable before the backend exists: a vote lands in
/// local storage immediately and queues for sync, and vote counts only render
/// once the server has answered at least once (no invented numbers).
class VoteService extends ChangeNotifier {
  VoteService._();
  static final VoteService instance = VoteService._();

  /// Planned endpoint on the site; not live yet. Every network failure is
  /// silent and retried on the next refresh.
  static const endpoint = 'https://hideip.net/api/votes';

  static const _kMine = 'votes_mine_v1';
  static const _kPending = 'votes_pending_v1';
  static const _kCounts = 'votes_counts_v1';

  SharedPreferences? _prefs;
  final Set<String> _mine = {};
  final Map<String, bool> _pending = {};
  Map<String, int>? _counts; // null until the server has ever answered
  bool _refreshing = false;

  /// Test hook: inject an http client; null uses a fresh default client.
  @visibleForTesting
  http.Client? clientOverride;

  /// The map's "tap a country to vote" hint stays up until the first vote is
  /// cast; retracting every vote brings it back. Derived, not a stored flag,
  /// so it self-corrects across installs and upgrades.
  bool get hintDismissed => _mine.isNotEmpty;
  bool hasVoted(String cc) => _mine.contains(cc);

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

  /// The countries this install has voted for.
  Set<String> get mine => Set.unmodifiable(_mine);

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

  Future<void> init() async {
    if (_prefs != null) {
      unawaited(refresh());
      return;
    }
    final p = _prefs = await SharedPreferences.getInstance();
    _mine
      ..clear()
      ..addAll(p.getStringList(_kMine) ?? const []);
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
  Future<void> toggle(String cc) async {
    final voting = !_mine.contains(cc);
    if (voting) {
      _mine.add(cc);
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
        final vote = _pending[cc]!;
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
    await p.setStringList(_kMine, _mine.toList());
    await p.setString(_kPending, json.encode(_pending));
    final c = _counts;
    if (c != null) await p.setString(_kCounts, json.encode(c));
  }
}
