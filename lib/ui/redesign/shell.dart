import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/deep_link.dart';
import '../../core/location.dart';
import '../../state/app_state.dart';
import 'detail_screen.dart';
import 'hip.dart';
import 'home_hero.dart';
import 'import_screen.dart';
import 'locations_screen.dart';
import 'onboarding_screen.dart';
import 'paywall_screen.dart';
import 'settings_screen.dart';

/// Whether the "get access from hideip.net" plans flow can exist on this
/// platform at all. Both stores ship it (StoreKit on iOS, Play Billing on
/// Android). This is only the build-time floor; whether any paywall entry
/// point actually renders is a further runtime check on the live catalog
/// (see [AppState.plansOffered]), so the app never advertises a purchase it
/// cannot complete, e.g. before the store products exist.
final bool kPlansAvailable = defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.android;

enum HipScreen {
  onboarding,
  home,
  locations,
  import,
  settings,
  detail,
  paywall,
  premium,
  trialExpired,
}

/// In-app navigator used by every redesign screen. A tiny state machine (the
/// same one the design prototype uses) instead of a Navigator stack: screens
/// are few, transitions are uniform, and the VPN state lives above them all.
class HipNav {
  final void Function(HipScreen screen) go;
  final void Function(Location loc) openDetail;

  /// Opens the import screen remembering where it was launched from, so back
  /// returns there (import is reachable from home, locations, onboarding,
  /// settings and the paywall).
  final VoidCallback openImport;

  /// Opens the importer with its input prefilled (used by `hideip://` deep
  /// links). Back returns home. The screen still waits for the user to tap
  /// Import; nothing is auto-imported.
  final void Function(String text) openImportWith;

  /// Opens the paywall remembering where it was launched from, so both back
  /// gestures and a cancelled purchase return there.
  final void Function(HipScreen from) openPaywall;

  /// Screens with internal steps (onboarding beats, import phases) claim the
  /// system back gesture so it walks their steps before leaving the screen.
  /// Unclaimed, the shell walks up the screen hierarchy instead.
  final void Function(VoidCallback handler) claimBack;
  final void Function(VoidCallback handler) releaseBack;

  const HipNav({
    required this.go,
    required this.openDetail,
    required this.openImport,
    required this.openImportWith,
    required this.openPaywall,
    required this.claimBack,
    required this.releaseBack,
  });
}

/// Root of the redesigned UI: owns which screen is visible plus the toast.
class HipShell extends StatefulWidget {
  final AppState state;
  const HipShell({super.key, required this.state});

  @override
  State<HipShell> createState() => _HipShellState();
}

