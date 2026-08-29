import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/haptics.dart';
import '../../state/app_state.dart';
import '../brand.dart';
import 'hip.dart';
import 'shell.dart';

/// Three-beat onboarding on the dark surface, then the access choice.
/// The brand cubes double as the progress indicator.
class OnboardingScreen extends StatefulWidget {
  final AppState state;
  final HipNav nav;
  const OnboardingScreen({super.key, required this.state, required this.nav});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0;

  @override
  void initState() {
    super.initState();
    widget.nav.claimBack(_sysBack);
  }

  @override
  void dispose() {
    widget.nav.releaseBack(_sysBack);
    super.dispose();
  }

  /// System back walks the beats; on the first one it leaves the app.
  void _sysBack() {
    if (_step > 0) {
      setState(() => _step--);
    } else {
      SystemNavigator.pop();
    }
  }

  Future<void> _done() async {
    await widget.state
        .updatePrefs(widget.state.prefs.copyWith(onboarded: true));
    widget.nav.go(HipScreen.home);
  }

  void _import() {
    widget.nav.openImport();
    // Leaving onboarding through import counts as having seen it.
    widget.state.updatePrefs(widget.state.prefs.copyWith(onboarded: true));
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    // The in-app plans pitch only where the catalog is live (both the platform
    // floor and the runtime availability): before the store products exist the
    // onboarding tells the BYO-only story instead of a dead purchase path.
    final plans = kPlansAvailable && widget.state.plansOffered;
    return Container(
      color: Hip.dark,
      padding: EdgeInsets.only(top: pad.top, bottom: pad.bottom),
      child: switch (_step) {
        0 => _page(
            lit: 1,
            title: 'Your IP address\ngives you away.',
            body:
                'hideip.net swaps it for one of ours. Websites, trackers and your network see the tunnel, never you.',
            cta: HipCta('Get started', onTap: () => setState(() => _step = 1)),
            subnote: 'No account · No logs',
            showWordmark: true,
          ),
        1 => _page(
            lit: 2,
            title: 'Made to get\nthrough blocks.',
            body:
                "Where ordinary VPNs get blocked, hideip.net uses stealth protocols like VLESS and VMess that look like normal traffic. Filtered networks and censorship don't stop you.",
            cta: HipCta('Next', onTap: () => setState(() => _step = 2)),
            onBack: () => setState(() => _step = 0),
          ),
        2 => _page(
            lit: 3,
            title: plans ? 'Access,\ntwo ways.' : 'Works with\nany provider.',
            bodyWidget: Column(children: [
              const SizedBox(height: 6),
              if (plans) ...[
                _way(Icons.shield_outlined, 'Buy access in the app',
                    'Pick a plan from hideip.net and connect instantly'),
                Container(
                    height: 1, color: Colors.white.withValues(alpha: .1)),
              ],
              _way(
                  Icons.link,
                  plans ? 'Or bring your own' : 'Bring your own',
                  'Paste a vless:// or vmess:// link, a subscription URL, or scan a QR, from any provider'),
            ]),
            cta: HipCta('Next', onTap: () => setState(() => _step = 3)),
            onBack: () => setState(() => _step = 1),
          ),
        _ => _choice(),
      },
    );
  }

