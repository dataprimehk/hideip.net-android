// Turns an incoming link into the text the import screen is prefilled with.
//
// Two shapes are accepted, and the difference between them is a migration in
// progress rather than a preference.
//
//   1. https://hideip.net/import#url=<encoded>&name=<optional>  -- the target.
//      (`/add` is the same link under the older name and stays accepted.)
//      An app link the operating system verifies against hideip.net, so no
//      other app can claim it, and the payload rides in the fragment, which a
//      browser never puts in the request line or a server log.
//
//   2. hideip://add?url=<encoded>  (also install-config, and import/<payload>)
//      -- the transitional shape. Any app may register a custom scheme, so a
//      hostile one could be handed the payload. It stays because the whole
//      seller channel already runs on it: the snippets on hideip.net/sellers
//      have been copied into third-party panels that nobody can edit for us,
//      and shape 1 cannot take over until assetlinks.json and the Apple
//      site association carry real values instead of placeholders. Removing
//      it before then would not move those links to the safe path, it would
//      only break them.
//
// Neither shape imports anything. Both land on the import screen with the
// field filled in, and a person has to press the button (see shell.dart), so
// a page that manages to open the app still cannot add a server behind the
// user's back.
//
// Retire shape 2 once the app links verify on both platforms and the site has
// emitted shape 1 long enough for seller panels to have been updated.

class DeepLinkImport {
  /// The import text: an https subscription URL, a `scheme://` share link, or
  /// a subscription blob. Never empty.
  final String text;

