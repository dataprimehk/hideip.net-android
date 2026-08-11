/// Returns a deep copy of a proxy config with replayable credentials removed.
///
/// Endpoint, protocol, transport and TLS metadata remain useful for support,
/// while UUIDs, passwords, private keys, tokens, usernames and subscription
/// URLs never reach the default clipboard action.
dynamic redactConfig(dynamic value) {
  if (value is Map) {
    return <String, dynamic>{
      for (final entry in value.entries)
        entry.key.toString(): _isSensitiveKey(entry.key.toString())
            ? '[REDACTED]'
            : redactConfig(entry.value),
    };
  }
  if (value is List) return value.map(redactConfig).toList(growable: false);
  return value;
}

bool _isSensitiveKey(String key) {
  final normalized = key.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
  return const {
    'auth',
    'authorization',
    'password',
    'passwd',
    'presharedkey',
    'privatekey',
    'psk',
    'secret',
    'subscriptionurl',
    'suburl',
    'token',
    'url',
    'user',
    'username',
    'uuid',
  }.contains(normalized);
}
