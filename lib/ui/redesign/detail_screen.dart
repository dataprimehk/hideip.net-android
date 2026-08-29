import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config_redaction.dart';
import '../../core/location.dart';
import '../../core/ping.dart';
import '../../core/sensitive_clipboard.dart';
import '../../core/sub_info.dart';
import '../../core/user_subscription.dart';
import '../../core/wg_speed_mode.dart';
import '../../state/app_state.dart';
import '../brand.dart';
import '../strings.dart';
import 'hip.dart';
import 'hip_sheet.dart';
import 'shell.dart';

/// The names the user gave their own servers.
///
/// The name the provider sent stays on the profile and is still shown under
/// the field, so renaming never loses it. Keyed by `Location.id`
/// (`host:port`), which survives a subscription refresh reordering the list.
class ServerNames extends ChangeNotifier {
  ServerNames._();

  static final ServerNames instance = ServerNames._();

  static const _key = 'server_names_v1';

  Map<String, String> _names = const {};
  bool _loaded = false;

  /// Reads the stored names once. Safe to call from every build path; the
  /// second call and later are free.
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await _prefs();
    final raw = prefs?.getString(_key);
    if (raw == null) return;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return;
    _names = {
      for (final e in decoded.entries)
        if (e.key is String && e.value is String)
          e.key as String: e.value as String,
    };
    notifyListeners();
  }

  /// The label to show for [location]: the user's name if there is one, the
  /// parsed one otherwise.
  String nameFor(Location location) => _names[location.id] ?? location.city;

  Future<void> rename(Location location, String name) async {
    final trimmed = name.trim();
    final next = Map<String, String>.from(_names);
    if (trimmed.isEmpty || trimmed == location.city) {
      next.remove(location.id);
    } else {
      next[location.id] = trimmed;
    }
    await _write(next);
  }

  /// Drops the name of a server that is no longer on the device.
  Future<void> forget(Location location) async {
    if (!_names.containsKey(location.id)) return;
    await _write(Map<String, String>.from(_names)..remove(location.id));
  }

  Future<void> _write(Map<String, String> next) async {
    _names = next;
    notifyListeners();
    final prefs = await _prefs();
    if (prefs == null) return;
    if (next.isEmpty) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, jsonEncode(next));
    }
  }

  /// Preferences, or null where the platform has no store for them. A name
  /// the device cannot remember is still the name on screen for this run,
  /// which is better than a screen that will not open.
  Future<SharedPreferences?> _prefs() async {
    try {
      return await SharedPreferences.getInstance();
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Test hook: forget everything held in memory so one test's rename is not
  /// the next test's starting state.
  @visibleForTesting
  void resetForTesting() {
    _names = const {};
    _loaded = false;
  }
}

/// Where a subscription refresh stands right now.
enum RefreshState { idle, busy, done, error }

/// One entry of the protocol list in Advanced view.
typedef ProtoChoice = ({String key, String name, String sub});

/// The protocol list, ported from `PROTOCOLS` in
/// `design/app-1_1_0/core.jsx`. Auto is the recommendation and the default.
const List<ProtoChoice> kProtoChoices = [
  (key: 'auto', name: S.tAuto, sub: S.gProtoAutoSub),
  (key: 'vless', name: S.tVless, sub: S.gProtoVlessSub),
  (key: 'reality', name: S.gProtoReality, sub: S.gProtoRealitySub),
  (key: 'vmess', name: S.gProtoVmess, sub: S.gProtoVmessSub),
  (key: 'trojan', name: S.gProtoTrojan, sub: S.gProtoTrojanSub),
  (key: 'ss', name: S.gProtoSs, sub: S.gProtoSsSub),
  (key: 'hy2', name: S.gProtoHy2, sub: S.gProtoHy2Sub),
];

/// Manage one server: rename it, see where it came from, refresh the
/// subscription it belongs to, remove it. Advanced view adds the protocol
/// list and the raw sing-box outbound.
///
/// Managed (hideip.net) servers show the header card only: there is nothing
/// on them for the user to rename, refresh or remove.
class DetailScreen extends StatefulWidget {
  final AppState state;
  final HipNav nav;
  final Location location;
  const DetailScreen({
    super.key,
    required this.state,
    required this.nav,
    required this.location,
  });

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  final ServerNames _names = ServerNames.instance;

  bool _testing = false;
  int? _ms;
  RefreshState _refresh = RefreshState.idle;
  int _refreshed = 0;
  String _proto = 'auto';

  @override
  void initState() {
    super.initState();
    final ping = widget.state.pingFor(widget.location.profile);
    if (ping is PingOk) _ms = ping.ms;
    _names.addListener(_changed);
    _names.ensureLoaded();
  }

  @override
  void dispose() {
    _names.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _test() async {
    setState(() => _testing = true);
    final p = widget.location.profile;
    final r = await Ping.measure(p.server, p.port,
        timeout: const Duration(seconds: 4));
    if (!mounted) return;
    setState(() {
      _testing = false;
      _ms = r is PingOk ? r.ms : null;
    });
  }

  Future<void> _rename(String name) => _names.rename(widget.location, name);

  /// Pulls the subscription this server came from. A failure keeps every
  /// server already on the device: nothing is dropped because a provider was
  /// briefly unreachable.
  Future<void> _refreshSubscription(String url) async {
    if (_refresh == RefreshState.busy) return;
    setState(() => _refresh = RefreshState.busy);
    final result = await UserSubscriptionService().fetch(url);
    if (!mounted) return;
    if (result == null) {
      setState(() => _refresh = RefreshState.error);
      return;
    }
    if (result.info != null) await SubInfoStore.put(url, result.info!);
    await widget.state.addProfiles(result.profiles);
    if (!mounted) return;
    // The provider may have retired this exact server. Its manage screen has
    // nothing left to manage, so the list is where the user belongs.
    final gone =
        widget.state.locations.every((l) => l.id != widget.location.id);
    if (gone) {
      widget.nav.go(HipScreen.locations);
      return;
    }
    setState(() {
      _refresh = RefreshState.done;
      _refreshed = result.profiles.length;
    });
  }

  Future<void> _copyConfig() async {
    const encoder = JsonEncoder.withIndent('  ');
    await Clipboard.setData(ClipboardData(
        text: encoder.convert(redactConfig(widget.location.profile.outbound))));
    widget.state.showToast(S.gToastRedacted);
  }

  Future<void> _copyFullConfig() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text(S.gCopyFullTitle),
            content: const Text(S.gCopyFullBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text(S.aCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text(S.gCopyFullAction),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    const encoder = JsonEncoder.withIndent('  ');
    try {
      await SensitiveClipboard.setText(
          encoder.convert(widget.location.profile.outbound));
      widget.state.showToast(S.gToastFull);
    } on PlatformException {
      widget.state.showToast(S.gToastFullFailed);
    }
  }

  Future<void> _confirmRemove(String name) async {
    final go = await showHipSheet<bool>(
      context,
      children: removeServerSheet(
        name: name,
        onCancel: () => Navigator.of(context).pop(false),
        onRemove: () => Navigator.of(context).pop(true),
      ),
    );
    if (go != true || !mounted) return;
    await _remove(name);
  }

  Future<void> _remove(String name) async {
    final state = widget.state;
    // Resolve the position by identity: a refresh may have reordered the list
    // since this screen was opened.
    final match =
        state.locations.where((l) => l.id == widget.location.id).toList();
    final index = match.isEmpty ? widget.location.index : match.first.index;
    final toAuto = removalFallsBackToAuto(
      autoSelect: state.prefs.autoSelect,
      selectedIndex: state.selectedIndex,
      removedIndex: index,
    );
    await state.remove(index);
    await _names.forget(widget.location);
    // The server that was selected is gone; Auto is the honest answer, not
    // whichever server happens to sit first in the list now.
    if (toAuto) await state.selectLocation(null);
    state.showToast(S.gRemoved(name));
    widget.nav.go(HipScreen.locations);
  }

  @override
  Widget build(BuildContext context) {
    final loc = widget.location;
    final advanced = widget.state.prefs.advanced;
    final managed = loc.premium;
    final name = managed ? loc.city : _names.nameFor(loc);
    final subUrl = loc.profile.subUrl;
    const encoder = JsonEncoder.withIndent('  ');

    return SafeArea(
      child: Column(children: [
        HipNavHead(title: name, onBack: widget.nav.back),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              _HeaderCard(
                location: loc,
                name: name,
                advanced: advanced,
                testing: _testing,
                ms: _ms,
                onTest: _testing ? null : _test,
              ),
              if (!managed)
                ManageServerSection(
                  name: name,
                  rawName: loc.rawName,
                  fromSubscription: subUrl != null,
                  refresh: _refresh,
                  refreshedServers: _refreshed,
                  lastUpdated: subUrl == null
                      ? null
                      : widget.state.subInfoFor(subUrl)?.fetchedAt,
                  onRename: _rename,
                  onRefresh:
                      subUrl == null ? null : () => _refreshSubscription(subUrl),
                ),
              if (advanced) ...[
                const HipSectionLabel(S.gProtocol),
                HipListGroup(children: [
                  for (final p in kProtoChoices)
                    HipListRow(
                      leading: _RadioDot(on: _proto == p.key),
                      title: p.name,
                      titleBadge:
                          p.key == 'auto' ? HipBadge.ok(S.gRecommended) : null,
                      subtitle: p.sub,
                      onTap: () => setState(() => _proto = p.key),
                    ),
                ]),
                const HipSectionLabel(S.gRawConfig),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
                  decoration: BoxDecoration(
                    color: Brand.hsl(220, 15, 10),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Text(encoder.convert(loc.profile.outbound),
                      style: Hip.mono(500, 10.5,
                          color: Brand.hsl(220, 10, 78), height: 1.7)),
                ),
                const SizedBox(height: 10),
                HipCta(S.gCopyConfig,
                    ghost: true,
                    leading: const Icon(Icons.copy_outlined),
                    onTap: _copyConfig),
                const SizedBox(height: 8),
                HipCta(S.gCopyFull,
                    ghost: true,
                    leading: const Icon(Icons.warning_amber_rounded),
                    onTap: _copyFullConfig),
              ],
              if (!managed)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: GestureDetector(
                    onTap: () => _confirmRemove(name),
                    behavior: HitTestBehavior.opaque,
                    child: const Padding(
                      padding: EdgeInsets.all(14),
                      child: Center(child: _DangerLabel(S.gRemove)),
                    ),
                  ),
                ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ]),
    );
  }
}

/// Whether removing the server at [removedIndex] should leave the app on
/// Auto: it should exactly when that server was the one explicitly selected.
/// Falling to whatever sits first in the list instead would silently move the
/// user to a server they never picked.
bool removalFallsBackToAuto({
  required bool autoSelect,
  required int selectedIndex,
  required int removedIndex,
}) =>
    !autoSelect && selectedIndex == removedIndex;

/// The confirmation for removing a server: it names what keeps working, so
/// the decision does not read as more final than it is.
List<Widget> removeServerSheet({
  required String name,
  required VoidCallback onCancel,
  required VoidCallback onRemove,
}) =>
    [
      HipSheetTitle(S.g5Title(name)),
      const HipSheetBody(S.g5Body),
      HipSheetActions(children: [
        HipCta(S.aRemove, danger: true, ghost: true, onTap: onRemove),
        HipCta(S.aCancel, quiet: true, onTap: onCancel),
      ]),
    ];

/// The `This server` section: rename, where the server came from, and (for a
/// subscription) a manual refresh with its four answers.
///
/// Takes plain values rather than the app state, so it renders the same in
/// every entitlement and can be exercised on its own.
class ManageServerSection extends StatefulWidget {
  /// The name shown for this server: the user's, or the parsed one.
  final String name;

  /// What the provider actually called it. Stays visible under the field.
  final String rawName;

  final bool fromSubscription;
  final RefreshState refresh;

  /// How many servers the last successful refresh returned.
  final int refreshedServers;

  /// When the subscription was last read, for the idle line.
  final DateTime? lastUpdated;

  final void Function(String name) onRename;
  final VoidCallback? onRefresh;

  const ManageServerSection({
    super.key,
    required this.name,
    required this.rawName,
    required this.fromSubscription,
    this.refresh = RefreshState.idle,
    this.refreshedServers = 0,
    this.lastUpdated,
    required this.onRename,
    this.onRefresh,
  });

  @override
  State<ManageServerSection> createState() => _ManageServerSectionState();
}

class _ManageServerSectionState extends State<ManageServerSection> {
  final TextEditingController _field = TextEditingController();
  bool _renaming = false;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _start() {
    _field.text = widget.name;
    _field.selection =
        TextSelection(baseOffset: 0, extentOffset: _field.text.length);
    setState(() => _renaming = true);
  }

  void _save() {
    setState(() => _renaming = false);
    widget.onRename(_field.text.trim().isEmpty ? widget.name : _field.text);
  }

  String get _subscriptionLine => switch (widget.refresh) {
        RefreshState.busy => S.gRefreshBusy,
        RefreshState.done => S.gRefreshDone(widget.refreshedServers),
        RefreshState.error => S.gRefreshError,
        RefreshState.idle => S.gRefreshIdle(_ago(widget.lastUpdated)),
      };

  /// How long ago the subscription was read, in words. Never read on this
  /// device reads as just now rather than as a number nobody measured.
  static String _ago(DateTime? at) {
    if (at == null) return S.gAgoJustNow;
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return S.gAgoJustNow;
    if (d.inMinutes < 60) return S.gAgoMinutes(d.inMinutes);
    if (d.inHours < 24) return S.gAgoHours(d.inHours);
    return S.gAgoDays(d.inDays);
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const HipSectionLabel(S.gThisServer),
      HipListGroup(children: [
        if (_renaming)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _field,
                  autofocus: true,
                  autocorrect: false,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _save(),
                  style: Hip.sans(650, 15.5, color: Hip.ink),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.only(top: 2, bottom: 5),
                    border: UnderlineInputBorder(
                        borderSide: BorderSide(color: Hip.blue, width: 1.5)),
                    enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Hip.blue, width: 1.5)),
                    focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Hip.blue, width: 1.5)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _MiniButton(S.gSave, onTap: _save),
            ]),
          )
        else
          HipListRow(
            title: S.gName,
            subtitle: S.gNameSub(widget.name, widget.rawName),
            trailing: Icon(Icons.edit_outlined, size: 16, color: Hip.muted2),
            onTap: _start,
          ),
        if (widget.fromSubscription)
          HipListRow(
            title: S.gSubscription,
            subtitle: _subscriptionLine,
            trailing: widget.refresh == RefreshState.busy
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Hip.muted2),
                  )
                : Icon(Icons.refresh, size: 16, color: Hip.muted2),
            onTap: widget.refresh == RefreshState.busy ? null : widget.onRefresh,
          )
        else
          const HipListRow(title: S.gSource, subtitle: S.gSourceSub),
      ]),
    ]);
  }
}

