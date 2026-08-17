import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/country_names.dart';
import '../../core/location.dart';
import '../../core/sub_info.dart';
import '../../core/votes.dart';
import '../../state/app_state.dart';
import 'hip.dart';
import 'shell.dart';

/// Server list: Auto on top, then the user's servers with clean names.
/// Advanced view swaps subtitles for endpoints and exposes the detail screen.
class LocationsScreen extends StatelessWidget {
  final AppState state;
  final HipNav nav;
  const LocationsScreen({super.key, required this.state, required this.nav});

  /// The "Your servers" list, grouped: profiles that came from the same
  /// subscription URL sit under a compact header row (provider title, data
  /// used, expiry); everything else (single-link imports) stays flat above.
  /// Order follows first appearance so the list stays stable across refreshes.
  List<Widget> _buildUserServers(
      List<Location> userLocs, Widget Function(Location) serverRow) {
    final loose = <Location>[]; // no subUrl: plain imports
    final grouped = <String, List<Location>>{}; // subUrl -> its locations
    final order = <String>[]; // subUrls in first-seen order
    for (final l in userLocs) {
      final u = l.profile.subUrl;
      if (u == null) {
        loose.add(l);
      } else {
        final group = grouped[u];
        if (group == null) {
          order.add(u);
          grouped[u] = [l];
        } else {
          group.add(l);
        }
      }
    }

    return [
      if (loose.isNotEmpty)
        HipListGroup(children: [for (final l in loose) serverRow(l)]),
      for (final u in order) ...[
        _SubHeader(
          info: state.subInfoFor(u),
          fallbackHost: Uri.tryParse(u)?.host ?? u,
        ),
        HipListGroup(children: [for (final l in grouped[u]!) serverRow(l)]),
      ],
    ];
  }

  Future<void> _select(Location? loc) async {
    await state.selectLocation(loc);
    nav.go(HipScreen.home);
    if (state.isConnected) {
      // Changing servers mid-tunnel means a quick reconnect.
      await state.disconnect();
      await state.connect();
    }
  }

