import 'dart:convert';

import 'package:yaml/yaml.dart';

import 'clash_parser.dart';
import 'proxy_profile.dart';
import 'share_link_parser.dart';
import 'singbox_json_parser.dart';

/// Decodes a subscription payload into a list of [ProxyProfile]s.
///
/// A subscription body may be any of the formats seller panels serve:
///  1. a sing-box JSON object with an `outbounds` array,
///  2. a Clash-family YAML document with a `proxies:` list,
///  3. a base64 blob whose decoded text is newline-separated share links, or
///  4. plain newline-separated share links.
///
/// Detection runs in that order. Lines/entries that fail to parse are collected
/// in [SubscriptionResult.errors] rather than aborting the whole set.
class Subscription {
  /// Parse raw subscription body text (already fetched over HTTP, or pasted).
  static SubscriptionResult parse(String body) {
    final trimmed = body.trim();

    // 1. sing-box JSON: a JSON object carrying an `outbounds` array.
    final json = _tryJsonOutbounds(trimmed);
    if (json != null) {
      final errors = <String>[];
      final profiles = SingboxJsonParser.parse(json, errors: errors);
      return SubscriptionResult(profiles: profiles, errors: errors);
    }

    // 2. Clash YAML: a mapping with a top-level `proxies:` list. Only attempt
    // YAML when the body is not a link list / base64 blob (those parse as YAML
    // scalars and would waste work).
    final yaml = _tryClashYaml(trimmed);
    if (yaml != null) {
      final errors = <String>[];
      final profiles = ClashParser.parse(yaml, errors: errors);
      return SubscriptionResult(profiles: profiles, errors: errors);
    }

    // 3 + 4. base64 blob or plain link list (the original fallback path).
    final text = _maybeBase64Decode(trimmed);
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

  /// Returns the decoded JSON object when [body] is a sing-box config with an
  /// `outbounds` array, else null.
  static Map<String, dynamic>? _tryJsonOutbounds(String body) {
    if (!body.startsWith('{')) return null;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic> && decoded['outbounds'] is List) {
        return decoded;
      }
    } catch (_) {
      // not JSON; fall through
    }
    return null;
  }

  /// Returns the parsed YAML mapping when [body] is a Clash document with a
  /// top-level `proxies:` list, else null.
  static Map<dynamic, dynamic>? _tryClashYaml(String body) {
    // A link list / base64 blob is not YAML we care about; skip cheaply.
    if (body.contains('://')) return null;
    if (!body.contains('proxies:')) return null;
    try {
      final doc = loadYaml(body);
      if (doc is Map && doc['proxies'] is List) {
        // Convert YamlMap/YamlList into plain Dart maps/lists so downstream
        // code never depends on the yaml package types.
        return _plain(doc) as Map<dynamic, dynamic>;
      }
    } catch (_) {
      // not YAML; fall through
    }
    return null;
  }

  /// Deep-converts YamlMap/YamlList (and scalars) into plain Map/List/values.
  static Object? _plain(Object? node) {
    if (node is YamlMap) {
      return node.map((k, v) => MapEntry(_plain(k), _plain(v)));
    }
    if (node is YamlList) {
      return node.map(_plain).toList();
    }
    return node;
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
