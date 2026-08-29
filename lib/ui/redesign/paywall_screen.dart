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
import '../strings.dart';
import 'hip.dart';
import 'locked_row.dart';
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

/// Legal footnote on a dark surface. A `|segment|` renders in mono at full
/// opacity: it is always a price or a date.
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

/// Locations ordered by measured latency, quickest first. An unmeasured one
/// sorts last rather than pretending to be instant.
List<Location> sortedByPing(AppState state, List<Location> src) {
  final list = [...src];
  list.sort((a, b) {
    final pa = state.pingFor(a.profile);
    final pb = state.pingFor(b.profile);
    final ma = pa is PingOk ? pa.ms : 1 << 30;
    final mb = pb is PingOk ? pb.ms : 1 << 30;
    return ma.compareTo(mb);
  });
  return list;
}

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
        Text(S.tPremium,
            style: Hip.sans(600, 11.5,
                color: dim ? Hip.muted : Colors.white, letterSpacing: .35)),
      ]),
    );
  }
}

/// What the primary button says. The yearly plan starts with seven free days
/// and says so; the monthly plan bills right away.
String paywallCtaLabel(PlanInfo info, {required bool failed}) => failed
    ? S.aTryAgain
    : info.trial
        ? S.pwCtaTrial
        : S.pwCtaBuy;

/// Everything on the paywall below the header: what the plan gives, which of
/// its two variants is picked, one price in large type, the legal line for
/// that variant and the primary button.
///
/// Plain parameters on purpose: the offer can be laid out and read without a
/// store, a subscription, or any app state behind it.
class PaywallOffer extends StatelessWidget {
  final PlanInfo yearly;
  final PlanInfo monthly;
  final PremiumPlan plan;
  final ValueChanged<PremiumPlan> onPlan;

  /// The city of the locked location that led here, when one did.
  final String? city;

  /// How many hideip.net locations the plan covers, or null while the catalog
  /// has not been read and there is no honest number to print.
  final int? locationCount;

  /// The first charge date for the yearly plan, already formatted.
  final String trialEnds;

  /// "App Store" or "Google Play".
  final String storeName;

  /// The previous attempt failed: the banner shows and the button retries.
  final bool failed;

  /// The store's own words for that failure, when it gave any.
  final String? storeMessage;

  final VoidCallback onBuy;
  final VoidCallback onRestore;
  final VoidCallback onTerms;
  final VoidCallback onPrivacy;

  const PaywallOffer({
    super.key,
    required this.yearly,
    required this.monthly,
    required this.plan,
    required this.onPlan,
    required this.trialEnds,
    required this.storeName,
    required this.onBuy,
    required this.onRestore,
    required this.onTerms,
    required this.onPrivacy,
    this.city,
    this.locationCount,
    this.failed = false,
    this.storeMessage,
  });

  PlanInfo get _info => plan == PremiumPlan.yearly ? yearly : monthly;