  /// Optional display name a seller attached, or null.
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
/// `hideip://link?v=1&id=<link_id>` deep link. The id is public and opaque;
/// approving it grants access rather than exposing this phone's credential.
class DeepLinkPairing {
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

/// Anything longer than this is not a link somebody meant to send.
const int _maxLinkLength = 256 * 1024;

DeepLinkPairing? parsePairingLink(String raw) {
  final input = raw.trim();
  if (input.isEmpty || input.length > _maxLinkLength) return null;

  final uri = Uri.tryParse(input);
  if (uri == null || uri.scheme.toLowerCase() != 'hideip') return null;
  if (_action(uri) != 'link') return null;

  final version = uri.queryParameters['v']?.trim();
  if (version != null && version.isNotEmpty && version != '1') return null;

  final id = uri.queryParameters['id']?.trim() ?? '';
  if (id.isEmpty) return null;
  return DeepLinkPairing(id);
}

/// The action a link names: the host, or the first path segment when a
/// launcher normalized `hideip://x` down to `hideip:/x`.
String _action(Uri uri) {
  final host = uri.host.toLowerCase();
  if (host.isNotEmpty) return host;
  final segments = uri.pathSegments;
  return segments.isNotEmpty ? segments.first.toLowerCase() : '';
}

/// Turns an import link of either shape into a prefill, or null when the link
/// is not one of ours or carries no payload.
DeepLinkImport? parseDeepLink(String raw) {
  final input = raw.trim();
  if (input.isEmpty || input.length > _maxLinkLength) return null;

  final uri = Uri.tryParse(input);
  if (uri == null) return null;

  final scheme = uri.scheme.toLowerCase();
  if (scheme == 'https') return _fromAppLink(uri);
  if (scheme == 'hideip') return _fromCustomScheme(uri, input);
  return null;
}

/// Shape 1. Tolerant about everything that does not change the destination:
/// a `www.` prefix, a trailing slash, and tracking parameters a seller's
/// analytics appended are all the same link, and refusing them would only
/// produce a dead button nobody can explain.
DeepLinkImport? _fromAppLink(Uri uri) {
  final host = uri.host.toLowerCase();
  if (host != 'hideip.net' && host != 'www.hideip.net') return null;
  final path = uri.path.toLowerCase();
  if (path != '/import' && path != '/import/' &&
      path != '/add' && path != '/add/') {
    return null;
  }

  // The fragment is where a payload belongs, but a link that came back
  // through something that dropped the fragment still has the query.
  final fromFragment = uri.hasFragment ? _split(uri.fragment) : null;
  final text = _clean(fromFragment?['url']) ?? _clean(uri.queryParameters['url']);
  if (text == null) return null;
  final name =
      _clean(fromFragment?['name']) ?? _clean(uri.queryParameters['name']);
  return DeepLinkImport(text, name);
}

/// Shape 2, the transitional custom scheme. Both conventions that circulate
/// among proxy clients are accepted, because both are already in the wild.
DeepLinkImport? _fromCustomScheme(Uri uri, String raw) {
  switch (_action(uri)) {
    case 'install-config':
    case 'add':
    case 'import'
        when uri.hasQuery && (uri.queryParameters['url'] ?? '').isNotEmpty:
      // Query style: url= carries the payload, name= the optional label.
      final url = _clean(uri.queryParameters['url']);
      if (url == null) return null;
      return DeepLinkImport(url, _clean(uri.queryParameters['name']));

    case 'import':
      // Path-append style: everything after `import/`, verbatim. The payload
      // may be a share link whose own `?query` and `#fragment` have to
      // survive, so slice the original string rather than trusting Uri's
      // decoded path, which would eat the share link's fragment as this
      // link's own.
      final text = _pathRemainder(raw);
      if (text == null || text.isEmpty) return null;
      final split = _splitTrailingName(text);
      return DeepLinkImport(split.$1, split.$2);

    default:
      return null;
  }
}

Map<String, String>? _split(String query) {
  try {
    return Uri.splitQueryString(query);
  } catch (_) {
    return null;
  }
}

/// Everything after the `import/` marker, decoded once. Handles both
/// `hideip://import/...` and the `hideip:/import/...` normalization some
/// launchers emit.
String? _pathRemainder(String raw) {
  const marker = 'import/';
  final lower = raw.toLowerCase();
  final schemeEnd = lower.indexOf('hideip:');
  if (schemeEnd < 0) return null;
  final at = lower.indexOf(marker, schemeEnd);
  if (at < 0) return null;
  // Senders url-encode a whole https/vless link so its `:` `/` `?` `#` do not
  // confuse the outer URI. Decoding an unencoded link is a harmless no-op.
  return _tryDecode(raw.substring(at + marker.length)).trim();
}

/// Splits a trailing `#name` off a payload, but only when the payload is not
/// itself a `scheme://` share link, since those own their fragment.
(String, String?) _splitTrailingName(String payload) {
  final looksLikeLink = RegExp(
    r'^[a-z][a-z0-9+.\-]*://',
    caseSensitive: false,
  ).hasMatch(payload);
  if (looksLikeLink) return (payload, null);
  final hash = payload.indexOf('#');
  if (hash < 0) return (payload, null);
  final text = payload.substring(0, hash).trim();
  if (text.isEmpty) return (payload, null);
  return (text, _clean(payload.substring(hash + 1)));
}

/// Percent-decodes [value], keeping the raw string when the encoding is
/// malformed: a stray `%` must not throw the payload away.
String _tryDecode(String value) {
  try {
    return Uri.decodeComponent(value);
  } catch (_) {
    return value;
  }
}

String? _clean(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

/// Drops a link the app has already acted on.
///
/// The same URI reaches the app more than once by design: a cold start reads
/// it from the launch intent and the link stream replays it, and a launcher
/// may redeliver the VIEW intent when the app is brought back. Acting on each
/// copy would throw a second importer over the one the user is reading, and
/// on a link that opens an approval sheet it would stack two sheets.
///
/// A link the user taps again later is a fresh request, so the guard only
/// covers the burst.
class DeepLinkOnce {
  static const Duration window = Duration(seconds: 10);

  String? _last;
  DateTime? _seenAt;

  /// True when [raw] should be handled; false for a repeat of the link that
  /// was just handled.
  bool accept(String raw, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final seenAt = _seenAt;
    if (raw == _last && seenAt != null && at.difference(seenAt) < window) {
      return false;
    }
    _last = raw;
    _seenAt = at;
    return true;
  }
}
