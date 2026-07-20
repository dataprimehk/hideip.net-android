import 'package:flutter/material.dart';

import '../../core/haptics.dart';
import '../brand.dart';

/// Design tokens and shared widgets for the 2.0 redesign.
///
/// The palette is the same on every platform. It comes in two variants
/// (mirroring app.css `.hip-root` and `.hip-root.dark-mode`): light content
/// surfaces, or dark surfaces when the user turns the in-app dark mode on.
/// The hero/onboarding panel is dark in both.
class Hip {
  Hip._();

  /// Dark-mode switch. The shell sets this from [UiPrefs.darkMode] before
  /// each frame; every token below resolves against it at build time, so a
  /// full rebuild (which the prefs change already triggers) recolors the app.
  static bool dm = false;

  // Palette (mirrors app.css .hip-root custom properties).
  static Color get blue =>
      dm ? Brand.hsl(220, 95, 60) : Brand.hsl(220, 95, 55);
  static Color get blueSoft =>
      dm ? Brand.hsl(220, 95, 60, .14) : Brand.hsl(220, 95, 55, .1);
  static Color get blueDeep =>
      dm ? Brand.hsl(220, 95, 72) : Brand.hsl(220, 95, 48);
  static Color get ink => dm ? Brand.hsl(220, 20, 93) : Brand.hsl(0, 0, 7);
  static Color get inkSoft =>
      dm ? Brand.hsl(220, 12, 78) : Brand.hsl(0, 0, 28);
  static Color get muted => dm ? Brand.hsl(220, 8, 58) : Brand.hsl(0, 0, 45);
  static Color get muted2 => dm ? Brand.hsl(220, 8, 44) : Brand.hsl(0, 0, 62);
  static Color get line => dm ? Brand.hsl(222, 14, 19) : Brand.hsl(0, 0, 92);
  static Color get line2 => dm ? Brand.hsl(222, 14, 14) : Brand.hsl(0, 0, 96);
  static Color get card => dm ? Brand.hsl(222, 20, 10) : Brand.hsl(0, 0, 100);
  static Color get surface =>
      dm ? Brand.hsl(222, 30, 6) : Brand.hsl(0, 0, 99);
  static Color get success =>
      dm ? Brand.hsl(152, 55, 50) : Brand.hsl(152, 60, 38);
  static Color get successSoft =>
      dm ? Brand.hsl(152, 60, 45, .14) : Brand.hsl(152, 60, 38, .1);
  static Color get danger => dm ? Brand.hsl(4, 80, 64) : Brand.hsl(4, 72, 50);
  static const dark = Color(0xFF0B0E14); // onboarding / paywall backdrop

  /// Home hero panel: #0B0E14, slightly lifted off the dark-mode surface.
  static Color get hero => dm ? Brand.hsl(222, 24, 8) : dark;

  static const double radius = 18;

  /// Inter with a precise variable weight (the design uses 550/650/750).
  static TextStyle sans(double weight, double size,
          {Color? color, double? letterSpacing, double? height}) =>
      TextStyle(
        fontFamily: Brand.bodyFont,
        fontVariations: [FontVariation('wght', weight)],
        fontSize: size,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
      );

  /// JetBrains Mono for IPs, ports, hosts and latencies.
  static TextStyle mono(double weight, double size,
          {Color? color, double? letterSpacing, double? height}) =>
      TextStyle(
        fontFamily: Brand.monoFont,
        fontVariations: [FontVariation('wght', weight)],
        fontFeatures: const [FontFeature.tabularFigures()],
        fontSize: size,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
      );
}

