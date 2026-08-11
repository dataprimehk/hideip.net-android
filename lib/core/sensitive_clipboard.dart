import 'package:flutter/services.dart';

/// Copies short-lived secrets with native sensitive/expiry metadata.
class SensitiveClipboard {
  static const _channel = MethodChannel('net.hideip.vpn/control');

  static Future<void> setText(
    String text, {
    Duration ttl = const Duration(minutes: 1),
  }) async {
    try {
      final written = await _channel.invokeMethod<bool>(
        'setSensitiveClipboard',
        {'text': text, 'ttlMs': ttl.inMilliseconds},
      );
      if (written != true) {
        throw PlatformException(
          code: 'clipboard_failed',
          message: 'The secure clipboard rejected the value.',
        );
      }
    } on MissingPluginException {
      // Desktop/test targets do not register the mobile channel. Full-secret
      // export is an explicitly confirmed Advanced action there as well.
      await Clipboard.setData(ClipboardData(text: text));
    }
  }
}
