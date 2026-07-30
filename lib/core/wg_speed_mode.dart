import 'wg_profile.dart';

/// Which path the tunnel is taking right now.
enum TunnelPath {
  /// The stealth profile: VLESS/Reality and friends, the default.
  stealth,

  /// WireGuard, chosen because Speed mode is on and the network allows it.
  speed,
}

/// Why Speed mode is not currently in use. Drives one quiet status line; none
/// of these are errors the user has to act on, because the stealth tunnel is
/// up and working in every one of them.
enum SpeedFallbackReason {
  /// Speed mode is off in settings.
  off,

  /// Speed mode is on and WireGuard is carrying the traffic.
  none,

  /// No subscription, so no WireGuard profile to use.
  noSubscription,

  /// Register has not returned a usable profile yet (first run, or offline).
  noProfile,

  /// The handshake did not complete in time on this network: WireGuard's UDP
  /// is being blocked or throttled. The common real-world case.
  blocked,

  /// The subscription already has five devices registered.
  deviceLimit,
}

/// The one-line status the home screen shows under the connection state.
/// Deliberately understated: Speed mode is a bonus, and falling back to the
/// stealth tunnel is the app working as designed, not a failure.
String? speedStatusLine(TunnelPath path, SpeedFallbackReason reason) {
  if (path == TunnelPath.speed) return 'speed mode';
  return switch (reason) {
    SpeedFallbackReason.blocked => 'stealth fallback',
    SpeedFallbackReason.deviceLimit => 'stealth fallback',
    SpeedFallbackReason.noProfile => 'stealth fallback',
    SpeedFallbackReason.off ||
    SpeedFallbackReason.none ||
    SpeedFallbackReason.noSubscription =>
      null,
  };
}

/// Decides whether a connect attempt should try WireGuard first.
///
/// Every "no" here is a silent fall through to the stealth profile: the rule
/// for this feature is that WireGuard may only ever be an upgrade, never a
/// regression, so anything unclear resolves to stealth.
class SpeedModeDecision {
  final bool useWireGuard;
  final SpeedFallbackReason reason;
  final WgServer? server;

  const SpeedModeDecision({
    required this.useWireGuard,
    required this.reason,
    this.server,
  });

  static const SpeedModeDecision _no = SpeedModeDecision(
      useWireGuard: false, reason: SpeedFallbackReason.off);

  /// [enabled] is the user's Speed mode preference, [profile] the cached
  /// register response, [premium] whether a subscription is live, and
  /// [blockedHere] whether WireGuard already failed to hand shake on this
  /// network (see [WgHandshakeMemory]).
  ///
  /// [preferredCountry] is the country code of the location the user picked in
  /// the app, so Speed mode exits through the same place the stealth tunnel
  /// would rather than teleporting the user somewhere else when they toggle it.
  static SpeedModeDecision decide({
    required bool enabled,
    required bool premium,
    required WgProfile? profile,
    bool blockedHere = false,
    String? preferredCountry,
    bool deviceLimited = false,
  }) {
    if (!enabled) return _no;
    if (!premium) {
      return const SpeedModeDecision(
          useWireGuard: false, reason: SpeedFallbackReason.noSubscription);
    }
    if (deviceLimited) {
      return const SpeedModeDecision(
          useWireGuard: false, reason: SpeedFallbackReason.deviceLimit);
    }
    if (profile == null || !profile.isUsable) {
      return const SpeedModeDecision(
          useWireGuard: false, reason: SpeedFallbackReason.noProfile);
    }
    if (blockedHere) {
      return const SpeedModeDecision(
          useWireGuard: false, reason: SpeedFallbackReason.blocked);
    }
    final server = pickServer(profile.servers, preferredCountry);
    if (server == null) {
      return const SpeedModeDecision(
          useWireGuard: false, reason: SpeedFallbackReason.noProfile);
    }
    return SpeedModeDecision(
        useWireGuard: true,
        reason: SpeedFallbackReason.none,
        server: server);
  }

  /// Choose which WireGuard server to exit through.
  ///
  /// The app's existing server picker ranks stealth profiles by measured TCP
  /// latency, which cannot be reused here: those probes connect to the stealth
  /// TCP port, while WireGuard listens on UDP on a different port, and a UDP
  /// probe from Dart would need a socket the app does not otherwise open.
  /// So the rule is to match the location the user already chose, by country,
  /// and otherwise take the first server the backend listed. The backend
  /// controls that order (`sort_weight`), which makes server preference a
  /// server-side decision rather than a guess baked into the client.
  static WgServer? pickServer(List<WgServer> servers, String? preferredCountry) {
    if (servers.isEmpty) return null;
    final want = preferredCountry?.toUpperCase();
    if (want != null && want.isNotEmpty) {
      for (final s in servers) {
        if (s.countryCode.toUpperCase() == want) return s;
      }
    }
    return servers.first;
  }
}

/// Remembers which networks WireGuard could not hand shake on.
///
/// Detection, and why it is shaped this way: sing-box does not report a
/// WireGuard handshake result over the app's method channel, and adding that
/// would mean touching both native layers. What the channel already exposes is
/// live byte counters ([VpnController.stats]) and a running flag. A WireGuard
/// tunnel that cannot hand shake behaves distinctly under those: the interface
/// comes up (so `running` is true and the UI would say "Connected") but not one
/// byte ever arrives, because the peer's reply is what carries the first
/// downlink bytes. A working tunnel, by contrast, has downlink traffic within a
/// second or two of any activity, and the app's own IP lookup generates that
/// activity immediately on connect.
///
/// So the probe is: bring WireGuard up, and if the downlink counter is still
/// zero after [probeWindow], call it blocked, tear it down, and reconnect on
/// the stealth profile. The uplink counter is ignored on purpose, since a
/// blocked tunnel still shows uplink bytes (we keep sending handshake
/// initiations into the void), which is exactly what makes downlink the
/// reliable signal.
///
/// The verdict is remembered per network so the next connect on a network
/// already known to block WireGuard goes straight to stealth instead of
/// spending the probe window again. It is keyed by a caller-supplied network
/// id, and it is a cache, not a permanent judgement: it lives in memory only,
/// so relaunching the app re-tests every network, and a network that starts
/// allowing WireGuard is picked up on the next launch.
class WgHandshakeMemory {
  /// How long a WireGuard tunnel gets to show inbound traffic before it is
  /// judged blocked. Long enough for a slow mobile network to complete a
  /// handshake and a DNS round trip, short enough that the user reads it as
  /// part of connecting rather than a stall.
  static const Duration probeWindow = Duration(seconds: 6);

  final Set<String> _blocked = <String>{};

  bool isBlocked(String? networkId) =>
      networkId != null && _blocked.contains(networkId);

  void markBlocked(String? networkId) {
    if (networkId != null) _blocked.add(networkId);
  }

  void markWorking(String? networkId) {
    if (networkId != null) _blocked.remove(networkId);
  }

  void clear() => _blocked.clear();

  /// Whether the counters seen after [probeWindow] mean the handshake failed.
  /// Downlink only, for the reason in the class doc.
  static bool looksBlocked({required int downlinkTotal}) => downlinkTotal <= 0;
}
