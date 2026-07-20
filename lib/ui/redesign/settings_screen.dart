import 'package:flutter/material.dart';

import '../../core/premium.dart';
import '../../state/app_state.dart';
import 'hip.dart';
import 'paywall_screen.dart';
import 'shell.dart';

/// Settings: Premium status, interface switches, connection behaviour,
/// and shortcuts.
class SettingsScreen extends StatelessWidget {
  final AppState state;
  final HipNav nav;
  const SettingsScreen({super.key, required this.state, required this.nav});

  String _premiumSubtitle(Premium p) => switch (p.status) {
        PremiumStatus.trial =>
          'Free trial; ends ${formatPremiumDate(p.renews!)}',
        PremiumStatus.active =>
          '${PlanInfo.of(p.plan!).name} plan; renews ${formatPremiumDate(p.renews!)}',
        PremiumStatus.expired => 'Trial ended; not renewing',
        PremiumStatus.none => 'Not subscribed; 7 days free to start',
      };

  @override
  Widget build(BuildContext context) {
    final prefs = state.prefs;
    final premium = state.premium;
    // A flat gray tile (the blue one is reserved for flags and Premium).
    Widget grayTile(IconData icon) => Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Hip.line2,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 19, color: Hip.inkSoft),
        );
    return SafeArea(
      child: Column(children: [
        HipNavHead(title: 'Settings', onBack: () => nav.go(HipScreen.home)),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              if (kPlansAvailable) ...[
                const HipSectionLabel('Account'),
                HipListGroup(children: [
                  HipListRow(
                    leading: const HipFlag(cc: '', child: PremiumCubeIcon()),
                    title: 'Premium',
                    titleBadge: premium.isOn ? HipBadge.ok('On') : null,
                    subtitle: _premiumSubtitle(premium),
                    trailing:
                        Icon(Icons.chevron_right, size: 17, color: Hip.muted2),
                    onTap: () => premium.status == PremiumStatus.none
                        ? nav.openPaywall(HipScreen.settings)
                        : nav.go(HipScreen.premium),
                  ),
                ]),
              ],
              const HipSectionLabel('Interface'),
              HipListGroup(children: [
                HipListRow(
                  leading: grayTile(Icons.dark_mode_outlined),
                  title: 'Dark mode',
                  subtitle: 'Darker surfaces across the whole app',
                  trailing: HipToggle(
                    on: prefs.darkMode,
                    onChanged: (v) =>
                        state.updatePrefs(prefs.copyWith(darkMode: v)),
                  ),
                ),
                HipListRow(
                  leading: grayTile(Icons.visibility_outlined),
                  title: 'Advanced view',
                  subtitle: 'Show protocols, endpoints and raw configs',
                  trailing: HipToggle(
                    on: prefs.advanced,
                    onChanged: (v) =>
                        state.updatePrefs(prefs.copyWith(advanced: v)),
                  ),
                ),
              ]),
              const HipSectionLabel('Connection'),
              HipListGroup(children: [
                HipListRow(
                  title: 'Connect on launch',
                  trailing: HipToggle(
                    on: prefs.autoConnect,
                    onChanged: (v) =>
                        state.updatePrefs(prefs.copyWith(autoConnect: v)),
                  ),
                ),
              ]),
              const HipSectionLabel('Connections'),
              HipListGroup(children: [
                HipListRow(
                  title: 'Add connection',
                  trailing: Icon(Icons.chevron_right, size: 17, color: Hip.muted2),
                  onTap: () => nav.openImport(),
                ),
                HipListRow(
                  title: 'Replay setup',
                  trailing: Icon(Icons.chevron_right, size: 17, color: Hip.muted2),
                  onTap: () => nav.go(HipScreen.onboarding),
                ),
              ]),
              const HipSubnote(
                  'hideip.net · Open source · No logs\nSame app on iOS and Android.'),
            ],
          ),
        ),
      ]),
    );
  }
}
