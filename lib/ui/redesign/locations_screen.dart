import 'package:flutter/material.dart';

import '../../core/country_names.dart';
import '../../core/location.dart';
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
              const _PremiumSectionHead(),
              if (hasSub && premiumLocs.isNotEmpty)
                HipListGroup(children: [
                  for (final l in premiumLocs) serverRow(l),
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
                    trailing:
                        Icon(Icons.chevron_right, size: 18, color: Hip.muted2),
                    onTap: () => nav.openPaywall(HipScreen.locations),
                  ),
                ]),
              const HipSectionLabel('Your servers'),
              if (userLocs.isEmpty)
                HipCard(
                  child: Text(
                    'No servers yet. Add a connection from your provider to get started.',
                    style: Hip.sans(400, 13.5, color: Hip.muted, height: 1.5),
                  ),
                )
              else
                HipListGroup(children: [
                  for (final l in userLocs) serverRow(l),
                ]),
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
