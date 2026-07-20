import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../core/haptics.dart';
import '../../core/ip_lookup.dart';
import '../../core/location.dart';
import '../../core/votes.dart';
import '../brand.dart';
import 'hip.dart';
import 'mark.dart' show MarkState;

/// Precision world map, ported from the design prototype's mapview.jsx.
///
/// Geometry is projected once (by scripts/build-world-geo.py) into a fixed
/// 402x640 Web Mercator reference plane; the widget only moves a camera
/// (cx, cy, zoom) over it, so container resizes and pan/zoom stay cheap.
/// The map opens centred on the user's IP location and glides in; connect
/// flies the camera to the exit node.
class WorldMap extends StatefulWidget {
  final List<Location> locations;
  final Location? active;
  final MarkState conn;
  final bool advanced;
  final bool open;
  final IpGeo? userGeo;
  final int? activePingMs;
  final ValueChanged<Location> onPick;
  final VoidCallback onConnect;
  final VoidCallback onAllLocations;

  const WorldMap({
    super.key,
    required this.locations,
    required this.active,
    required this.conn,
    required this.advanced,
    required this.open,
    required this.userGeo,
    required this.activePingMs,
    required this.onPick,
    required this.onConnect,
    required this.onAllLocations,
  });

  @override
  State<WorldMap> createState() => _WorldMapState();
}

// Reference plane and camera limits (identical to the prototype).
const _refW = 402.0;
const _refH = 640.0;
const _zReg = 11.0; // regional zoom on the exit node
const _zYou = 8.0; // idle zoom on the user
const _zMax = 34.0;
const _zMin = 1.05;

Offset _project(double lat, double lon) {
  const scale = _refW / (2 * math.pi);
  final la = lat.clamp(-85.0511, 85.0511) * math.pi / 180;
  return Offset(
    _refW / 2 + scale * lon * math.pi / 180,
    _refH / 2 - scale * math.log(math.tan(math.pi / 4 + la / 2)),
  );
}

final _yTop = _project(84, 0).dy; // pan bounds, matching the prototype
final _yBottom = _project(-60, 0).dy;

/// ISO 3166 alpha-2 -> numeric ids used by the world-atlas geometry, for
/// highlighting countries that have a node. Covers the countries the
/// location parser recognizes.
const _ccIso = {
  'AE': '784', 'AL': '008', 'AM': '051', 'AR': '032', 'AT': '040',
  'AU': '036', 'AZ': '031', 'BA': '070', 'BE': '056', 'BG': '100',
  'BR': '076', 'BY': '112', 'CA': '124', 'CH': '756', 'CL': '152',
  'CO': '170', 'CY': '196', 'CZ': '203', 'DE': '276', 'DK': '208',
  'EE': '233', 'EG': '818', 'ES': '724', 'FI': '246', 'FR': '250',
  'GB': '826', 'GE': '268', 'GR': '300', 'HK': '344', 'HR': '191',
  'HU': '348', 'ID': '360', 'IE': '372', 'IL': '376', 'IN': '356',
  'IS': '352', 'IT': '380', 'JP': '392', 'KR': '410', 'KZ': '398',
  'LT': '440', 'LU': '442', 'LV': '428', 'MD': '498', 'ME': '499',
  'MK': '807', 'MT': '470', 'MX': '484', 'MY': '458', 'NL': '528',
  'NO': '578', 'NZ': '554', 'PH': '608', 'PL': '616', 'PT': '620',
  'RO': '642', 'RS': '688', 'RU': '643', 'SA': '682', 'SE': '752',
  'SG': '702', 'SI': '705', 'SK': '703', 'TH': '764', 'TR': '792',
  'TW': '158', 'UA': '804', 'US': '840', 'VN': '704', 'ZA': '710',
};

class _Country {
  final String id; // ISO 3166-1 numeric, as used by world-atlas
  final String name;
  final Path path;
  final Rect bounds; // cached: the invite pulse scans these every cycle
  _Country(this.id, this.name, this.path) : bounds = path.getBounds();
}

/// Pre-projected world geometry, decoded once from assets/world_geo.json.
class _WorldGeo {
  final List<_Country> countries;
  final Path borders;
  final Path graticule;
  const _WorldGeo(this.countries, this.borders, this.graticule);

  static Future<_WorldGeo>? _loading;

  static Future<_WorldGeo> load() => _loading ??= _decode();

