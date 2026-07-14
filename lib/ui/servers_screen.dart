import 'package:flutter/material.dart';

import '../core/haptics.dart';
import '../core/ping.dart';
import '../state/app_state.dart';
import 'brand.dart';
import 'import_screen.dart';

/// List of saved servers: tap to select, swipe to delete.
class ServersScreen extends StatelessWidget {
  final AppState state;
  const ServersScreen({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final t = context.brand;
        final profiles = state.profiles;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Servers'),
            actions: [
              if (profiles.isNotEmpty)
                IconButton(
                  tooltip: 'Test latency',
                  icon: state.pinging
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.network_check),
                  onPressed: state.pinging
                      ? null
                      : () {
                          Haptics.tap();
                          state.pingAll();
                        },
                ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: t.primary,
            foregroundColor: Colors.white,
            onPressed: () {
              Haptics.tap();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ImportScreen(state: state)),
              );
            },
            icon: const Icon(Icons.add),
            label: const Text('Import'),
          ),
          body: profiles.isEmpty
              ? const _Empty()
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                  itemCount: profiles.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final p = profiles[i];
                    final selected = i == state.selectedIndex;
                    return Dismissible(
                      key: ValueKey('${p.protocol}/${p.server}/${p.port}/$i'),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        decoration: BoxDecoration(
                          color: t.destructive.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.delete_outline, color: Colors.white),
                      ),
                      onDismissed: (_) {
                        Haptics.tap();
                        state.remove(i);
                      },
                      child: Card(
                        color: selected ? t.secondary : t.card,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: selected
                              ? BorderSide(color: t.primary, width: 1.5)
                              : BorderSide(color: t.border),
                        ),
                        child: ListTile(
                          onTap: () => state.select(i),
                          leading: Icon(
                            selected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            color: selected ? t.primary : t.mutedForeground,
                          ),
                          title: Text(p.name,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            '${p.protocol} · ${p.server}:${p.port}',
                            style: Brand.mono
                                .copyWith(fontSize: 12, color: t.mutedForeground),
                          ),
                          trailing: _PingBadge(result: state.pingFor(p)),
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}

/// Latency pill for a server: coloured by speed, or a dash when untested.
class _PingBadge extends StatelessWidget {
  final PingResult? result;
  const _PingBadge({required this.result});

  @override
  Widget build(BuildContext context) {
    final t = context.brand;
    final r = result;
    if (r == null) {
      return Text('--', style: TextStyle(color: t.mutedForeground));
    }
    if (r is PingFail) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 8, color: t.destructive),
          const SizedBox(width: 5),
          Text('timeout',
              style: TextStyle(fontSize: 12, color: t.mutedForeground)),
        ],
      );
    }
    final ms = (r as PingOk).ms;
    final color = ms < 150
        ? const Color(0xFF22C55E) // green: fast
        : ms < 400
            ? const Color(0xFFEAB308) // amber: ok
            : t.destructive; // red: slow
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 8, color: color),
        const SizedBox(width: 5),
        Text('$ms ms',
            style: Brand.mono.copyWith(fontSize: 13, color: t.foreground)),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) {
    final t = context.brand;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.dns_outlined, size: 48, color: t.mutedForeground),
            const SizedBox(height: 16),
            Text('No servers yet',
                style: TextStyle(
                    fontFamily: Brand.displayFont,
                    fontSize: 18,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text('Tap Import to add a server link or subscription.',
                textAlign: TextAlign.center,
                style: TextStyle(color: t.mutedForeground)),
          ],
        ),
      ),
    );
  }
}
