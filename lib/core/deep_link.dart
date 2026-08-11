// Import payloads use a verified HTTPS app link and live only in its fragment,
// which is delivered to the app but never sent in the HTTP request or server
// logs: https://hideip.net/add#url=<encoded>&name=<optional>.

class DeepLinkImport {
  final String text;
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

String _action(Uri uri) {
  final host = uri.host.toLowerCase();
  if (host.isNotEmpty) return host;
  final segments = uri.pathSegments;
  return segments.isNotEmpty ? segments.first.toLowerCase() : '';
}

/// Turns a verified hideip.net HTTPS app link into an import preview.
/// Credential-bearing custom-scheme links are deliberately rejected: another
/// app can register `hideip://` and receive their full payload.
DeepLinkImport? parseDeepLink(String raw) {
  final input = raw.trim();
  if (input.isEmpty || input.length > 256 * 1024) return null;

  final uri = Uri.tryParse(input);
  if (uri == null ||
      uri.scheme.toLowerCase() != 'https' ||
      uri.host.toLowerCase() != 'hideip.net' ||
      uri.path != '/add' ||
      uri.hasQuery ||
      !uri.hasFragment) {
    return null;
  }
  try {
    final values = Uri.splitQueryString(uri.fragment);
    final text = values['url']?.trim() ?? '';
    if (text.isEmpty) return null;
    return DeepLinkImport(text, _clean(values['name']));
  } catch (_) {
    return null;
  }
}

String? _clean(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
