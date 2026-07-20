# Location voting API

The map lets users tap a country that has no exit node yet and vote for where
to build next. The client is fully implemented (`lib/core/votes.dart`); this
document is the contract the hideip.net backend implements to make the counts
live. Until the endpoint exists the app stores votes locally, queues them for
sync, and simply omits the vote counts (it never invents numbers).

## Privacy

Voting is anonymous by design and must stay that way:

- No account, no user identifier, no device identifier. The request body is
  only the country code and the vote direction.
- The server must not store per-voter records; it keeps aggregate counters.
- Standard abuse protection (rate limiting by IP) must not persist the IP
  beyond what the rate limiter itself needs.
- This keeps the app's "Data Not Collected" store declarations truthful.

## Endpoints

Base URL: `https://hideip.net/api/votes`

### GET /api/votes

Returns all non-zero counters.

```
200 OK
{"votes": {"076": 141, "356": 95}}
```

Keys are ISO 3166-1 numeric codes (zero-padded strings, as used by the
world-atlas geometry the map is built from). Values are non-negative integers.
Countries without votes may be omitted. A `Cache-Control: max-age=60` header
is recommended; the client also caches the last answer on disk.

### POST /api/votes

Casts (`"vote": true`) or retracts (`"vote": false`) one vote.

```
POST /api/votes
Content-Type: application/json

{"country": "688", "vote": true}
```

```
200 OK
{"country": "688", "votes": 142}
```

- `country`: ISO 3166-1 numeric code string. Reject anything that is not a
  known code with `400`.
- Retracting below zero clamps to zero.
- On any non-200 answer the client keeps the vote queued and retries later,
  so transient failures need no special handling.

## Client behaviour (already shipped)

- One vote per country per install, toggleable; the voted set persists locally.
- Votes cast while offline (or before the backend exists) are queued and
  drained on the next successful contact.
- Counts shown in the UI are the last server totals plus any queued local
  adjustment; with no server contact ever, no number is shown.
- The locations list renders a top-5 leaderboard derived from the GET totals,
  so the counters double as the "coming next" ranking users see.
