import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/haptics.dart';
import '../../core/location.dart';
import '../../core/ping.dart';
import '../../core/premium.dart';
import '../../core/purchase_service.dart';
import '../../state/app_state.dart';
import '../brand.dart';
import 'hip.dart';
import 'shell.dart';

bool get _ios => defaultTargetPlatform == TargetPlatform.iOS;

/// "App Store" / "Google Play" in purchase copy, per platform.
String get _storeName => _ios ? 'App Store' : 'Google Play';

/// The store's own subscription-management page.
String get _manageUrl => _ios
    ? 'https://apps.apple.com/account/subscriptions'
    : 'https://play.google.com/store/account/subscriptions';

/// Apple requires a Terms of Use (EULA) link on the paywall; the standard
/// Apple EULA is the one the App Store listing declares.
String get _termsUrl => _ios
    ? 'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/'
    : 'https://hideip.net/terms';

const _privacyUrl = 'https://hideip.net/privacy';

void _openUrl(String url) =>
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

/// The brand cube outline used everywhere Premium is referenced. Proportions
/// follow the prototype icon (a 15/24 rounded square at stroke 2).
class PremiumCubeIcon extends StatelessWidget {
  final double size;
  final Color? color;
  const PremiumCubeIcon({super.key, this.size = 19, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Hip.blueDeep;
    return Center(
      child: Container(
        width: size * 15 / 24,
        height: size * 15 / 24,
        decoration: BoxDecoration(
          border: Border.all(color: c, width: size * 2 / 24),
          borderRadius: BorderRadius.circular(size * 3.5 / 24),
        ),
      ),
    );
  }
}

/// Gradient "Premium" pill.
class PremiumBadge extends StatelessWidget {
  final bool dim;
  const PremiumBadge({super.key, this.dim = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: dim ? Hip.line2 : null,
        gradient: dim
            ? null
            : LinearGradient(colors: [Hip.blue, Brand.hsl(197, 85, 49)]),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        PremiumCubeIcon(size: 13, color: dim ? Hip.muted : Colors.white),
        const SizedBox(width: 5),
        Text('Premium',
            style: Hip.sans(600, 11.5,
                color: dim ? Hip.muted : Colors.white, letterSpacing: .35)),
      ]),
    );
  }
}

/// The paywall: one plan in two variants, priced and disclosed before the
/// purchase, with restore and the legal links (App Store guideline 3.1.2).
/// Always on the dark surface, like onboarding.
class PaywallScreen extends StatefulWidget {
  final AppState state;
  final HipNav nav;
  final HipScreen from;
  const PaywallScreen(
      {super.key, required this.state, required this.nav, required this.from});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

enum _PwPhase { plans, buying, success, error }

class _PaywallScreenState extends State<PaywallScreen> {
  PremiumPlan _plan = PremiumPlan.yearly;
  _PwPhase _phase = _PwPhase.plans;
  String _busyMsg = '';

  void _back() => widget.nav.go(widget.from);

  Future<void> _buy() async {
    setState(() {
      _busyMsg = 'Confirming with the $_storeName';
      _phase = _PwPhase.buying;
    });
    final outcome = await widget.state.purchasePremium(_plan);
    if (!mounted) return;
    switch (outcome) {
      case PurchaseOutcome.success:
        Haptics.success();
        setState(() => _phase = _PwPhase.success);
      case PurchaseOutcome.canceled:
        // Their choice, not a failure: back to the plans without a banner.
        setState(() => _phase = _PwPhase.plans);
      case PurchaseOutcome.failed:
        Haptics.error();
        setState(() => _phase = _PwPhase.error);
    }
  }

  Future<void> _restore() async {
    final prev = _phase;
    setState(() {
      _busyMsg = 'Checking your previous purchases';
      _phase = _PwPhase.buying;
    });
    await widget.state.restorePurchases();
    if (!mounted) return;
    setState(() => _phase =
        widget.state.premium.isOn ? _PwPhase.success : prev);
  }

  String get _trialEnds =>
      formatPremiumDate(DateTime.now().add(const Duration(days: 7)));