  @override
  Widget build(BuildContext context) {
    final advanced = state.prefs.advanced;
    final auto = state.prefs.autoSelect;
    final locations = state.locations;
    final premiumLocs = locations.where((l) => l.premium).toList();
    final userLocs = locations.where((l) => !l.premium).toList();
    final hasSub = state.premium.isOn;

    Widget serverRow(Location l) => HipListRow(
          leading: HipFlag(cc: l.cc),
          title: l.city,
          titleBadge: l.premium
              ? HipBadge.blue('hideip.net')
              : (l.provider != null ? HipBadge.blue(l.provider!) : null),
          subtitle: advanced ? '${l.protoLabel} · ${l.host}' : l.country,
          subtitleMono: advanced,
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            HipBars(level: state.levelFor(l.profile)),
            SizedBox(
              width: 30,
              child: !auto && state.selectedIndex == l.index
                  ? Icon(Icons.check, size: 18, color: Hip.blue)
                  : null,
            ),
            if (advanced)
              GestureDetector(
                onTap: () => nav.openDetail(l),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child:
                      Icon(Icons.chevron_right, size: 18, color: Hip.muted2),
                ),
              ),
          ]),
          onTap: () => _select(l),
        );

    return SafeArea(
      bottom: false,
      child: Column(children: [
        HipNavHead(
          title: 'Locations',
          onBack: () => nav.go(HipScreen.home),
          trailing: HipIconButton(Icons.add, onTap: () => nav.openImport()),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              HipListGroup(children: [
                HipListRow(
                  leading: HipFlag(
                      cc: '',
                      child: Icon(Icons.bolt_outlined,
                          size: 19, color: Hip.blueDeep)),
                  title: 'Auto',
                  subtitle: 'Always picks the fastest server',
                  trailing: auto
                      ? Icon(Icons.check, size: 18, color: Hip.blue)
                      : const SizedBox(width: 18),
                  onTap: () => _select(null),
                ),
              ]),
              // The whole Premium section rides on the plans catalog being
              // live for this platform and confirmed purchasable; an existing
              // subscriber keeps their servers visible regardless (plansOffered
              // stays true while premium is on, and hasSub mirrors it here).
              if ((kPlansAvailable && state.plansOffered) || hasSub) ...[
                const _PremiumSectionHead(),
                if (hasSub && premiumLocs.isNotEmpty)
                  HipListGroup(children: [
                    for (final l in premiumLocs) serverRow(l),
                  ])
                else if (hasSub && state.premiumEnded)
                  // The backend is finished with this subscription; waiting on
                  // servers that will never arrive would be the wrong story.
                  HipListGroup(children: [
                    HipListRow(
                      leading: HipFlag(
                          cc: '',
                          child: Icon(Icons.error_outline,
                              size: 19, color: Hip.muted2)),
                      title: 'Subscription expired',
                      subtitle: 'Renew it to get your premium locations back',
                    ),
                  ])
                else if (hasSub)
                  // Subscribed, but the profiles have not landed yet (first
                  // provision in flight, or offline): keep the place visible.
                  HipListGroup(children: [
                    HipListRow(
                      leading: HipFlag(
                          cc: '',
                          child: SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Hip.blueDeep),
                          )),
                      title: 'Setting up your servers',
                      subtitle: 'Premium locations appear here shortly',
                    ),
                  ])
                else
                  HipListGroup(children: [
                    HipListRow(
                      leading: HipFlag(
                          cc: '',
                          child: Text('IP',
                              style: Hip.mono(700, 13,
                                  color: Hip.blueDeep, letterSpacing: .5))),
                      title: 'Premium servers',
                      subtitle: 'Fast locations run by hideip.net',
                      trailing: Icon(Icons.chevron_right,
                          size: 18, color: Hip.muted2),
                      onTap: () => nav.openPaywall(HipScreen.locations),
                    ),
                  ]),
              ],
              const HipSectionLabel('Your servers'),
              if (userLocs.isEmpty)
                HipCard(
                  child: Text(
                    'No servers yet. Add a connection from your provider to get started.',
                    style: Hip.sans(400, 13.5, color: Hip.muted, height: 1.5),
                  ),
                )
              else
                ..._buildUserServers(userLocs, serverRow),
              if (userLocs.isNotEmpty)
                const HipSubnote(
                    'Names and flags are cleaned up automatically from whatever your provider sends.'),
              _VoteSection(onOpenMap: () {
                final prefs = state.prefs;
                if (!prefs.homeMap) {
                  state.updatePrefs(prefs.copyWith(homeMap: true));
                }
                nav.go(HipScreen.home);
              }),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
              22, 14, 22, MediaQuery.paddingOf(context).bottom + 14),
          child: HipCta(
            'Add connection',
            ghost: true,
            leading: const Icon(Icons.add),
            onTap: () => nav.openImport(),
          ),
        ),
      ]),
    );
  }
}

/// Compact header above a subscription's servers: the provider title (or the
/// URL host when it sent none), and, when the provider reported them, the data
/// used against the quota and the expiry date. Numbers and the date render in
/// mono per the brand rules. A trailing icon opens the seller's panel when a
/// web-page URL is known. Deliberately one quiet row, no card-within-card.
class _SubHeader extends StatelessWidget {
  final SubInfo? info;
  final String fallbackHost;
  const _SubHeader({required this.info, required this.fallbackHost});

  @override
  Widget build(BuildContext context) {
    final i = info;
    final title = (i?.title != null && i!.title!.isNotEmpty) ? i.title! : fallbackHost;

    // Data used against the quota, e.g. "1.5 / 50.0 GB". Only when a quota is
    // known; a bare used figure without a total reads as noise here.
    String? usage;
    if (i != null && i.hasQuota) {
      usage = '${SubInfo.formatBytes(i.usedBytes).replaceAll(' GB', '')}'
          ' / ${SubInfo.formatBytes(i.totalBytes!)}';
    }

    // Expiry: past -> danger; within 7 days -> muted date; otherwise silent
    // (unless usage carries the row) to keep the header short.
    String? expiryText;
    Color? expiryColor;
    final e = i?.expire;
    if (e != null) {
      final now = DateTime.now();
      if (e.isBefore(now)) {
        expiryText = 'Expired ${_date(e)}';
        expiryColor = Hip.danger;
      } else if (e.difference(now).inDays <= 7) {
        expiryText = 'Expires ${_date(e)}';
        expiryColor = Hip.muted;
      }
    }

    final webUrl = i?.webPageUrl;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 16, 6, 6),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title.toUpperCase(),
                overflow: TextOverflow.ellipsis,
                style: Hip.sans(650, 12, color: Hip.muted2, letterSpacing: .84)),
            if (usage != null || expiryText != null)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Row(children: [
                  if (usage != null)
                    Text(usage, style: Hip.mono(600, 11, color: Hip.muted)),
                  if (usage != null && expiryText != null)
                    Text('  ·  ', style: Hip.sans(400, 11, color: Hip.muted2)),
                  if (expiryText != null)
                    Text(expiryText,
                        style: Hip.mono(600, 11, color: expiryColor)),
                ]),
              ),
          ]),
        ),
        // url_launcher is already a dependency (used by the paywall), so the
        // panel button ships; no deferral needed.
        if (webUrl != null)
          HipIconButton(
            Icons.open_in_new,
            color: Hip.muted2,
            onTap: () => launchUrl(Uri.parse(webUrl),
                mode: LaunchMode.externalApplication),
          ),
      ]),
    );
  }

  /// Short date like "24 Jul 2026" (mono digits carry it).
  static String _date(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}