  static Future<_WorldGeo> _decode() async {
    final raw = await rootBundle.loadString('assets/world_geo.json');
    final data = json.decode(raw) as Map<String, dynamic>;

    Path polyline(List pts, {bool close = false}) {
      final p = Path()..moveTo((pts[0] as num).toDouble(), (pts[1] as num).toDouble());
      for (var i = 2; i < pts.length; i += 2) {
        p.lineTo((pts[i] as num).toDouble(), (pts[i + 1] as num).toDouble());
      }
      if (close) p.close();
      return p;
    }

    final countries = <_Country>[];
    for (final c in data['countries'] as List) {
      final path = Path();
      for (final ring in c['p'] as List) {
        path.addPath(polyline(ring as List, close: true), Offset.zero);
      }
      countries.add(
          _Country(c['id'] as String, (c['name'] as String?) ?? '', path));
    }

    final borders = Path();
    for (final arc in data['borders'] as List) {
      borders.addPath(polyline(arc as List), Offset.zero);
    }

    // Mercator graticule is a straight 10-degree grid.
    final grat = Path();
    for (var lon = -180; lon <= 180; lon += 10) {
      grat
        ..moveTo(_project(84, lon.toDouble()).dx, _yTop)
        ..lineTo(_project(84, lon.toDouble()).dx, _project(-80, 0).dy);
    }
    for (var lat = -80; lat <= 80; lat += 10) {
      final y = _project(lat.toDouble(), 0).dy;
      grat
        ..moveTo(_project(0, -180).dx, y)
        ..lineTo(_project(0, 180).dx, y);
    }

    return _WorldGeo(countries, borders, grat);
  }
}

class _View {
  final double cx, cy, z;
  const _View(this.cx, this.cy, this.z);
}

class _WorldMapState extends State<WorldMap> with TickerProviderStateMixin {
  _WorldGeo? _geo;
  Size _box = Size.zero;
  _View? _view;