  @override
  Widget build(BuildContext context) {
    final info = _info;
    return Column(children: [
      Expanded(
        // Centered rather than spread with flexible gaps: the offer has to
        // survive a short screen and a large text scale, and a column that
        // measures itself never clips what it cannot fit.
        child: LayoutBuilder(builder: (context, box) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: Center(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    _hero(),
                    const SizedBox(height: 22),
                    _benefits(),
                    const SizedBox(height: 22),
                    _segment(),
                    _price(info),
                    const SizedBox(height: 18),
                    if (failed) _errorBanner(),
                    _legal(info.trial
                        ? S.pwLegalTrial(trialEnds, storeName)
                        : S.pwLegalNow(storeName)),
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
        child: HipCta(paywallCtaLabel(info, failed: failed),
            connect: true, onTap: onBuy),
      ),
    ]);
  }

  Widget _hero() {
    final where = city;
    return Column(children: [
      const SizedBox(height: 2),
      const PremiumBadge(),
      const SizedBox(height: 11),
      Text(where == null ? S.pwTitle : S.pwTitleCity(where),
          textAlign: TextAlign.center,
          style: Hip.sans(750, 23,
              color: Colors.white, height: 1.18, letterSpacing: -.64)),
      const SizedBox(height: 6),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: Text(S.pwSub,
            textAlign: TextAlign.center,
            style: Hip.sans(400, 13,
                color: Colors.white.withValues(alpha: .58), height: 1.5)),
      ),
    ]);
  }

  /// Five rows, one promise each, divided by hairlines. The first carries the
  /// number of locations, which is the claim that does the selling.
  Widget _benefits() {
    Widget row(String title,
            {String? sub, bool badge = false, bool first = false}) =>
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
          decoration: first
              ? null
              : BoxDecoration(
                  border: Border(
                      top: BorderSide(
                          color: Colors.white.withValues(alpha: .09)))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Icon(Icons.check, size: 16, color: Brand.hsl(220, 95, 68)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(
                        child: Text(title,
                            style: Hip.sans(550, 14.5,
                                color: Colors.white, letterSpacing: -.17)),
                      ),
                      if (badge) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: Brand.hsl(220, 95, 60, .2),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(S.setBadgeNew.toUpperCase(),
                              style: Hip.sans(700, 9.5,
                                  color: Brand.hsl(220, 95, 78),
                                  letterSpacing: .5)),
                        ),
                      ],
                    ]),
                    if (sub != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(sub,
                            style: Hip.sans(500, 12,
                                color: Colors.white.withValues(alpha: .55))),
                      ),
                  ]),
            ),
          ]),
        );
    final count = locationCount;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(children: [
        row(count == null ? S.pwAllLocationsPlain : S.pwAllLocations(count),
            first: true),
        row(S.pwSpeed, sub: S.pwSpeedSub, badge: true),
        row(S.pwBlocked),
        row(S.pwNoLogs),
        row(S.pwDevices),
      ]),
    );
  }

  /// One choice, then one price. Two priced cards side by side make the
  /// reader compare offers; a segment makes them pick a rhythm.
  Widget _segment() {
    final yearlyOn = plan == PremiumPlan.yearly;
    Widget tab(PremiumPlan p, PlanInfo info, {Widget? badge}) {
      final on = plan == p;
      return Expanded(
        child: GestureDetector(
          onTap: () {
            if (!on) Haptics.selection();
            onPlan(p);
          },
          child: AnimatedContainer(
            duration: Hip.dur(const Duration(milliseconds: 180)),
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? Hip.blue : Colors.transparent,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(info.name,
                  style: Hip.sans(600, 14,
                      color:
                          on ? Colors.white : Colors.white.withValues(alpha: .6),
                      letterSpacing: -.14)),
              if (badge != null) ...[const SizedBox(width: 8), badge],
            ]),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .06),
        border: Border.all(color: Colors.white.withValues(alpha: .1)),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Row(children: [
        tab(PremiumPlan.yearly, yearly,
            badge: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: yearlyOn
                    ? Colors.white.withValues(alpha: .22)
                    : Brand.hsl(152, 60, 46, .18),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(S.pwSave,
                  style: Hip.sans(650, 10.5,
                      color: yearlyOn ? Colors.white : Brand.hsl(152, 60, 60),
                      letterSpacing: .2)),
            )),
        tab(PremiumPlan.monthly, monthly),
      ]),
    );
  }

  Widget _price(PlanInfo info) {
    final perMonth = info.perMonth;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(children: [
        Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(info.price,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Hip.mono(700, 28,
                        color: Colors.white, letterSpacing: -.7)),
              ),
              const SizedBox(width: 6),
              Text(S.pwPer(info.per),
                  style: Hip.sans(550, 14,
                      color: Colors.white.withValues(alpha: .55))),
            ]),
        const SizedBox(height: 6),
        Text(
            info.trial
                ? (perMonth == null ? S.pwTrialFree : S.pwPerMonth(perMonth))
                : S.pwMonthlyNote,
            textAlign: TextAlign.center,
            style: Hip.sans(400, 12.5,
                color: Colors.white.withValues(alpha: .5), height: 1.5)),
      ]),
    );
  }

  Widget _errorBanner() {
    final msg = storeMessage;
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
              '${S.pwFailed}${msg != null && msg.isNotEmpty ? '\n($msg)' : ''}',
              style: Hip.sans(400, 12.5,
                  color: Brand.hsl(35, 90, 78), height: 1.5)),
        ),
      ]),
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
              onTap: onRestore, child: Text(S.pwRestore, style: style)),
          dot(),
          GestureDetector(onTap: onTerms, child: Text(S.setTerms, style: style)),
          dot(),
          GestureDetector(
              onTap: onPrivacy, child: Text(S.setPrivacyPolicy, style: style)),
        ]),
      ),
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

  /// The locked location the user tapped to get here ([Location.id]), when
  /// there was one. It is what personalises the headline.
  final String? locId;
  const PaywallScreen({
    super.key,
    required this.state,
    required this.nav,
    required this.from,
    this.locId,
  });

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

