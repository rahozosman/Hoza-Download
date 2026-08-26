# Hoza Download — backend & logic hardening plan

Living checklist. Each phase is independently buildable; `flutter analyze` and a
debug APK build must pass before moving on. Ticks are updated as work lands.

## Phase 1 — Link resolution (app)
- [x] Redirect-first: short links (`vt.tiktok.com`, `tiktok.com/t/`, `fb.watch`,
      `youtu.be`, `instagram.com/share/…`, `l.instagram.com?u=`) are expanded
      with one body-less request before a provider is chosen; tracking params
      (`utm_*`, `igsh`, `fbclid`, …) are stripped. `link_canonicalizer.dart`
- [x] Resolution cache, 10 min, keyed by canonical URL. Re-sharing the same
      link opens instantly. Bypassed by the sheet's "Try again". `source_registry.dart`
- [x] Lookup cancellation: closing the sheet stops the provider chain.
- [x] Media probes from the social provider require a media content type
      (`expectMedia: true`) — an HTML error page with status 200 no longer passes.
- [x] Expiry-aware resume: `x-expires` / `oe` / `expire` / `Expires` are parsed
      from the media URL; a queued download whose address has expired is
      re-resolved *before* the request instead of after a 403. `url_expiry.dart`
- [x] Retry policy by error class: 429 → wait 30 s and retry; 5xx → 3 retries
      with 5/15/45 s back-off; 401/403 → re-read the link; 404/410 → stop, say
      the file was removed. `download_engine.dart`, `downloads_provider.dart`

## Phase 2 — Network truthfulness
- [x] Offline verdicts are verified (DNS) and re-checked; Wi-Fi ↔ mobile
      hand-over no longer reports offline. (landed earlier)
- [x] Reachability probe hits an HTTP `204` endpoint (configurable `pingUrl`,
      default `connectivitycheck.gstatic.com/generate_204`); a `200` with HTML
      means a captive portal → "Sign in to this Wi-Fi network".
- [x] Offline re-check backs off 5 → 10 → 20 → 60 s with jitter.

## Phase 3 — Notifications
- [x] Percent, size, speed, time left; immediate FGS; throttled. (landed earlier)
- [x] Aggregate progress across every running download.
- [x] Pause / Resume / Cancel actions on the ongoing notification
      (`DownloadActionReceiver.kt` → Dart).
- [x] "N downloads paused — tap to resume" after the process was killed.

## Phase 4 — Photos
- [x] Save all photos in one tap; children share a `group_id` (schema v4).
- [x] Photos probed 4 at a time instead of 20 in parallel.
- [x] TikTok mirror fallback: a photo refused on one CDN host is probed on
      the next `urlList` entry.

## Phase 5 — Remote config & telemetry (server)
- [x] `RemoteConfig`: JSON fetched on launch (ETag, 24 h cache, built-in
      fallback). Carries per-platform kill switches with a message, extractor
      patterns, `pingUrl`, `telemetryUrl`, `minAppVersion`. Extractor lists in
      `SocialMediaProvider` come from the catalog instead of hard-coded lists.
- [x] `FailureReporter`: anonymous `{platform, reason, appVersion}` events,
      batched, posted only when `telemetryUrl` is set.
- [x] `server/`: FastAPI reference service — `/ping`, `/config`, `/events`,
      `/resolve` (yt-dlp fallback) — with Dockerfile and README.

## Phase 6 — Hygiene
- [x] Pending share persisted on arrival, replayed on next launch if the
      process died before the sheet showed.
- [x] Schema version bump with additive migration.

## Deferred (needs a device or a server to verify)
- Facebook routes (`m.facebook.com`) — region-blocked from the dev network.
- Per-host reachability holds — needs field data from telemetry first.
