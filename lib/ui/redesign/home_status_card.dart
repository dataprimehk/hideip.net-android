import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../brand.dart';
import '../strings.dart';
import 'hip.dart';

/// The four tones the status card can be in. They are what the whole card
/// is coloured from, so a state can never say one thing and look another.
enum StatusTone {
  /// No network at all: neutral grey, nothing to alarm anyone with.
  off,

  /// A handshake is in flight.
  busy,

  /// The tunnel is up.
  safe,

  /// The real address is on show.
  risk,
}

/// The glass status card on the hero panel (`hero-compact` in
/// `design/app-1_1_0/screens-home.jsx`, `.statcard` in `app.css`).
///
/// Everything it shows arrives as a plain value: the card has no idea what a
/// tunnel is, which keeps it honest and makes every state testable without a
/// running app. The one thing it owns is the copy affordance, because the
/// check mark that replaces the icon for 1400 ms is purely local.
///
/// The card is deliberately NOT a button. Only the copy icon reacts to a tap,
/// so nobody discovers by accident that the hero opens something.
class HomeStatusCard extends StatefulWidget {
  final StatusTone tone;

  /// The status word: `Exposed`, `Protected`, `Connecting…`, `No connection`.
  final String status;

  /// The address on show, or null while there is nothing to show (offline).
  final String? ip;

  /// The line under the address: `ISP · City, CC` exposed, `City, Country`
  /// connected, the offline explanation when there is no network.
  final String context;

  /// The extra line a slow handshake earns after ten seconds (B16).
  final String? slowLine;

  const HomeStatusCard({
    super.key,
    required this.tone,
    required this.status,
    required this.context,
    this.ip,
    this.slowLine,
  });

  @override
  State<HomeStatusCard> createState() => _HomeStatusCardState();
}

class _HomeStatusCardState extends State<HomeStatusCard>
    with SingleTickerProviderStateMixin {
  bool _copied = false;
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    _syncSpin();
  }

  @override
  void didUpdateWidget(HomeStatusCard old) {
    super.didUpdateWidget(old);
    if (old.tone != widget.tone) _syncSpin();
  }

  // Reduced motion keeps the icon still: the word "Connecting…" already says
  // everything the spin was there to say.
  void _syncSpin() {
    if (widget.tone == StatusTone.busy && !Hip.reducedMotion) {
      _spin.repeat();
    } else {
      _spin.stop();
      _spin.value = 0;
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  Future<void> _copy() async {
    final ip = widget.ip;
    if (ip == null || ip.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: ip));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (mounted) setState(() => _copied = false);
  }

  Color get _sc => switch (widget.tone) {
        StatusTone.off => Brand.hsl(220, 8, 60),
        StatusTone.busy => Brand.hsl(220, 95, 62),
        StatusTone.safe => Brand.hsl(152, 60, 52),
        StatusTone.risk => Brand.hsl(4, 82, 64),
      };

  IconData get _icon => switch (widget.tone) {
        StatusTone.off => Icons.public,
        StatusTone.busy => Icons.autorenew,
        StatusTone.safe => Icons.shield_outlined,
        StatusTone.risk => Icons.visibility_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final sc = _sc;
    final ip = widget.ip;
    final white = Colors.white;
    return AnimatedContainer(
      duration: Hip.dur(const Duration(milliseconds: 900)),
      curve: Curves.easeOut,
      padding: const EdgeInsets.fromLTRB(15, 14, 15, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Brand.hsl(222, 18, 15, .30),
            Brand.hsl(222, 22, 9, .46),
          ],
        ),
        border: Border.all(color: white.withValues(alpha: .16)),
        boxShadow: [
          BoxShadow(
            color: sc.withValues(alpha: .30),
            blurRadius: 30,
            spreadRadius: -12,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: Brand.hsl(222, 40, 4, .5),
            blurRadius: 10,
            spreadRadius: -4,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(children: [
        // --- tone icon ----------------------------------------------------
        AnimatedContainer(
          duration: Hip.dur(const Duration(milliseconds: 900)),
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: sc.withValues(alpha: .14),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: sc.withValues(alpha: .26)),
          ),
          child: Center(
            child: RotationTransition(
              turns: _spin,
              child: Icon(_icon, size: 20, color: sc),
            ),
          ),
        ),
        const SizedBox(width: 13),

        // --- status, address, context ---------------------------------------
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                _ToneDot(color: sc, fast: widget.tone == StatusTone.busy),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    widget.status.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Hip.sans(750, 10.5,
                        color: sc, letterSpacing: .95, height: 1.1),
                  ),
                ),
              ]),
              if (ip != null) ...[
                const SizedBox(height: 2.5),
                AnimatedOpacity(
                  duration: Hip.dur(const Duration(milliseconds: 300)),
                  opacity: widget.tone == StatusTone.busy ? .55 : 1,
                  child: Text(
                    ip,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Hip.mono(650, 18,
                        color: white, letterSpacing: .27, height: 1.15),
                  ),
                ),
              ],
              const SizedBox(height: 2.5),
              Text(
                widget.context,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Hip.sans(400, 11.5,
                    color: white.withValues(alpha: .5), height: 1.2),
              ),
              if (widget.slowLine != null) ...[
                const SizedBox(height: 4),
                Text(
                  widget.slowLine!,
                  style: Hip.sans(400, 12,
                      color: white.withValues(alpha: .66), height: 1.4),
                ),
              ],
            ],
          ),
        ),

        // --- copy -----------------------------------------------------------
        if (ip != null) ...[
          const SizedBox(width: 8),
          Semantics(
            button: true,
            label: _copied ? S.homeCopiedIp : S.homeCopyIp,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _copy,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: white.withValues(alpha: .05),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: white.withValues(alpha: .08)),
                    ),
                    child: Icon(
                      _copied ? Icons.check : Icons.copy_outlined,
                      size: 15,
                      color: _copied
                          ? Brand.hsl(152, 60, 60)
                          : white.withValues(alpha: .45),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

/// The small pulsing dot in front of the status word (`.statcard .st .d`).
class _ToneDot extends StatefulWidget {
  final Color color;
  final bool fast;
  const _ToneDot({required this.color, required this.fast});

  @override
  State<_ToneDot> createState() => _ToneDotState();
}

class _ToneDotState extends State<_ToneDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.fast ? 1000 : 2400),
  );

  @override
  void initState() {
    super.initState();
    if (!Hip.reducedMotion) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_ToneDot old) {
    super.didUpdateWidget(old);
    if (old.fast != widget.fast) {
      _c.duration = Duration(milliseconds: widget.fast ? 1000 : 2400);
      if (!Hip.reducedMotion) _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 1, end: .45).animate(_c),
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}
