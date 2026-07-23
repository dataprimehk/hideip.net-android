import 'package:flutter/material.dart';

import '../../core/haptics.dart';
import '../../core/location.dart';
import '../../core/ping.dart';
import '../../state/app_state.dart';
import '../../vpn_controller.dart';
import '../brand.dart';
import 'hip.dart';
import 'mark.dart';
import 'shell.dart';
import 'worldmap.dart';

/// Home: the dark hero panel (living mark + status + IP) with a Servers/Map
/// switch. Servers keeps a short list under the panel; Map grows the panel
/// over the whole screen and shows the world map.
class HomeHeroScreen extends StatefulWidget {
  final AppState state;
  final HipNav nav;
  const HomeHeroScreen({super.key, required this.state, required this.nav});

  @override
  State<HomeHeroScreen> createState() => _HomeHeroScreenState();
}

class _HomeHeroScreenState extends State<HomeHeroScreen> {
  // The native side disconnects near-instantly; hold the state long enough
  // for the mark's re-expose sweep to read.
  bool _disconnecting = false;

  final _heroKey = GlobalKey();
  final _ctaKey = GlobalKey();
  // Hero content + CTA bar, measured after layout. The measured value is kept
  // across remounts (the shell rebuilds this screen on every visit), so coming
  // back from another screen lays out exactly on the first frame instead of
  // overflowing the column across the CTA until the measurement lands.
  static double? _measuredChrome;
  double? _chromeH = _measuredChrome;

  MarkState get _markState {
    if (_disconnecting) return MarkState.disconnecting;
    switch (widget.state.conn) {
      case ConnState.connecting:
        return MarkState.connecting;
      case ConnState.connected:
        return MarkState.connected;
      case ConnState.disconnected:
      case ConnState.error:
        return MarkState.disconnected;
    }
  }

  (String, String) get _statusCopy {
    if (_disconnecting) return ('Disconnecting…', 'Closing the tunnel.');
    switch (widget.state.conn) {
      case ConnState.connecting:
        return ('Connecting…', 'Securing your connection.');
      case ConnState.connected:
        return ('Connected', 'Your traffic is private.');
      case ConnState.error:
        return ('Not connected', widget.state.error ?? 'Something went wrong.');
      case ConnState.disconnected:
        return ('Not connected', 'Your IP is exposed.');
    }
  }

  Future<void> _disconnect() async {
    setState(() => _disconnecting = true);
    // Let the scan line sweep before the state actually flips.
    await Future.delayed(const Duration(milliseconds: 850));
    await widget.state.disconnect();
    if (mounted) setState(() => _disconnecting = false);
    _maybeWarnAlwaysOn();
  }