  Widget _cubes(int lit) => Padding(
        padding: const EdgeInsets.only(bottom: 30),
        child: Row(children: [
          for (var i = 0; i < 3; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              width: 56,
              height: 56,
              margin: EdgeInsets.only(left: i == 0 ? 0 : 14),
              decoration: BoxDecoration(
                color: i < lit
                    ? const Color(0xFF2FA872)
                    : Colors.white.withValues(alpha: .05),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  width: 2,
                  color: i < lit
                      ? const Color(0xFF35BD80)
                      : Colors.white.withValues(alpha: .14),
                ),
                boxShadow: i < lit
                    ? [
                        BoxShadow(
                          color: const Color(0xFF2FA872).withValues(alpha: .45),
                          blurRadius: 30,
                          offset: const Offset(0, 8),
                          spreadRadius: -6,
                        ),
                      ]
                    : null,
              ),
            ),
        ]),
      );

  Widget _page({
    required int lit,
    required String title,
    String? body,
    Widget? bodyWidget,
    required Widget cta,
    String? subnote,
    bool showWordmark = false,
    VoidCallback? onBack,
  }) {
    return Column(children: [
      // Fixed-height header slot: the wordmark and the back chevron overlay
      // here so the content below sits at the same y on every beat.
      SizedBox(
        height: 46,
        width: double.infinity,
        child: Stack(children: [
          if (showWordmark)
            const Positioned(
              top: 12,
              left: 30,
              child: HipWordmark(size: 17, color: Colors.white),
            ),
          if (onBack != null)
            Positioned(
              top: 4,
              left: 14,
              child: HipIconButton(Icons.chevron_left,
                  onTap: onBack, color: Colors.white.withValues(alpha: .75)),
            ),
        ]),
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(30, 56, 30, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _cubes(lit),
              Text(title,
                  style: Hip.sans(750, 29,
                      color: Colors.white, height: 1.16, letterSpacing: -.87)),
              const SizedBox(height: 12),
              if (body != null)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 290),
                  child: Text(body,
                      style: Hip.sans(400, 15,
                          color: Colors.white.withValues(alpha: .6),
                          height: 1.55)),
                ),
              ?bodyWidget,
            ],
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 14),
        child: Column(children: [
          cta,
          // Fixed-height footnote slot; keeps the CTA from jumping between
          // beats that do and don't have one.
          SizedBox(
            height: 30,
            child: subnote != null ? HipSubnote(subnote, onDark: true) : null,
          ),
        ]),
      ),
    ]);
  }

  Widget _way(IconData icon, String title, String sub) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 15),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFF2FA872).withValues(alpha: .16),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, size: 20, color: const Color(0xFF4CCB8F)),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Hip.sans(650, 15, color: Colors.white)),
            const SizedBox(height: 2),
            Text(sub,
                style: Hip.sans(400, 12.5,
                    color: Colors.white.withValues(alpha: .55), height: 1.45)),
          ]),
        ),
      ]),
    );
  }

  Widget _choice() {
    final plans = kPlansAvailable && widget.state.plansOffered;
    return Column(children: [
      SizedBox(
        height: 46,
        width: double.infinity,
        child: Stack(children: [
          Positioned(
            top: 4,
            left: 14,
            child: HipIconButton(Icons.chevron_left,
                onTap: () => setState(() => _step = 2),
                color: Colors.white.withValues(alpha: .75)),
          ),
        ]),
      ),
      const SizedBox(height: 10),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          children: [
            Text('How do you\nwant to start?',
                style: Hip.sans(750, 25,
                    color: Colors.white, height: 1.2, letterSpacing: -.7)),
            const SizedBox(height: 4),
            Text('You can always change this later.',
                style: Hip.sans(400, 14,
                    color: Colors.white.withValues(alpha: .55), height: 1.5)),
            const SizedBox(height: 18),
            if (plans)
              _opt(
                  Icons.shield_outlined,
                  'Get access from hideip.net',
                  'Try Premium free for 7 days; locations appear instantly',
                  () => widget.nav.openPaywall(from: HipScreen.onboarding)),
            _opt(Icons.link, 'I have a link or QR code',
                'From Telegram, email or a website: vless://, vmess://, anything',
                _import),
            _opt(Icons.autorenew, 'I have a subscription URL',
                'Servers update themselves whenever your provider changes them',
                _import),
            const HipSubnote(
                'You never need to know what a protocol is.\nUnless you want to: see Advanced view in Settings.',
                onDark: true),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 14),
        child: HipCta('Just looking around',
            ghost: true, darkGhost: true, onTap: _done),
      ),
    ]);
  }

  Widget _opt(IconData icon, String title, String sub, VoidCallback onTap) {
    return GestureDetector(
      onTap: () {
        Haptics.selection();
        onTap();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .05),
          border:
              Border.all(color: Colors.white.withValues(alpha: .12), width: 1.5),
          borderRadius: BorderRadius.circular(Hip.radius),
        ),
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Brand.hsl(220, 95, 60, .18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, size: 22, color: Brand.hsl(220, 95, 70)),
          ),
          const SizedBox(width: 13),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: Hip.sans(650, 15.5, color: Colors.white)),
              const SizedBox(height: 2),
              Text(sub,
                  style: Hip.sans(400, 12.5,
                      color: Colors.white.withValues(alpha: .55), height: 1.4)),
            ]),
          ),
          Icon(Icons.chevron_right,
              size: 17, color: Colors.white.withValues(alpha: .35)),
        ]),
      ),
    );
  }
}
