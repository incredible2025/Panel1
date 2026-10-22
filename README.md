# ULTRAVPN PLAYER IPTV

A Flutter app for Android phones and Android TV using your own Xtream Codes account. One APK includes touch navigation and a remote-friendly TV layout.

**v0.6.0** adds a built-in updater with configurable HTTPS hosting, release notes, optional automatic checks, verified APK downloads and Android installer integration. See [online updates](docs/UPDATES.md). Reliable in-place updates require the permanent release key.

**v0.5.2** introduces ULTRAVPN PLAYER branding, including the supplied artwork, shield launcher icon, splash and TV banner. See [release notes](docs/RELEASE_NOTES_0.5.2.md) and [branding notes](docs/BRANDING.md).

**v0.5.1** adds comprehensive connection diagnosis with stage-by-stage error explanations, safe reports and optional stream sampling. Open it from Settings, sign-in or the player error screen. See [release notes](docs/RELEASE_NOTES_0.5.1.md) and [diagnosis details](docs/CONNECTION_DIAGNOSIS.md).

**v0.5.0** adds a cinematic Home screen, midnight-blue/cyan styling, auto-hiding player controls, full Settings, a built-in compatibility player, per-account movie recommendations, category management and parental protection. See [release notes](docs/RELEASE_NOTES_0.5.0.md) and the [design/behaviour specification](docs/V0.5_DESIGN.md).

## Download the APK

