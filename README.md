<<<<<<< HEAD
<div align="center">

<img src="assets/icon/hoza_mark.png" alt="Hoza Download" width="96" />

# Hoza Download

**Share a link. Pick a quality. It lands in your Downloads folder.**

A fast, polished media downloader for Android — video, audio and photos from
TikTok, Instagram, Facebook, YouTube and direct links, saved where every other
app can see them.

![Flutter](https://img.shields.io/badge/Flutter-3.44%2B-02569B?logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-3.12%2B-0175C2?logo=dart&logoColor=white)
![Android](https://img.shields.io/badge/Android-7.0%2B%20(API%2024)-3DDC84?logo=android&logoColor=white)
![Kotlin](https://img.shields.io/badge/Kotlin-native%20channels-7F52FF?logo=kotlin&logoColor=white)
![Status](https://img.shields.io/badge/status-active-4C7DFF)

</div>

---

## Contents

- [Highlights](#highlights)
- [Supported sources](#supported-sources)
- [How it works](#how-it-works)
- [Getting started](#getting-started)
- [Building a release](#building-a-release)
- [Configuration](#configuration)
- [Backend (optional)](#backend-optional)
- [Project structure](#project-structure)
- [Reliability & networking](#reliability--networking)
- [Privacy](#privacy)
- [Testing on a device](#testing-on-a-device)
- [Roadmap](#roadmap)
- [License](#license)

---

## Highlights

- **Share‑sheet first.** Tap *Share → Hoza Download* in any app. A floating
  half‑sheet slides up *over* the app you were in — you never leave it.
- **Video, audio and photos.** Reels, slideshows, carousels and single photos
  are all first‑class: pick one photo, or **Save all** in one tap.
- **Real download engine.** Streaming to disk, byte‑range resume, pause,
  cancel, retry, concurrency cap, stall detection, and segmented transfers on
  hosts that allow it.
- **Truthful progress.** A live notification with percent, size, speed and time
  left — plus Pause / Resume / Cancel buttons — and the same figures in the
  app, animated, never invented.
- **Self‑healing.** Expired CDN links are re‑resolved *before* they fail,
  429/5xx get sensible back‑off, and a false "offline" from Android is
  verified against the real network before anything is held.
- **Remote‑updatable extractors.** When a platform changes its page markup,
  the fix ships as a JSON file — no store release.
- **Designed, not assembled.** Dark and light themes, a stroke‑drawn launch
  mark that flies into the masthead, posters that fly into the tray,
  illustrated empty states, rings that draw their own check when a download
  completes.
- **Does not bypass anything.** No DRM, no login walls, no private posts. If a
  source will not share it, Hoza says so and stops.

## Supported sources

| Source | Video | Audio | Photos | Notes |
| --- | :-: | :-: | :-: | --- |
| TikTok | ✅ | — | ✅ slideshows | Short links (`vt.tiktok.com`, `/t/…`) expanded automatically |
| Instagram | ✅ reels | — | ✅ single & carousel, full size | Read via the public embed page |
| Facebook | ✅ | — | ✅ | Region‑dependent — some networks receive a login wall for all content |
| YouTube | ✅ | ✅ | — | Separate audio/video streams are merged on device |
| Direct links | ✅ | ✅ | ✅ | `.mp4 .webm .m4a .mp3 .jpg .png .webp …` |
| Other pages | ✅ | ✅ | — | Open Graph / JSON‑LD media on any public page |

Only content a source publishes as downloadable is offered. Private,
age‑gated or sign‑in‑only posts are reported, not worked around.

## How it works

```
Share / paste link
      │
      ▼
LinkCanonicalizer     expand short links, strip tracking params
      │
      ▼
SourceRegistry        10‑min cache · cancellable · kill switches from remote config
      │  first provider that claims the link, then fallbacks
      ▼
Providers             YouTube → Social (TikTok/IG/FB) → DirectMedia → PageMedia
      │  each returns real, probed variants — never padded
      ▼
Link sheet            Video / Audio / Image switch, quality tiles, Save all
      │
      ▼
DownloadsController   queue, concurrency, holds, retries, expiry refresh
      │
      ▼
Download engines      HTTP streaming · segmented · muxing (video + audio)
      │
      ▼
MediaStore            Download/Hoza Download/{Videos,Audio,Images}
```

Everything runs in one Flutter isolate shared by both windows (the full app
and the floating share sheet), kept alive by a foreground service while
transfers run.

## Getting started

**Requirements**

- Flutter **3.44+** (Dart 3.12+)
- Android SDK; a device or emulator on **API 24+**
- JDK 17 for the Gradle build

```bash
git clone <your-repo-url>
cd hoza_download
flutter pub get
flutter run            # debug build on the connected device
flutter analyze        # expected: No issues found!
```

The debug build installs as `com.hoza.download.debug`, so it can live next to
a release install.

## Building a release

```bash
flutter build apk --release          # single APK  → build/app/outputs/flutter-apk/
flutter build appbundle --release    # AAB for Play → build/app/outputs/bundle/release/
```

**Signing.** Copy `android/key.properties.example` to `android/key.properties`
and fill in your keystore details. `key.properties`, `*.jks` and `*.keystore`
are git‑ignored — never commit them, and back the keystore up: losing it means
losing the ability to update the app on the store.

**Versioning.** Bump `version:` in `pubspec.yaml` **and** `AppInfo.version` in
`lib/core/constants/app_info.dart`; the remote config compares against the
latter.

## Configuration

All configuration is compile‑time constants in `lib/core/constants/app_info.dart`:

| Constant | Purpose | Default |
| --- | --- | --- |
| `remoteConfigUrl` | HTTPS URL of the remote config JSON (kill switches, extractor patterns, ping/telemetry endpoints). Empty = fully offline, built‑in defaults. | `''` |
| `version` | App version shown in About and sent with telemetry | `1.0.0` |
| `downloadFolder` | Shown to the user as the save location | `Download/Hoza Download` |

Download behaviour the **user** controls lives in Settings: default media type,
video/audio format, quality preference, concurrent downloads, Wi‑Fi only,
auto‑start, notifications, theme.

## Backend (optional)

The app runs entirely on‑device. A small backend adds three things:

| Endpoint | Gives you |
| --- | --- |
| `GET /config` | **Fix a broken platform in minutes** — swap extractor regexes or switch a platform off with a message, no store release |
| `POST /events` | Anonymous outcome counts per platform (never a URL, title or device id) — know Instagram broke before users tell you |
| `POST /resolve` | yt‑dlp fallback resolver for links the phone cannot read (e.g. region blocks) |

The cheapest deployment is **one static JSON file on any HTTPS host** — see
[`server/README.md`](server/README.md) for the file format, the FastAPI
reference service, and a Dockerfile.

## Project structure

```
lib/
  main.dart                       opens the database, loads settings, starts the app
  app/                            root widget, router, theme tokens & ThemeData
  core/                           constants, logging, formatters, URL/expiry/filename utilities
  data/
    database/                     SQLite schema (v4), migrations, DAO, settings store
    models/                       DownloadRecord, settings, media & status enums
    providers/                    DownloadsController (queue), settings, share hand‑off
  features/
    downloader/
      data/                       engines, providers, link canonicaliser, source registry
      domain/                     provider contracts, error kinds, variant selection
      presentation/               link sheet, download sheet, picker, progress view
    downloads/  home/  settings/  share/  shell/  splash/  onboarding/  about/
  services/
    config/                       RemoteConfig + ExtractorCatalog (built‑in patterns live here)
    networking/                   shared HttpClient and timeouts
    platform/                     permissions, foreground service bridge, notifications, network
    share/                        share channel, pending‑share store
    telemetry/                    FailureReporter (anonymous, batched, opt‑in)
  shared/widgets/                 component library: sheets, buttons, rings, flights, art…

android/app/src/main/kotlin/com/hoza/download/
  HozaEngine.kt                   the one Flutter engine both windows attach to
  ShareSheetActivity.kt           the translucent share window
  DownloadForegroundService.kt    ongoing progress notification with actions
  DownloadActionReceiver.kt       Pause / Resume / Cancel → Dart
  NotificationsChannel.kt         completion, failure and info notifications
  MediaStoreChannel.kt            publish, exists, open, share, rename
  NetworkChannel.kt               connectivity that survives Wi‑Fi ↔ mobile hand‑over
  MuxerChannel.kt                 merges separate audio/video tracks

server/                           optional FastAPI backend + config/extractors.json
docs/HARDENING_PLAN.md            the reliability checklist and what each item became
```

State management is **Riverpod**. Business logic lives in controllers and
services; widgets present. `DownloadsController` is the single source of truth
for records *and* scheduling.

## Reliability & networking

- **Link resolution** — redirect‑first for short links, tracking stripped,
  10‑minute cache, cancelled when the sheet closes, HTML‑as‑200 rejected.
- **Expiry‑aware** — `x-expires` / `oe` / `expire` parsed from CDN URLs; a
  queued download with an expired address is re‑resolved before the request.
- **Retry policy** — 429 → 30 s / 90 s; 5xx → 5 / 15 / 45 s; 401/403 → re‑read
  the source page; 404/410 → stop and say the file was removed.
- **Network truth** — an "offline" verdict from Android is verified with an
  HTTP `204` probe (captive portals detected) and re‑checked with back‑off.
- **Process death** — interrupted transfers are settled to *Paused* on next
  launch with a notification; a share that never got its sheet is replayed.
- **Storage** — Android 10+: `MediaStore.Downloads`, no permission. Android
  9 and older: public Downloads with `WRITE_EXTERNAL_STORAGE` (capped at API
  28). `MANAGE_EXTERNAL_STORAGE` is never requested.

## Privacy

- No accounts, no sign‑in, no cookies beyond the single page fetch a
  download needs.
- Nothing leaves the device unless you configure `remoteConfigUrl` **and** the
  config names a `telemetryUrl` — and then only `{platform, event, reason,
  appVersion, osVersion}`. Never a URL, title, file name or identifier.
- Permissions: `INTERNET`, `ACCESS_NETWORK_STATE`, `FOREGROUND_SERVICE`,
  `FOREGROUND_SERVICE_DATA_SYNC`, `POST_NOTIFICATIONS`, and
  `WRITE_EXTERNAL_STORAGE` only up to Android 9.

## Testing on a device

```bash
flutter analyze                # must be clean
flutter build apk --debug      # must succeed
```

Then on a phone: share from TikTok, Instagram and YouTube with the app closed
and open; switch Wi‑Fi → mobile mid‑download; deny then allow notifications;
lock the screen for ten minutes; force‑stop mid‑download and reopen. The full
manual checklist is in [`docs/HARDENING_PLAN.md`](docs/HARDENING_PLAN.md).

## Roadmap

- Photo picker grid with per‑photo selection in the link sheet
- "Use mobile data this time" override on the Wi‑Fi‑only hold
- Clipboard link detection on Home
- Grouped card for multi‑photo sets in the Downloads list
- Arabic and Kurdish localisation with RTL layout
- Client hook for the backend `/resolve` fallback

## License

Copyright © 2026 Rahoz Osman. All rights reserved.

No license is granted for redistribution or commercial use. Open an issue if
you would like to discuss usage.
=======
# Hoza-Download
Hoza Download: one share button to save videos, audio and photos from TikTok, Instagram, Facebook, YouTube and direct links. Choose the quality, download in the background, pause and resume anytime, and find every file in Download/Hoza Download. Free, no account, no ads.
>>>>>>> b2eb04aaa73fa9e043ecf11b49f7da8649131b3a