  /// With Android's system Always-on VPN enabled but our in-app Always-on
  /// opt-in off, the OS can keep holding traffic after a disconnect (the
  /// service refuses the system's restart). The user has to resolve that in
  /// system settings, so say it plainly and take them there.
  void _maybeWarnAlwaysOn() {
    final state = widget.state;
    if (!mounted || !state.systemAlwaysOn || state.prefs.alwaysOn) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Hip.card,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Hip.radius)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Always-on VPN is still active',
                  style: Hip.sans(650, 17, color: Hip.ink)),
              const SizedBox(height: 10),
              Text(
                'Android\'s Always-on VPN is enabled for hideip.net, so the '
                'system may keep blocking traffic while you are disconnected. '
                'Turn it off in Android settings, or enable Always-on VPN in '
                'app Settings to reconnect automatically.',
                style: Hip.sans(550, 14, color: Hip.inkSoft, height: 1.45),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text('Dismiss',
                        style: Hip.sans(650, 14, color: Hip.muted)),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      VpnController.openVpnSettings();
                    },
                    child: Text('Open Android settings',
                        style: Hip.sans(650, 14, color: Hip.blue)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _selectFromMap(Location loc) async {
    final state = widget.state;
    await state.selectLocation(loc);
    if (state.isConnected) {
      await state.disconnect();
      await state.connect();
    }
  }

  void _setMapMode(bool map) {
    final prefs = widget.state.prefs;
    if (prefs.homeMap != map) {
      Haptics.selection();
      widget.state.updatePrefs(prefs.copyWith(homeMap: map));
    }
  }

  void _measureChrome() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final hero = _heroKey.currentContext?.size?.height;
      final cta = _ctaKey.currentContext?.size?.height;
      if (hero == null || cta == null || !mounted) return;
      final h = hero + cta;
      if ((h - (_chromeH ?? 0)).abs() > 1) {
        _measuredChrome = h;
        setState(() => _chromeH = h);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final nav = widget.nav;
    final on = state.isConnected && !_disconnecting;
    final busy = state.isBusy || _disconnecting;
    final loc = state.activeLocation;
    final (title, sub) = _statusCopy;
    final hasServers = state.profiles.isNotEmpty;
    final mapMode = state.prefs.homeMap;
    _measureChrome();

    final activePing = loc == null ? null : state.pingFor(loc.profile);

    return LayoutBuilder(builder: (context, cons) {
      // Before the first measurement the guess must only ever overshoot: a map
      // a touch too short settles smoothly, a map too tall overflows the
      // column. 470 covers the fixed hero + CTA content with slack to spare.
      final pad = MediaQuery.paddingOf(context);
      final chrome = _chromeH ?? (pad.top + pad.bottom + 470);
      // 14 = the map's top margin inside the hero panel.
      final mapH = (cons.maxHeight - chrome - 14).clamp(0.0, cons.maxHeight);
      // In map mode the strip under the panel (where the CTA sits) darkens
      // with the same timing as the map expand, so the screen reads as one
      // dark surface instead of a light band under a wall of map.
      return AnimatedContainer(
        duration: const Duration(milliseconds: 650),
        curve: const Cubic(.32, .72, 0, 1),
        color: mapMode ? Hip.hero : Hip.surface,
        child: Column(children: [
        // --- dark hero panel ------------------------------------------------
        ClipRRect(
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            width: double.infinity,
            decoration: BoxDecoration(
              // Both states are gradients so the implicit animation is a
              // clean color wash; lerping a solid color against a gradient
              // dips through transparency halfway and reads as a flash.
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: on
                    ? const [Color(0xFF0B1410), Color(0xFF0D2A1E)]
                    : [Hip.hero, Hip.hero],
              ),
            ),
            child: Column(children: [
              Column(key: _heroKey, children: [
                SizedBox(height: MediaQuery.paddingOf(context).top + 6),
                HipAppHead(
                  onDark: true,
                  onServers: () => nav.go(HipScreen.locations),
                  onSettings: () => nav.go(HipScreen.settings),
                ),
                HideipMark(state: _markState, unit: 32, darkSurface: true),
                const SizedBox(height: 4),
                // Status flips (Connecting… -> Connected) crossfade with a
                // small rise instead of snapping between frames.
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 320),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween(
                              begin: const Offset(0, .22), end: Offset.zero)
                          .animate(anim),
                      child: child,
                    ),
                  ),
                  child: Text(title,
                      key: ValueKey(title),
                      style: Hip.sans(700, 26,
                          color: on ? Brand.hsl(152, 60, 60) : Colors.white,
                          letterSpacing: -.65)),
                ),
                const SizedBox(height: 5),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 320),
                  child: Text(sub,
                      key: ValueKey(sub),
                      style: Hip.sans(400, 13.5,
                          color: Colors.white.withValues(alpha: .55))),
                ),
                const SizedBox(height: 18),
                _IpLine(state: state, protectedNow: on),
                const SizedBox(height: 16),
                _HomeSeg(mapMode: mapMode, onChanged: _setMapMode),
                // Animates in step with the map container below: jumping to
                // 20 while the map is still tall overflows the hero by 20px.
                AnimatedContainer(
                  duration: const Duration(milliseconds: 650),
                  curve: const Cubic(.32, .72, 0, 1),
                  height: mapMode ? 0 : 20,
                ),
              ]),
              // The map keeps living (camera and all) while collapsed; only
              // its height animates, so the expand is one fluid move.
              AnimatedContainer(
                duration: const Duration(milliseconds: 650),
                curve: const Cubic(.32, .72, 0, 1),
                height: mapMode ? mapH : 0,
                margin: EdgeInsets.only(top: mapMode ? 14 : 0),
                child: WorldMap(
                  locations: state.locations,
                  active: loc,
                  conn: _markState,
                  advanced: state.prefs.advanced,
                  open: mapMode,
                  userGeo: state.userGeo,
                  activePingMs: activePing is PingOk ? activePing.ms : null,
                  onPick: _selectFromMap,
                  onConnect: () {
                    if (busy) return;
                    hasServers ? state.connect() : nav.openImport();
                  },
                  onAllLocations: () => nav.go(HipScreen.locations),
                ),
              ),
            ]),
          ),
        ),

        // --- server list (hidden in map mode) -------------------------------
        Expanded(
          child: IgnorePointer(
            ignoring: mapMode,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: mapMode ? 0 : 1,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: _HomeList(state: state, nav: nav, on: on),
              ),
            ),
          ),
        ),

        // --- CTA bar --------------------------------------------------------
        Padding(
          key: _ctaKey,
          padding: EdgeInsets.fromLTRB(
              22, 14, 22, MediaQuery.paddingOf(context).bottom + 14),
          // The two CTA variants (filled Connect / ghost Disconnect) swap
          // with a short crossfade; a hard swap between such different
          // buttons reads as a glitch.
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: ScaleTransition(
                scale: Tween(begin: .98, end: 1.0).animate(anim),
                child: child,
              ),
            ),
            child: on || _disconnecting
                ? HipCta(
                    _disconnecting ? 'Disconnecting…' : 'Disconnect',
                    key: const ValueKey('cta-off'),
                    ghost: true,
                    danger: true,
                    darkGhost: mapMode,
                    onTap: _disconnecting ? null : _disconnect,
                  )
                : HipCta(
                    state.isBusy ? 'Connecting…' : 'Connect',
                    key: const ValueKey('cta-on'),
                    connect: true,
                    onTap: busy
                        ? null
                        : hasServers
                            ? state.connect
                            : () => nav.openImport(),
                  ),
          ),
        ),
      ]));
    });
  }
}

