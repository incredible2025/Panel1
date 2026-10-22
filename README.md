# Streamline IPTV

A Flutter app for Android phones and Android TV using your own Xtream Codes account. One APK includes touch navigation and a remote-friendly TV layout.

**v0.2.0** introduces a cinematic interface with charcoal surfaces, ivory typography, champagne accents, bundled fonts and richer artwork-led browsing. Movie and series details, the live guide, login and playback controls share the new [visual system](docs/PREMIUM_DESIGN.md).

## Download the testing APK

Open **[Actions → Android test APK](https://github.com/incredible2025/Panel1/actions/workflows/android-apk.yml)**, select a successful run, then download **streamline-test-apk** from its Artifacts section. Unzip it and install `streamline-test.apk` on your phone or TV. GitHub requires you to be signed in to download workflow artifacts. Runs are also available from Actions → Run workflow, and artifacts expire after 14 days.

The release-mode test APK uses a disposable Android debug signing key. It is suitable for sideload testing. A future build made on another runner may require uninstalling the previous APK first, which removes its local history. Production distribution needs your own persistent signing key.

## Stack

- Flutter **3.35.7**, Dart 3.9, Material 3 and **Riverpod** state management.
- `video_player`, backed by Android ExoPlayer, for HLS (`.m3u8`), MPEG-TS (`.ts`) and provider-supported VOD containers. Codec and hardware decoder availability depend on the device.
- **SQLite** for account-scoped watch history and EPG cache; **flutter_secure_storage** for encrypted saved credentials and session metadata.
- Native Android `UiModeManager` detection for TV mode, Leanback launcher support and D-pad focus traversal.

## Features

- Login using server URL, username and password; restores the encrypted session after relaunch.
- Live TV category filters, channel search, short EPG preview and full-screen channel zapping.
- Movie categories and poster grids, details, recently opened films and Continue Watching.
- Resume or restart prompt when movie progress is **strictly above 5% and below 95%**.
- Series categories, details, season selectors and episode playback.
- Movie progress snapshots every five seconds, on pause/background and before navigating back. Recent opens update the access timestamp without erasing saved progress.
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
    platform_mode.dart         # Android TV MethodChannel
    design_system.dart         # visual tokens, bundled type, brand and theme
  data/
    models.dart                # tolerant Xtream + history models
    xtream_api.dart            # API requests, validation, stream URIs
    local_store.dart           # encrypted session and SQLite persistence
  features/
    login_screen.dart
    dashboard_screen.dart      # Live / Movies / Series, two layouts
    movie_detail_screen.dart   # metadata, recent open, resume prompt
    series_detail_screen.dart
    player_screen.dart         # playback, remote keys, history flush
  widgets/                     # focusable cards, artwork, shared states
android/                       # app, Leanback manifest, TV detection
assets/fonts/                  # bundled Roboto families and licenses
test/                          # API, SQLite, playback and widget tests
.github/workflows/android-apk.yml
docs/TESTING.md
docs/PREMIUM_DESIGN.md
```

## Run locally

Install Flutter 3.35.7, JDK 17 and Android SDK 35+ with build tools. Then:

```sh
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter run
flutter build apk --release
```

The APK is written to `build/app/outputs/flutter-apk/app-release.apk`. The application ID is `com.streamline.iptv`, minimum Android API 24 (Android 7). Both phone and TV launchers can discover it.

The v0.2 suite contains **35 automated tests**, covering API/model parsing, SQLite account isolation, resume thresholds, playback lifecycle/cleanup and phone/TV widget behavior. See [TESTING.md](docs/TESTING.md) for screenshot capture and device checks.

## Xtream API

Requests use `{server}/player_api.php` with URI-encoded `username` and `password` query parameters and a bounded timeout. Server URLs may include a port and base path. Authentication validates `user_info.auth` and account status, and stores `user_info` and `server_info`.

| Area | Actions |
| --- | --- |
| Live | `get_live_categories`, `get_live_streams`, `get_short_epg&stream_id=…` |
| Movies | `get_vod_categories`, `get_vod_streams`, `get_vod_info&vod_id=…` |
| Series | `get_series_categories`, `get_series`, `get_series_info&series_id=…` |

Playback URLs follow Xtream's `/live/{username}/{password}/{id}.m3u8`, `/movie/.../{id}.{extension}` and `/series/.../{episodeId}.{extension}` forms. Provider-reported movie and episode extensions are respected. Live HLS is the default; explicit `.ts` channels and accounts restricted to MPEG-TS use `.ts`. The short EPG endpoint supplies the preview and has a two-hour local fallback cache.

## Controls

| Control | Behavior |
| --- | --- |
| D-pad on browsing screens | Move focus between navigation, filters and cards |
| Select / Enter | Activate focused control; toggle playback on video |
| Media Play / Pause | Control playback |
| Left / Right on video | Seek VOD |
| Up / Down on video | Previous / next live channel |
| Back | Save movie progress and leave player |
| Touch | Tap controls and scrub VOD timeline |

See [the device test guide](docs/TESTING.md) for acceptance checks and known limits.
