import 'package:flutter/material.dart';

import '../../core/location.dart';
import '../strings.dart';
import 'hip.dart';

/// Where a locked row was tapped. The paywall gets this so the moment it
/// opens in can be told apart from every other way in.
enum LockedFrom {
  /// One locked row in the home list.
  homeRow,

  /// A locked row among home search results.
  homeSearch,

  /// The locked group on the Locations screen.
  locationsLock,

  /// The paused locations on the trial-expired screen.
  expired,
}

/// A hideip.net location the user has no subscription for.
///
/// Same shape as every other row, with the real measured latency in place:
/// the comparison is what sells, so nothing here pulses and nothing shouts.
/// Ported from `design/app-1_1_0/screens-home.jsx` `LockedRow`.
///
/// Simple view puts `{country} · {ms} ms` in the subtitle; Advanced view swaps
/// it for the mono chain `{proto} · {host}`, exactly like an open row.
class LockedRow extends StatelessWidget {
  final Location location;

  /// Measured latency, or null while the probe has not answered yet (the row
  /// then shows the country alone rather than inventing a number).
  final int? pingMs;

  /// Signal bars, 0 to 4.
  final int level;
  final bool advanced;
  final LockedFrom from;
  final void Function(LockedFrom from, String locId)? onTap;

  const LockedRow({
    super.key,
    required this.location,
    required this.from,
    this.pingMs,
    this.level = 0,
    this.advanced = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ms = pingMs;
    final subtitle = advanced
        ? S.tunnelChain(location.protoLabel, location.host)
        : (ms == null ? location.country : S.lockedSub(location.country, ms));
    return HipListRow(
      leading: HipFlag(cc: location.cc),
      title: location.city,
      titleBadge: location.won
          ? HipBadge.won(S.badgeVoted, icon: Icons.emoji_events_outlined)
          : null,
      subtitle: subtitle,
      subtitleMono: advanced,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        HipBars(level: level),
        const SizedBox(width: 12),
        // app.css `.lockic.sm`: the padlock is the deep blue, not a muted
        // gray. It marks what a plan opens, so it wears the brand colour.
        Icon(Icons.lock_outline, size: 17, color: Hip.blueDeep),
      ]),
      onTap: onTap == null ? null : () => onTap!(from, location.id),
    );
  }
}