/// The Servers/Map segmented pill on the hero panel.
class _HomeSeg extends StatelessWidget {
  final bool mapMode;
  final ValueChanged<bool> onChanged;
  const _HomeSeg({required this.mapMode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget seg(String label, IconData icon, bool active, bool toMap) =>
        GestureDetector(
          onTap: () => onChanged(toMap),
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 118,
            padding: const EdgeInsets.symmetric(vertical: 8),
            alignment: Alignment.center,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 300),
                style: Hip.sans(600, 13,
                    color: Colors.white.withValues(alpha: active ? 1 : .55)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon,
                      size: 15,
                      color: Colors.white.withValues(alpha: active ? 1 : .55)),
                  const SizedBox(width: 7),
                  Text(label),
                ]),
              ),
            ]),
          ),
        );

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .06),
        border: Border.all(color: Colors.white.withValues(alpha: .1)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: SizedBox(
        width: 118 * 2 + 3,
        height: 33,
        child: Stack(children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 500),
            curve: const Cubic(.32, .72, 0, 1),
            alignment: mapMode ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 118,
              height: 33,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .13),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          Row(mainAxisSize: MainAxisSize.min, children: [
            seg('Servers', Icons.dns_outlined, !mapMode, false),
            const SizedBox(width: 3),
            seg('Map', Icons.public, mapMode, true),
          ]),
        ]),
      ),
    );
  }
}

/// Servers view: speed while connected, Auto + the fastest picks, then the
/// door to the full list. Mirrors the prototype's home list.
class _HomeList extends StatelessWidget {
  final AppState state;
  final HipNav nav;
  final bool on;
  const _HomeList({required this.state, required this.nav, required this.on});

