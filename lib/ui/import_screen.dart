import 'package:flutter/material.dart';

import '../core/haptics.dart';
import '../core/proxy_profile.dart';
import '../state/app_state.dart';
import 'brand.dart';
import 'qr_scan_screen.dart';

/// Paste a single share link or a subscription body, then import.
class ImportScreen extends StatefulWidget {
  final AppState state;
  const ImportScreen({super.key, required this.state});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final _ctrl = TextEditingController();
  bool _busy = false;
  String? _msg;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) {
      setState(() => _msg = 'Paste a link or subscription first.');
      return;
    }
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      // A single line that is one link -> addLink; otherwise treat as subscription.
      final lines = text.split('\n').where((l) => l.trim().isNotEmpty).toList();
      if (lines.length == 1 && _looksLikeLink(lines.first)) {
        await widget.state.addLink(lines.first.trim());
        Haptics.success();
        if (mounted) Navigator.of(context).pop();
        return;
      }
      final res = await widget.state.addSubscription(text);
      if (res.isEmpty) {
        Haptics.error();
        setState(() => _msg = 'No valid servers found.'
            '${res.errors.isNotEmpty ? '\n${res.errors.first}' : ''}');
        return;
      }
      if (mounted) {
        final added = res.profiles.length;
        final failed = res.errors.length;
        Haptics.success();
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Imported $added server${added == 1 ? '' : 's'}'
              '${failed > 0 ? ', $failed skipped' : ''}.'),
        ));
      }
    } on ProfileParseException catch (e) {
      Haptics.error();
      setState(() => _msg = e.message);
    } catch (e) {
      Haptics.error();
      setState(() => _msg = 'Import failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _looksLikeLink(String s) => s.trim().contains('://');

  Future<void> _scanQr() async {
    Haptics.tap();
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );
    if (result == null || result.isEmpty) return;
    // Drop the decoded payload into the field and import straight away.
    _ctrl.text = result;
    await _import();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Import servers')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Paste a server link (vless://, vmess://, ss://, trojan://, '
              'hysteria2://, tuic://, anytls://, socks://, http://) or a '
              'subscription (one link per line, or a base64 subscription body).',
              style: TextStyle(color: context.brand.mutedForeground),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: TextField(
                controller: _ctrl,
                expands: true,
                maxLines: null,
                textAlignVertical: TextAlignVertical.top,
                style: Brand.mono.copyWith(fontSize: 12),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'vless://…',
                  alignLabelWithHint: true,
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_msg != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_msg!,
                    style: TextStyle(color: context.brand.destructive)),
              ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: context.brand.primary,
                side: BorderSide(color: context.brand.border),
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _busy ? null : _scanQr,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan QR code'),
            ),
            const SizedBox(height: 10),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: context.brand.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _busy ? null : _import,
              child: _busy
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Import'),
            ),
          ],
        ),
      ),
    );
  }
}