enum _PwPhase { plans, buying, success, error }

class _PaywallScreenState extends State<PaywallScreen> {
  PremiumPlan _plan = PremiumPlan.yearly;
  _PwPhase _phase = _PwPhase.plans;
  String _busyMsg = '';

  /// The locations that were locked when this screen opened. Kept because
  /// they are exactly what a purchase unlocks: the success screen owes the
  /// user those, not whatever happens to be in the server list.
  late final List<Location> _wasLocked;

  @override
  void initState() {
    super.initState();
    _wasLocked = sortedByPing(widget.state, widget.state.lockedLocations);
  }

  void _back() => widget.nav.go(widget.from);

  Future<void> _buy() async {
    setState(() {
      _busyMsg = S.pwConfirming(_storeName);
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
      _busyMsg = S.pwChecking;
      _phase = _PwPhase.buying;
    });
    await widget.state.restorePurchases();
    if (!mounted) return;
    setState(
        () => _phase = widget.state.premium.isOn ? _PwPhase.success : prev);
  }

  String get _trialEnds =>
      formatPremiumDate(DateTime.now().add(const Duration(days: 7)));

  /// The city of the locked row that opened this screen, if it is still
  /// known. Nothing is invented: an id that matches nothing leaves the
  /// headline generic.
  String? get _city {
    final id = widget.locId;
    if (id == null) return null;
    for (final l in [
      ...widget.state.lockedLocations,
      ..._wasLocked,
      ...widget.state.locations,
    ]) {
      if (l.id == id) return l.city;
    }
    return null;
  }

  /// How many hideip.net locations the plan covers right now, or null while
  /// the catalog has not answered and there is nothing true to count.
  int? get _locationCount {
    final locked = widget.state.lockedLocations.length;
    if (locked > 0) return locked;
    if (_wasLocked.isNotEmpty) return _wasLocked.length;
    final owned = widget.state.locations.where((l) => l.premium).length;
    return owned > 0 ? owned : null;
  }