/// Wordmark: bold "hide", the blue "IP" chip, then muted ".net".
/// Display face per the brand kit; the chip digits are JetBrains Mono.
class HipWordmark extends StatelessWidget {
  final double size;
  final Color? color;
  final Color? tldColor;
  const HipWordmark({super.key, this.size = 20, this.color, this.tldColor});

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      fontFamily: Brand.wordmarkFont,
      fontVariations: const [FontVariation('wght', 700)],
      fontFeatures: const [FontFeature('ss01'), FontFeature('ss02')],
      fontSize: size,
      letterSpacing: -.045 * size,
      color: color ?? Hip.ink,
    );
    return Text.rich(TextSpan(children: [
      TextSpan(text: 'hide', style: base),
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        // The chip's CSS em paddings resolve against its own font size.
        child: Builder(builder: (context) {
          final em = .82 * size;
          // `middle` centres on the full line box (descender included);
          // the CSS flexbox centres on the glyphs, so lift the chip a bit.
          return Transform.translate(
            offset: Offset(0, -.05 * size),
            child: Container(
              margin: EdgeInsets.only(left: .09 * em),
              padding:
                  EdgeInsets.fromLTRB(.17 * em, .1 * em, .17 * em, .12 * em),
              decoration: BoxDecoration(
                color: Brand.hsl(220, 95, 55),
                borderRadius: BorderRadius.circular(.22 * em),
              ),
              child: Text('IP',
                  style: Hip.mono(700, em,
                      color: Colors.white,
                      letterSpacing: -.02 * em,
                      height: 1)),
            ),
          );
        }),
      ),
      WidgetSpan(child: SizedBox(width: .1 * size)),
      TextSpan(
        text: '.net',
        style: base.copyWith(
          color: tldColor ?? Hip.muted2,
          fontVariations: const [FontVariation('wght', 500)],
        ),
      ),
    ]));
  }
}

/// Square "flag": country code in mono on a soft blue tile.
class HipFlag extends StatelessWidget {
  final String cc;
  final bool small;
  final Widget? child; // overrides the code (e.g. the Auto zap icon)
  const HipFlag({super.key, required this.cc, this.small = false, this.child});

  @override
  Widget build(BuildContext context) {
    final s = small ? 30.0 : 38.0;
    return Container(
      width: s,
      height: s,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Hip.blueSoft,
        borderRadius: BorderRadius.circular(small ? 9 : 12),
      ),
      child: child ??
          Text(cc,
              style: Hip.mono(700, small ? 11 : 13,
                  color: Hip.blueDeep, letterSpacing: .5)),
    );
  }
}

/// Four ascending ping bars; [level] 0-4 are lit green.
class HipBars extends StatelessWidget {
  final int level;
  const HipBars({super.key, required this.level});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 1; i <= 4; i++)
          Container(
            width: 3.5,
            height: 2 + i * 3.0,
            margin: EdgeInsets.only(left: i == 1 ? 0 : 2.5),
            decoration: BoxDecoration(
              color: i <= level ? Hip.success : Hip.line,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
      ],
    );
  }
}

/// iOS-style toggle in brand colors (green when on).
class HipToggle extends StatelessWidget {
  final bool on;
  final ValueChanged<bool> onChanged;
  const HipToggle({super.key, required this.on, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Haptics.selection();
        onChanged(!on);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 46,
        height: 28,
        padding: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(
          color: on
              ? Hip.success
              : (Hip.dm ? Brand.hsl(222, 12, 25) : Hip.line),
          borderRadius: BorderRadius.circular(999),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: on ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 23,
            height: 23,
            decoration: BoxDecoration(
              color: Hip.dm ? Brand.hsl(220, 15, 96) : Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .25),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pill badge (protocol, Verified, provider handle).
class HipBadge extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  final bool monoFont;
  final IconData? icon;
  const HipBadge(this.text,
      {super.key,
      required this.bg,
      required this.fg,
      this.monoFont = false,
      this.icon});

  factory HipBadge.proto(String text) => HipBadge(text,
      bg: Hip.line2, fg: Hip.inkSoft, monoFont: true);
  factory HipBadge.ok(String text, {IconData? icon}) => HipBadge(text,
      bg: Hip.successSoft,
      fg: Hip.dm ? Brand.hsl(152, 55, 55) : Hip.success,
      icon: icon);
  factory HipBadge.blue(String text) =>
      HipBadge(text, bg: Hip.blueSoft, fg: Hip.blueDeep);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 5),
        ],
        Text(text,
            style: monoFont
                ? Hip.mono(600, 10.5, color: fg)
                : Hip.sans(600, 11.5, color: fg, letterSpacing: .1)),
      ]),
    );
  }
}

/// Bordered white card, radius 18.
class HipCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? borderColor;
  const HipCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
    this.onTap,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final box = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Hip.card,
        border: Border.all(color: borderColor ?? Hip.line, width: 1.5),
        borderRadius: BorderRadius.circular(Hip.radius),
      ),
      child: child,
    );
    if (onTap == null) return box;
    return GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: box);
  }
}

