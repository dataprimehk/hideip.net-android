import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_version.dart';
import '../../core/haptics.dart';
import '../../core/location.dart';
import '../../core/ping.dart';
import '../../core/proxy_profile.dart';
import '../../core/safe_http.dart';
import '../../core/share_link_parser.dart';
import '../../core/sub_info.dart';
import '../../core/subscription.dart';
import '../../state/app_state.dart';
import '../brand.dart';
import '../qr_scan_screen.dart';
import 'hip.dart';
import 'shell.dart';

enum _Phase { input, parsing, result }

/// The universal importer: paste anything a provider sends (a share link,
/// a subscription URL, a base64 blob) and it becomes a clean, named location.
class ImportScreen extends StatefulWidget {
  final AppState state;
  final HipNav nav;

  /// The screen a back gesture from the input phase returns to; the shell
  /// remembers where the importer was opened from.
  final HipScreen exitTo;

  /// Text to prefill the input with, e.g. from a `hideip://` deep link. The
  /// screen still shows the detected preview and waits for the user to tap
  /// Import; it never auto-imports.
  final String? initialText;
  const ImportScreen({
    super.key,
    required this.state,
    required this.nav,
    this.exitTo = HipScreen.home,
    this.initialText,
  });

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final _text = TextEditingController();
  _Phase _phase = _Phase.input;
  bool _tech = false;
  String? _error;

  // Parse progress: which of [_steps] are done / active.
  List<String> _steps = const [];
  int _stepDone = 0;

