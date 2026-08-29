# App events API

The app reports three one-shot usage events so hideip.net can see its funnel
(opened, added a server, tunnel came up) as daily totals. The client is
`lib/core/app_telemetry.dart`; this document is the contract the hideip.net
backend implements (`src/app/api/app/events`, table `hideip.app_event_daily`).

## Privacy

Same rules as the voting API, and for the same reason: the store declarations
say "Data Not Collected" and this must keep them true.

- The body is the event name and the platform. Nothing else: no device or
  advertising identifier, no app version, no locale, no timestamp.
- Each event is sent at most once per install (a local flag remembers it).
- The server keeps aggregate daily counters only, sets no cookie, and does
  not persist the IP beyond what its in-memory rate limiter needs.
- The user can switch it off in Settings ("Anonymous usage counts"). Off
  means no request is made at all.

## Endpoint

`POST https://hideip.net/api/app/events`

```
{"event": "first_open", "platform": "android"}
```

`event` is one of `first_open`, `first_profile`, `first_connect`.
`platform` is `android` or `ios`.

Responses: `200 {"ok": true}` on success; `400 {"error": "invalid_event"}`;
`429` with `Retry-After` when rate limited; `503` when the database is down.
The client treats anything but 200 as "try again on the next trigger".

## Triggers in the app

| Event           | When                                              |
|-----------------|---------------------------------------------------|
| `first_open`    | first `AppState.init()` after install              |
| `first_profile` | first time the profile list goes from empty to any |
| `first_connect` | first time the tunnel reaches `connected`          |

Trial starts and purchases are not app events: the stores report them to the
provisioning backend, which counts them server-side.