/// The server card at the top: flag, place, what runs it, and a ping badge
/// that measures again on tap.
class _HeaderCard extends StatelessWidget {
  final Location location;
  final String name;
  final bool advanced;
  final bool testing;
  final int? ms;
  final VoidCallback? onTest;
  const _HeaderCard({
    required this.location,
    required this.name,
    required this.advanced,
    required this.testing,
    required this.ms,
    required this.onTest,
  });

  @override
  Widget build(BuildContext context) {
    final proto = protoShort(location) ?? location.profile.protocol;
    final line = advanced
        ? S.tunnelChain(location.protoLabel, location.host)
        : location.premium
            ? S.gManagedBy(proto)
            : S.gFromProvider(proto, location.provider ?? S.gYourProvider);

    return HipCard(
      child: Row(children: [
        HipFlag(cc: location.cc),
        const SizedBox(width: 14),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$name, ${location.country}',
                overflow: TextOverflow.ellipsis,
                style:
                    Hip.sans(650, 15.5, color: Hip.ink, letterSpacing: -.15)),
            const SizedBox(height: 2),
            Text(line,
                overflow: TextOverflow.ellipsis,
                style: advanced
                    ? Hip.mono(600, 12, color: Hip.muted)
                    : Hip.sans(400, Hip.calloutSize, color: Hip.muted)),
          ]),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: onTest,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            height: 44,
            child: Center(
              child: HipBadge.blue(testing
                  ? S.gTesting
                  : ms != null
                      ? S.gMs(ms!)
                      : S.gTest),
            ),
          ),
        ),
      ]),
    );
  }
}

/// The radio in front of a protocol choice (app.css `.seg-check`).
class _RadioDot extends StatelessWidget {
  final bool on;
  const _RadioDot({required this.on});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? Hip.blue : null,
        border: Border.all(color: on ? Hip.blue : Hip.line, width: 1.8),
      ),
      child:
          on ? const Icon(Icons.check, size: 13, color: Colors.white) : null,
    );
  }
}

/// Small inline button beside a field (app.css `.minibtn`).
class _MiniButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _MiniButton(this.label, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 44,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          color: Hip.line2,
          border: Border.all(color: Hip.line, width: 1.5),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Text(label, style: Hip.sans(650, 12.5, color: Hip.ink)),
      ),
    );
  }
}

class _DangerLabel extends StatelessWidget {
  final String text;
  const _DangerLabel(this.text);

  @override
  Widget build(BuildContext context) =>
      Text(text, style: Hip.sans(600, 14.5, color: Hip.danger));
}
