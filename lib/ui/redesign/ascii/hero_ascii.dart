import 'package:flutter/widgets.dart';

import '../mark.dart' show MarkState;

/// Which field the hero draws. `modeFor(state)` in
/// `design/app-1_1_0/home-ascii.js`: connected is hidden, connecting and
/// disconnecting are transit, everything else is exposed.
enum HeroAsciiMode { exposed, transit, hidden }

/// The mode [state] belongs to, and with it the palette and the glyph set.
HeroAsciiMode heroAsciiModeFor(MarkState state) => switch (state) {
      MarkState.connected => HeroAsciiMode.hidden,
      MarkState.connecting || MarkState.disconnecting => HeroAsciiMode.transit,
      MarkState.disconnected => HeroAsciiMode.exposed,
    };

/// The ASCII field behind the home status card.
///
/// **This is the F0 stub.** It renders nothing and holds no ticker, so Home
/// can mount it today and the engine can land later without touching the
/// screen. F7 fills it in from `design/app-1_1_0/home-ascii.js` using
/// `ascii/ascii_core.dart`.
///
/// The signature is frozen as of F0 and does not change when the engine
/// arrives: [state] drives the mode and the one-shot wave (left to right on
/// connect, right to left on disconnect), and [front] selects the sparser,
/// larger foreground layer that sits over the card.
class HeroAscii extends StatelessWidget {
  final MarkState state;
  final bool front;

  const HeroAscii({super.key, required this.state, this.front = false});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
