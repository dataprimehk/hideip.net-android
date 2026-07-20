# hideip.net

A small, no-account VPN client. It runs a [sing-box](https://github.com/SagerNet/sing-box)
core inside a system tunnel (`VpnService` on Android) and connects to servers
you bring yourself, imported from a share link, a QR code, or a subscription
URL. Android is the primary platform; an iOS port is underway in this repo
(the app builds and runs, the packet tunnel extension is still being wired
to the core).

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
