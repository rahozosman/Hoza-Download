# Hoza Download backend

Everything the app needs from a server, in one small FastAPI service. **All of
it is optional** — the app runs fully on its built-in defaults until
`AppInfo.remoteConfigUrl` points at a config.

| Endpoint | Purpose | Used by |
| --- | --- | --- |
| `GET /ping` → `204` | Real-network check (also detects captive portals) | `NetworkStatusController` when `pingUrl` is set |
| `GET /config` | Remote config JSON with `ETag` | `RemoteConfigController` on launch, ≤ once per 24 h |
| `POST /events` | Anonymous outcome counters | `FailureReporter` when `telemetryUrl` is set |
| `GET /events/summary` | Counts since start — "is Instagram broken?" | you |
| `POST /resolve` | yt-dlp fallback resolver | reserved for `resolveUrl` (client hook not wired yet) |

## The cheapest possible deployment

You do not need the Python service to get the biggest win (the kill switches
and extractor patterns). The app only needs **one static HTTPS JSON file**:

1. Copy `config/extractors.json` somewhere public — a GitHub repo (raw URL),
   Cloudflare Pages, Netlify, S3, your own nginx.
2. Set `AppInfo.remoteConfigUrl` in `lib/core/constants/app_info.dart` to that
   URL and ship the app.
3. When TikTok or Instagram changes its page, edit the JSON. Phones pick it up
   on their next launch (24 h cache, `ETag` revalidation).

`pingUrl` / `telemetryUrl` / `resolveUrl` stay `null` in that setup.

## Running the full service

```bash
cd server
python -m venv .venv && . .venv/bin/activate      # Windows: .venv\Scripts\activate
pip install -r requirements.txt
uvicorn app:app --host 0.0.0.0 --port 8080
```

or

```bash
docker build -t hoza-backend .
docker run -p 8080:8080 -v $(pwd)/config:/srv/config hoza-backend
```

Put it behind HTTPS (Caddy, nginx + certbot, Cloudflare Tunnel). The app
refuses any `http://` address in the config, on purpose.

Then in `config/extractors.json` set:

```json
"pingUrl":      "https://api.yourdomain.com/ping",
"telemetryUrl": "https://api.yourdomain.com/events"
```

## Config file reference

```jsonc
{
  "version": 3,                       // bump on every edit; shown in the app log
  "platforms": {
    "facebook": { "enabled": false,   // kill switch — link is refused instantly
                  "message": "Facebook downloads are paused while we fix them." }
  },
  "extractors": {                     // per platform; omit a platform to keep the built-in list
    "instagram": [ { "pattern": "...regex with one capture group...", "label": "Original" } ]
  },
  "pingUrl": "https://…/ping",        // must answer 204 with no body
  "telemetryUrl": "https://…/events",
  "resolveUrl": null,
  "minAppVersion": "1.0.0",           // app compares against AppInfo.version
  "updateMessage": null
}
```

Rules the app enforces when reading it:

- Only `https` URLs are accepted; anything else is ignored.
- A pattern that does not compile is dropped; an empty list keeps the built-in one.
- A malformed file is ignored entirely and the previous copy kept.
- Platform names: `tiktok`, `instagram`, `facebook`, `youtube`.

## What telemetry contains

One line per event, e.g.

```json
{"event":"refused","platform":"instagram","provider":"Social","reason":"restricted","app":"1.0.0","os":"Android 14","at":"2026-08-26T10:12:03Z"}
```

Never a URL, title, file name, IP-derived location, or device identifier. If
you add fields, keep that promise.

## Security notes

- The config is trusted over HTTPS only; there is no signature. If you host
  it on a domain you do not fully control, add an HMAC field and verify it in
  `RemoteConfigController._applyBody` before adopting the body.
- `/resolve` is rate-limited per IP (`HOZA_RESOLVE_PER_MINUTE`, default 6).
  Put an API key on it before exposing it publicly.

## The extractor watchdog (automatic detection and repair)

`.github/workflows/extractor-watchdog.yml` runs `tool/watchdog/watchdog_test.dart`
once a day and on demand (Actions → *Extractor watchdog* → *Run workflow*).
It needs **Settings → Actions → General → Workflow permissions → Read and
write** once, so it can commit and open issues.

What one run does, per platform, with the app's own resolver code:

1. Resolves the public posts listed in `config/watchdog.json` (`links`).
   At least one must yield a downloadable video.
2. Checks that the patterns in `config/extractors.json` still find that video
   in the page — a post can survive on the Open Graph fallback while the
   patterns quietly rot.
3. If either check fails, tries every pattern in `config/watchdog.json`
   (`candidates` for the platform, then `generic`) against the pages it just
   fetched. A pattern is adopted **only** if the address it finds is fetched
   and actually serves media. Adopted patterns go first, the old ones stay
   behind them as fallbacks, `version` is bumped, and the workflow commits
   `config/extractors.json`. Phones pick it up through the remote config.
4. If nothing works, it opens (or updates) a GitHub issue labelled `watchdog`
   with the report and the pages it read attached to the run, and the run
   fails. The issue is closed automatically once the platform works again.

The report is in the run's summary and the `watchdog-report` artifact.

Maintaining it:

- **Test links go stale** (posts get deleted). Keep two or three public posts
  per platform in `links`; a platform with no working link reads as broken.
- **Teach it new keys**: when a platform is repaired by hand, add the pattern
  to `candidates` too, so the next rename is handled without you.
- **Drill**: run the workflow with `simulate_break` set to a platform. The
  patterns are replaced with a broken one and the repair has to find its way
  back. Nothing is committed in a drill; the would-be config is in the
  artifact as `extractors.simulated.json`.
- Locally: `flutter test tool/watchdog/watchdog_test.dart`
  (add `--dart-define=WATCHDOG_SIMULATE_BREAK=facebook` for a drill, or
  `--dart-define=WATCHDOG_HEAL=false` to report only).

What it cannot do: a platform that moves its media behind a new API call, a
token, or a sign-in is a code change, not a pattern. The issue it opens is
the signal for that.
