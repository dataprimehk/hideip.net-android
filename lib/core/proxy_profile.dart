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

  const ProxyProfile({
    required this.name,
    required this.protocol,
    required this.server,
    required this.port,
    required this.outbound,
    this.extraOutbounds = const [],
  });

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
