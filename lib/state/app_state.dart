import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MissingPluginException;

import '../core/haptics.dart';
import '../core/ip_lookup.dart';
import '../core/location.dart';
import '../core/ping.dart';
import '../core/premium.dart';
import '../core/profile_store.dart';
import '../core/provisioning.dart';
import '../core/proxy_profile.dart';
import '../core/purchase_service.dart';
import '../core/share_link_parser.dart';
import '../core/singbox_config.dart';
import '../core/sub_info.dart';
import '../core/subscription.dart';
import '../core/ui_prefs.dart';
import '../core/user_subscription.dart';
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
  IpGeo? _userGeo;
  bool _ipLoading = false;
  Timer? _statusPoll;
  VpnStats _stats = VpnStats.zero;
  // Latency probes, keyed by "host:port". Absent = never tested.
  final Map<String, PingResult> _pings = {};
  bool _pinging = false;
  UiPrefs _prefs = const UiPrefs();
  final PurchaseService _purchases = PurchaseService();
  final ProvisioningService _provisioning = ProvisioningService();
  final UserSubscriptionService _userSubs = UserSubscriptionService();
  // Plan metadata (data used, expiry, provider name/links) keyed by
  // subscription URL, captured from the provider's response headers on refresh.
  final Map<String, SubInfo> _subInfos = {};
  Premium _premium = const Premium.none();
  String? _toast;
  Timer? _toastTimer;
  bool _ready = false;

  List<ProxyProfile> get profiles => List.unmodifiable(_profiles);
  int get selectedIndex => _selected;
  ProxyProfile? get selected =>
      (_selected >= 0 && _selected < _profiles.length) ? _profiles[_selected] : null;
  ConnState get conn => _conn;
  String? get error => _error;
  String? get publicIp => _publicIp;

  /// Where the user's real IP geolocates (the map's "you" pin). Only
  /// refreshed while the tunnel is down; with it up the public IP would
  /// geolocate to the exit node instead.
  IpGeo? get userGeo => _userGeo;
  bool get ipLoading => _ipLoading;
  bool get isConnected => _conn == ConnState.connected;
  bool get isBusy => _conn == ConnState.connecting;
  VpnStats get stats => _stats;
  bool get pinging => _pinging;
  PingResult? pingFor(ProxyProfile p) => _pings['${p.server}:${p.port}'];

  /// Plan metadata the provider sent for the subscription at [subUrl] (data
  /// used, expiry, panel link), or null when none was captured.
  SubInfo? subInfoFor(String subUrl) => _subInfos[subUrl];
  UiPrefs get prefs => _prefs;
  /// The current entitlement with expiry applied at read time. The persisted
  /// copy is only re-evaluated on launch, but a session can outlive the
  /// period (long-running app, or a clock that was behind at load); the real
  /// gate stays server-side receipt validation.
  Premium get premium {
    final r = _premium.renews;
    if (_premium.isOn && r != null && r.isBefore(DateTime.now())) {
      return Premium(
          status: PremiumStatus.expired, plan: _premium.plan, renews: r);
    }
    return _premium;
  }
  String? get toast => _toast;

  /// Whether Android's system Always-on VPN is enabled for this app (as last
  /// reported by the native service). With it on and [UiPrefs.alwaysOn] off,
  /// a disconnect can leave the OS holding traffic; the UI warns about that.
  bool get systemAlwaysOn => _systemAlwaysOn;
  bool _systemAlwaysOn = false;

  /// True once [init] has loaded persisted state (gates the first frame).
  bool get ready => _ready;

  /// Display-friendly view over [profiles], in the same order.
  List<Location> get locations => Location.deriveAll(_profiles);

  /// The location the tunnel would use right now. In auto mode this is the
  /// lowest-latency probed server (falling back to the persisted selection).
  Location? get activeLocation {
    final all = locations;
    if (all.isEmpty) return null;
    if (_prefs.autoSelect) {
      Location? best;
      int? bestMs;
      for (final l in all) {
        final ping = pingFor(l.profile);
        if (ping is PingOk && (bestMs == null || ping.ms < bestMs)) {
          bestMs = ping.ms;
          best = l;
        }
      }
      if (best != null) return best;
    }
    if (_selected >= 0 && _selected < all.length) return all[_selected];
    return all.first;
  }

  /// Signal level 0-4 for the ping bars.
  int levelFor(ProxyProfile p) {
    final ping = pingFor(p);
    if (ping is! PingOk) return 0;
    if (ping.ms < 60) return 4;
    if (ping.ms < 120) return 3;
    if (ping.ms < 250) return 2;
    return 1;
  }

  /// Load persisted state + initial IP. Call once at startup.
  Future<void> init() async {
    _prefs = await UiPrefs.load();
    // Keep the native side's copy of the Always-on opt-in current (the service
    // reads it on system-initiated starts, when no Dart is running).
    VpnController.setAlwaysOn(_prefs.alwaysOn);
    // Same for the kill switch: the native layer acts on it (on-drop
    // reconnect / on-demand rules) with no Dart in the loop.
    VpnController.setKillSwitch(_prefs.killSwitch);
    _premium = await Premium.load();
    iapLog('[iap] loaded: ${_premium.status.name} plan=${_premium.plan?.name}'
        ' renews=${_premium.renews} now=${DateTime.now()}');
    // The store is the source of truth: every entitlement it reports (a
    // purchase, a restore, a renewal from a previous session) lands here.
    _purchases.init(
      onPremium: (p, proof) {
        // The store replays past transactions in arbitrary order (a stale
        // renewal can land right after the newest one); an entitlement only
        // ever moves forward. Plan changes are safe under this rule: in a
        // subscription group the replacing transaction always starts at or
        // after the old one's period end.
        final held = _premium.renews;
        if (held != null && p.renews != null && p.renews!.isBefore(held)) {
          return;
        }
        _premium = p;
        notifyListeners();
        p.save();
        // Every live entitlement re-provisions: a first purchase creates the
        // server profile, a renewal extends its lifetime server-side.
        if (p.isOn && proof != null) _provisionPremium(proof);
      },
      // The catalog loads asynchronously; the paywall entry points are gated
      // on availability, so a rebuild has to follow when it flips.
      onAvailability: notifyListeners,
    );
    _profiles.addAll(await ProfileStore.load());
    _subInfos.addAll(await SubInfoStore.load());
    final savedIdx = await ProfileStore.loadSelectedIndex();
    if (savedIdx >= 0 && savedIdx < _profiles.length) _selected = savedIdx;
    // Keep the premium server profiles current (or drop them once the
    // subscription lapsed); fire-and-forget, list updates when it lands.
    _refreshPremiumProfiles();
    // Same for the user's own subscription imports: providers rotate servers
    // behind their URL, so re-pull each one.
    _refreshUserSubscriptions();
    _ready = true;
    notifyListeners();
    refreshIp();
    // Latency probes power the Auto choice and the signal bars.
    pingAll();
    _backfillGeo();
    // Reconcile with whatever the native service reports (e.g. after restart).
    // On a cold start we ignore a stale native error when nothing is running:
    // a leftover error from a previous session must not greet the user.
    _syncStatus(initial: true);
    if (_prefs.autoConnect && _profiles.isNotEmpty && !isConnected) {
      connect();
    }
  }

  // --- Premium -----------------------------------------------------------

  /// The store bridge, exposed for the paywall (live prices, availability,
  /// the store's message for a failed purchase).
  PurchaseService get purchases => _purchases;

  /// Whether to show any in-app plans entry point right now. True once the
  /// store catalog is confirmed purchasable, or whenever the user already has
  /// a subscription (their Premium status stays reachable even if the catalog
  /// is momentarily unavailable). False keeps every paywall entry point hidden
  /// so the app never advertises a purchase it cannot complete, e.g. before
  /// the Play products exist. Gated further by [kPlansAvailable] at each site.
  bool get plansOffered => _purchases.available || premium.isOn;

  /// [PlanInfo] for [plan] with the store's localized price once the catalog
  /// has loaded; before that the USD fallback.
  PlanInfo planInfo(PremiumPlan plan) {
    final price = _purchases.priceOf(plan);
    final base = PlanInfo.of(plan);
    return price == null ? base : base.withPrice(price);
  }

  /// Buy the Premium subscription. The entitlement itself lands through the
  /// purchase stream (see [init]); this reports how the attempt ended.
  Future<PurchaseOutcome> purchasePremium(PremiumPlan plan) =>
      _purchases.buy(plan);

  /// Re-check the store for an existing subscription.
  Future<void> restorePurchases() async {
    final restored = await _purchases.restore();
    showToast(restored ? 'Purchases restored' : 'No purchases to restore');
  }

  /// Exchange the signed purchase proof for tunnel credentials and pull the
  /// premium profiles in. Every step is retried on the next launch (or the
  /// next store event) if it fails here, so errors stay silent.
  Future<void> _provisionPremium(PurchasePayload proof) async {
    await PremiumSub.saveProof(proof);
    final url = await _provisioning.provision(proof);
    if (url == null) return;
    await PremiumSub.saveUrl(url);
    final fresh = await _provisioning.fetchProfiles(url);
    if (fresh != null && fresh.isNotEmpty) {
      _applyPremiumProfiles(fresh);
      iapLog('[iap] provisioned: ${fresh.length} profile(s)');
    }
  }

  /// On launch: re-fetch premium profiles while the subscription lives (the
  /// server may rotate keys or add locations), retry a provision that never
  /// completed, and clear the managed profiles once the subscription lapsed.
  Future<void> _refreshPremiumProfiles() async {
    if (!premium.isOn) {
      if (premium.status == PremiumStatus.expired &&
          _profiles.any(isPremiumProfile)) {
        _applyPremiumProfiles(const []);
        await PremiumSub.clear();
        iapLog('[iap] premium lapsed: managed profiles removed');
      }
      return;
    }
    final url = await PremiumSub.url();
    if (url == null) {
      final proof = await PremiumSub.proof();
      if (proof != null) await _provisionPremium(proof);
      return;
    }
    final fresh = await _provisioning.fetchProfiles(url);
    if (fresh == null) return; // transient failure: keep what we have
    if (fresh.isEmpty && !_profiles.any(isPremiumProfile)) return;
    _applyPremiumProfiles(fresh);
  }

  /// Swap the managed premium profiles for [fresh], preserving the user's
  /// own profiles and, when possible, the current selection.
  void _applyPremiumProfiles(List<ProxyProfile> fresh) {
    _applyMerged(mergePremiumProfiles(_profiles, fresh));
  }

  // --- User subscriptions --------------------------------------------------

  /// On launch: re-pull every subscription URL the user has imported and swap
  /// in the fresh server lists (providers rotate servers behind their URL).
  /// A transient failure keeps the current servers; only a definitive 404/410
  /// clears a group, since the provider retired that link.
  Future<void> _refreshUserSubscriptions() async {
    for (final url in userSubUrls(_profiles)) {
      final result = await _userSubs.fetch(url);
      if (result == null) continue; // transient failure: keep what we have
      if (result.info != null) {
        _subInfos[url] = result.info!;
        await SubInfoStore.put(url, result.info!);
        notifyListeners();
      }
      _applyMerged(mergeUserSubProfiles(_profiles, url, result.profiles));
    }
  }

  /// Replace the profile list with [merged], preserving the current selection
  /// when its profile survived the merge.
  void _applyMerged(List<ProxyProfile> merged) {
    final sel = selected;
    _profiles
      ..clear()
      ..addAll(merged);
    _selected = sel == null ? -1 : _profiles.indexOf(sel);
    if (_selected < 0 && _profiles.isNotEmpty) _selected = 0;
    _persist();
    notifyListeners();
    pingAll();
    _backfillGeo();
  }

  // --- UI preferences / toast --------------------------------------------

  Future<void> updatePrefs(UiPrefs next) async {
    final alwaysOnChanged = next.alwaysOn != _prefs.alwaysOn;
    final killSwitchChanged = next.killSwitch != _prefs.killSwitch;
    _prefs = next;
    notifyListeners();
    await next.save();
    if (alwaysOnChanged) await VpnController.setAlwaysOn(next.alwaysOn);
    if (killSwitchChanged) await VpnController.setKillSwitch(next.killSwitch);
  }

  void showToast(String message) {
    _toast = message;
    notifyListeners();
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(milliseconds: 2400), () {
      _toast = null;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _statusPoll?.cancel();
    _toastTimer?.cancel();
    _purchases.dispose();
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
    _backfillGeo();
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
      _backfillGeo();
    }
    return res;
  }

  /// Add pre-parsed profiles (the redesign import screen parses before
  /// committing, so the user can review what was detected first).
  Future<void> addProfiles(List<ProxyProfile> newProfiles,
      {bool select = false}) async {
    if (newProfiles.isEmpty) return;
    final sel = selected;
    // Re-importing a subscription the list already holds must replace its
    // group, not stack a second copy of every server next to the first.
    final subUrls = {
      for (final p in newProfiles)
        if (p.subUrl != null) p.subUrl!,
    };
    if (subUrls.isNotEmpty) {
      _profiles.removeWhere((p) => !p.premium && subUrls.contains(p.subUrl));
    }
    _profiles.addAll(newProfiles);
    // A subscription import may have just written fresh SubInfo to the store
    // (import screen does this directly); pull it in so its plan row shows now.
    if (subUrls.isNotEmpty) {
      _subInfos.addAll(await SubInfoStore.load());
    }
    if (select || _selected < 0) {
      _selected = _profiles.length - newProfiles.length;
      await updatePrefs(_prefs.copyWith(autoSelect: false));
    } else {
      // The removal above may have shifted (or removed) the selected profile.
      _selected = sel == null ? -1 : _profiles.indexOf(sel);
      if (_selected < 0 && _profiles.isNotEmpty) _selected = 0;
    }
    await _persist();
    notifyListeners();
    pingAll();
    _backfillGeo();
  }

  /// Fill in country codes for profiles whose name reveals no location by
  /// geolocating the server address. Fire-and-forget: rows silently gain
  /// their flag (and map pin) when an answer arrives, and profiles that
  /// cannot be resolved right now are retried on the next app start.
  Future<void> _backfillGeo() async {
    for (final p in [..._profiles]) {
      if (p.cc != null) continue;
      final idx = _profiles.indexOf(p);
      if (idx < 0) continue;
      if (Location.derive(p, idx).cc != '··') continue;
      final cc = await IpLookup.countryFor(p.server);
      if (cc == null) continue;
      // The list may have shifted while the lookup was in flight.
      final at = _profiles.indexOf(p);
      if (at < 0) continue;
      _profiles[at] = p.copyWith(cc: cc);
      await _persist();
      notifyListeners();
    }
  }

  /// Explicitly pick a server (turns Auto off), or pass null for Auto.
  Future<void> selectLocation(Location? loc) async {
    if (loc == null) {
      await updatePrefs(_prefs.copyWith(autoSelect: true));
      Haptics.selection();
      return;
    }
    await updatePrefs(_prefs.copyWith(autoSelect: false));
    await select(loc.index);
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
    // Auto mode resolves to the best probed server; otherwise the selection.
    final profile = activeLocation?.profile ?? selected;
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
      final config =
          SingboxConfig.buildJson(profile, killSwitch: _prefs.killSwitch);
      await VpnController.start(config, label: profile.name);
      _startStatusPoll();
      // Optimistic; the poll will confirm/flip to error.
      _conn = ConnState.connected;
      Haptics.success();
      notifyListeners();
      _refreshIpAfterToggle();
    } on MissingPluginException {
      // No native VPN side on this platform yet (iOS before the PacketTunnel
      // port). Keep the rest of the app usable; only connecting is off-limits.
      _setError('VPN is not yet supported on this platform.');
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
    _refreshIpAfterToggle();
  }

  /// Connect/disconnect flips the route table a moment AFTER the platform
  /// call returns (on iOS the extension boots asynchronously), so a single
  /// immediate lookup usually still travels the old path and shows the old
  /// address. Poll until the address actually changes, then stop; give up
  /// quietly after a few attempts so a flaky lookup can't spin forever.
  Future<void> _refreshIpAfterToggle() async {
    final before = _publicIp;
    for (var attempt = 0; attempt < 6; attempt++) {
      await refreshIp();
      if (_publicIp != null && _publicIp != before) return;
      await Future<void>.delayed(const Duration(milliseconds: 1500));
    }
  }

  Future<void> refreshIp() async {
    _ipLoading = true;
    notifyListeners();
    final ip = await IpLookup.current();
    _publicIp = ip;
    _ipLoading = false;
    notifyListeners();
    if (!isConnected) {
      final geo = await IpLookup.locate();
      if (geo != null && !isConnected) {
        _userGeo = geo;
        notifyListeners();
      }
    }
  }

  // --- internals -------------------------------------------------------------

  void _startStatusPoll() {
    _statusPoll?.cancel();
    _statusPoll = Timer.periodic(const Duration(seconds: 2), (_) => _syncStatus());
  }

  Future<void> _syncStatus({bool initial = false}) async {
    final s = await VpnController.status();
    if (s.alwaysOn != _systemAlwaysOn) {
      _systemAlwaysOn = s.alwaysOn;
      notifyListeners();
    }
    if (s.error != null && s.error!.isNotEmpty) {
      // On the initial cold-start reconcile, a native error while nothing is
      // running is stale (left over from a previous session); discard it.
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