  @override
  Widget build(BuildContext context) {
    if (_phase == _PwPhase.success) return _success();

    final info = widget.state.planInfo(_plan);
    return Container(
      color: Hip.dark,
      child: SafeArea(
        child: Stack(children: [
          Column(children: [
            HipNavHead(
              title: '',
              onBack: _back,
              onDark: true,
              trailing: HipIconButton(Icons.close,
                  onTap: _back, color: Colors.white.withValues(alpha: .6)),
            ),
            Expanded(
              child: LayoutBuilder(builder: (context, box) {
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: box.maxHeight),
                    child: IntrinsicHeight(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(children: [
                          _hero(),
                          const Spacer(),
                          _benefits(),
                          const Spacer(),
                          _plans(),
                          const Spacer(),
                          if (_phase == _PwPhase.error) _errorBanner(),
                          _legal(info.trial
                              ? '7 days free, then |${info.price}| per ${info.per}. '
                                  'Nothing is charged before |$_trialEnds|. '
                                  'Auto-renews; cancel anytime in your $_storeName settings.'
                              : '|${info.price}| per ${info.per}, charged today. '
                                  'Auto-renews; cancel anytime in your $_storeName settings.'),
                          _links(),
                        ]),
                      ),
                    ),
                  ),
                );
              }),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 20),
              child: HipCta(
                  _phase == _PwPhase.error
                      ? 'Try again'
                      : info.trial
                          ? 'Start 7-day free trial'
                          : 'Subscribe now',
                  connect: true,
                  onTap: _buy),
            ),
          ]),
          if (_phase == _PwPhase.buying) _buyingOverlay(),
        ]),
      ),
    );
  }

  Widget _hero() {
    Widget cube({bool hero = false}) => Container(
          width: hero ? 43 : 33,
          height: hero ? 43 : 33,
          decoration: BoxDecoration(
            color: hero ? null : Colors.white.withValues(alpha: .05),
            gradient: hero
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Brand.hsl(220, 95, 55), Brand.hsl(197, 85, 49)],
                  )
                : null,
            border: Border.all(
                width: 2,
                color: hero
                    ? Brand.hsl(220, 95, 72, .9)
                    : Colors.white.withValues(alpha: .14)),
            borderRadius: BorderRadius.circular(hero ? 12 : 10),
            boxShadow: hero
                ? [
                    BoxShadow(
                      color: Brand.hsl(220, 95, 55, .55),
                      blurRadius: 40,
                      offset: const Offset(0, 14),
                      spreadRadius: -8,
                    ),
                  ]
                : null,
          ),
        );
    return Column(children: [
      const SizedBox(height: 2),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        cube(),
        const SizedBox(width: 10),
        cube(hero: true),
        const SizedBox(width: 10),
        cube(),
      ]),
      const SizedBox(height: 13),
      const PremiumBadge(),
      const SizedBox(height: 11),
      Text('Everything on, everywhere.',
          style: Hip.sans(750, 23,
              color: Colors.white, height: 1.18, letterSpacing: -.64)),
      const SizedBox(height: 6),
      Text('One plan. It works where others get blocked.',
          textAlign: TextAlign.center,
          style: Hip.sans(400, 13,
              color: Colors.white.withValues(alpha: .58), height: 1.5)),
    ]);
  }

  Widget _benefits() {
    Widget b(IconData icon, String title, String sub, {bool monoTitle = false}) =>
        Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .04),
              border: Border.all(color: Colors.white.withValues(alpha: .08)),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: Brand.hsl(220, 95, 60, .16),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 14, color: Brand.hsl(220, 95, 70)),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: monoTitle
                              ? Hip.mono(650, 12, color: Colors.white)
                              : Hip.sans(650, 12.5,
                                  color: Colors.white, letterSpacing: -.13)),
                      const SizedBox(height: 2),
                      Text(sub,
                          style: Hip.sans(400, 10.5,
                              color: Colors.white.withValues(alpha: .5),
                              height: 1.35)),
                    ]),
              ),
            ]),
          ),
        );
    // IntrinsicHeight equalizes the two cards in each row; stretch alone
    // would inherit the column's unbounded height during layout.
    return Column(children: [
      IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          b(Icons.shield_outlined, 'Blocked networks', 'Stealth by default'),
          const SizedBox(width: 9),
          b(Icons.public, 'All locations', 'Every location included'),
        ]),
      ),
      const SizedBox(height: 9),
      IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          b(Icons.bolt_outlined, 'Unlimited', 'No caps; fair use'),
          const SizedBox(width: 9),
          b(Icons.devices, '3 devices', 'At the same time'),
        ]),
      ),
    ]);
  }

  Widget _plans() {
    Widget planRow(PremiumPlan plan, {Widget? nameBadge}) {
      final info = widget.state.planInfo(plan);
      final on = _plan == plan;
      return GestureDetector(
        onTap: () {
          if (_plan != plan) Haptics.selection();
          setState(() => _plan = plan);
        },
        child: Container(
          margin: EdgeInsets.only(top: plan == PremiumPlan.yearly ? 0 : 9),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: on
                ? Brand.hsl(220, 95, 55, .12)
                : Colors.white.withValues(alpha: .04),
            // The prototype's 1.5px border + 1px ring reads as one 2.5px
            // stroke; a shadow ring would bleed through the translucent fill.
            border: Border.all(
                width: on ? 2.5 : 1.5,
                color: on
                    ? Brand.hsl(220, 95, 62)
                    : Colors.white.withValues(alpha: .14)),
            borderRadius: BorderRadius.circular(Hip.radius),
          ),
          child: Row(children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: on ? Hip.blue : null,
                border: on
                    ? null
                    : Border.all(
                        color: Colors.white.withValues(alpha: .3), width: 1.8),
                shape: BoxShape.circle,
              ),
              child: on
                  ? const Icon(Icons.check, size: 13, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text(info.name,
                          style: Hip.sans(650, 15,
                              color: Colors.white, letterSpacing: -.15)),
                      if (nameBadge != null) ...[
                        const SizedBox(width: 8),
                        nameBadge,
                      ],
                    ]),
                    const SizedBox(height: 3),
                    Text(info.note,
                        style: Hip.sans(550, 11.5,
                            color: Colors.white.withValues(alpha: .55),
                            letterSpacing: .12)),
                  ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(info.price,
                  style: Hip.sans(750, 17,
                      color: Colors.white, letterSpacing: -.17)),
              const SizedBox(height: 2),
              Text('per ${info.per}',
                  style: Hip.sans(550, 11,
                      color: Colors.white.withValues(alpha: .5))),
            ]),
          ]),
        ),
      );
    }

    return Column(children: [
      planRow(
        PremiumPlan.yearly,
        nameBadge: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            color: Brand.hsl(152, 60, 46, .18),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text('Save 50%',
              style: Hip.sans(600, 10.5, color: Brand.hsl(152, 60, 58))),
        ),
      ),
      planRow(PremiumPlan.monthly),
    ]);
  }

  Widget _errorBanner() {
    final storeMsg = widget.state.purchases.lastError;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        color: Brand.hsl(35, 90, 55, .1),
        border: Border.all(color: Brand.hsl(35, 90, 55, .28), width: 1.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline, size: 18, color: Brand.hsl(35, 90, 78)),
        const SizedBox(width: 11),
        Expanded(
          child: Text(
              "That didn't go through, and you haven't been charged. "
              'Check your payment method, then try again; or restore an '
              'earlier purchase.'
              '${storeMsg != null && storeMsg.isNotEmpty ? '\n($storeMsg)' : ''}',
              style: Hip.sans(400, 12.5,
                  color: Brand.hsl(35, 90, 78), height: 1.5)),
        ),
      ]),
    );
  }

  /// Legal footnote; |text| segments render in mono at full opacity.
  Widget _legal(String text) {
    final parts = text.split('|');
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text.rich(
        TextSpan(children: [
          for (var i = 0; i < parts.length; i++)
            TextSpan(
              text: parts[i],
              style: i.isOdd
                  ? Hip.mono(600, 11, color: Colors.white.withValues(alpha: .7))
                  : Hip.sans(400, 11,
                      color: Colors.white.withValues(alpha: .45), height: 1.5),
            ),
        ]),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _links() {
    final style = Hip.sans(550, 12, color: Colors.white.withValues(alpha: .55));
    Widget dot() => Container(
          width: 3,
          height: 3,
          margin: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .25),
            shape: BoxShape.circle,
          ),
        );
    // FittedBox: the three links brush past narrow widths otherwise
    // (a 38px overflow on a 402pt screen).
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 11, 0, 4),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          GestureDetector(
              onTap: _restore, child: Text('Restore purchases', style: style)),
          dot(),
          GestureDetector(
              onTap: () => _openUrl(_termsUrl),
              child: Text('Terms of Use', style: style)),
          dot(),
          GestureDetector(
              onTap: () => _openUrl(_privacyUrl),
              child: Text('Privacy Policy', style: style)),
        ]),
      ),
    );
  }

  Widget _buyingOverlay() {
    return Positioned.fill(
      child: Container(
        color: Brand.hsl(222, 25, 7, .97),
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          SizedBox(
            width: 30,
            height: 30,
            child: CircularProgressIndicator(
                strokeWidth: 3, color: Brand.hsl(220, 95, 68)),
          ),
          const SizedBox(height: 18),
          Text(_busyMsg,
              textAlign: TextAlign.center,
              style: Hip.sans(650, 15, color: Colors.white)),
          const SizedBox(height: 4),
          Text('This usually takes a moment.',
              textAlign: TextAlign.center,
              style: Hip.sans(400, 13.5,
                  color: Colors.white.withValues(alpha: .55), height: 1.6)),
        ]),
      ),
    );
  }

  Widget _success() {
    final p = widget.state.premium;
    final trial = p.status == PremiumStatus.trial;
    final renewsDate =
        p.renews != null ? formatPremiumDate(p.renews!) : _trialEnds;
    final locations = widget.state.locations.take(4).toList();
    return Container(
      color: Hip.dark,
      child: SafeArea(
        child: Column(children: [
          const SizedBox(height: 46),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Brand.hsl(152, 60, 46, .16),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.check,
                      size: 30, color: Brand.hsl(152, 60, 58)),
                ),
                const SizedBox(height: 16),
                Text("You're in.",
                    style: Hip.sans(750, 23,
                        color: Colors.white, letterSpacing: -.64)),
                const SizedBox(height: 6),
                Text(
                    '${trial ? 'Your 7-day free trial is active.' : 'Your subscription is active.'}'
                    '${locations.isEmpty ? '' : ' Ready when you are:'}',
                    textAlign: TextAlign.center,
                    style: Hip.sans(400, 13,
                        color: Colors.white.withValues(alpha: .58),
                        height: 1.5)),
                const SizedBox(height: 18),
                for (final l in locations) _unlockRow(l),
                const Spacer(),
                _legal(trial
                    ? 'First charge on |$renewsDate| '
                        'unless you cancel before then.'
                    : 'Renews on |$renewsDate|; cancel anytime '
                        'in your $_storeName settings.'),
                const SizedBox(height: 8),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 20),
            child: HipCta('Start browsing',
                onTap: () => widget.nav.go(HipScreen.home)),
          ),
        ]),
      ),
    );
  }

  Widget _unlockRow(Location l) {
    final ping = widget.state.pingFor(l.profile);
    final ms = ping is PingOk ? '${ping.ms} ms' : '';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .06),
        border: Border.all(color: Colors.white.withValues(alpha: .1)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Brand.hsl(220, 95, 60, .18),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(l.cc,
              style: Hip.mono(700, 11,
                  color: Brand.hsl(220, 95, 72), letterSpacing: .5)),
        ),
        const SizedBox(width: 11),
        Text(l.city, style: Hip.sans(600, 14, color: Colors.white)),
        const Spacer(),
        Text(ms,
            style:
                Hip.mono(600, 11, color: Colors.white.withValues(alpha: .5))),
      ]),
    );
  }
}