  // Camera animation: z and the screen-offset products lerp linearly, which
  // matches how CSS interpolates the prototype's transform matrix.
  late final AnimationController _cam = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1050));
  final _camCurve = const Cubic(.3, .72, .2, 1);
  _View? _from, _to;

  // Ambient loop driving halo blips, the connecting dash, the HUD dot and
  // the invite pulse.
  late final AnimationController _tick = AnimationController(
      vsync: this, duration: const Duration(seconds: 4))
    ..repeat();

  bool _entered = false;
  _View? _gStart;
  Offset _gFocal = Offset.zero;
  Offset? _doubleTapAt;

  // Voting: a tapped country without a node, and the shared vote state.
  _Country? _voteSel;
  final VoteService _votes = VoteService.instance;

  // Invite pulse: once per ambient cycle one visible country without a node
  // glows briefly, so the map itself says plain land is tappable (voting).
  String? _pulseId;
  int _pulseCycle = -1;
  double _lastTick = 0;

  @override
  void initState() {
    super.initState();
    _WorldGeo.load().then((g) {
      if (mounted) setState(() => _geo = g);
    });
    _cam.addListener(() => setState(() {}));
    _tick.addListener(_onTick);
    _votes.addListener(_onVotes);
    _votes.init();
  }

  void _onTick() {
    // A wrap of the 4s loop starts the next pulse; before the first pulse,
    // keep trying until the geometry and layout are ready.
    if (_tick.value < _lastTick || (_pulseId == null && _pulseCycle < 0)) {
      _advancePulse();
    }
    _lastTick = _tick.value;
  }

  void _advancePulse() {
    final g = _geo;
    if (g == null || _box.isEmpty) return;
    final v = _current;
    final hw = _box.width / (2 * v.z), hh = _box.height / (2 * v.z);
    final vis = Rect.fromLTRB(v.cx - hw, v.cy - hh, v.cx + hw, v.cy + hh);
    final has = _hasNodeIds;
    // Only countries the user can actually see and notice (roughly 30x30
    // screen px and up) are worth pulsing.
    final candidates = <_Country>[
      for (final c in g.countries)
        if (c.name.isNotEmpty &&
            !has.contains(c.id) &&
            c.bounds.overlaps(vis) &&
            c.bounds.width * c.bounds.height * v.z * v.z > 900)
          c,
    ];
    if (candidates.isEmpty) {
      _pulseId = null;
      return;
    }
    _pulseCycle++;
    _pulseId = candidates[_pulseCycle % candidates.length].id;
  }

  void _onVotes() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _votes.removeListener(_onVotes);
    _cam.dispose();
    _tick.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant WorldMap old) {
    super.didUpdateWidget(old);
    if (!widget.open && old.open) _entered = false;
    // A state change re-frames the camera; drop the vote card rather than
    // have it ride over the transition. Voting itself works in any state.
    if (widget.conn != old.conn) _voteSel = null;
    if (widget.conn != old.conn ||
        widget.active?.index != old.active?.index ||
        (widget.userGeo == null) != (old.userGeo == null)) {
      if (_view != null && !_box.isEmpty) _animateTo(_camFor());
    }
  }

  // --- camera ------------------------------------------------------------

  Offset? get _up {
    final g = widget.userGeo;
    return g == null ? null : _project(g.lat, g.lon);
  }

  Offset? get _activeP {
    final a = widget.active;
    return (a == null || a.lat == null) ? null : _project(a.lat!, a.lon!);
  }

  _View _clamp(_View v) {
    final z = math.min(_zMax, math.max(math.max(_zMin, _box.width / _refW), v.z));
    final hw = _box.width / (2 * z), hh = _box.height / (2 * z);
    final minX = hw, maxX = _refW - hw;
    final cx = minX > maxX ? _refW / 2 : v.cx.clamp(minX, maxX);
    final minY = _yTop + hh, maxY = _yBottom - hh;
    final cy = minY > maxY ? (_yTop + _yBottom) / 2 : v.cy.clamp(minY, maxY);
    return _View(cx, cy, z);
  }

  _View _camFor() {
    final up = _up, a = _activeP ?? up;
    _View fit(List<Offset> pts) {
      final xs = pts.map((p) => p.dx), ys = pts.map((p) => p.dy);
      final x0 = xs.reduce(math.min), x1 = xs.reduce(math.max);
      final y0 = ys.reduce(math.min), y1 = ys.reduce(math.max);
      final z = math.min(
          _zReg,
          math.min(_box.width / math.max((x1 - x0) * 1.8, .001),
              _box.height / math.max((y1 - y0) * 2.3, .001)));
      return _View((x0 + x1) / 2, (y0 + y1) / 2, math.max(2.2, z));
    }

    switch (widget.conn) {
      case MarkState.connected:
        if (a != null) return _View(a.dx, a.dy, _zReg);
      case MarkState.connecting || MarkState.disconnecting:
        if (up != null && a != null) return fit([up, a]);
        if (a != null) return _View(a.dx, a.dy, _zReg);
      case MarkState.disconnected:
        if (up != null) return _View(up.dx, up.dy, _zYou);
    }
    // No IP geolocation yet: frame whatever nodes exist, or the world.
    final pts = _nodePoints;
    if (pts.isNotEmpty) return fit(pts.map((p) => p.$2).toList());
    return _View(_refW / 2, _project(30, 0).dy, 2.2);
  }

  List<(Location, Offset)> get _nodePoints => [
        for (final l in widget.locations)
          if (l.lat != null) (l, _project(l.lat!, l.lon!)),
      ];

  Set<String> get _hasNodeIds => {
        for (final l in widget.locations)
          if (_ccIso[l.cc] != null) _ccIso[l.cc]!,
      };

  _View get _current {
    if (_cam.isAnimating && _from != null && _to != null) {
      final t = _camCurve.transform(_cam.value);
      final z = ui.lerpDouble(_from!.z, _to!.z, t)!;
      final ex = ui.lerpDouble(_from!.z * _from!.cx, _to!.z * _to!.cx, t)!;
      final ey = ui.lerpDouble(_from!.z * _from!.cy, _to!.z * _to!.cy, t)!;
      return _View(ex / z, ey / z, z);
    }
    return _view ?? _clamp(_camFor());
  }

  void _animateTo(_View target) {
    _from = _current;
    _to = _clamp(target);
    _view = _to;
    _cam.forward(from: 0);
  }

  void _setView(_View v) {
    _cam.stop();
    setState(() => _view = _clamp(v));
  }

  void _ensureEntrance() {
    if (_entered || !widget.open || _box.isEmpty) return;
    _entered = true;
    final t = _clamp(_camFor());
    _view = _clamp(_View(t.cx, t.cy, math.max(2.2, t.z * .45)));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.open) _animateTo(t);
    });
  }

  // --- gestures ----------------------------------------------------------

  void _zoomAt(Offset p, double f) {
    final v = _current;
    final z = (v.z * f).clamp(_zMin, _zMax);
    final mx = v.cx + (p.dx - _box.width / 2) / v.z;
    final my = v.cy + (p.dy - _box.height / 2) / v.z;
    _setView(_View(
        mx - (p.dx - _box.width / 2) / z, my - (p.dy - _box.height / 2) / z, z));
  }

  void _onScaleStart(ScaleStartDetails d) {
    _cam.stop();
    _gStart = _current;
    _view = _gStart;
    _gFocal = d.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final v0 = _gStart;
    if (v0 == null) return;
    final z = (v0.z * d.scale).clamp(_zMin, _zMax).toDouble();
    final wx = v0.cx + (_gFocal.dx - _box.width / 2) / v0.z;
    final wy = v0.cy + (_gFocal.dy - _box.height / 2) / v0.z;
    _setView(_View(wx - (d.localFocalPoint.dx - _box.width / 2) / z,
        wy - (d.localFocalPoint.dy - _box.height / 2) / z, z));
  }

  void _onTapUp(TapUpDetails d) {
    final v = _current;
    final r = Offset(v.cx + (d.localPosition.dx - _box.width / 2) / v.z,
        v.cy + (d.localPosition.dy - _box.height / 2) / v.z);

    // Pins first (13 screen px hit radius, like the prototype).
    for (final (loc, p) in _nodePoints) {
      if ((p - r).distance * v.z <= 13) {
        widget.onPick(loc);
        return;
      }
    }
    // Then the floating tag above the active pin (its Connect action).
    final a = _activeP;
    if (a != null &&
        widget.conn == MarkState.disconnected) {
      final local = (r - a) * v.z; // tag coords are screen px around the pin
      final tagW = _tagWidth();
      if (local.dx.abs() <= tagW / 2 + 9 &&
          local.dy >= -52 &&
          local.dy <= -6) {
        widget.onConnect();
        return;
      }
    }

    // Finally the land itself: a country without a node opens the vote card,
    // tunnel up or down; anything else closes it.
    final g = _geo;
    if (g == null) return;
    _Country? hit;
    for (final c in g.countries) {
      if (c.path.contains(r)) {
        hit = c;
        break;
      }
    }
    final pick =
        (hit == null || hit.name.isEmpty || _hasNodeIds.contains(hit.id))
            ? null
            : hit;
    if (pick != null) Haptics.selection();
    setState(() => _voteSel = pick);
  }

  // --- copy --------------------------------------------------------------

  String _fmtGeo(double lat, double lon) =>
      '${lat.abs().toStringAsFixed(2)}°${lat >= 0 ? 'N' : 'S'} '
      '${lon.abs().toStringAsFixed(2)}°${lon >= 0 ? 'E' : 'W'}';

  (String, Color) _hud() {
    final a = widget.active;
    final ping = widget.activePingMs != null ? '${widget.activePingMs} MS' : '…';
    switch (widget.conn) {
      case MarkState.connected when a != null:
        return (
          widget.advanced
              ? 'EXIT ${a.host} · $ping'
              : 'EXIT ${a.city.toUpperCase()}'
                  '${a.lat != null ? ' · ${_fmtGeo(a.lat!, a.lon!)}' : ''} · $ping',
          Brand.hsl(152, 60, 50)
        );
      case MarkState.connecting when a != null:
        return ('LINK → ${a.city.toUpperCase()} · HANDSHAKE…', Brand.hsl(220, 95, 62));
      case MarkState.disconnecting:
        return ('CLOSING TUNNEL…', Brand.hsl(220, 95, 62));
      default:
        final g = widget.userGeo;
        return (
          g != null
              ? 'YOU · ${g.city.toUpperCase()} · ${_fmtGeo(g.lat, g.lon)}'
              : 'YOU · LOCATION UNKNOWN',
          Brand.hsl(4, 75, 58)
        );
    }
  }

  String get _tagCity => switch (widget.conn) {
        MarkState.connecting => 'Connecting…',
        MarkState.disconnecting => 'Disconnecting…',
        _ => widget.active?.city ?? '',
      };

  String get _tagAction =>
      widget.conn == MarkState.disconnected && widget.active != null
          ? ' · Connect'
          : '';

  double _tagWidth() {
    final tp = TextPainter(
      text: TextSpan(text: _tagCity + _tagAction, style: Hip.sans(650, 11)),
      textDirection: TextDirection.ltr,
    )..layout();
    return tp.width + 40;
  }

  // --- build -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, cons) {
      final box = Size(cons.maxWidth, cons.maxHeight);
      if (box != _box && box.width > 0 && box.height > 0) {
        // Track the focus point through the container's expand animation.
        final hadView = _view != null;
        _box = box;
        if (hadView && !_cam.isAnimating) _view = _clamp(_view!);
      }
      if (_box.isEmpty) return const SizedBox.shrink();
      _ensureEntrance();

      final (hudText, hudColor) = _hud();
      // Runs the same green wash as the hero panel above (same duration and
      // curve), so panel, seam and ocean move as one surface on connect.
      return TweenAnimationBuilder<double>(
        tween: Tween(
            begin: 0,
            end: widget.conn == MarkState.connected ? 1.0 : 0.0),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (context, connT, _) => _buildStack(hudText, hudColor, connT),
      );
    });
  }

  Widget _buildStack(String hudText, Color hudColor, double connT) {
    return Stack(children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            onTapUp: _onTapUp,
            onDoubleTapDown: (d) => _doubleTapAt = d.localPosition,
            onDoubleTap: () {
              if (_doubleTapAt != null) _zoomAt(_doubleTapAt!, 1.8);
            },
            child: AnimatedBuilder(
              animation: _tick,
              builder: (context, _) => CustomPaint(
                size: _box,
                painter: _MapPainter(
                  geo: _geo,
                  view: _current,
                  box: _box,
                  nodes: _nodePoints,
                  activeIndex: widget.active?.index,
                  up: _up,
                  userCity: widget.userGeo?.city,
                  conn: widget.conn,
                  tagCity: _tagCity,
                  tagAction: _tagAction,
                  hasNodeIds: _hasNodeIds,
                  selectedId: _voteSel?.id,
                  pulseId: _voteSel == null ? _pulseId : null,
                  t: _tick.value,
                  connT: connT,
                ),
              ),
            ),
          ),
        ),
        // Soft vignette so the panel's dark chrome bleeds into the map. Its
        // edges follow the connected wash so the blend matches whatever the
        // panel above currently shows.
        IgnorePointer(
          child: Builder(builder: (context) {
            final top = Color.lerp(Hip.dark, const Color(0xFF0B1D15), connT)!;
            final bottom = Color.lerp(
                Brand.hsl(222, 30, 5, .5),
                const Color(0xFF08150F).withValues(alpha: .5),
                connT)!;
            return DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    top,
                    top.withValues(alpha: 0),
                    top.withValues(alpha: 0),
                    bottom,
                  ],
                  stops: const [0, .15, .84, 1],
                ),
              ),
              child: const SizedBox.expand(),
            );
          }),
        ),
        if (_geo == null)
          Center(
            child: Text('LOADING MAP…',
                style: Hip.sans(600, 10.5,
                    color: Colors.white.withValues(alpha: .35),
                    letterSpacing: .84)),
          ),
        if (_geo != null &&
            widget.open &&
            _voteSel == null &&
            !_votes.hintDismissed)
          const Positioned(top: 10, left: 12, child: _VoteHint()),
        if (_voteSel != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 60,
            child: _VoteCard(
              key: ValueKey(_voteSel!.id),
              countryId: _voteSel!.id,
              countryName: _voteSel!.name,
              votes: _votes,
              onClose: () => setState(() => _voteSel = null),
            ),
          ),
        Positioned(
          top: 10,
          right: 12,
          child: GestureDetector(
            onTap: () => _animateTo(_camFor()),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Brand.hsl(222, 20, 9, .8),
                border: Border.all(color: Colors.white.withValues(alpha: .12)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.explore_outlined,
                  size: 16, color: Colors.white.withValues(alpha: .75)),
            ),
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: Container(
            height: 38,
            padding: const EdgeInsets.only(left: 13, right: 5),
            decoration: BoxDecoration(
              color: Brand.hsl(222, 20, 8, .85),
              border: Border.all(color: Colors.white.withValues(alpha: .1)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              AnimatedBuilder(
                animation: _tick,
                builder: (context, _) {
                  final busy = widget.conn == MarkState.connecting ||
                      widget.conn == MarkState.disconnecting;
                  final beat =
                      .5 + .5 * math.sin(_tick.value * 4 * 2 * math.pi);
                  return Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: busy
                          ? hudColor.withValues(alpha: .55 + .45 * beat)
                          : hudColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                            color: hudColor.withValues(alpha: .2),
                            spreadRadius: 3),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(hudText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Hip.mono(600, 10.5,
                        color: Colors.white.withValues(alpha: .78),
                        letterSpacing: .5)),
              ),
              const SizedBox(width: 9),
              GestureDetector(
                onTap: widget.onAllLocations,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('All locations',
                        style: Hip.sans(600, 11.5,
                            color: Colors.white.withValues(alpha: .88))),
                    const SizedBox(width: 3),
                    Icon(Icons.chevron_right,
                        size: 12, color: Colors.white.withValues(alpha: .5)),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ]);
  }
}

class _MapPainter extends CustomPainter {
  final _WorldGeo? geo;
  final _View view;
  final Size box;
  final List<(Location, Offset)> nodes;
  final int? activeIndex;
  final Offset? up;
  final String? userCity;
  final MarkState conn;
  final String tagCity;
  final String tagAction;
  final Set<String> hasNodeIds;
  final String? selectedId; // country picked for voting
  final String? pulseId; // country glowing this ambient cycle (invite pulse)
  final double t; // 0..1 ambient loop (4s)
  final double connT; // 0..1 connected wash, in step with the hero panel

  _MapPainter({
    required this.geo,
    required this.view,
    required this.box,
    required this.nodes,
    required this.activeIndex,
    required this.up,
    required this.userCity,
    required this.conn,
    required this.tagCity,
    required this.tagAction,
    required this.hasNodeIds,
    required this.selectedId,
    required this.pulseId,
    required this.t,
    required this.connT,
  });

  // Ocean base and its connected-state counterpart. While the tunnel is up
  // the hero panel behind the map washes green; tinting the ocean the same
  // way keeps the panel and the map reading as one surface instead of a
  // green band sitting on a black rectangle.
  static final _bgBase = Brand.hsl(222, 32, 4.5);
  static const _bgOn = Color(0xFF071510);

  @override
  void paint(Canvas canvas, Size size) {
    // The camera projects far beyond the widget; never paint outside it.
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(Offset.zero & size,
        Paint()..color = Color.lerp(_bgBase, _bgOn, connT)!);
    final z = view.z, iz = 1 / z;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(z);
    canvas.translate(-view.cx, -view.cy);

    final g = geo;
    if (g != null) {
      final grat = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .5 * iz
        ..color = Brand.hsl(221, 16, 14.5);
      canvas.drawPath(g.graticule, grat);

      final landFill = Paint()..color = Brand.hsl(221, 15, 13);
      final landHasFill = Paint()..color = Brand.hsl(221, 32, 16);
      final landStroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .8 * iz
        ..color = Brand.hsl(221, 17, 31);
      final landHasStroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .8 * iz
        ..color = Brand.hsl(221, 40, 36);
      final landSelFill = Paint()..color = Brand.hsl(221, 55, 21);
      final landSelStroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .8 * iz
        ..color = Brand.hsl(220, 90, 62, .8);
      for (final c in g.countries) {
        final sel = c.id == selectedId;
        final has = hasNodeIds.contains(c.id);
        canvas.drawPath(
            c.path, sel ? landSelFill : (has ? landHasFill : landFill));
        canvas.drawPath(
            c.path, sel ? landSelStroke : (has ? landHasStroke : landStroke));
      }
      final borders = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .6 * iz
        ..color = Brand.hsl(221, 13, 21);
      canvas.drawPath(g.borders, borders);

      // Invite pulse: a soft in-and-out glow in the vote selection tint, so
      // the map itself keeps saying that plain land answers a tap.
      if (pulseId != null) {
        final env = math.sin(t * math.pi);
        final a = env * env;
        for (final c in g.countries) {
          if (c.id != pulseId) continue;
          canvas.drawPath(c.path, Paint()..color = Brand.hsl(221, 55, 26, .5 * a));
          canvas.drawPath(
              c.path,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = .8 * iz
                ..color = Brand.hsl(220, 90, 62, .5 * a));
          break;
        }
      }
    }

    final connected = conn == MarkState.connected;
    final connecting = conn == MarkState.connecting;
    final busy = connecting || conn == MarkState.disconnecting;
    final acc = connected ? Brand.hsl(152, 60, 48) : Brand.hsl(220, 95, 62);

    Offset? activeP;
    for (final (l, p) in nodes) {
      if (l.index == activeIndex) activeP = p;
    }
    activeP ??= nodes.isEmpty ? null : nodes.first.$2;

    // Attention glow: red on the exposed user, accent on the exit.
    final glowP = (connected || busy) && activeP != null ? activeP : up;
    final glowC = connected
        ? Brand.hsl(152, 60, 45)
        : busy
            ? Brand.hsl(220, 95, 58)
            : Brand.hsl(4, 72, 52);
    if (glowP != null) {
      final r = 72 * iz;
      canvas.drawCircle(
        glowP,
        r,
        Paint()
          ..shader = ui.Gradient.radial(glowP, r, [
            glowC.withValues(alpha: .2),
            glowC.withValues(alpha: .07),
            glowC.withValues(alpha: 0),
          ], [
            0,
            .55,
            1,
          ]),
      );
    }

    // Tunnel line: you -> exit, arched, flowing while the handshake runs.
    if (up != null && activeP != null && conn != MarkState.disconnected) {
      final lift =
          math.min(up!.dy, activeP.dy) - (activeP - up!).distance * .22;
      final line = Path()
        ..moveTo(up!.dx, up!.dy)
        ..quadraticBezierTo(
            (up!.dx + activeP.dx) / 2, lift, activeP.dx, activeP.dy);
      final dim = conn == MarkState.disconnecting ? .3 : 1.0;
      if (connected) {
        canvas.drawPath(
          line,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = 5 * iz
            ..color = Brand.hsl(152, 60, 45, .22 * dim),
        );
      }
      final core = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 1.6 * iz
        ..color = acc.withValues(alpha: dim);
      if (connecting) {
        // One dash period (6+5 px) glides by every 1.15s, like mv-dash.
        final ph = -((t * 4) % 1.15) / 1.15 * 11 * iz;
        _drawDashed(canvas, line, core, 6 * iz, 5 * iz, phase: ph);
      } else {
        canvas.drawPath(line, core);
      }
    }

    // Blips share the loop: pins on a 2.6s beat, the user halo on 3.2s.
    double blip(double period) {
      final ph = (t * 4 / period) % 1;
      return .25 + .6 * (.5 - .5 * math.cos(ph * 2 * math.pi));
    }

    if (up != null) {
      canvas.drawCircle(up!, 10 * iz,
          Paint()..color = Brand.hsl(220, 95, 58, .16 * blip(3.2) / .85));
      canvas.drawCircle(up!, 3.4 * iz, Paint()..color = Colors.white);
      canvas.drawCircle(
        up!,
        3.4 * iz,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4 * iz
          ..color = Brand.hsl(220, 95, 58),
      );
      _label(canvas, '${userCity ?? 'you'} · you', up!, 19 * iz, iz);
    }

    for (final (l, p) in nodes) {
      final on = activeIndex != null ? l.index == activeIndex : p == activeP;
      final tick = Paint()
        ..strokeWidth = 1.1 * iz
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: on ? .6 : .35);
      for (final (a, b) in [
        (Offset(-8.5, 0), Offset(-4.5, 0)),
        (Offset(4.5, 0), Offset(8.5, 0)),
        (Offset(0, -8.5), Offset(0, -4.5)),
        (Offset(0, 4.5), Offset(0, 8.5)),
      ]) {
        canvas.drawLine(p + a * iz, p + b * iz, tick);
      }
      if (on) {
        canvas.drawCircle(
          p,
          7 * iz,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2 * iz
            ..color = acc.withValues(alpha: blip(2.6)),
        );
      }
      canvas.drawCircle(
          p,
          2.6 * iz,
          Paint()
            ..color = on ? acc : Colors.white.withValues(alpha: .65));
      if (!on && z > 11) _label(canvas, l.city, p, 19 * iz, iz);
    }

    // Floating tag above the active pin; tapping it connects.
    if (activeP != null && tagCity.isNotEmpty) {
      final tp = TextPainter(
        text: TextSpan(children: [
          TextSpan(text: tagCity, style: Hip.sans(650, 11, color: Colors.white)),
          if (tagAction.isNotEmpty)
            TextSpan(
                text: tagAction,
                style: Hip.sans(650, 11, color: Brand.hsl(220, 95, 70))),
        ]),
        textDirection: TextDirection.ltr,
      )..layout();
      final tagW = tp.width + 40;
      canvas.save();
      canvas.translate(activeP.dx, activeP.dy);
      canvas.scale(iz);
      final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(-tagW / 2, -42, tagW, 27), const Radius.circular(13.5));
      canvas.drawRRect(rect, Paint()..color = Brand.hsl(222, 20, 8, .85));
      canvas.drawRRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.white.withValues(alpha: .16),
      );
      canvas.drawCircle(Offset(-tagW / 2 + 14, -28.5), 2.8, Paint()..color = acc);
      tp.paint(canvas, Offset(-tagW / 2 + 22, -28.5 - tp.height / 2));
      canvas.restore();
    }

    canvas.restore();
  }

  /// City label with the dark outline the prototype gets from paint-order.
  void _label(Canvas canvas, String text, Offset at, double dy, double iz) {
    final style = Hip.sans(650, 9, letterSpacing: .13);
    final stroke = TextPainter(
      text: TextSpan(
        text: text,
        style: style.copyWith(
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..strokeJoin = StrokeJoin.round
            ..color = Hip.dark,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final fill = TextPainter(
      text: TextSpan(
          text: text,
          style: style.copyWith(color: Colors.white.withValues(alpha: .72))),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.save();
    canvas.translate(at.dx, at.dy + dy);
    canvas.scale(iz);
    stroke.paint(canvas, Offset(-stroke.width / 2, -stroke.height / 2));
    fill.paint(canvas, Offset(-fill.width / 2, -fill.height / 2));
    canvas.restore();
  }

  void _drawDashed(Canvas canvas, Path path, Paint paint, double on, double off,
      {double phase = 0}) {
    for (final metric in path.computeMetrics()) {
      var d = phase % (on + off);
      if (d > 0) d -= on + off;
      while (d < metric.length) {
        final start = math.max(0.0, d);
        final end = math.min(metric.length, d + on);
        if (end > start) {
          canvas.drawPath(metric.extractPath(start, end), paint);
        }
        d += on + off;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MapPainter old) => true;
}

/// "Tap a country to vote" pill, shown until the first vote is cast.
class _VoteHint extends StatelessWidget {
  const _VoteHint();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 1150),
        curve: const Interval(.48, 1, curve: Cubic(.22, .61, .36, 1)),
        builder: (context, v, child) => Opacity(
          opacity: v,
          child: Transform.translate(offset: Offset(0, -6 * (1 - v)), child: child),
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 7, 12, 7),
          decoration: BoxDecoration(
            color: Brand.hsl(222, 20, 8, .78),
            border: Border.all(color: Colors.white.withValues(alpha: .1)),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.public, size: 13, color: Brand.hsl(220, 95, 68)),
            const SizedBox(width: 7),
            Text('Tap a country to vote for the next location',
                style: Hip.sans(600, 11,
                    color: Colors.white.withValues(alpha: .72))),
          ]),
        ),
      ),
    );
  }
}

