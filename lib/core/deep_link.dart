// Parses an incoming `hideip://` deep link into the text the import screen
// should be prefilled with, plus an optional display name.
//
// Two conventions both work (the two dominant ones among proxy clients):
//
//  1. Path-append style: `hideip://import/<raw-url-or-share-link>`.
//     Everything after `import/` is taken verbatim; it may itself be an
//     https subscription URL or a `vless://...` share link. An optional URL
//     fragment `#<name>` carries a display name.
//
//  2. Query style: `hideip://install-config?url=<urlencoded>&name=<optional>`.
//
// Pure and platform-free so it can be unit-tested without platform channels.

/// The result of parsing a deep link: the raw text to hand the importer, and
/// an optional human name a seller attached.
class DeepLinkImport {
  /// The import text: an https subscription URL, a `scheme://` share link, or
  /// a subscription blob. Never empty.
  final String text;

  /// Optional display name (from `name=` or a `#fragment`), or null.
  final String? name;

  const DeepLinkImport(this.text, this.name);

  @override
  bool operator ==(Object other) =>
      other is DeepLinkImport && other.text == text && other.name == name;

  @override
  int get hashCode => Object.hash(text, name);

  @override
  String toString() => 'DeepLinkImport(text: $text, name: $name)';
}

/// A device-link request read off a QR code or an incoming
/// `hideip://link?v=1&id=<link_id>` deep link. The id is the only thing the QR
/// carries: it is public by design, and approving it grants access rather than
/// taking any, so a photographed code gives an attacker nothing.
class DeepLinkPairing {
  /// The backend's link id, handed straight back to `/v1/link/approve`.
  final String linkId;

  const DeepLinkPairing(this.linkId);

  @override
  bool operator ==(Object other) =>
      other is DeepLinkPairing && other.linkId == linkId;

  @override
  int get hashCode => linkId.hashCode;

  @override
  String toString() => 'DeepLinkPairing(linkId: $linkId)';
}

/// Turns a `hideip://link?v=1&id=…` string into a [DeepLinkPairing], or null
/// for anything else (an import link, another scheme, or a link with no id).
///
/// Version tolerance: `v` is accepted when absent or `1`. A future version
/// carries a payload this build cannot be trusted to understand, so it is
/// refused rather than approved blind.
DeepLinkPairing? parsePairingLink(String raw) {
  final input = raw.trim();
  if (input.isEmpty) return null;

  final uri = Uri.tryParse(input);
  if (uri == null || uri.scheme.toLowerCase() != 'hideip') return null;
  if (_action(uri) != 'link') return null;

  final version = uri.queryParameters['v']?.trim();
  if (version != null && version.isNotEmpty && version != '1') return null;

  final id = uri.queryParameters['id']?.trim() ?? '';
  if (id.isEmpty) return null;
  return DeepLinkPairing(id);
}

/// The action a hideip link names: the host, or the first path segment when a
/// launcher normalized `hideip://x` down to `hideip:/x`.
String _action(Uri uri) {
  final host = uri.host.toLowerCase();
  if (host.isNotEmpty) return host;
  final segments = uri.pathSegments;
  return segments.isNotEmpty ? segments.first.toLowerCase() : '';
}

/// Turns a `hideip://` deep-link string into a [DeepLinkImport], or returns
/// null for anything that is not a recognized hideip link or carries no
/// usable payload.
DeepLinkImport? parseDeepLink(String raw) {
  final input = raw.trim();
  if (input.isEmpty) return null;

  final uri = Uri.tryParse(input);
  if (uri == null || uri.scheme.toLowerCase() != 'hideip') return null;

  // The action is the host or the first path segment, whichever carries it:
  // `hideip://import/...` gives host=import, while some launchers normalize to
  // `hideip:/import/...` giving an empty host and a leading path segment.
  switch (_action(uri)) {
    case 'install-config':
    case 'add':
    case 'import' when uri.hasQuery && (uri.queryParameters['url'] ?? '').isNotEmpty:
      // Query style: url= carries the payload, name= the optional label.
      final url = uri.queryParameters['url']?.trim() ?? '';
      if (url.isEmpty) return null;
      final name = _clean(uri.queryParameters['name']);
      return DeepLinkImport(url, name);

    case 'import':
      // Path-append style: take everything after `import/` verbatim. The
      // remainder can be a full https:// URL or a scheme:// share link whose
      // own `?query` and `#fragment` must survive intact, so slice the
      // original string rather than trusting Uri's decoded path (which would
      // consume the share link's fragment as this link's fragment).
      final text = _pathRemainder(input);
      if (text == null || text.isEmpty) return null;
      // A trailing `#name` only applies when the payload is not itself a
      // share link carrying its own fragment (share links keep everything).
      final split = _splitTrailingName(text);
      return DeepLinkImport(split.$1, split.$2);

    default:
      return null;
  }
}

/// Everything after the `import/` marker in the raw link, still URL-encoded as
/// the sender wrote it. Handles both `hideip://import/...` (host is `import`)
/// and the `hideip:/import/...` path-only normalization some launchers emit.
String? _pathRemainder(String raw) {
  const marker = 'import/';
  final lower = raw.toLowerCase();
  final schemeEnd = lower.indexOf('hideip:');
  if (schemeEnd < 0) return null;
  final at = lower.indexOf(marker, schemeEnd);
  if (at < 0) return null;
  var rest = raw.substring(at + marker.length);
  // Percent-decode the payload: senders url-encode a whole https/vless link so
  // its `:` `/` `?` `#` do not confuse the outer hideip URI. Decode once; if it
  // was not encoded (already a bare link) decoding is a harmless no-op on the
  // link body.
  rest = _tryDecode(rest);
  return rest.trim();
}

/// Splits a trailing `#name` off a payload, but only when the payload does not
/// look like a `scheme://` share link (those own their fragment). Returns
/// (text, name).
(String, String?) _splitTrailingName(String payload) {
  final looksLikeLink =
      RegExp(r'^[a-z][a-z0-9+.\-]*://', caseSensitive: false).hasMatch(payload);
  if (looksLikeLink) return (payload, null);
  final hash = payload.indexOf('#');
  if (hash < 0) return (payload, null);
  final text = payload.substring(0, hash).trim();
  final name = _clean(payload.substring(hash + 1));
  if (text.isEmpty) return (payload, null);
  return (text, name);
}

/// Percent-decodes [s], falling back to the raw string when it is not valid
/// encoding (a malformed `%` sequence must not throw away the payload).
String _tryDecode(String s) {
  try {
    return Uri.decodeComponent(s);
  } catch (_) {
    return s;
  }
}

/// Trims a name and maps empty to null.
String? _clean(String? s) {
  final t = s?.trim();
  return (t == null || t.isEmpty) ? null : t;
}
