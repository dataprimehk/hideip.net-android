import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/config_redaction.dart';
import '../../core/location.dart';
import '../../core/ping.dart';
import '../../core/sensitive_clipboard.dart';
import '../../state/app_state.dart';
import '../brand.dart';
import 'hip.dart';
import 'shell.dart';

/// Advanced-view server detail: endpoint, protocol, the raw sing-box
/// outbound, and removal. The protocol is what the server speaks; shown,
/// not editable.
class DetailScreen extends StatefulWidget {
  final AppState state;
  final HipNav nav;
  final Location location;
  const DetailScreen({
    super.key,
    required this.state,
    required this.nav,
    required this.location,
  });

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  bool _testing = false;
  int? _ms;

  @override
  void initState() {
    super.initState();
    final ping = widget.state.pingFor(widget.location.profile);
    if (ping is PingOk) _ms = ping.ms;
  }

  Future<void> _test() async {
    setState(() => _testing = true);
    final p = widget.location.profile;
    final r = await Ping.measure(p.server, p.port,
        timeout: const Duration(seconds: 4));
    if (!mounted) return;
    setState(() {
      _testing = false;
      _ms = r is PingOk ? r.ms : null;
    });
  }

  Future<void> _copyConfig() async {
    const encoder = JsonEncoder.withIndent('  ');
    await Clipboard.setData(ClipboardData(
        text: encoder.convert(redactConfig(widget.location.profile.outbound))));
    widget.state.showToast('Redacted config copied');
  }

  Future<void> _copyFullConfig() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Copy full config?'),
            content: const Text(
              'The full config contains credentials that can be used to access '
              'this server. It will be marked sensitive and expire after one minute.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Copy for 1 minute'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    const encoder = JsonEncoder.withIndent('  ');
    try {
      await SensitiveClipboard.setText(
          encoder.convert(widget.location.profile.outbound));
      widget.state.showToast('Full config copied for 1 minute');
    } on PlatformException {
      widget.state.showToast('Could not copy full config');
    }
  }

  Future<void> _remove() async {
    await widget.state.remove(widget.location.index);
    widget.state.showToast('${widget.location.city} removed');
    widget.nav.go(HipScreen.locations);
  }

  @override
  Widget build(BuildContext context) {
    final loc = widget.location;
    const encoder = JsonEncoder.withIndent('  ');
    final rawJson = encoder.convert(loc.profile.outbound);

    return SafeArea(
      child: Column(children: [
        HipNavHead(title: loc.city, onBack: () => nav.go(HipScreen.locations)),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              HipCard(
                child: Row(children: [
                  HipFlag(cc: loc.cc),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${loc.city}, ${loc.country}',
                              style: Hip.sans(650, 15.5,
                                  color: Hip.ink, letterSpacing: -.15)),
                          const SizedBox(height: 2),
                          Text(loc.host,
                              style: Hip.mono(600, 12, color: Hip.muted)),
                        ]),
                  ),
                  GestureDetector(
                    onTap: _testing ? null : _test,
                    child: HipBadge.blue(_testing
                        ? 'Testing…'
                        : _ms != null
                            ? '$_ms ms'
                            : 'Test'),
                  ),
                ]),
              ),
              const HipSectionLabel('Protocol'),
              HipListGroup(children: [
                HipListRow(
                  title: loc.protoLabel,
                  subtitle: 'Set by the server. Pick a different server '
                      'to use a different protocol.',
                  trailing: HipBadge.proto(loc.profile.protocol),
                ),
              ]),
              const HipSectionLabel('Raw config'),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
                decoration: BoxDecoration(
                  color: Brand.hsl(220, 15, 10),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Text(rawJson,
                    style: Hip.mono(500, 10.5,
                        color: Brand.hsl(220, 10, 78), height: 1.7)),
              ),
              const SizedBox(height: 10),
              HipCta('Copy config',
                  ghost: true,
                  leading: const Icon(Icons.copy_outlined),
                  onTap: _copyConfig),
              const SizedBox(height: 8),
              HipCta('Copy full config',
                  ghost: true,
                  leading: const Icon(Icons.warning_amber_rounded),
                  onTap: _copyFullConfig),
              GestureDetector(
                onTap: _remove,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Center(
                    child: Text('Remove server',
                        style: Hip.sans(600, 14.5, color: Hip.danger)),
                  ),
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ]),
    );
  }

  HipNav get nav => widget.nav;
}