/// Primary CTA. `connect: true` gets the animated brand gradient + glow.
class HipCta extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final bool connect;
  final bool ghost;
  final bool quiet;
  final bool darkGhost; // ghost on a dark (onboarding) surface
  final Widget? leading;
  const HipCta(this.label,
      {super.key,
      this.onTap,
      this.connect = false,
      this.ghost = false,
      this.quiet = false,
      this.darkGhost = false,
      this.leading});

  @override
  State<HipCta> createState() => _HipCtaState();
}

class _HipCtaState extends State<HipCta> with SingleTickerProviderStateMixin {
  // Created on first use so non-connect CTAs never carry a ticker. Must NOT
  // be `late final`: dispose() would then be a first use, and constructing a
  // controller during dispose looks up TickerMode on a deactivated element.
  AnimationController? _gradCtrl;
  AnimationController get _grad => _gradCtrl ??= AnimationController(
      vsync: this, duration: const Duration(seconds: 6));

  @override
  void initState() {
    super.initState();
    if (widget.connect) _grad.repeat();
  }

  @override
  void didUpdateWidget(covariant HipCta old) {
    super.didUpdateWidget(old);
    if (widget.connect && !_grad.isAnimating) _grad.repeat();
    if (!widget.connect) _gradCtrl?.stop();
  }

  @override
  void dispose() {
    _gradCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onTap == null;
    final height = widget.quiet ? 44.0 : 54.0;

    Color fg;
    if (widget.connect) {
      fg = Colors.white;
    } else if (widget.ghost) {
      fg = widget.darkGhost ? Colors.white : Hip.ink;
    } else if (widget.quiet) {
      fg = widget.darkGhost ? Colors.white.withValues(alpha: .55) : Hip.muted;
    } else {
      fg = Colors.white;
    }

    final label = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.leading != null) ...[
          IconTheme(
              data: IconThemeData(color: fg, size: 18), child: widget.leading!),
          const SizedBox(width: 8),
        ],
        Text(widget.label,
            style: Hip.sans(widget.quiet ? 550 : 600, widget.quiet ? 15 : 16.5,
                color: fg)),
      ],
    );

    Widget button;
    if (widget.connect) {
      button = AnimatedBuilder(
        animation: _grad,
        builder: (context, child) {
          // Sliding 115deg gradient. The colour pattern repeats every 3
          // alignment units (stop period .4 of the 7.5-unit span), so a
          // 3-unit shift per cycle loops seamlessly; anything else shows a
          // visible restart.
          final dx = _grad.value * 3;
          return Container(
            height: height,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: Brand.hsl(220, 95, 72, .8), width: 1.5),
              gradient: LinearGradient(
                begin: Alignment(-1 - dx, -.35),
                end: Alignment(6.5 - dx, .35),
                colors: [
                  Hip.blue,
                  Brand.hsl(210, 95, 53),
                  Brand.hsl(197, 85, 49),
                  Hip.blue,
                  Brand.hsl(210, 95, 53),
                  Brand.hsl(197, 85, 49),
                  Hip.blue,
                ],
                stops: const [0, .14, .25, .4, .54, .65, .8],
              ),
              boxShadow: [
                BoxShadow(
                  color: Brand.hsl(220, 95, 55, .55),
                  blurRadius: 26,
                  offset: const Offset(0, 10),
                  spreadRadius: -12,
                ),
              ],
            ),
            child: child,
          );
        },
        child: label,
      );
    } else {
      Color bg;
      if (widget.ghost) {
        bg = widget.darkGhost
            ? Colors.white.withValues(alpha: .09)
            : (Hip.dm ? Brand.hsl(222, 14, 16) : Hip.line2);
      } else if (widget.quiet) {
        bg = Colors.transparent;
      } else {
        bg = Hip.blue;
      }
      button = Container(
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: label,
      );
    }

    return GestureDetector(
      onTap: disabled
          ? null
          : () {
              Haptics.tap();
              widget.onTap!();
            },
      child: Opacity(opacity: disabled ? .55 : 1, child: button),
    );
  }
}

/// Round-cornered icon button used in headers.
class HipIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;
  const HipIconButton(this.icon, {super.key, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 38,
        height: 38,
        child: Icon(icon, size: 22, color: color ?? Hip.inkSoft),
      ),
    );
  }
}