/// Settings → Premium: the subscription at a glance plus billing shortcuts.
class PremiumManageScreen extends StatelessWidget {
  final AppState state;
  final HipNav nav;
  const PremiumManageScreen(
      {super.key, required this.state, required this.nav});

  @override
  Widget build(BuildContext context) {
    final p = state.premium;
    final info = state.planInfo(p.plan ?? PremiumPlan.yearly);
    final expired = p.status == PremiumStatus.expired;
    final statusBadge = switch (p.status) {
      PremiumStatus.active => HipBadge.ok('Active'),
      PremiumStatus.trial => HipBadge.blue('Free trial'),
      _ => HipBadge('Expired', bg: Hip.line2, fg: Hip.inkSoft),
    };
    return SafeArea(
      child: Column(children: [
        HipNavHead(title: 'Premium', onBack: () => nav.go(HipScreen.settings)),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              HipCard(
                child: Row(children: [
                  const HipFlag(cc: '', child: PremiumCubeIcon()),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('hideip.net Premium',
                              style: Hip.sans(650, 15.5,
                                  color: Hip.ink, letterSpacing: -.15)),
                          const SizedBox(height: 2),
                          Text(
                              expired
                                  ? 'Subscription ended; not renewing'
                                  : '${info.name} plan',
                              style: Hip.sans(550, 12, color: Hip.muted)),
                        ]),
                  ),
                  statusBadge,
                ]),
              ),
              if (!expired) ...[
                const HipSectionLabel('Subscription'),
                HipListGroup(children: [
                  HipListRow(
                    title: 'Plan',
                    trailing: Text.rich(TextSpan(children: [
                      TextSpan(
                          text: info.price,
                          style: Hip.mono(600, 12.5, color: Hip.muted)),
                      TextSpan(
                          text: ' per ${info.per}',
                          style: Hip.sans(400, 12.5, color: Hip.muted)),
                    ])),
                  ),
                  HipListRow(
                    title: p.status == PremiumStatus.trial
                        ? 'Trial ends'
                        : 'Renews',
                    trailing: Text(
                        p.renews != null ? formatPremiumDate(p.renews!) : '',
                        style: Hip.mono(600, 12.5, color: Hip.muted)),
                  ),
                ]),
              ],
              const HipSectionLabel('Billing'),
              HipListGroup(children: [
                HipListRow(
                  title: 'Manage in $_storeName',
                  subtitle: 'Change plan, cancel, or update payment',
                  trailing:
                      Icon(Icons.open_in_new, size: 17, color: Hip.muted2),
                  onTap: () => _openUrl(_manageUrl),
                ),
                HipListRow(
                  title: 'Restore purchases',
                  trailing:
                      Icon(Icons.chevron_right, size: 17, color: Hip.muted2),
                  onTap: state.restorePurchases,
                ),
              ]),
              HipSubnote('Billing is handled by the $_storeName;\n'
                  'hideip.net never sees your payment details.'),
              if (expired)
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 14, 0, 24),
                  child: HipCta('Restart Premium',
                      onTap: () => nav.openPaywall(HipScreen.settings)),
                ),
            ],
          ),
        ),
      ]),
    );
  }
}

