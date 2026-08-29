import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MissingPluginException;

/// Whether the device has any network at all.
///
/// This answers one question and refuses to pretend it answers a second one:
/// it reports the presence of a link, not that the link reaches anywhere. A
/// captive portal, a dead uplink and a filtered network all read as online
/// here, and they should: the app's job in those cases is to try and report
/// what happened, not to claim in advance that it cannot.
///
/// What it is for: with no link at all, Connect is off, its reason is stated
/// under the button, and the "Connection failed" sheet stays shut. Blaming the
/// tunnel for a phone in flight mode would be a lie the user can see through.
class ConnectivityWatch {
  final Connectivity _plugin;
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _offline = false;

  /// Fires whenever [offline] changes.
  final void Function(bool offline) onChanged;

  ConnectivityWatch({required this.onChanged, @visibleForTesting Connectivity? plugin})
      : _plugin = plugin ?? Connectivity();

  bool get offline => _offline;

  /// Reads the current state once and subscribes to changes.
  ///
  /// Every failure resolves to "online". A platform without the plugin (unit
  /// tests, an iOS build before the extension lands) must not be able to
  /// disable the Connect button for everyone on it.
  Future<void> start() async {
    try {
      _apply(await _plugin.checkConnectivity());
    } on MissingPluginException {
      return; // no platform side: stay online, do not subscribe
    } catch (_) {
      // Keep the optimistic default and still try to subscribe below.
    }
    try {
      _sub = _plugin.onConnectivityChanged.listen(_apply, onError: (_) {});
    } on MissingPluginException {
      // Same: nothing to listen to.
    }
  }

  void _apply(List<ConnectivityResult> results) {
    final next = results.isEmpty ||
        results.every((r) => r == ConnectivityResult.none);
    if (next == _offline) return;
    _offline = next;
    onChanged(next);
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }
}
