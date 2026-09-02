# hideip.net

A small, no-account VPN client. It runs a [sing-box](https://github.com/SagerNet/sing-box)
core inside a system tunnel (`VpnService` on Android) and connects to servers
you bring yourself, imported from a share link, a QR code, or a subscription
URL. Both the Android and the iOS app are built from this repo.

There is no sign-up and no telemetry. Profiles live on the device. The point is
to be a clean, auditable front end for a proxy core you already trust, not a
managed service.

## Features

- Imports `vless://`, `vmess://`, `ss://`, `trojan://`, `hysteria2://`,
  `tuic://`, `anytls://`, `socks://` and `http(s)://` proxy links, plus
  subscription URLs that return a list of those.
- VLESS over Reality with `xtls-rprx-vision`, Shadowsocks, Trojan, VMess and the
  rest, all handled by the sing-box core.
- QR import that works on devices without Google Play Services (uses ZXing
  directly, so it decodes on GrapheneOS and other de-Googled ROMs too).
- A foreground tunnel with an ongoing notification, a Disconnect action, and
  live up/down traffic counters.
- Server latency check before you connect.
- Public-IP readout so you can confirm the tunnel actually changed your exit IP.
- A world map of exit locations. Tapping a country that has no node yet casts
  an anonymous vote (just the country code, no identifiers) for where to build
  next; the contract is in [docs/voting-api.md](docs/voting-api.md).

## Download

- **Google Play**: <https://play.google.com/store/apps/details?id=net.hideip.vpn>
- **App Store**: <https://apps.apple.com/app/id6793134083>
- **GitHub Releases**: <https://github.com/dataprimehk/hideip.net-app/releases>

Every tagged release carries two APKs. Take the `arm64-v8a` one on any phone
from the last several years; `armeabi-v7a` is only for older 32-bit devices.

### Verify what you downloaded

Each release also ships `SHA256SUMS.txt`. Put it next to the APK and run:

```sh
sha256sum --ignore-missing -c SHA256SUMS.txt
```

On macOS the command is `shasum -a 256 --ignore-missing -c SHA256SUMS.txt`.

The GitHub APKs are signed with the same release key on every release, so a new
build installs straight over the previous one and your profiles stay put. You
can check the signing certificate yourself:

```sh
apksigner verify --print-certs hideip.net-1.1.0-arm64-v8a.apk
```

It must print:

```
Signer #1 certificate DN: CN=Dataprime LTD, O=Dataprime LTD, L=Hong Kong, C=HK
Signer #1 certificate SHA-256 digest: 8980ca20cb32bd32e90cbb7bd66bfd42da291dd724386a593626192969ac3ae8
```

Google Play ships its own copy of the app, re-signed by Play App Signing, so a
Play install and a GitHub install carry different signatures and will not
update over one another. Pick one source and stay with it.

### Obtainium

If you use [Obtainium](https://github.com/ImranR98/Obtainium), add

```
https://github.com/dataprimehk/hideip.net-app
```

as a source. It tracks the GitHub releases and offers each new version as soon
as it is tagged.

## Build

You need the Flutter SDK (Dart 3.12+) and the Android SDK.

```sh
flutter pub get
flutter run            # debug, on a connected device
flutter build apk      # release APK
flutter build appbundle
```

For iOS you also need a full Xcode installation. The sing-box core framework
is a build artifact, not committed; build it once with
`scripts/build-libbox-ios.sh` (requires Go 1.23+), then `flutter build ios`.

The launcher icons are generated from `assets/icon/` with:

```sh
dart run flutter_launcher_icons
```

### Project layout

- `lib/core/` parsing, sing-box config generation, profile storage, voting,
  IP and ping helpers.
- `lib/ui/redesign/` the screens (home with the world map, locations, import
  and QR scan, onboarding, settings) and the shared widget kit.
- `lib/vpn_controller.dart` the Dart side of the `MethodChannel`.
- `android/.../HideipVpnService.kt` the `VpnService` and foreground notification.
- `android/.../MainActivity.kt` the native bridge: VPN consent and the
  Android 13+ notification permission.

## Permissions

| Permission | Why |
| --- | --- |
| `INTERNET`, `ACCESS_NETWORK_STATE` | network access |
| `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_SPECIAL_USE` | keep the tunnel alive |
| `POST_NOTIFICATIONS` | the ongoing connection notification (optional; declining it still lets the tunnel run) |
| `CAMERA` | scanning a server QR code (only used on the scan screen) |

## License

GPLv3. See [LICENSE](LICENSE). sing-box is licensed separately under GPLv3 by
its authors.
