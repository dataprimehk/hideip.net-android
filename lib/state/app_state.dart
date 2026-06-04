import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/haptics.dart';
import '../core/ip_lookup.dart';
import '../core/ping.dart';
import '../core/profile_store.dart';
import '../core/proxy_profile.dart';
import '../core/share_link_parser.dart';
import '../core/singbox_config.dart';
import '../core/subscription.dart';
import '../vpn_controller.dart';

enum ConnState { disconnected, connecting, connected, error }

/// Single source of truth for the UI: holds the profile list, the selected
/// profile, the connection state, the current public IP, and bridges the
/// parser/config to [VpnController]. Backed by [ProfileStore] for persistence.
class AppState extends ChangeNotifier {
  final List<ProxyProfile> _profiles = [];
  int _selected = -1;
  ConnState _conn = ConnState.disconnected;
  String? _error;
  String? _publicIp;
  bool _ipLoading = false;
  Timer? _statusPoll;
  VpnStats _stats = VpnStats.zero;
  // Latency probes, keyed by "host:port". Absent = never tested.
  final Map<String, PingResult> _pings = {};
  bool _pinging = false;

  List<ProxyProfile> get profiles => List.unmodifiable(_profiles);
  int get selectedIndex => _selected;
  ProxyProfile? get selected =>
      (_selected >= 0 && _selected < _profiles.length) ? _profiles[_selected] : null;
  ConnState get conn => _conn;
  String? get error => _error;
  String? get publicIp => _publicIp;
  bool get ipLoading => _ipLoading;
  bool get isConnected => _conn == ConnState.connected;
  bool get isBusy => _conn == ConnState.connecting;
  VpnStats get stats => _stats;
  bool get pinging => _pinging;
  PingResult? pingFor(ProxyProfile p) => _pings['${p.server}:${p.port}'];

  /// Load persisted state + initial IP. Call once at startup.
  Future<void> init() async {
    _profiles.addAll(await ProfileStore.load());
    final savedIdx = await ProfileStore.loadSelectedIndex();
    if (savedIdx >= 0 && savedIdx < _profiles.length) _selected = savedIdx;
    notifyListeners();
    refreshIp();
    // Reconcile with whatever the native service reports (e.g. after restart).
    // On a cold start we ignore a stale native error when nothing is running:
    // a leftover error from a previous session must not greet the user.
    _syncStatus(initial: true);
  }

  @override
  void dispose() {
    _statusPoll?.cancel();
    super.dispose();
  }

  // --- Profile management ----------------------------------------------------

  /// Add a single share link. Throws [ProfileParseException] on bad input.
  Future<void> addLink(String link) async {
    final p = ShareLinkParser.parse(link);
    if (p == null) throw const ProfileParseException('Empty or comment line');
    _profiles.add(p);
    if (_selected < 0) _selected = 0;
    await _persist();
    notifyListeners();
  }

  /// Import a subscription body (base64 blob or newline links). Returns the
  /// result so the UI can report how many were added and what failed.
  Future<SubscriptionResult> addSubscription(String body) async {
    final res = Subscription.parse(body);
    if (res.profiles.isNotEmpty) {
      _profiles.addAll(res.profiles);
      if (_selected < 0) _selected = 0;
      await _persist();
      notifyListeners();
    }
    return res;
  }

  Future<void> select(int index) async {
    if (index < 0 || index >= _profiles.length) return;
    if (index != _selected) Haptics.selection();
    _selected = index;
    // Picking a server clears any prior error (e.g. "select a server first").
    if (_error != null && _conn != ConnState.connecting) {
      _error = null;
      if (_conn == ConnState.error) _conn = ConnState.disconnected;
    }
    await ProfileStore.saveSelectedIndex(_selected);
    notifyListeners();
  }

  Future<void> remove(int index) async {
    if (index < 0 || index >= _profiles.length) return;
    _profiles.removeAt(index);
    if (_selected == index) {
      _selected = _profiles.isEmpty ? -1 : 0;
    } else if (_selected > index) {
      _selected -= 1;
    }
    await _persist();
    notifyListeners();
  }

  // --- Latency ---------------------------------------------------------------

  /// Probes every server's TCP latency concurrently and updates the UI as each
  /// result lands. No-op while a probe run is already in flight.
  Future<void> pingAll() async {
    if (_pinging || _profiles.isEmpty) return;
    _pinging = true;
    notifyListeners();
    await Future.wait(_profiles.map((p) async {
      final key = '${p.server}:${p.port}';
      final result = await Ping.measure(p.server, p.port);
      _pings[key] = result;
      notifyListeners();
    }));
    _pinging = false;
    notifyListeners();
  }

  // --- Connection ------------------------------------------------------------

  Future<void> connect() async {
    final profile = selected;
    if (profile == null) {
      _setError('Select a server first.');
      return;
    }
    _conn = ConnState.connecting;
    _error = null;
    notifyListeners();

    try {
      // The OS consent dialog returns via the platform channel. Guard against a
      // dropped/never-delivered result so the UI can't get stuck "Connecting…".
      final ok = await VpnController.prepare()
          .timeout(const Duration(seconds: 60), onTimeout: () => false);
      if (!ok) {
        // User cancelled consent (or it timed out): return to a clean state.
        _conn = ConnState.disconnected;
        _error = null;
        notifyListeners();
        return;
      }
      final config = SingboxConfig.buildJson(profile);
      await VpnController.start(config, label: profile.name);
      _startStatusPoll();
      // Optimistic; the poll will confirm/flip to error.
      _conn = ConnState.connected;
      Haptics.success();
      notifyListeners();
      refreshIp();
    } catch (e) {
      _setError('Failed to connect: $e');
    }
  }

  Future<void> disconnect() async {
    try {
      await VpnController.stop();
    } catch (_) {
      // best-effort; report state from poll
    }
    _statusPoll?.cancel();
    _conn = ConnState.disconnected;
    _error = null;
    notifyListeners();
    refreshIp();
  }

  Future<void> refreshIp() async {
    _ipLoading = true;
    notifyListeners();
    final ip = await IpLookup.current();
    _publicIp = ip;
    _ipLoading = false;
    notifyListeners();
  }

  // --- internals -------------------------------------------------------------

  void _startStatusPoll() {
    _statusPoll?.cancel();
    _statusPoll = Timer.periodic(const Duration(seconds: 2), (_) => _syncStatus());
  }

  Future<void> _syncStatus({bool initial = false}) async {
    final s = await VpnController.status();
    if (s.error != null && s.error!.isNotEmpty) {
      // On the initial cold-start reconcile, a native error while nothing is
      // running is stale (left over from a previous session) — discard it.
      if (initial && !s.running) return;
      _setError(s.error!);
      _statusPoll?.cancel();
      return;
    }
    final newState = s.running ? ConnState.connected : ConnState.disconnected;
    if (newState != _conn && _conn != ConnState.connecting) {
      _conn = newState;
      if (newState == ConnState.connected) {
        Haptics.success();
        _startStatusPoll();
      }
      if (newState == ConnState.disconnected) {
        _statusPoll?.cancel();
        _stats = VpnStats.zero;
      }
      notifyListeners();
      refreshIp();
    }

    // While connected, refresh live traffic counters each tick.
    if (_conn == ConnState.connected) {
      _stats = await VpnController.stats();
      notifyListeners();
    }
  }

  void _setError(String msg) {
    _conn = ConnState.error;
    _error = msg;
    Haptics.error();
    notifyListeners();
  }

  Future<void> _persist() async {
    await ProfileStore.save(_profiles);
    await ProfileStore.saveSelectedIndex(_selected);
  }
}