/// The vote card for a country without a node: count plus a toggle button.
/// The count renders only when the server total is known; a local vote is
/// stored and queued regardless (see VoteService).
class _VoteCard extends StatelessWidget {
  final String countryId;
  final String countryName;
  final VoteService votes;
  final VoidCallback onClose;
  const _VoteCard({
    super.key,
    required this.countryId,
    required this.countryName,
    required this.votes,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final voted = votes.hasVoted(countryId);
    final count = votes.displayCount(countryId);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 450),
      curve: const Cubic(.26, .9, .32, 1.18),
      builder: (context, v, child) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, 14 * (1 - v)),
          child: Transform.scale(scale: .95 + .05 * v, child: child),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
        decoration: BoxDecoration(
          color: Brand.hsl(222, 20, 8, .92),
          border: Border.all(color: Colors.white.withValues(alpha: .12)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(countryName,
                  style: Hip.sans(650, 14, color: Colors.white)),
            ),
            GestureDetector(
              onTap: onClose,
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.white.withValues(alpha: .06),
                ),
                child: Icon(Icons.close,
                    size: 14, color: Colors.white.withValues(alpha: .45)),
              ),
            ),
          ]),
          const SizedBox(height: 3),
          Text(
              'No exit node here yet. Vote to tell us where to build next. '
              'Votes are anonymous, no account needed.',
              style: Hip.sans(450, 12,
                  color: Colors.white.withValues(alpha: .55), height: 1.45)),
          const SizedBox(height: 11),
          Row(children: [
            if (count != null)
              Text.rich(
                TextSpan(children: [
                  TextSpan(
                      text: '$count',
                      style: Hip.mono(700, 12.5, color: Colors.white)),
                  TextSpan(
                      text: ' votes',
                      style: Hip.sans(500, 12.5,
                          color: Colors.white.withValues(alpha: .65))),
                ]),
              ),
            const Spacer(),
            GestureDetector(
              onTap: () {
                if (voted) {
                  Haptics.selection();
                } else {
                  Haptics.success();
                }
                votes.toggle(countryId);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding:
                    const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                decoration: BoxDecoration(
                  color: voted
                      ? Brand.hsl(152, 60, 40, .22)
                      : Brand.hsl(220, 95, 55),
                  border: voted
                      ? Border.all(color: Brand.hsl(152, 60, 45, .4))
                      : null,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(voted ? 'Voted' : 'Vote for $countryName',
                      style: Hip.sans(650, 12.5,
                          color:
                              voted ? Brand.hsl(152, 60, 62) : Colors.white)),
                  if (voted) ...[
                    const SizedBox(width: 5),
                    Icon(Icons.check, size: 13, color: Brand.hsl(152, 60, 62)),
                  ],
                ]),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
