import 'dart:convert';

/// One WireGuard server the subscription can exit through.
class WgServer {
  final String serverId;
  final String label;
  final String countryCode;
  final String city;
  final String host;
  final int port;
  final String serverPubkey;

  const WgServer({
    required this.serverId,
    required this.label,
    required this.countryCode,
    required this.city,
    required this.host,
    required this.port,
    required this.serverPubkey,
  });

  static WgServer? tryParse(Map<String, dynamic> m) {
    final host = m['host'] as String?;
    final port = (m['port'] as num?)?.toInt();
    final pubkey = m['server_pubkey'] as String?;
    if (host == null || host.isEmpty) return null;
    if (port == null || port <= 0 || port > 65535) return null;
    if (pubkey == null || pubkey.isEmpty) return null;
    return WgServer(
      serverId: m['server_id'] as String? ?? '',
      label: m['label'] as String? ?? '',
      countryCode: m['country_code'] as String? ?? '',
      city: m['city'] as String? ?? '',
      host: host,
      port: port,
      serverPubkey: pubkey,
    );
  }

  Map<String, dynamic> toJson() => {
        'server_id': serverId,
        'label': label,
        'country_code': countryCode,
        'city': city,
        'host': host,
        'port': port,
        'server_pubkey': serverPubkey,
      };

  @override
  String toString() => 'WgServer($label $host:$port)';
}

/// The WireGuard profile the backend issued for this device's public key: the
/// `POST /v1/wg/register` response, cached locally.
///
/// This is per-device by design, which is why it does not travel through
/// `/v1/sub` with the stealth profiles: the subscription token is shared across
/// a subscriber's devices, but a WireGuard peer is one key on one device.
class WgProfile {
  /// The tunnel address assigned to this device, e.g. "10.66.0.10/32".
  final String address;
  final List<String> dns;
  final int mtu;
  final int persistentKeepalive;
  final List<String> allowedIps;
  final List<WgServer> servers;

  /// When this profile was fetched, used only to show staleness in Advanced
  /// view; the register call is idempotent so refreshing is always safe.
  final DateTime fetchedAt;

  const WgProfile({
    required this.address,
    required this.dns,
    required this.mtu,
    required this.persistentKeepalive,
    required this.allowedIps,
    required this.servers,
    required this.fetchedAt,
  });

  bool get isUsable => address.isNotEmpty && servers.isNotEmpty;

  /// Parse a register response per CONTRACTS-FLEET.md section 2. Returns null
  /// when the payload is missing the parts a tunnel cannot be built without.
  ///
  /// The MTU is deliberately NOT taken at face value: see [effectiveMtu].
  static WgProfile? tryParse(Map<String, dynamic> m, {DateTime? at}) {
    final address = m['address'] as String?;
    if (address == null || address.isEmpty) return null;
    final servers = (m['servers'] as List?)
            ?.whereType<Map>()
            .map((e) => WgServer.tryParse(e.cast<String, dynamic>()))
            .whereType<WgServer>()
            .toList() ??
        const <WgServer>[];
    if (servers.isEmpty) return null;
    return WgProfile(
      address: address,
      dns: (m['dns'] as List?)?.whereType<String>().toList() ??
          const ['1.1.1.1', '1.0.0.1'],
      mtu: (m['mtu'] as num?)?.toInt() ?? wgMtu,
      persistentKeepalive:
          (m['persistent_keepalive'] as num?)?.toInt() ?? 25,
      allowedIps: (m['allowed_ips'] as List?)?.whereType<String>().toList() ??
          const ['0.0.0.0/0', '::/0'],
      servers: servers,
      fetchedAt: at ?? DateTime.now(),
    );
  }

  /// The MTU the tunnel actually uses.
  ///
  /// Hard-capped at [wgMtu] whatever the backend says. This is the same
  /// expensive lesson the TUN inbound already carries: an MTU sized for the
  /// physical link leaves no room for encapsulation, so large packets are
  /// silently dropped somewhere in the middle of the path. Small HTTP requests
  /// still pass, which makes it look like the tunnel works, but HTTPS bursts
  /// and speed tests stall. 1280 is the IPv6 minimum, so it traverses every
  /// network (DSL/PPPoE, cellular, double NAT) with headroom left for the
  /// WireGuard header on top.
  int get effectiveMtu => mtu <= 0 || mtu > wgMtu ? wgMtu : mtu;

  Map<String, dynamic> toJson() => {
        'address': address,
        'dns': dns,
        'mtu': mtu,
        'persistent_keepalive': persistentKeepalive,
        'allowed_ips': allowedIps,
        'servers': servers.map((s) => s.toJson()).toList(),
        'fetched_at': fetchedAt.millisecondsSinceEpoch,
      };

  static WgProfile? fromJson(Map<String, dynamic> m) {
    final ms = (m['fetched_at'] as num?)?.toInt();
    return tryParse(
      m,
      at: ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms),
    );
  }

  static String encode(WgProfile p) => jsonEncode(p.toJson());

  static WgProfile? decode(String raw) {
    try {
      return fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}

/// The tunnel MTU for WireGuard, for the reason spelled out in
/// [WgProfile.effectiveMtu]. Never raise this without re-testing large-packet
/// throughput on a mobile network and a PPPoE line.
const int wgMtu = 1280;