**[Download the latest ultravpn-player.apk](https://github.com/incredible2025/Panel1/releases/latest/download/ultravpn-player.apk)** and install it on your phone or TV. The direct release download requires no ZIP extraction. Versioned downloads are available on the repository's [Releases page](https://github.com/incredible2025/Panel1/releases).

As a fallback, open **[Actions → ULTRAVPN PLAYER Android release](https://github.com/incredible2025/Panel1/actions/workflows/android-apk.yml)**, select a successful main-branch run and download **ultravpn-player-apk** from Artifacts. Artifact downloads require GitHub sign-in and ZIP extraction; they expire after 30 days.

The current APK uses Android's disposable testing key. Builds from different runners may require uninstalling the previous testing app, which clears its saved login and local history. Permanent signing is prepared but not enabled; it is required for reliable online updates. See [release signing](docs/SIGNING.md) for the prepared setup.

## Stack

- Flutter **3.35.7**, Dart 3.9, Material 3 and **Riverpod** state management.
- `video_player`, backed by Android ExoPlayer, plus an optional `media_kit` compatibility engine, for HLS (`.m3u8`), MPEG-TS (`.ts`) and provider-supported VOD containers. Codec and hardware decoder availability depend on the device.
- **SQLite v4** for account-scoped watch history, preferences, favourites, recent channels and EPG cache; **flutter_secure_storage** for encrypted credentials, session metadata and salted parental-PIN records.
- Native Android `UiModeManager` detection for TV mode, Leanback launcher support and D-pad focus traversal.

## Features

- App updates from GitHub or your own HTTPS server, verified APK downloads and installer handoff.
- Settings for player choice, control timeout, audio/subtitles, picture, appearance, category visibility/order and parental PIN.
- Local movie recommendations from meaningful viewing and provider categories; watched/hidden/locked titles are excluded.
- Refreshed account information and expiry reminders, with missing fields labelled honestly.
- Remembered section/category/channel selection; optional muted live previews and playback diagnostics.
- Login using server URL, username and password; restores the encrypted session after relaunch.
- Live TV category filters, channel search, short EPG preview and full-screen channel zapping.
- Favorite channel toggles/filter and the latest **20 distinct successfully played live channels**, stored separately for each account.
- Movie/series home shelves, including up to five provider-category rows, with **Browse all** opening a lazy poster grid.
- **Newest**, **Title: A–Z** and **Title: Z–A** sorting. Recently added rows use real provider timestamps; missing dates are left unknown and sort after dated titles under Newest.
- Movie details, recently opened films and Continue Watching.
- Resume or restart prompt when movie progress is **strictly above 5% and below 95%**.
- Series resume, watched episode markers, Continue Watching and a cancellable eight-second next-episode countdown.
- Movie/series My List shelves and saved-only filters, separated by account.
- Full channel/time guide with programme descriptions, device-local times, date selection and limited-EPG fallback.
- Bounded automatic reconnects, Fit/Fill/Stretch and stream-provided audio/subtitle controls.
- Movie and episode progress snapshots every five seconds, on pause/background and before navigating back. Recent opens update the access timestamp without erasing saved progress.
- Loading, empty and retry states; credentials and stream URLs are excluded from user-facing error messages.
- Provider backdrops and posters, movie/series metadata, title-based artwork fallbacks and animated TV focus states that respect reduced motion.

No credentials, provider addresses, playlists or media are included. Enter an account for a provider you are authorized to use. HTTP providers are supported; HTTPS protects credentials in transit.

## Project structure

```text
lib/
  main.dart                    # storage/session/platform bootstrap
  app.dart                     # app theme, shortcuts, auth routing
  core/
    providers.dart             # Riverpod session, API, catalog, EPG/history
    player_tracks.dart         # native audio/subtitle bridge
    platform_mode.dart         # Android TV MethodChannel
    settings_controller.dart   # serialized preferences and protected-access session
    playback_handle.dart       # shared ExoPlayer/media_kit interface
    design_system.dart         # visual tokens, bundled type, brand and theme
  data/
    models.dart                # tolerant Xtream + history models
    xtream_api.dart            # API requests, validation, stream URIs
    local_store.dart           # encrypted session and SQLite persistence
  features/
    home_screen.dart           # featured, continue, recommended and saved shelves
    settings_screen.dart       # preferences, account, categories and PIN
    login_screen.dart
    dashboard_screen.dart      # Live / Movies / Series, two layouts
    movie_detail_screen.dart   # metadata, recent open, resume prompt
    series_detail_screen.dart   # saved season, episode progress and resume
    tv_guide_screen.dart        # scrollable channel/time schedule
    player_screen.dart         # playback, remote keys, history flush
  widgets/                     # focusable cards, artwork, shared states
packages/video_player_android/  # pinned player with native track extension
android/                       # app, Leanback manifest, TV detection
assets/fonts/                  # bundled Roboto families and licenses
test/                          # API, SQLite, playback and widget tests
.github/workflows/android-apk.yml
docs/TESTING.md
docs/PREMIUM_DESIGN.md
docs/SIGNING.md
```

## Run locally

Install Flutter 3.35.7, JDK 17 and Android SDK 36 with build tools. Then:

```sh
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter run
# Uses the testing key unless optional release signing is configured.
flutter build apk --release
```

The APK is written to `build/app/outputs/flutter-apk/app-release.apk`. The application ID is `com.streamline.iptv`, minimum Android API 24 (Android 7). Both phone and TV launchers can discover it.

Recommendations use at least one minute and five percent of playback, provider categories, recency and supplied ratings. They run on this device without uploading viewing history. They are content-based suggestions, not collaborative or AI recommendations.

The automated suite covers API/model parsing, provider dates and sorting, SQLite migration/account isolation, favorites/recent channels, resume thresholds, playback lifecycle/cleanup and phone/TV widget behavior. See [TESTING.md](docs/TESTING.md) for commands, screenshot capture and device checks.

## Xtream API

Requests use `{server}/player_api.php` with URI-encoded `username` and `password` query parameters and a bounded timeout. Server URLs may include a port and base path. Authentication validates `user_info.auth` and account status, and stores `user_info` and `server_info`.

| Area | Actions |
| --- | --- |
| Live | `get_live_categories`, `get_live_streams`, `get_short_epg&stream_id=…`, `get_simple_data_table&stream_id=…` |
| Movies | `get_vod_categories`, `get_vod_streams`, `get_vod_info&vod_id=…` |
| Series | `get_series_categories`, `get_series`, `get_series_info&series_id=…` |

Playback URLs follow Xtream's `/live/{username}/{password}/{id}.m3u8`, `/movie/.../{id}.{extension}` and `/series/.../{episodeId}.{extension}` forms. Provider-reported movie and episode extensions are respected. Live HLS is the default; explicit `.ts` channels and accounts restricted to MPEG-TS use `.ts`. The short EPG endpoint supplies the preview and has a two-hour local fallback cache. The full guide uses get_simple_data_table, a 15-minute fresh cache and up to 24-hour cached fallback. Some providers supply only a short schedule; date controls do not create missing programmes or enable catch-up.

## Controls

| Control | Behavior |
| --- | --- |
| D-pad on browsing screens | Move focus between navigation, filters and cards |
| Select / Enter | Activate focused control; toggle playback on video |
| Media Play / Pause | Control playback |
| Left / Right on video | Seek VOD |
| Up / Down on video | Previous / next live channel |
| Back | Hide visible controls during playback, then save progress and exit |
| Touch | Tap controls and scrub VOD timeline |

See [the device test guide](docs/TESTING.md) for acceptance checks and known limits.