class _HipShellState extends State<HipShell>
    with SingleTickerProviderStateMixin {
  HipScreen? _screen; // null until AppState.ready decides the entry screen
  Location? _detailLoc;
  HipScreen _importFrom = HipScreen.home;
  HipScreen _paywallFrom = HipScreen.home;
  VoidCallback? _backOverride;

  // Deep-link plumbing. A `hideip://` link parses into text the importer is
  // prefilled with; while onboarding is still up the link waits here and opens
  // the importer once the shell settles on a real screen.
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSub;
  String? _importInitialText; // consumed by the next import build
  String? _pendingLinkText; // held until the shell is past onboarding

  // iOS edge-swipe back: with no Navigator stack there is no system gesture,
  // so a drag that starts at the left edge maps onto the same hierarchy the
  // back arrows use. The screen it would return to renders underneath and the
  // current one follows the finger (the Cupertino pop feel); a claimed back
  // handler has internal steps the shell cannot preview, so it just fires on
  // a completed swipe.
  late final AnimationController _swipeCtrl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 240));
  HipScreen? _swipeTarget; // non-null while a peek drag/settle is showing
  bool _swipeSettling = false; // release animation running, ignore updates
  bool _swipeClaimed = false; // drag belongs to a claimed handler
  double _dragExtent = 0;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    _swipeCtrl.dispose();
    super.dispose();
  }

  /// Wires the `hideip://` deep-link sources: the cold-start link (app opened
  /// by a link) and the warm stream (a link arriving while running). The
  /// stream also emits the initial link, so we only read the initial link
  /// explicitly for the cold-start case and let the stream cover the rest.
  Future<void> _initDeepLinks() async {
    _linkSub = _appLinks.uriLinkStream.listen(_onDeepLink, onError: (_) {});
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) _onDeepLink(initial);
    } catch (_) {
      // No initial link (or no platform side, e.g. tests): nothing to do.
    }
  }

  /// Turns a deep link into importer text and routes to the import screen.
  /// While onboarding is still showing, the text is parked and opened once the
  /// user reaches a real screen (see [build]). Never auto-imports.
  void _onDeepLink(Uri uri) {
    final parsed = parseDeepLink(uri.toString());
    if (parsed == null) return; // not a hideip import link
    if (!mounted) return;
    // Onboarding is a modal flow; land on import only after it finishes.
    if (_screen == HipScreen.onboarding ||
        (_screen == null && !widget.state.prefs.onboarded)) {
      _pendingLinkText = parsed.text;
      return;
    }
    _openImportWith(parsed.text);
  }

  void _openImportWith(String text) {
    setState(() {
      _importInitialText = text;
      _importFrom = HipScreen.home;
      _screen = HipScreen.import;
    });
  }

  late final HipNav _nav = HipNav(
    go: (s) => setState(() => _screen = s),
    openDetail: (loc) => setState(() {
      _detailLoc = loc;
      _screen = HipScreen.detail;
    }),
    openImport: () => setState(() {
      _importInitialText = null;
      _importFrom = _screen ?? HipScreen.home;
      _screen = HipScreen.import;
    }),
    openImportWith: _openImportWith,
    openPaywall: (from) => setState(() {
      _paywallFrom = from;
      _screen = HipScreen.paywall;
    }),
    claimBack: (h) => _backOverride = h,
    // Only the claimant may release; a new screen may already hold the claim
    // by the time the old one is disposed.
    releaseBack: (h) {
      if (_backOverride == h) _backOverride = null;
    },
  );

  /// Where a back gesture leads from [s], or null when [s] is a root screen
  /// and back belongs to the OS.
  HipScreen? _backTargetOf(HipScreen? s) => switch (s) {
        HipScreen.locations || HipScreen.settings => HipScreen.home,
        HipScreen.detail => HipScreen.locations,
        HipScreen.import => _importFrom,
        HipScreen.paywall => _paywallFrom,
        HipScreen.premium => HipScreen.settings,
        HipScreen.trialExpired => HipScreen.home,
        _ => null,
      };

  /// The system back gesture, mapped onto the same hierarchy the in-app back
  /// arrows use. Only the two root screens hand back to the OS.
  void _systemBack() {
    final claimed = _backOverride;
    if (claimed != null) {
      claimed();
      return;
    }
    final target = _backTargetOf(_screen);
    if (target != null) {
      _nav.go(target);
    } else {
      SystemNavigator.pop();
    }
  }

  void _swipeStart(DragStartDetails d) {
    _dragExtent = 0;
    _swipeClaimed = false;
    if (_swipeSettling) return;
    if (_backOverride != null) {
      // Internal steps (import phases, onboarding beats): no preview, the
      // completed swipe fires the claimed handler like the arrow would.
      _swipeClaimed = true;
      return;
    }
    final target = _backTargetOf(_screen);
    if (target == null) return; // root screen: never background the app
    setState(() => _swipeTarget = target);
  }

  void _swipeUpdate(DragUpdateDetails d) {
    _dragExtent += d.delta.dx;
    if (_swipeTarget != null && !_swipeSettling) {
      final width = context.size?.width ?? 1;
      _swipeCtrl.value = (_dragExtent / width).clamp(0.0, 1.0);
    }
  }

  Future<void> _swipeEnd(DragEndDetails d) async {
    final velocity = d.primaryVelocity ?? 0;
    if (_swipeClaimed) {
      _swipeClaimed = false;
      if (_dragExtent > 72 || velocity > 500) _systemBack();
      return;
    }
    final target = _swipeTarget;
    if (target == null || _swipeSettling) return;
    final commit =
        velocity > 300 || (_swipeCtrl.value > 0.35 && velocity > -300);
    _swipeSettling = true;
    final remaining = commit ? 1 - _swipeCtrl.value : _swipeCtrl.value;
    final duration = _swipeCtrl.duration! * remaining;
    if (commit) {
      await _swipeCtrl.animateTo(1, duration: duration, curve: Curves.easeOut);
    } else {
      await _swipeCtrl.animateBack(0, duration: duration, curve: Curves.easeOut);
    }
    if (!mounted) return;
    setState(() {
      if (commit) _screen = target;
      _swipeTarget = null;
      _swipeCtrl.value = 0;
      _swipeSettling = false;
    });
  }

  Widget _buildScreen(HipScreen s, AppState state) => switch (s) {
        HipScreen.onboarding => OnboardingScreen(state: state, nav: _nav),
        HipScreen.home => HomeHeroScreen(state: state, nav: _nav),
        HipScreen.locations => LocationsScreen(state: state, nav: _nav),
        HipScreen.import => ImportScreen(
            // A new deep link while the importer is already open must rebuild
            // its state so the fresh text prefills; key on the text to force it.
            key: ValueKey('import:${_importInitialText ?? ''}'),
            state: state,
            nav: _nav,
            exitTo: _importFrom,
            initialText: _importInitialText,
          ),
        HipScreen.settings => SettingsScreen(state: state, nav: _nav),
        HipScreen.detail =>
          DetailScreen(state: state, nav: _nav, location: _detailLoc!),
        HipScreen.paywall =>
          PaywallScreen(state: state, nav: _nav, from: _paywallFrom),
        HipScreen.premium => PremiumManageScreen(state: state, nav: _nav),
        HipScreen.trialExpired => TrialExpiredScreen(state: state, nav: _nav),
      };

  Color _bgFor(HipScreen s) =>
      s == HipScreen.onboarding || s == HipScreen.paywall
          ? Hip.dark
          : Hip.surface;

  /// The mid-swipe frame: the back target sits underneath with the Cupertino
  /// parallax while the current screen follows the finger, carrying an edge
  /// shadow. Both get opaque backgrounds so nothing shows through the seam.
  Widget _buildPeek(AppState state, {required Widget current}) {
    final target = _swipeTarget!;
    final under = KeyedSubtree(
        key: ValueKey(target), child: _buildScreen(target, state));
    return AnimatedBuilder(
      animation: _swipeCtrl,
      builder: (context, _) {
        final p = _swipeCtrl.value;
        final width = MediaQuery.sizeOf(context).width;
        return Stack(children: [
          Positioned.fill(
            child: Transform.translate(
              offset: Offset(-width * 0.3 * (1 - p), 0),
              child: ColoredBox(color: _bgFor(target), child: under),
            ),
          ),
          Positioned.fill(
            child: Transform.translate(
              offset: Offset(width * p, 0),
              child: DecoratedBox(
                decoration: const BoxDecoration(boxShadow: [
                  BoxShadow(color: Colors.black26, blurRadius: 16),
                ]),
                child: ColoredBox(color: _bgFor(_screen!), child: current),
              ),
            ),
          ),
        ]);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        final state = widget.state;
        if (!state.ready) {
          return const Scaffold(backgroundColor: Hip.dark, body: SizedBox());
        }
        // Resolve the token palette for this frame; the prefs change that
        // flips it already rebuilds the whole tree below.
        Hip.dm = state.prefs.darkMode;
        _screen ??=
            state.prefs.onboarded ? HipScreen.home : HipScreen.onboarding;

        // A deep link that arrived during onboarding lands on import once the
        // user finishes and the shell leaves the onboarding screen.
        if (_pendingLinkText != null && _screen != HipScreen.onboarding) {
          final text = _pendingLinkText!;
          _pendingLinkText = null;
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _openImportWith(text));
        }

        final iosSwipe = Theme.of(context).platform == TargetPlatform.iOS;
        final onDark = _screen == HipScreen.onboarding ||
            _screen == HipScreen.paywall;
        Widget content = KeyedSubtree(
            key: ValueKey(_screen), child: _buildScreen(_screen!, state));
        if (_swipeTarget != null) {
          content = _buildPeek(state, current: content);
        }

        return AnnotatedRegion<SystemUiOverlayStyle>(
          // Home also starts under the dark hero panel; in dark mode every
          // surface is dark.
          value: onDark || _screen == HipScreen.home || Hip.dm
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark,
          child: PopScope(
            // The shell handles every back gesture itself; screens are a
            // state machine, not a Navigator stack, so a real pop would
            // background the whole app.
            canPop: false,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) _systemBack();
            },
            child: RawGestureDetector(
              // iOS has no system back gesture without a Navigator stack;
              // Android's arrives through PopScope already. The recognizer
              // only competes for pointers that land on the left screen edge
              // (like the native gesture), so pans and horizontal scrolls
              // anywhere else never lose the arena to it.
              gestures: {
                if (iosSwipe)
                  _EdgeBackDragRecognizer: GestureRecognizerFactoryWithHandlers<
                      _EdgeBackDragRecognizer>(
                    () => _EdgeBackDragRecognizer(debugOwner: this),
                    (r) => r
                      ..onStart = _swipeStart
                      ..onUpdate = _swipeUpdate
                      ..onEnd = _swipeEnd,
                  ),
              },
              child: Scaffold(
                backgroundColor: onDark ? Hip.dark : Hip.surface,
                body: Stack(children: [
                  content,
                  if (state.toast != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 96,
                      child: Center(child: HipToast(state.toast!)),
                    ),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A horizontal drag that only enters the gesture arena for pointers that
/// land within the left screen edge, mirroring the native iOS back gesture.
/// Anywhere else the shell never competes, so the map pan and horizontal
/// scrolls keep their gestures.
class _EdgeBackDragRecognizer extends HorizontalDragGestureRecognizer {
  _EdgeBackDragRecognizer({super.debugOwner});

  static const double edgeWidth = 32;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (event.position.dx > edgeWidth) return;
    super.addAllowedPointer(event);
  }
}