/// Shown when the trial lapses: nothing is lost, Premium is just paused.
class TrialExpiredScreen extends StatelessWidget {
  final AppState state;
  final HipNav nav;
  const TrialExpiredScreen(
      {super.key, required this.state, required this.nav});

  @override
  Widget build(BuildContext context) {
    final locations = state.locations;
    final shown = locations.take(3).toList();
    final more = locations.length - shown.length;
    return SafeArea(
      child: Column(children: [
        HipNavHead(title: '', onBack: () => nav.go(HipScreen.home)),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 36, 0, 22),
                child:
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  _ghostCube(),
                  const SizedBox(width: 12),
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: Hip.blueSoft,
                      border: Border.all(
                          color: Hip.blue.withValues(alpha: .35), width: 2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: PremiumCubeIcon(size: 25, color: Hip.blueDeep),
                  ),
                  const SizedBox(width: 12),
                  _ghostCube(),
                ]),
              ),
              Text('Your free trial has ended',
                  style: Hip.sans(750, 23, color: Hip.ink, letterSpacing: -.58)),
              const SizedBox(height: 9),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 290),
                child: Text(
                    'Nothing was charged. Your settings and imported '
                    'connections are untouched; Premium locations are paused '
                    "until you're back.",
                    textAlign: TextAlign.center,
                    style: Hip.sans(400, 13.5, color: Hip.muted, height: 1.55)),
              ),
              const SizedBox(height: 22),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  for (final l in shown) _chip(l),
                  if (more > 0) _moreChip(more),
                ],
              ),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 20),
          child: Column(children: [
            HipCta('Continue with Premium',
                onTap: () => nav.openPaywall(HipScreen.trialExpired)),
            const SizedBox(height: 8),
            HipCta('Use your own connection link',
                quiet: true, onTap: () => nav.openImport()),
          ]),
        ),
      ]),
    );
  }

  Widget _ghostCube() => Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Hip.line2,
          border: Border.all(
              color: Hip.dm ? Brand.hsl(222, 12, 27) : Brand.hsl(0, 0, 80),
              width: 2),
          borderRadius: BorderRadius.circular(12),
        ),
      );

  Widget _chip(Location l) => Container(
        padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
        decoration: BoxDecoration(
          border: Border.all(color: Hip.line, width: 1.5),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Opacity(opacity: .55, child: HipFlag(cc: l.cc, small: true)),
          const SizedBox(width: 7),
          Text(l.city, style: Hip.sans(600, 12.5, color: Hip.muted)),
        ]),
      );

  Widget _moreChip(int n) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: Hip.line, width: 1.5),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text('+$n', style: Hip.mono(600, 12.5, color: Hip.muted)),
      );
}