  @override
  Widget build(BuildContext context) {
    final locations = state.locations;
    if (locations.isEmpty) {
      return HipCard(
        onTap: () => nav.openImport(),
        child: Row(children: [
          const HipFlag(cc: '+', small: false),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('No servers yet', style: Hip.sans(650, 15.5, color: Hip.ink)),
              const SizedBox(height: 3),
              Text('Add a connection to get started',
                  style: Hip.sans(400, 12.5, color: Hip.muted)),
            ]),
          ),
          Icon(Icons.chevron_right, size: 20, color: Hip.muted2),
        ]),
      );
    }

    final active = state.activeLocation;
    final auto = state.prefs.autoSelect;
    final advanced = state.prefs.advanced;

    // Fastest first; unprobed servers keep their list order at the back.
    final sorted = [...locations]..sort((a, b) {
        final pa = state.pingFor(a.profile), pb = state.pingFor(b.profile);
        final ma = pa is PingOk ? pa.ms : 1 << 30;
        final mb = pb is PingOk ? pb.ms : 1 << 30;
        return ma.compareTo(mb);
      });
    final fastest = sorted.first;
    // The chosen server always leads the list, even when it is not among
    // the fastest three; the rest keep the speed order.
    final rows = <Location>[
      if (!auto && active != null) active,
      ...sorted.where((l) => auto || l.index != active?.index),
    ].take(3).toList();

    String subtitleFor(Location l) {
      final ping = state.pingFor(l.profile);
      final ms = ping is PingOk ? ' · ${ping.ms} ms' : '';
      return '${l.country}$ms';
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (on) ...[
        _SpeedCard(stats: state.stats),
        const SizedBox(height: 4),
      ],
      const HipSectionLabel('Recommended'),
      HipListGroup(children: [
        HipListRow(
          leading: HipFlag(cc: '', child: Icon(Icons.bolt, size: 19, color: Hip.blueDeep)),
          title: 'Auto',
          subtitle: 'Fastest server, now ${fastest.city}',
          selected: auto,
          live: auto && on,
          trailing: auto ? Icon(Icons.check, size: 18, color: Hip.blue) : null,
          onTap: () => state.selectLocation(null),
        ),
        for (final l in rows)
          HipListRow(
            leading: HipFlag(cc: l.cc),
            title: l.city,
            titleBadge: l.provider != null ? HipBadge.blue(l.provider!) : null,
            subtitle: advanced ? '${l.protoLabel} · ${l.host}' : subtitleFor(l),
            subtitleMono: advanced,
            selected: !auto && active?.index == l.index,
            live: !auto && active?.index == l.index && on,
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              HipBars(level: state.levelFor(l.profile)),
              SizedBox(
                width: 30,
                child: !auto && active?.index == l.index
                    ? Icon(Icons.check, size: 18, color: Hip.blue)
                    : null,
              ),
            ]),
            onTap: () => state.selectLocation(l),
          ),
      ]),
      const SizedBox(height: 14),
      HipListGroup(children: [
        HipListRow(
          leading: HipFlag(cc: '', child: Icon(Icons.public, size: 19, color: Hip.blueDeep)),
          title: 'All locations',
          subtitle: '${locations.length} '
              '${locations.length == 1 ? 'server' : 'servers'} · import & manage',
          trailing: Icon(Icons.chevron_right, size: 17, color: Hip.muted2),
          onTap: () => nav.go(HipScreen.locations),
        ),
      ]),
    ]);
  }
}

/// "Current IP  185.130.47.77  EXPOSED/Protected" pill on the hero panel.
class _IpLine extends StatelessWidget {
  final AppState state;
  final bool protectedNow;
  const _IpLine({required this.state, required this.protectedNow});

  @override
  Widget build(BuildContext context) {
    final green = Brand.hsl(152, 60, 55);
    final red = Brand.hsl(4, 80, 64);
    final ip = state.publicIp ?? (state.ipLoading ? '…' : 'unknown');
    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: protectedNow
            ? green.withValues(alpha: .1)
            : red.withValues(alpha: .09),
        border: Border.all(
          color: protectedNow
              ? green.withValues(alpha: .3)
              : red.withValues(alpha: .28),
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('Current IP',
            style: Hip.sans(550, 11.5,
                color: Colors.white.withValues(alpha: .45))),
        const SizedBox(width: 10),
        // The address swap (old exit -> new exit) crossfades so the pill
        // does not stutter mid-connect while the lookup settles.
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          child: Text(
            ip,
            key: ValueKey(ip),
            style: Hip.mono(600, 14, color: Colors.white, letterSpacing: .3),
          ),
        ),
        const SizedBox(width: 10),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          child: protectedNow
              ? Row(
                  key: const ValueKey('protected'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.shield_outlined, size: 12, color: green),
                    const SizedBox(width: 4),
                    Text('PROTECTED',
                        style:
                            Hip.sans(700, 11, color: green, letterSpacing: .66)),
                  ],
                )
              : Text('EXPOSED',
                  key: const ValueKey('exposed'),
                  style: Hip.sans(700, 11, color: red, letterSpacing: .66)),
        ),
      ]),
    );
  }
}

/// Live download/upload readout while connected.
class _SpeedCard extends StatelessWidget {
  final VpnStats stats;
  const _SpeedCard({required this.stats});

  static String _rate(int bytesPerSec) {
    if (bytesPerSec >= 1024 * 1024) {
      return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    }
    return '${(bytesPerSec / 1024).round()} KB/s';
  }

  @override
  Widget build(BuildContext context) {
    Widget cell(String arrow, String value, String label, Color valueColor) =>
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$arrow $value', style: Hip.mono(700, 16, color: valueColor)),
            const SizedBox(height: 2),
            Text(label, style: Hip.sans(400, 12, color: Hip.muted)),
          ]),
        );

    return HipCard(
      child: Row(children: [
        cell('↓', _rate(stats.downlink), 'Download', Hip.blue),
        Container(
            width: 1.5,
            height: 34,
            margin: const EdgeInsets.symmetric(horizontal: 14),
            color: Hip.line),
        cell('↑', _rate(stats.uplink), 'Upload', Hip.ink),
      ]),
    );
  }
}