/// Section header for the managed servers: the brand wordmark where the
/// other sections carry an uppercase label, same metrics so the rhythm of
/// the list holds on any screen width.
class _PremiumSectionHead extends StatelessWidget {
  const _PremiumSectionHead();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(14, 18, 14, 7),
      child: Align(
        alignment: Alignment.centerLeft,
        child: HipWordmark(size: 13.5),
      ),
    );
  }
}

/// "Coming next": the pointer to voting on the map plus the live leaderboard.
/// Counts render only once the server has ever answered (see VoteService);
/// until then the section still shows the user's own votes, just without
/// numbers, so a cast vote never looks lost.
class _VoteSection extends StatefulWidget {
  final VoidCallback onOpenMap;
  const _VoteSection({required this.onOpenMap});

  @override
  State<_VoteSection> createState() => _VoteSectionState();
}

class _VoteSectionState extends State<_VoteSection> {
  final VoteService _votes = VoteService.instance;
  Map<String, String> _names = const {};

  @override
  void initState() {
    super.initState();
    _votes.addListener(_changed);
    _votes.init();
    CountryNames.load().then((m) {
      if (mounted) setState(() => _names = m);
    });
  }

  @override
  void dispose() {
    _votes.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final board = _votes.leaderboard(5);
    final onBoard = {for (final (cc, _) in board) cc};
    // The user's own votes always show, even below the top 5 or before the
    // server has ever answered.
    final mine = _votes.mine.where((cc) => !onBoard.contains(cc)).toList()
      ..sort((a, b) => (_names[a] ?? a).compareTo(_names[b] ?? b));

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const HipSectionLabel('Coming next'),
      HipListGroup(children: [
        HipListRow(
          leading: HipFlag(
              cc: '',
              child: Icon(Icons.how_to_vote, size: 19, color: Hip.blueDeep)),
          title: 'Vote for new locations',
          subtitle: 'Anonymous voting on the map',
          trailing: Icon(Icons.chevron_right, size: 18, color: Hip.muted2),
          onTap: widget.onOpenMap,
        ),
        for (final (i, (cc, count)) in board.indexed)
          HipListRow(
            leading: HipFlag(cc: '${i + 1}'),
            title: _names[cc] ?? cc,
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              if (_votes.hasVoted(cc)) ...[
                Icon(Icons.check, size: 15, color: Hip.blue),
                const SizedBox(width: 7),
              ],
              Text('$count', style: Hip.mono(700, 13, color: Hip.ink)),
              const SizedBox(width: 4),
              Text('votes', style: Hip.sans(500, 12, color: Hip.muted)),
            ]),
            onTap: widget.onOpenMap,
          ),
        for (final cc in mine)
          HipListRow(
            leading: HipFlag(
                cc: '',
                child: Icon(Icons.check, size: 17, color: Hip.blueDeep)),
            title: _names[cc] ?? cc,
            subtitle: 'Your vote',
            trailing: switch (_votes.displayCount(cc)) {
              null => null,
              final count => Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('$count', style: Hip.mono(700, 13, color: Hip.ink)),
                  const SizedBox(width: 4),
                  Text('votes', style: Hip.sans(500, 12, color: Hip.muted)),
                ]),
            },
            onTap: widget.onOpenMap,
          ),
      ]),
      if (board.isNotEmpty || mine.isNotEmpty)
        const HipSubnote(
            'Anonymous, one vote per country. Tap a country on the map to change yours.'),
    ]);
  }
}
