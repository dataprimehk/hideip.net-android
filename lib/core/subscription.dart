import 'dart:convert';

import 'proxy_profile.dart';
import 'share_link_parser.dart';

/// Decodes a subscription payload into a list of [ProxyProfile]s.
///
/// A subscription is the body returned by a subscription URL: usually a single
/// base64 blob whose decoded text is newline-separated share links, but it may
/// also already be plain newline-separated links. Lines that fail to parse are
/// collected in [SubscriptionResult.errors] rather than aborting the whole set.
class Subscription {
  /// Parse raw subscription body text (already fetched over HTTP, or pasted).
  static SubscriptionResult parse(String body) {
    final text = _maybeBase64Decode(body.trim());
    final lines = const LineSplitter().convert(text);

    final profiles = <ProxyProfile>[];
    final errors = <String>[];
    for (final line in lines) {
      final l = line.trim();
      if (l.isEmpty) continue;
      try {
        final p = ShareLinkParser.parse(l);
        if (p != null) profiles.add(p);
      } catch (e) {
        errors.add('${_short(l)} -> $e');
      }
    }
    return SubscriptionResult(profiles: profiles, errors: errors);
  }

  /// A whole-body base64 blob has no "://" and decodes to text containing one.
  /// If decoding doesn't reveal links, treat the body as plain text.
  static String _maybeBase64Decode(String body) {
    if (body.contains('://')) return body; // already plain links
    try {
      final decoded = utf8.decode(base64.decode(_padBase64(body)));
      if (decoded.contains('://')) return decoded;
    } catch (_) {
      // not base64; fall through
    }
    return body;
  }

  static String _padBase64(String s) {
    var out = s.replaceAll('-', '+').replaceAll('_', '/').replaceAll('\n', '').replaceAll('\r', '');
    final mod = out.length % 4;
    if (mod > 0) out += '=' * (4 - mod);
    return out;
  }

  static String _short(String s) => s.length > 40 ? '${s.substring(0, 40)}...' : s;
}

class SubscriptionResult {
  final List<ProxyProfile> profiles;
  final List<String> errors;
  const SubscriptionResult({required this.profiles, required this.errors});

  bool get isEmpty => profiles.isEmpty;
}
