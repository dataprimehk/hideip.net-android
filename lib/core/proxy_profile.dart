/// One parsed proxy server. Holds the sing-box outbound map plus display info.
///
/// [outbound] is a sing-box outbound object (e.g. {"type":"vless", ...}) WITHOUT
/// a "tag"; the tag is assigned by [SingboxConfig] when the full config is built,
/// so a profile can be reused under different tags. [name] is the human label
/// (from the link fragment or subscription), [protocol] the scheme (vless, etc.).
class ProxyProfile {
  final String name;
  final String protocol;
  final String server;
  final int port;
  final Map<String, dynamic> outbound;

  /// Supporting outbounds this profile's [outbound] depends on (e.g. a
  /// ShadowTLS outbound that the shadowsocks outbound detours into). These
  /// already carry their own "tag" and are added to the config as-is.
  final List<Map<String, dynamic>> extraOutbounds;

  /// Country code geolocated from [server] when the name reveals no location
  /// (most bare-IP links). Null until (and unless) that lookup succeeds.
  final String? cc;

  /// True for profiles managed by the hideip.net premium subscription (they
  /// came from the provisioning backend, not a user import). Managed profiles
  /// are replaced wholesale on refresh and removed when the subscription
  /// lapses; user imports are never touched.
  final bool premium;

  const ProxyProfile({
    required this.name,
    required this.protocol,
    required this.server,
    required this.port,
    required this.outbound,
    this.extraOutbounds = const [],
    this.cc,
    this.premium = false,
  });

  ProxyProfile copyWith({String? cc, bool? premium}) => ProxyProfile(
        name: name,
        protocol: protocol,
        server: server,
        port: port,
        outbound: outbound,
        extraOutbounds: extraOutbounds,
        cc: cc ?? this.cc,
        premium: premium ?? this.premium,
      );

  /// A copy of [outbound] with the given [tag] injected.
  Map<String, dynamic> taggedOutbound(String tag) => {
        'tag': tag,
        ...outbound,
      };

  @override
  String toString() => '$protocol://$server:$port ($name)';
}

/// Thrown when a share link cannot be parsed into a [ProxyProfile].
class ProfileParseException implements Exception {
  final String message;
  const ProfileParseException(this.message);
  @override
  String toString() => 'ProfileParseException: $message';
}