/// App header: wordmark left, action icons right.
class HipAppHead extends StatelessWidget {
  final VoidCallback? onServers;
  final VoidCallback? onSettings;
  final bool onDark;
  const HipAppHead({super.key, this.onServers, this.onSettings, this.onDark = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
      child: Row(children: [
        HipWordmark(
            color: onDark ? Colors.white : null,
            tldColor: onDark ? Colors.white.withValues(alpha: .4) : null),
        const Spacer(),
        if (onServers != null)
          HipIconButton(Icons.dns_outlined,
              onTap: onServers!,
              color: onDark ? Colors.white.withValues(alpha: .7) : null),
        if (onSettings != null) ...[
          const SizedBox(width: 10),
          HipIconButton(Icons.settings_outlined,
              onTap: onSettings!,
              color: onDark ? Colors.white.withValues(alpha: .7) : null),
        ],
      ]),
    );
  }
}

/// Sub-screen header: back chevron + title + optional trailing action.
class HipNavHead extends StatelessWidget {
  final String title;
  final VoidCallback onBack;
  final Widget? trailing;
  final bool onDark;
  const HipNavHead({
    super.key,
    required this.title,
    required this.onBack,
    this.trailing,
    this.onDark = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
      child: Row(children: [
        HipIconButton(Icons.chevron_left,
            onTap: onBack,
            color: onDark ? Colors.white.withValues(alpha: .75) : null),
        const SizedBox(width: 6),
        Text(title,
            style: Hip.sans(650, 19,
                color: onDark ? Colors.white : Hip.ink, letterSpacing: -.38)),
        const Spacer(),
        ?trailing,
      ]),
    );
  }
}

/// Section label above a list group (uppercase, tracked out).
class HipSectionLabel extends StatelessWidget {
  final String text;
  const HipSectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 7),
      child: Text(text.toUpperCase(),
          style: Hip.sans(650, 12, color: Hip.muted2, letterSpacing: .84)),
    );
  }
}

/// Card-backed group of list rows with hairline separators.
class HipListGroup extends StatelessWidget {
  final List<Widget> children;
  const HipListGroup({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Hip.card,
        border: Border.all(color: Hip.line, width: 1.5),
        borderRadius: BorderRadius.circular(Hip.radius),
      ),
      child: Column(children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) Container(height: 1, color: Hip.line2),
          children[i],
        ],
      ]),
    );
  }
}

/// One row inside a [HipListGroup].
class HipListRow extends StatelessWidget {
  final Widget? leading;
  final String title;
  final Widget? titleBadge;
  final String? subtitle;
  final bool subtitleMono;
  final Widget? trailing;
  final VoidCallback? onTap;
  const HipListRow({
    super.key,
    this.leading,
    required this.title,
    this.titleBadge,
    this.subtitle,
    this.subtitleMono = false,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(children: [
        if (leading != null) ...[leading!, const SizedBox(width: 12)],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(
                child: Text(title,
                    overflow: TextOverflow.ellipsis,
                    style: Hip.sans(650, 15.5,
                        color: Hip.ink, letterSpacing: -.15)),
              ),
              if (titleBadge != null) ...[
                const SizedBox(width: 7),
                titleBadge!,
              ],
            ]),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text(subtitle!,
                    overflow: TextOverflow.ellipsis,
                    style: subtitleMono
                        ? Hip.mono(600, 11, color: Hip.muted)
                        : Hip.sans(400, 12.5, color: Hip.muted)),
              ),
          ]),
        ),
        if (trailing != null) ...[const SizedBox(width: 12), trailing!],
      ]),
    );
    if (onTap == null) return row;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: row,
    );
  }
}

/// Centered footnote under lists/CTAs.
class HipSubnote extends StatelessWidget {
  final String text;
  final bool onDark;
  const HipSubnote(this.text, {super.key, this.onDark = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
      child: Text(text,
          textAlign: TextAlign.center,
          style: Hip.sans(400, 12,
              color: onDark ? Colors.white.withValues(alpha: .4) : Hip.muted2,
              height: 1.5)),
    );
  }
}

/// Floating dark toast with a green check, shown near the bottom.
class HipToast extends StatelessWidget {
  final String message;
  const HipToast(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
      decoration: BoxDecoration(
        color: Hip.dm ? Brand.hsl(222, 18, 16) : Brand.hsl(220, 15, 12),
        border: Hip.dm
            ? Border.all(color: Brand.hsl(222, 12, 27))
            : null,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .4),
            blurRadius: 30,
            offset: const Offset(0, 12),
            spreadRadius: -8,
          ),
        ],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.check, size: 16, color: Brand.hsl(152, 60, 55)),
        const SizedBox(width: 8),
        Text(message, style: Hip.sans(600, 13.5, color: Colors.white)),
      ]),
    );
  }
}
