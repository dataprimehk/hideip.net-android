import 'package:flutter/material.dart';

import '../core/haptics.dart';
import '../state/app_state.dart';
import 'brand.dart';
import 'import_screen.dart';
import 'logo_mark.dart';
import 'magnetic_button.dart';
import 'servers_screen.dart';

/// Main screen: connection toggle, status, current public IP, selected server.
class HomeScreen extends StatelessWidget {
  final AppState state;
  const HomeScreen({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 16,
            title: const Wordmark(size: 22),
            actions: [
              IconButton(
                icon: const Icon(Icons.dns_outlined),
                tooltip: 'Servers',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => ServersScreen(state: state)),
                ),
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: state.profiles.isEmpty
                ? _Onboarding(state: state)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 16),
                      const Center(child: LogoMark(size: 30)),
                      const SizedBox(height: 28),
                      _StatusOrb(state: state),
                      const SizedBox(height: 32),
                      _IpCard(state: state),
                      if (state.isConnected) ...[
                        const SizedBox(height: 16),
                        _TrafficCard(state: state),
                      ],
                      const SizedBox(height: 16),
                      _ServerCard(state: state),
                      const Spacer(),
                      if (state.error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(state.error!,
                              textAlign: TextAlign.center,
                              style:
                                  TextStyle(color: context.brand.destructive)),
                        ),
                      _ConnectButton(state: state),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

/// First-run state: no servers yet. Explains the app in one line and gives two
/// clear ways in (scan a QR or paste a link), both opening the import screen.
class _Onboarding extends StatelessWidget {
  final AppState state;
  const _Onboarding({required this.state});

  void _openImport(BuildContext context) {
    Haptics.tap();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ImportScreen(state: state)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.brand;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(flex: 2),
        const Center(child: LogoMark(size: 34)),
        const SizedBox(height: 32),
        Text(
          'Add your first server',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: Brand.displayFont,
            fontSize: 26,
            fontWeight: FontWeight.w700,
            letterSpacing: -1,
            color: t.foreground,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'hideip.net connects through a server profile you provide. '
          'Scan a QR code or paste a share link to get started.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: Brand.bodyFont,
            fontSize: 14,
            height: 1.4,
            color: t.mutedForeground,
          ),
        ),
        const Spacer(flex: 3),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: t.primary,
            side: BorderSide(color: t.border),
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: () => _openImport(context),
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('Scan or paste a server'),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _StatusOrb extends StatelessWidget {
  final AppState state;
  const _StatusOrb({required this.state});

  @override
  Widget build(BuildContext context) {
    final t = context.brand;
    final connected = state.isConnected;
    final busy = state.isBusy;
    final color = connected ? t.primary : t.mutedForeground;
    final label = busy
        ? 'Connecting…'
        : connected
            ? 'Connected'
            : 'Disconnected';
    return Column(
      children: [
        Container(
          width: 128,
          height: 128,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.12),
            border: Border.all(color: color, width: 2),
          ),
          child: Icon(
            connected ? Icons.shield : Icons.shield_outlined,
            size: 56,
            color: color,
          ),
        ),
        const SizedBox(height: 18),
        Text(label,
            style: TextStyle(
                fontFamily: Brand.displayFont,
                fontSize: 30,
                fontWeight: FontWeight.w700,
                letterSpacing: -1,
                color: t.foreground)),
        const SizedBox(height: 4),
        Text(
            connected
                ? 'Your traffic is private.'
                : busy
                    ? 'Setting up the tunnel…'
                    : 'Not protected yet.',
            style: TextStyle(
                fontFamily: Brand.bodyFont,
                fontSize: 14,
                color: t.mutedForeground)),
      ],
    );
  }
}

class _IpCard extends StatelessWidget {
  final AppState state;
  const _IpCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final t = context.brand;
    return Card(
      child: ListTile(
        leading: Icon(Icons.public, color: t.mutedForeground),
        title: Text('Public IP',
            style: TextStyle(color: t.mutedForeground, fontSize: 13)),
        subtitle: state.ipLoading
            ? Text('…', style: Brand.mono.copyWith(color: t.foreground))
            : Text(state.publicIp ?? 'unavailable',
                style: Brand.mono.copyWith(fontSize: 16, color: t.foreground)),
        trailing: IconButton(
          icon: const Icon(Icons.refresh, size: 20),
          onPressed: state.ipLoading ? null : state.refreshIp,
        ),
      ),
    );
  }
}

class _ServerCard extends StatelessWidget {
  final AppState state;
  const _ServerCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final t = context.brand;
    final sel = state.selected;
    return Card(
      child: ListTile(
        leading: Icon(Icons.dns_outlined, color: t.mutedForeground),
        title: Text(
          sel?.name ?? 'No server selected',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: sel == null
            ? Text('Tap to choose', style: TextStyle(color: t.mutedForeground))
            : Text('${sel.protocol} · ${sel.server}:${sel.port}',
                style: Brand.mono.copyWith(fontSize: 12, color: t.mutedForeground)),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ServersScreen(state: state)),
        ),
      ),
    );
  }
}

/// Live upload/download rate + session total, shown only while connected.
class _TrafficCard extends StatelessWidget {
  final AppState state;
  const _TrafficCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final t = context.brand;
    final s = state.stats;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: _Meter(
                icon: Icons.arrow_downward,
                color: t.primary,
                rate: _fmtRate(s.downlink),
                total: _fmtBytes(s.downlinkTotal),
                label: 'Download',
              ),
            ),
            Container(width: 1, height: 40, color: t.border),
            Expanded(
              child: _Meter(
                icon: Icons.arrow_upward,
                color: t.foreground,
                rate: _fmtRate(s.uplink),
                total: _fmtBytes(s.uplinkTotal),
                label: 'Upload',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Meter extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String rate;
  final String total;
  final String label;
  const _Meter({
    required this.icon,
    required this.color,
    required this.rate,
    required this.total,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.brand;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(rate,
                style: Brand.mono.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: t.foreground)),
          ],
        ),
        const SizedBox(height: 2),
        Text('$total · $label',
            style: TextStyle(fontSize: 11, color: t.mutedForeground)),
      ],
    );
  }
}

String _fmtRate(int bytesPerSec) => '${_fmtBytes(bytesPerSec)}/s';

String _fmtBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  double v = bytes / 1024;
  int u = 0;
  while (v >= 1024 && u < units.length - 1) {
    v /= 1024;
    u++;
  }
  return '${v < 10 ? v.toStringAsFixed(1) : v.toStringAsFixed(0)} ${units[u]}';
}

class _ConnectButton extends StatelessWidget {
  final AppState state;
  const _ConnectButton({required this.state});

  @override
  Widget build(BuildContext context) {
    final connected = state.isConnected;
    final busy = state.isBusy;
    return MagneticButton(
      subdued: connected,
      onPressed: busy
          ? null
          : connected
              ? () {
                  Haptics.tap();
                  state.disconnect();
                }
              : () {
                  Haptics.tap();
                  state.connect();
                },
      child: busy
          ? const SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white))
          : Text(connected ? 'Disconnect' : 'Connect'),
    );
  }
}
