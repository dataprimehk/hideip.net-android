/// Every user-facing string in the app, in one place.
///
/// Keys follow the vocabulary in `design/Screen Atlas 1.1.0.html`
/// (`script#screen-graph`, `vocabulary[]`) where that vocabulary has an entry;
/// everything else is named after the Atlas state code it belongs to (B0, B14,
/// E6 and so on).
///
/// This is NOT i18n. It is the single place i18n can start from without
/// walking through twelve files again: when the eleven languages come, this
/// class becomes the interface and the generated `AppLocalizations` its
/// implementation.
///
/// House rules for anything added here:
///  * No new user-facing literal may appear in a `lib/ui/` file. If a screen
///    needs a string, it goes in the section for its group below.
///  * Numbers (IP, port, latency, date) are never concatenated into a constant.
///    They arrive as parameters of a function, so a translation can reorder
///    them.
///  * Prices and billing dates come from the store (`PlanInfo`); `S` only
///    frames them.
///  * No em dash and no en dash anywhere in this file. `·` is the only
///    separator in metadata lines.
///  * A full stop ends an explanation, never a label, a button or a badge.
///
/// Each group F1 to F7 owns one section below and only ever appends to its
/// own. Nobody edits another group's constants.
abstract final class S {
  // ---------------------------------------------------------------------
  // Vocabulary (Atlas `vocabulary[]`). The words the whole product agrees on.
  // ---------------------------------------------------------------------
  static const tSpeed = 'Speed mode';
  static const tFast = 'Fast mode';
  static const tStealth = 'Stealth';
  static const tKill = 'Kill switch';
  static const tAuto = 'Auto';
  static const tAddConn = 'Add connection';
  static const tProtected = 'Protected';
  static const tExposed = 'Exposed';
  static const tConnect = 'Connect';
  static const tConnecting = 'Connecting…';
  static const tDisconnect = 'Disconnect';
  static const tDisconnecting = 'Disconnecting…';
  static const tLocations = 'Locations';
  static const tSettings = 'Settings';
  static const tPremium = 'Premium';
  static const tFreeTrial = 'Free trial';
  static const tWireGuard = 'WireGuard';
  static const tVless = 'VLESS';

  // ---------------------------------------------------------------------
  // Shared actions and labels used by more than one group.
  // ---------------------------------------------------------------------
  static const aContinue = 'Continue';
  static const aNotNow = 'Not now';
  static const aCancel = 'Cancel';
  static const aClose = 'Close';
  static const aTryAgain = 'Try again';
  static const aOpenSettings = 'Open settings';
  static const aSeePlans = 'See plans';
  static const aRemove = 'Remove';
  static const badgeVoted = 'Voted';

  // ---------------------------------------------------------------------
  // F0 · foundation. State, connection flow and everything the shell says.
  // ---------------------------------------------------------------------

  // B0, Connect with no servers yet.
  static const b0Title = 'No connection yet.';
  static const b0Body =
      'A link, a QR code or a WireGuard config sets one up in about a minute.';
  static const b0SeePremium = 'See Premium locations';

  // B13, the one system permission, shown once before the first Connect.
  static const b13Title = 'One system permission';
  static const b13Body =
      'The system asks for permission to add a VPN configuration. That is what '
      'routes this device through the selected server; hideip.net cannot read '
      'what passes through it.';

  // B14, the system VPN permission was declined.
  static const b14Line =
      'The VPN configuration was declined, so connecting is not possible yet.';
  static const b14Action = aOpenSettings;

  // B15, no network at all.
  static const b15Status = 'No connection';
  static const b15Context = 'This device is not online yet.';
  static const b15CtaNote = 'Connecting needs an internet connection.';

  // B16, the handshake is taking its time.
  static const b16Slow =
      'Still handshaking. Filtered networks can take longer.';

