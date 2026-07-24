import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

import '../../core/premium.dart';
import '../../state/app_state.dart';
import '../../vpn_controller.dart';
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
        PremiumStatus.expired => 'Subscription ended; not renewing',
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
                HipListRow(
                  title: 'Kill switch',
                  // Android holds the TUN up through a drop (traffic is
                  // blocked, not leaked); iOS can only redial via on-demand.
                  subtitle: defaultTargetPlatform == TargetPlatform.android
                      ? 'Block traffic and reconnect if the VPN drops unexpectedly'
                      : 'Reconnect automatically if the VPN drops unexpectedly',
                  trailing: HipToggle(
                    on: prefs.killSwitch,
                    onChanged: (v) async {
                      await state.updatePrefs(prefs.copyWith(killSwitch: v));
                      if (state.isConnected) {
                        state.showToast(
                            'Applies fully from the next connection');
                      }
                    },
                  ),
                ),
                if (defaultTargetPlatform == TargetPlatform.android)
                  _AndroidAlwaysOnRows(state: state),
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

/// The Always-on pair of rows (Android only): the in-app opt-in toggle and a
/// shortcut into the system VPN screen. Android gives no API to flip the
/// system's Always-on switch from an app, so the closest honest UX is showing
/// the live system state (the secure setting is readable) and walking the
/// user to the exact screen. Re-reads the state whenever the app resumes,
/// i.e. right after the user comes back from Android settings.
class _AndroidAlwaysOnRows extends StatefulWidget {
  final AppState state;
  const _AndroidAlwaysOnRows({required this.state});

  @override
  State<_AndroidAlwaysOnRows> createState() => _AndroidAlwaysOnRowsState();
}

class _AndroidAlwaysOnRowsState extends State<_AndroidAlwaysOnRows>
    with WidgetsBindingObserver {
  VpnStatus? _status;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final st = await VpnController.status();
    if (mounted) setState(() => _status = st);
  }

  String get _systemSubtitle {
    final st = _status;
    if (st == null) return 'Checking the system Always-on state…';
    if (!st.alwaysOn) return 'System Always-on is off · tap to open';
    return st.lockdown
        ? 'System Always-on is on, with Block connections without VPN'
        : 'System Always-on is on';
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final prefs = state.prefs;
    return Column(children: [
      HipListRow(
        title: 'Always-on VPN',
        subtitle:
            'Reconnect the last server when Android\'s Always-on VPN starts hideip.net',
        trailing: HipToggle(
          on: prefs.alwaysOn,
          onChanged: (v) async {
            await state.updatePrefs(prefs.copyWith(alwaysOn: v));
            // The system half can only be flipped by the user in Android
            // settings; take them straight there when it is still off.
            if (v && _status?.alwaysOn != true) {
              state.showToast(
                  'Tap the gear next to hideip.net and turn on Always-on VPN');
              await VpnController.openVpnSettings();
            }
          },
        ),
      ),
      Container(height: 1, color: Hip.line2),
      HipListRow(
        title: 'Android VPN settings',
        subtitle: _systemSubtitle,
        trailing: Icon(Icons.chevron_right, size: 17, color: Hip.muted2),
        onTap: VpnController.openVpnSettings,
      ),
    ]);
  }
}