  @override
  Widget build(BuildContext context) {
    if (_phase == _PwPhase.success) return _success();

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
              child: PaywallOffer(
                yearly: widget.state.planInfo(PremiumPlan.yearly),
                monthly: widget.state.planInfo(PremiumPlan.monthly),
                plan: _plan,
                onPlan: (p) => setState(() => _plan = p),
                city: _city,
                locationCount: _locationCount,
                trialEnds: _trialEnds,
                storeName: _storeName,
                failed: _phase == _PwPhase.error,
                storeMessage: widget.state.purchases.lastError,
                onBuy: _buy,
                onRestore: _restore,
                onTerms: () => _openUrl(_termsUrl),
                onPrivacy: () => _openUrl(_privacyUrl),
              ),
            ),
          ]),
          if (_phase == _PwPhase.buying) _buyingOverlay(),
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
          Text(S.pwBusySub,
              textAlign: TextAlign.center,
              style: Hip.sans(400, 13.5,
                  color: Colors.white.withValues(alpha: .55), height: 1.6)),
        ]),
      ),
    );
  }

  /// What the purchase actually bought: the locations that carried a padlock
  /// a moment ago. Once provisioning has landed they are real servers on the
  /// same endpoints, so the live ones are preferred; until then the catalog
  /// rows stand in, with the latencies already measured on them.
  List<Location> get _unlocked {
    if (_wasLocked.isEmpty) return const [];
    final ids = {for (final l in _wasLocked) l.id};
    final live =
        widget.state.locations.where((l) => ids.contains(l.id)).toList();
    final shown = live.isEmpty ? _wasLocked : sortedByPing(widget.state, live);
    return shown.take(4).toList();
  }

  Widget _success() {
    final p = widget.state.premium;
    final trial = p.status == PremiumStatus.trial;
    final renewsDate =
        p.renews != null ? formatPremiumDate(p.renews!) : _trialEnds;
    final locations = _unlocked;
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
                Text(S.pwDoneTitle,
                    style: Hip.sans(750, 23,
                        color: Colors.white, letterSpacing: -.64)),
                const SizedBox(height: 6),
                Text(
                    locations.isEmpty
                        ? (trial ? S.pwDoneTrial : S.pwDonePaid)
                        : (trial ? S.pwDoneTrialNew : S.pwDonePaidNew),
                    textAlign: TextAlign.center,
                    style: Hip.sans(400, 13,
                        color: Colors.white.withValues(alpha: .58),
                        height: 1.5)),
                const SizedBox(height: 18),
                for (var i = 0; i < locations.length; i++)
                  UnlockIn(index: i, child: _unlockRow(locations[i])),
                const Spacer(),
                _legal(trial
                    ? S.pwDoneLegalTrial(renewsDate)
                    : S.pwDoneLegalPaid(renewsDate)),
                const SizedBox(height: 8),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 20),
            child: HipCta(S.pwDoneCta,
                onTap: () => widget.nav.go(HipScreen.home)),
          ),
        ]),
      ),
    );
  }

  Widget _unlockRow(Location l) {
    final ping = widget.state.pingFor(l.profile);
    final ms = ping is PingOk ? S.pwPing(ping.ms) : '';
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

/// Deals one unlocked location in, a beat after the one above it.
///
/// app.css `.unlock`: a 450 ms rise from 10px down, the first row starting at
/// 250 ms and every next one 160 ms later. The stagger is what makes the list
/// read as things gained one by one instead of a block that appears. The
/// timing goes through [Hip.dur], so "reduce motion" draws every row in place
/// at once.
class UnlockIn extends StatefulWidget {
  final int index;
  final Widget child;
  const UnlockIn({super.key, required this.index, required this.child});

  static const first = Duration(milliseconds: 250);
  static const step = Duration(milliseconds: 160);
  static const run = Duration(milliseconds: 450);

  @override
  State<UnlockIn> createState() => _UnlockInState();
}

class _UnlockInState extends State<UnlockIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final CurvedAnimation _rise;

  @override
  void initState() {
    super.initState();
    final delay = UnlockIn.first + UnlockIn.step * widget.index;
    final total = delay + UnlockIn.run;
    _c = AnimationController(vsync: this, duration: Hip.dur(total));
    // One controller per row rather than a shared clock: the delay is the
    // dead part of its own curve, which keeps a row that is added later
    // (the catalog answering after the purchase) on the same rhythm.
    _rise = CurvedAnimation(
      parent: _c,
      curve: Interval(
        delay.inMilliseconds / total.inMilliseconds,
        1,
        curve: const Cubic(.22, .61, .36, 1),
      ),
    );
    _c.forward();
  }

  @override
  void dispose() {
    _rise.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _rise,
      child: widget.child,
      builder: (_, child) => Opacity(
        opacity: _rise.value,
        child: Transform.translate(
          offset: Offset(0, 10 * (1 - _rise.value)),
          child: child,
        ),
      ),
    );
  }
}

/// Settings → Premium: the subscription at a glance plus billing shortcuts.
class PremiumManageScreen extends StatefulWidget {
  final AppState state;
  final HipNav nav;
  const PremiumManageScreen(
      {super.key, required this.state, required this.nav});

  @override
  State<PremiumManageScreen> createState() => _PremiumManageScreenState();
}

class _PremiumManageScreenState extends State<PremiumManageScreen> {
  bool _restoring = false;

