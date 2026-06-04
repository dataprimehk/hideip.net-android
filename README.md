# hideip.net for Android

A small, no-account VPN client for Android. It runs a [sing-box](https://github.com/SagerNet/sing-box)
core inside a `VpnService` tunnel and connects to servers you bring yourself,
imported from a share link, a QR code, or a subscription URL.

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

## Build

You need the Flutter SDK (Dart 3.12+) and the Android SDK.

```sh
flutter pub get
flutter run            # debug, on a connected device
flutter build apk      # release APK
flutter build appbundle
```

The launcher icons are generated from `assets/icon/` with:

```sh
dart run flutter_launcher_icons
```

### Project layout

- `lib/core/` parsing, sing-box config generation, profile storage, IP and
  ping helpers.
- `lib/ui/` the screens (home, servers, import, QR scan) and the theme.
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
