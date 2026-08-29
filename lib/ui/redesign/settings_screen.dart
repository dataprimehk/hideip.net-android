import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

import '../../core/premium.dart';
import '../../core/ui_prefs.dart';
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
              // The Account section rides on the plans catalog being live for
              // this platform; an existing subscriber keeps it regardless
              // (plansOffered stays true while premium is on).
              if (kPlansAvailable && state.plansOffered) ...[
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
                        ? nav.openPaywall(from: HipScreen.settings)
                        : nav.go(HipScreen.premium),
                  ),
                  // Only a phone that actually holds a provisioned
                  // subscription can hand access to anything else, so the row
                  // appears with the token rather than with the entitlement.
                  if (state.canLinkDevices)
                    HipListRow(
                      leading: grayTile(Icons.devices_outlined),
                      title: 'Linked devices',
                      subtitle: 'Use Premium in your browser and on desktop',
                      trailing: Icon(Icons.chevron_right,
                          size: 17, color: Hip.muted2),
                      onTap: () => nav.go(HipScreen.linkedDevices),
                    ),
                ]),
              ],
              const HipSectionLabel('Interface'),
              HipListGroup(children: [
                HipListRow(
                  leading: grayTile(Icons.dark_mode_outlined),
                  title: 'Dark mode',
                  subtitle: 'Darker surfaces across the whole app',
                  // Placeholder wiring: F4 replaces this toggle with the
                  // three-way Light / Dark / System segment the design asks
                  // for. Until then the switch drives the same setting, with
                  // System reading as off.
                  trailing: HipToggle(
                    on: prefs.themeMode == AppThemeMode.dark,
                    onChanged: (v) => state.setThemeMode(
                        v ? AppThemeMode.dark : AppThemeMode.light),
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
                // Speed mode rides on the hideip.net fleet, which is what the
                // subscription pays for. The copy says "hideip.net locations"
                // on purpose: WireGuard itself is free, anyone can import
                // their own through Add connection.
                if (premium.isOn)
                  HipListRow(
                    title: 'Speed mode',
                    subtitle: state.speedDeviceLimit
                        ? 'Already set up on 5 devices; turn it off on one of them'
                        : 'WireGuard on hideip.net locations, where the network allows it',
                    trailing: HipToggle(
                      on: prefs.speedMode,
                      onChanged: (v) async {
                        await state.setSpeedMode(v);
                        if (v && state.isConnected) {
                          state.showToast(
                              'Applies from the next connection');
                        }
                      },
                    ),
                  )
                else if (kPlansAvailable && state.plansOffered)
                  HipListRow(
                    title: 'Speed mode',
                    titleBadge: HipBadge.blue('New'),
                    // The second clause matters: a lock next to the word
                    // WireGuard would otherwise read as "WireGuard is paid".
                    subtitle: 'Part of Premium. WireGuard on hideip.net '
                        'locations; importing your own config is free.',
                    trailing:
                        Icon(Icons.lock_outline, size: 17, color: Hip.muted2),
                    onTap: () => nav.openPaywall(from: HipScreen.settings),
                  ),
                if (defaultTargetPlatform == TargetPlatform.android)
                  _AndroidAlwaysOnRows(state: state),
              ]),
              const HipSectionLabel('Privacy'),
              HipListGroup(children: [
                HipListRow(
                  leading: grayTile(Icons.bar_chart_outlined),
                  title: 'Anonymous usage counts',
                  subtitle: 'Three one-time events, no identifiers. '
                      'Details at hideip.net/privacy',
                  trailing: HipToggle(
                    on: prefs.usageCounts,
                    onChanged: (v) =>
                        state.updatePrefs(prefs.copyWith(usageCounts: v)),
                  ),
                ),
              ]),
              const HipSectionLabel('Connections'),
              HipListGroup(children: [
                HipListRow(
                  title: 'Add connection',
                  subtitle:
                      'From any provider, or your own WireGuard server',
                  trailing: Icon(Icons.chevron_right, size: 17, color: Hip.muted2),
                  onTap: () => nav.openImport(),
                ),
                HipListRow(
                  title: 'Replay setup',
                  trailing: Icon(Icons.chevron_right, size: 17, color: Hip.muted2),
                  onTap: () => nav.go(HipScreen.onboarding),
                ),
              ]),
              // Apple guideline 2.3.10: no other-platform mentions on iOS.
              HipSubnote(defaultTargetPlatform == TargetPlatform.iOS
                  ? 'hideip.net · Open source · No logs'
                  : 'hideip.net · Open source · No logs\n'
                      'Same app on iOS and Android.'),
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
