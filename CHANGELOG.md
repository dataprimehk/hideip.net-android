# Changelog

Notable changes to the hideip.net app. The same history is published at
https://hideip.net/apps/changelog.

## 1.1.0 (2026-09-02)

### Added
- Speed mode: WireGuard on hideip.net locations for Premium subscribers, with
  automatic fallback to stealth protocols on networks where WireGuard is
  blocked.
- WireGuard imports: paste a config, open a .conf file, or scan it as a QR
  code. Bringing your own WireGuard server is free.
- QR scanning built into the import flow, with a plain-language camera note
  before the system permission prompt.
- A world map of locations with voting for the next hideip.net location.
- Location search on the home screen.
- Linked devices: one subscription shared across phone, browser and desktop,
  paired with a QR code and no account.
- Optional notifications on two separate channels: connection drops and voting
  updates.
- The home screen names the network and city beside the public IP, through a
  lookup on hideip.net that stores nothing.
- hideip.net app links open the app directly.

### Changed
- Every screen redesigned: home, locations, import, settings, world map,
  Premium and onboarding, with light, dark and system themes.
- Numbers everywhere in JetBrains Mono, sized for glanceability.
- iOS now requires iOS 14 or later.

### Security
- Profiles migrated to encrypted on-device storage.
- Import parsing hardened: response size ceilings, strict endpoint checks, and
  no third-party geo services.
- The server catalog is signed; a build without the production verification key
  refuses the catalog rather than trusting it.

### Privacy
- Three anonymous one-time counters (first open, first profile, first connect)
  carrying only the event name and the platform, with an off switch in
  Settings. The stores' "no data collected" declarations remain accurate.

## 1.0.0 (2026-08-03)

First public release. VLESS (Reality, xtls-rprx-vision), VMess, Shadowsocks,
Trojan, Hysteria2, TUIC, AnyTLS, ShadowTLS, SOCKS and HTTP(S) imports,
subscription URLs, the sing-box tunnel core, latency measurements, and optional
Premium locations. Android on Google Play (2026-08-03), iOS on the App Store
(2026-08-11).