  // B6, the connection failed sheet.
  static const b6Title = 'Connection failed';
  static const b6Body =
      'The server did not respond. Networks that filter traffic often block '
      'servers imported from a provider.';
  static const b6BodyByo =
      'hideip.net locations are built to keep working on filtered networks.';
  static const b6Another = 'Choose another location';

  // F5, the subscription already covers five devices.
  static const f5Title = 'Speed mode is set up on 5 devices';
  static const f5Body =
      'A subscription covers five devices. Speed mode can be turned off on one '
      'of them to free a slot. Everything else keeps working; this connection '
      'stays stealth in the meantime.';

  // C4, the notification pre-prompt after the first vote.
  static const c4Title = 'Location updates';
  static const c4Body =
      'hideip.net can notify you when a location you voted for becomes '
      'available. Nothing else is sent.';

  // Connection errors and confirmations the state layer raises.
  static const errNoServer = 'Select a server first.';
  static const errNoPlatform = 'VPN is not yet supported on this platform.';
  static String errConnect(Object detail) => 'Failed to connect: $detail';
  static const toastRestored = 'Purchases restored';
  static const toastNothingToRestore = 'No purchases to restore';
  static const toastNoSubscription = 'No active subscription found';
  static const toastLinkEmpty = 'That link carries nothing we can import';
  static const toastLinkNeedsPremium =
      'Premium is needed to link another device';

  /// The tunnel chip, always visible while connected. Simple view names the
  /// path in words; Advanced view carries the full chain instead.
  static const tunnelSpeed = '$tSpeed · $tWireGuard';
  static const tunnelBlocked = '$tStealth · $tWireGuard blocked here';
  static String tunnelStealth(String proto) => '$tStealth · $proto';
  static String tunnelChain(String proto, String host) => '$proto · $host';

  /// Session duration under an hour, e.g. `4m 07s`.
  static String durMinutes(int minutes, int seconds) =>
      '${minutes}m ${seconds.toString().padLeft(2, '0')}s';

  /// Session duration of an hour or more, e.g. `2h 05m`.
  static String durHours(int hours, int minutes) =>
      '${hours}h ${minutes.toString().padLeft(2, '0')}m';

  /// Auto's subtitle: it names the server it would pick and why.
  static String autoSub(String city, int ms, {bool managed = false}) =>
      'Fastest right now: $city · $ms ms${managed ? ' · hideip.net' : ''}';

  /// A locked row in Simple view: country and the real measured latency.
  static String lockedSub(String country, int ms) => '$country · $ms ms';

  /// Notification channel names and the two things the app may ever send.
  static const notifConnTitle = 'Connection alerts';
  static const notifConnBody = 'Tell you if the VPN drops';
  static const notifVoteTitle = 'Voting updates';
  static const notifVoteBody =
      'When a location you voted for becomes available';

  // ---------------------------------------------------------------------
  // F1 · Home. Statcard, banners, search, session card, empty state.
  // Owned by the Home group; append only.
  // ---------------------------------------------------------------------

  // ---------------------------------------------------------------------
  // F2 · Locations and Manage server.
  // Owned by the Locations group; append only.
  // ---------------------------------------------------------------------

  // ---------------------------------------------------------------------
  // F3 · Import.
  // Owned by the Import group; append only.
  // ---------------------------------------------------------------------

  // ---------------------------------------------------------------------
  // F4 · Settings, Paywall, Premium manage, Trial expired.
  // Owned by the Settings/Premium group; append only.
  // ---------------------------------------------------------------------

  // ---------------------------------------------------------------------
  // F5 · Map and voting.
  // Owned by the Map group; append only.
  // ---------------------------------------------------------------------

  // ---------------------------------------------------------------------
  // F6 · Onboarding v3.
  // Owned by the Onboarding group; append only.
  // ---------------------------------------------------------------------

  // ---------------------------------------------------------------------
  // F7 · Home ASCII engine. No strings beyond the address samples, which
  // live in the engine because they are drawn glyphs, not copy.
  // ---------------------------------------------------------------------
}