  // Parse output, waiting for the user to commit.
  List<ProxyProfile> _pending = const [];
  Location? _preview;
  int? _previewPingMs;
  bool _isSubscription = false;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() => _error = null));
    // A deep link (or any caller) can hand us text to prefill. We surface the
    // detection preview but never auto-run the import: the user still taps
    // Import so they see exactly what a link is about to add.
    if (widget.initialText != null && widget.initialText!.isNotEmpty) {
      _text.text = widget.initialText!;
    }
  }

  @override
  void dispose() {
    widget.nav.releaseBack(_back);
    _text.dispose();
    super.dispose();
  }

  /// System back mirrors the header arrow: result/parsing fall back to the
  /// input phase first, input leaves the screen. The claim is held only while
  /// there is an internal step to walk, so the shell knows a back gesture from
  /// the input phase leaves the screen (and can animate towards [ImportScreen.exitTo]).
  void _syncBackClaim() {
    if (_phase == _Phase.input) {
      widget.nav.releaseBack(_back);
    } else {
      widget.nav.claimBack(_back);
    }
  }

  // --- input detection -------------------------------------------------------

  static (String, bool)? _detect(String input) {
    final t = input.trim();
    if (t.isEmpty) return null;
    final schemes = {
      'vless': 'VLESS link detected',
      'vmess': 'VMess link detected',
      'ss': 'Shadowsocks link detected',
      'trojan': 'Trojan link detected',
      'hysteria2': 'Hysteria2 link detected',
      'hy2': 'Hysteria2 link detected',
      'tuic': 'TUIC link detected',
      'anytls': 'AnyTLS link detected',
      'socks': 'SOCKS link detected',
      'socks5': 'SOCKS link detected',
    };
    final m = RegExp(r'^([a-z0-9]+)://', caseSensitive: false).firstMatch(t);
    if (m != null) {
      final scheme = m.group(1)!.toLowerCase();
      if (schemes.containsKey(scheme)) return (schemes[scheme]!, false);
      if (scheme == 'http' || scheme == 'https') {
        return ('Subscription link detected', true);
      }
    }
    // Multi-line or base64 blobs are treated as subscription bodies.
    if (t.contains('\n') || RegExp(r'^[A-Za-z0-9+/=_\-]{40,}$').hasMatch(t)) {
      return ('Subscription content detected', true);
    }
    return null;
  }

  // --- the import pipeline ----------------------------------------------------

  Future<void> _runImport() async {
    final input = _text.text.trim();
    final det = _detect(input);
    if (det == null) return;
    final (_, isSub) = det;

    setState(() {
      _phase = _Phase.parsing;
      _syncBackClaim();
      _stepDone = 0;
      _error = null;
      _isSubscription = isSub;
      _steps = [
        isSub ? 'Fetching the subscription' : 'Reading the link',
        'Detecting the protocol',
        'Checking the endpoint',
        'Naming it',
      ];
    });

    try {
      // Step 1: obtain profiles.
      List<ProxyProfile> profiles;
      if (isSub && input.startsWith(RegExp(r'https?://', caseSensitive: false))) {
        final res = await SafeHttpFetcher().get(
          Uri.parse(input),
          headers: subscriptionHeaders,
          timeout: const Duration(seconds: 12),
        );
        if (res.statusCode != 200) {
          throw 'The subscription server answered ${res.statusCode}.';
        }
        final parsed = await Subscription.parseAsync(res.body);
        if (parsed.profiles.isEmpty) throw _subError(parsed);
        // Remember the origin so the app can re-pull it on later launches
        // when the provider rotates its servers.
        profiles =
            parsed.profiles.map((p) => p.copyWith(subUrl: input)).toList();
        // Capture any plan metadata the provider sent (data used, expiry,
        // panel link) so the locations screen can show it under this sub.
        final info = SubInfo.fromHeaders(res.headers, fetchedAt: DateTime.now());
        if (info != null) await SubInfoStore.put(input, info);
      } else if (isSub) {
        final parsed = await Subscription.parseAsync(input);
        if (parsed.profiles.isEmpty) throw _subError(parsed);
        profiles = parsed.profiles;
      } else {
        final p = ShareLinkParser.parse(input);
        if (p == null) throw 'That does not look like a server link.';
        profiles = [p];
      }
      await _advance(1);

      // Step 2: protocol identified; rewrite the step label with the truth.
      final first = Location.derive(profiles.first, 0);
      _steps[1] = isSub
          ? 'Found ${profiles.length} server${profiles.length == 1 ? '' : 's'}'
          : 'Detected ${first.protoLabel}';
      await _advance(2);

      // Step 3: reachability probe (informative; failure does not block).
      final ping = await Ping.measure(
          profiles.first.server, profiles.first.port,
          timeout: const Duration(seconds: 3));
      _previewPingMs = ping is PingOk ? ping.ms : null;
      _steps[2] =
          ping is PingOk ? 'Endpoint verified' : 'Endpoint not reachable yet';
      await _advance(3);

      // Step 4: clean name.
      _steps[3] = 'Named it ${first.city}';
      await _advance(4);

      setState(() {
        _pending = profiles;
        _preview = first;
        _phase = _Phase.result;
        _syncBackClaim();
      });
    } catch (e) {
      Haptics.error();
      setState(() {
        _phase = _Phase.input;
        _syncBackClaim();
        _error = e is ProfileParseException ? e.message : e.toString();
      });
    }
  }

  static String _subError(SubscriptionResult r) => r.errors.isNotEmpty
      ? 'Could not read the subscription: ${r.errors.first}'
      : 'The subscription contains no servers.';

  /// Marks step [n] done with a small beat so the progress reads naturally.
  Future<void> _advance(int n) async {
    await Future.delayed(const Duration(milliseconds: 340));
    if (mounted) setState(() => _stepDone = n);
  }

  Future<void> _commit({required bool connect}) async {
    await widget.state.addProfiles(_pending, select: true);
    widget.state.showToast('${_preview!.city} added');
    widget.nav.go(HipScreen.home);
    if (connect) {
      await Future.delayed(const Duration(milliseconds: 250));
      await widget.state.connect();
    }
  }

  // --- quick actions -----------------------------------------------------------

  Future<void> _scanQr() async {
    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );
    if (scanned != null && scanned.isNotEmpty) {
      _text.text = scanned;
    }
  }

  Future<void> _pasteClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final t = data?.text?.trim();
    if (t == null || t.isEmpty) {
      setState(() => _error = 'The clipboard is empty.');
      return;
    }
    _text.text = t;
  }

  void _back() {
    if (_phase != _Phase.input) {
      setState(() {
        _phase = _Phase.input;
        _syncBackClaim();
      });
      return;
    }
    widget.nav.go(widget.exitTo);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(children: [
        HipNavHead(title: 'Add connection', onBack: _back),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: switch (_phase) {
              _Phase.input => _buildInput(),
              _Phase.parsing => _buildParsing(),
              _Phase.result => _buildResult(),
            },
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
              22, 14, 22, MediaQuery.paddingOf(context).bottom + 14),
          child: switch (_phase) {
            _Phase.input => HipCta('Import',
                onTap: _detect(_text.text) == null ? null : _runImport),
            _Phase.parsing => const SizedBox(),
            _Phase.result => Column(mainAxisSize: MainAxisSize.min, children: [
                HipCta('Add & Connect', onTap: () => _commit(connect: true)),
                const SizedBox(height: 8),
                HipCta('Add without connecting',
                    quiet: true, onTap: () => _commit(connect: false)),
              ]),
          },
        ),
      ]),
    );
  }

  Widget _buildInput() {
    final det = _detect(_text.text);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        constraints: const BoxConstraints(minHeight: 118),
        decoration: BoxDecoration(
          color: Hip.card,
          borderRadius: BorderRadius.circular(Hip.radius),
          border: Border.all(
              color: Hip.dm ? Brand.hsl(222, 12, 27) : Brand.hsl(0, 0, 84),
              width: 1.5),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
        child: TextField(
          controller: _text,
          maxLines: 5,
          minLines: 3,
          style: Hip.mono(500, 12.5, color: Hip.ink, height: 1.55),
          decoration: InputDecoration(
            border: InputBorder.none,
            hintText:
                'Paste anything: a vless:// or vmess:// link, a subscription URL, or a config file’s contents.',
            hintStyle: Hip.sans(400, 13.5, color: Hip.muted2, height: 1.5),
          ),
        ),
      ),
      if (_error != null)
        _DetectBox(text: _error!, tone: _Tone.error)
      else if (det != null)
        _DetectBox(text: det.$1, tone: _Tone.ok)
      else if (_text.text.trim().isNotEmpty)
        const _DetectBox(
            text: 'Not recognized yet. Keep typing or paste the full link.',
            tone: _Tone.neutral),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
            child: _QuickAction(
                icon: Icons.qr_code_scanner, label: 'Scan QR code', onTap: _scanQr)),
        const SizedBox(width: 10),
        Expanded(
            child: _QuickAction(
                icon: Icons.content_paste_outlined,
                label: 'Paste from clipboard',
                onTap: _pasteClipboard)),
      ]),
      const HipSubnote(
          'Works with links from any provider: VLESS, VMess, Trojan, Shadowsocks, Hysteria2, TUIC, subscriptions.'),
    ]);
  }

  Widget _buildParsing() {
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(children: [
        for (var i = 0; i < _steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _stepDone > i
                      ? Hip.successSoft
                      : _stepDone == i
                          ? Hip.blueSoft
                          : Hip.line2,
                ),
                child: _stepDone > i
                    ? Icon(Icons.check, size: 14, color: Hip.success)
                    : _stepDone == i
                        ? Padding(
                            padding: const EdgeInsets.all(6),
                            child: CircularProgressIndicator(
                                strokeWidth: 1.8, color: Hip.blue),
                          )
                        : null,
              ),
              const SizedBox(width: 12),
              Text(_steps[i],
                  style: Hip.sans(550, 14,
                      color: _stepDone > i ? Hip.ink : Hip.muted2)),
            ]),
          ),
      ]),
    );
  }

  Widget _buildResult() {
    final loc = _preview!;
    final renamed = loc.city.toLowerCase() != loc.rawName.toLowerCase();
    final o = loc.profile.outbound;
    final tls = o['tls'] is Map ? o['tls'] as Map : const {};
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _DetectBox(
        text: _isSubscription
            ? 'Subscription imported: ${_pending.length} server${_pending.length == 1 ? '' : 's'}'
            : 'Ready to add',
        tone: _Tone.ok,
      ),
      const SizedBox(height: 12),
      HipCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            HipFlag(cc: loc.cc),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${loc.city}, ${loc.country}',
                        style: Hip.sans(650, 15.5,
                            color: Hip.ink, letterSpacing: -.15)),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (loc.provider != null) 'from ${loc.provider}',
                        if (_previewPingMs != null) '$_previewPingMs ms',
                      ].join(' · '),
                      style: Hip.sans(550, 12, color: Hip.muted),
                    ),
                  ]),
            ),
            if (_previewPingMs != null) HipBadge.ok('Verified'),
          ]),
          GestureDetector(
            onTap: () => setState(() => _tech = !_tech),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 2),
              child: Row(children: [
                AnimatedRotation(
                  turns: _tech ? .25 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.chevron_right, size: 14, color: Hip.muted),
                ),
                const SizedBox(width: 6),
                Text('Technical details',
                    style: Hip.sans(600, 12.5, color: Hip.muted)),
              ]),
            ),
          ),
          if (_tech)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              width: double.infinity,
              decoration: BoxDecoration(
                color: Hip.line2,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _kv('protocol', loc.protoLabel),
                  _kv('endpoint', loc.host),
                  if (o['flow'] is String) _kv('flow', o['flow'] as String),
                  if (tls['server_name'] is String)
                    _kv('sni', tls['server_name'] as String),
                  _kv('original name', loc.rawName),
                ],
              ),
            ),
        ]),
      ),
      if (renamed)
        HipSubnote(
            'We renamed “${loc.rawName}” to ${loc.city}. The original is kept in Advanced view.'),
    ]);
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1.5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 104, child: Text(k, style: Hip.mono(500, 11, color: Hip.muted))),
          Expanded(child: Text(v, style: Hip.mono(600, 11, color: Hip.ink))),
        ]),
      );
}

enum _Tone { ok, neutral, error }

class _DetectBox extends StatelessWidget {
  final String text;
  final _Tone tone;
  const _DetectBox({required this.text, required this.tone});

  @override
  Widget build(BuildContext context) {
    final (bg, fg, icon) = switch (tone) {
      _Tone.ok => (Hip.successSoft, Hip.success, Icons.check),
      _Tone.neutral => (Hip.line2, Hip.muted, Icons.visibility_outlined),
      _Tone.error => (
          Hip.danger.withValues(alpha: .08),
          Hip.danger,
          Icons.error_outline
        ),
    };
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        Icon(icon, size: 17, color: fg),
        const SizedBox(width: 9),
        Expanded(
            child: Text(text, style: Hip.sans(600, 13, color: fg, height: 1.3))),
      ]),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QuickAction(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: Hip.card,
          border: Border.all(color: Hip.line, width: 1.5),
          borderRadius: BorderRadius.circular(15),
        ),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 20, color: Hip.blue),
          const SizedBox(height: 8),
          Text(label, style: Hip.sans(600, 13.5, color: Hip.ink)),
        ]),
      ),
    );
  }
}
