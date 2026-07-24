import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Plan metadata a seller panel returns in the subscription response headers
/// (the `subscription-userinfo` / `profile-*` conventions shared by 3x-ui,
/// Marzban, Hiddify and Remnawave). The app captures these per subscription URL
/// so a user can see data usage, expiry and provider info without leaving the
/// app. Everything is optional: providers send any subset, or nothing at all.
class SubInfo {
  final String? title;
  final int? uploadBytes;
  final int? downloadBytes;
  final int? totalBytes;
  final DateTime? expire;
  final int? updateIntervalHours;
  final String? webPageUrl;
  final String? supportUrl;

  /// When this snapshot was captured (so the UI can tell fresh from stale).
  final DateTime fetchedAt;

  const SubInfo({
    this.title,
    this.uploadBytes,
    this.downloadBytes,
    this.totalBytes,
    this.expire,
    this.updateIntervalHours,
    this.webPageUrl,
    this.supportUrl,
    required this.fetchedAt,
  });

  /// Bytes consumed against the plan quota. Panels report upload and download
  /// separately; the used total is their sum (0 when neither is present).
  int get usedBytes => (uploadBytes ?? 0) + (downloadBytes ?? 0);

  /// Whether a quota is known (a total the UI can render "used / total" for).
  bool get hasQuota => totalBytes != null && totalBytes! > 0;

  /// Whether the plan's expiry is in the past.
  bool get isExpired {
    final e = expire;
    return e != null && e.isBefore(DateTime.now());
  }

  /// Parse the relevant headers into a [SubInfo], or null when none of them
  /// are present (nothing worth surfacing). Header names are already lowercased
  /// by the http package; malformed fields are ignored, never fatal.
  static SubInfo? fromHeaders(Map<String, String> headers,
      {required DateTime fetchedAt}) {
    final userinfo = headers['subscription-userinfo'];
    final rawTitle = headers['profile-title'];
    final interval = headers['profile-update-interval'];
    final webPage = headers['profile-web-page-url'];
    final support = headers['support-url'];

    if (userinfo == null &&
        rawTitle == null &&
        interval == null &&
        webPage == null &&
        support == null) {
      return null;
    }

    int? upload, download, total;
    DateTime? expire;
    if (userinfo != null) {
      // Semicolon-separated key=value pairs, e.g.
      // "upload=1234; download=5678; total=10000000; expire=1700000000".
      for (final pair in userinfo.split(';')) {
        final eq = pair.indexOf('=');
        if (eq <= 0) continue;
        final key = pair.substring(0, eq).trim().toLowerCase();
        final n = int.tryParse(pair.substring(eq + 1).trim());
        if (n == null) continue;
        switch (key) {
          case 'upload':
            upload = n;
          case 'download':
            download = n;
          case 'total':
            total = n;
          case 'expire':
            // Unix seconds; 0 (or negative) means "no expiry" by convention.
            if (n > 0) {
              expire = DateTime.fromMillisecondsSinceEpoch(n * 1000);
            }
        }
      }
    }

    return SubInfo(
      title: _decodeTitle(rawTitle),
      uploadBytes: upload,
      downloadBytes: download,
      totalBytes: total,
      expire: expire,
      updateIntervalHours: interval == null ? null : int.tryParse(interval.trim()),
      webPageUrl: _clean(webPage),
      supportUrl: _clean(support),
      fetchedAt: fetchedAt,
    );
  }

  /// A "base64:" prefix means the remainder is base64-encoded UTF-8 (Hiddify
  /// uses this so titles can carry non-ASCII safely).
  static String? _decodeTitle(String? raw) {
    final v = _clean(raw);
    if (v == null) return null;
    if (v.startsWith('base64:')) {
      try {
        return utf8.decode(base64.decode(_padBase64(v.substring(7).trim())));
      } catch (_) {
        return v; // not valid base64: keep the literal so nothing is lost
      }
    }
    return v;
  }

  static String? _clean(String? s) {
    if (s == null) return null;
    final t = s.trim();
    return t.isEmpty ? null : t;
  }

  static String _padBase64(String s) {
    var out = s.replaceAll('-', '+').replaceAll('_', '/');
    final mod = out.length % 4;
    if (mod > 0) out += '=' * (4 - mod);
    return out;
  }

  Map<String, dynamic> toJson() => {
        if (title != null) 'title': title,
        if (uploadBytes != null) 'upload': uploadBytes,
        if (downloadBytes != null) 'download': downloadBytes,
        if (totalBytes != null) 'total': totalBytes,
        if (expire != null) 'expire': expire!.millisecondsSinceEpoch,
        if (updateIntervalHours != null) 'interval': updateIntervalHours,
        if (webPageUrl != null) 'webPage': webPageUrl,
        if (supportUrl != null) 'support': supportUrl,
        'fetchedAt': fetchedAt.millisecondsSinceEpoch,
      };

  static SubInfo fromJson(Map<String, dynamic> m) => SubInfo(
        title: m['title'] as String?,
        uploadBytes: m['upload'] as int?,
        downloadBytes: m['download'] as int?,
        totalBytes: m['total'] as int?,
        expire: m['expire'] is int
            ? DateTime.fromMillisecondsSinceEpoch(m['expire'] as int)
            : null,
        updateIntervalHours: m['interval'] as int?,
        webPageUrl: m['webPage'] as String?,
        supportUrl: m['support'] as String?,
        fetchedAt: m['fetchedAt'] is int
            ? DateTime.fromMillisecondsSinceEpoch(m['fetchedAt'] as int)
            : DateTime.fromMillisecondsSinceEpoch(0),
      );

  /// A byte count as GB with one decimal (the app's convention for data
  /// figures), e.g. 1610612736 -> "1.5 GB".
  static String formatBytes(int bytes) {
    final gb = bytes / (1024 * 1024 * 1024);
    return '${gb.toStringAsFixed(1)} GB';
  }
}

/// Persists a map of subscription URL -> [SubInfo] in shared_preferences as
/// JSON, mirroring [ProfileStore]. Small and overwritten wholesale on refresh.
class SubInfoStore {
  static const _kInfos = 'sub_infos_v1';

  /// Load all saved subscription infos. Corrupt entries yield an empty map.
  static Future<Map<String, SubInfo>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kInfos);
    if (raw == null || raw.isEmpty) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map((url, v) =>
          MapEntry(url, SubInfo.fromJson((v as Map).cast<String, dynamic>())));
    } catch (_) {
      return {};
    }
  }

  /// Overwrite the whole map.
  static Future<void> save(Map<String, SubInfo> infos) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded =
        jsonEncode(infos.map((url, info) => MapEntry(url, info.toJson())));
    await prefs.setString(_kInfos, encoded);
  }

  /// Store (or replace) the info for a single [url], preserving the rest.
  static Future<void> put(String url, SubInfo info) async {
    final all = await load();
    all[url] = info;
    await save(all);
  }
}