  Future<void> _restore() async {
    if (_restoring) return;
    setState(() => _restoring = true);
    await widget.state.restorePurchases();
    if (mounted) setState(() => _restoring = false);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final nav = widget.nav;
    final p = state.premium;
    final info = state.planInfo(p.plan ?? PremiumPlan.yearly);
    final expired = p.status == PremiumStatus.expired;
    final statusBadge = switch (p.status) {
      PremiumStatus.active => HipBadge.ok(S.pmActive),
      PremiumStatus.trial => HipBadge.blue(S.tFreeTrial),
      _ => HipBadge(S.pmExpired, bg: Hip.line2, fg: Hip.inkSoft),
    };
    return SafeArea(
      child: Column(children: [
        HipNavHead(title: S.tPremium, onBack: () => nav.go(HipScreen.settings)),
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
                          Text(S.pmBrand,
                              style: Hip.sans(650, 15.5,
                                  color: Hip.ink, letterSpacing: -.15)),
                          const SizedBox(height: 2),
                          Text(
                              expired
                                  ? S.setPremiumEnded
                                  : S.pmPlanName(info.name),
                              style: Hip.sans(550, 12, color: Hip.muted)),
                        ]),
                  ),
                  statusBadge,
                ]),
              ),
              if (!expired) ...[
                const HipSectionLabel(S.pmSubscription),
                HipListGroup(children: [
                  HipListRow(
                    title: S.pmPlan,
                    trailing: Text.rich(TextSpan(children: [
                      TextSpan(
                          text: info.price,
                          style: Hip.mono(600, 12.5, color: Hip.muted)),
                      TextSpan(
                          text: ' ${S.pwPer(info.per)}',
                          style: Hip.sans(400, 12.5, color: Hip.muted)),
                    ])),
                  ),
                  HipListRow(
                    title: p.status == PremiumStatus.trial
                        ? S.pmTrialEnds
                        : S.pmRenews,
                    trailing: Text(
                        p.renews != null ? formatPremiumDate(p.renews!) : '',
                        style: Hip.mono(600, 12.5, color: Hip.muted)),
                  ),
                ]),
              ],
              const HipSectionLabel(S.pmBilling),
              HipListGroup(children: [
                HipListRow(
                  title: S.pmManage(_storeName),
                  subtitle: S.pmManageSub,
                  trailing:
                      Icon(Icons.open_in_new, size: 17, color: Hip.muted2),
                  onTap: () => _openUrl(_manageUrl),
                ),
                HipListRow(
                  title: _restoring ? S.pmChecking : S.pwRestore,
                  trailing: _restoring
                      ? SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Hip.muted2),
                        )
                      : Icon(Icons.chevron_right, size: 17, color: Hip.muted2),
                  onTap: _restoring ? null : _restore,
                ),
              ]),
              HipSubnote(S.pmSubnote(_storeName)),
              if (expired)
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 14, 0, 24),
                  child: HipCta(S.pmRestart,
                      onTap: () => nav.openPaywall(from: HipScreen.settings)),
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
    // The paused rows are hideip.net locations, never the user's own imports:
    // an imported server keeps working and was never part of the plan.
    final paused = sortedByPing(state, state.lockedLocations);
    return SafeArea(
      child: Column(children: [
        HipNavHead(title: '', onBack: () => nav.go(HipScreen.home)),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
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
              Text(S.expTitle,
                  textAlign: TextAlign.center,
                  style:
                      Hip.sans(750, 23, color: Hip.ink, letterSpacing: -.58)),
              const SizedBox(height: 9),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 290),
                  child: Text(S.expBody,
                      textAlign: TextAlign.center,
                      style:
                          Hip.sans(400, 13.5, color: Hip.muted, height: 1.55)),
                ),
              ),
              // Same rows as Locations: same bars, same padlock, same words.
              // One visual language for Premium, because the comparison is
              // the whole offer.
              if (paused.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: HipSectionLabel(S.expPaused),
                ),
                HipListGroup(children: [
                  for (final l in paused)
                    LockedRow(
                      location: l,
                      from: LockedFrom.expired,
                      pingMs: switch (state.pingFor(l.profile)) {
                        PingOk(ms: final ms) => ms,
                        _ => null,
                      },
                      level: state.levelFor(l.profile),
                      advanced: state.prefs.advanced,
                      onTap: (from, locId) => nav.openPaywall(
                          from: HipScreen.trialExpired, locId: locId),
                    ),
                ]),
              ],
              const SizedBox(height: 12),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 20),
          child: Column(children: [
            HipCta(S.expCta,
                onTap: () => nav.openPaywall(from: HipScreen.trialExpired)),
            const SizedBox(height: 8),
            HipCta(S.expCtaImport, quiet: true, onTap: () => nav.openImport()),
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
}
