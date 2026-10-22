# Streamline IPTV

A Flutter app for Android phones and Android TV using your own Xtream Codes account. One APK includes touch navigation and a remote-friendly TV layout.

**v0.3.0** adds horizontal movie/series shelves, recently added titles, Newest/A–Z/Z–A sorting, favorite channels and recently played channels. The cinematic [visual system](docs/PREMIUM_DESIGN.md) pairs charcoal surfaces, ivory typography, champagne accents and bundled fonts.

## Download the APK

**[Download the latest streamline.apk](https://github.com/incredible2025/Panel1/releases/latest/download/streamline.apk)** and install it on your phone or TV. The direct release download requires no ZIP extraction. Versioned downloads are available on the repository's [Releases page](https://github.com/incredible2025/Panel1/releases).

As a fallback, open **[Actions → Android APK release](https://github.com/incredible2025/Panel1/actions/workflows/android-apk.yml)**, select a successful main-branch run and download **streamline-apk** from Artifacts. Artifact downloads require GitHub sign-in and ZIP extraction; they expire after 30 days.

v0.3 introduces a permanent release key. Replacing an older disposable-key testing build may require uninstalling that older app once, which clears its saved login and local history. Later releases signed with the same key can update in place. See [release signing](docs/SIGNING.md) for key backup, configuration and update requirements.

## Stack

- Flutter **3.35.7**, Dart 3.9, Material 3 and **Riverpod** state management.
- `video_player`, backed by Android ExoPlayer, for HLS (`.m3u8`), MPEG-TS (`.ts`) and provider-supported VOD containers. Codec and hardware decoder availability depend on the device.
- **SQLite** for account-scoped watch history, favorites, recent channels and EPG cache; **flutter_secure_storage** for encrypted saved credentials and session metadata.
- Native Android `UiModeManager` detection for TV mode, Leanback launcher support and D-pad focus traversal.

## Features

- Login using server URL, username and password; restores the encrypted session after relaunch.
- Live TV category filters, channel search, short EPG preview and full-screen channel zapping.
- Favorite channel toggles/filter and the latest **20 distinct successfully played live channels**, stored separately for each account.
- Movie/series home shelves, including up to five provider-category rows, with **Browse all** opening a lazy poster grid.
- **Newest**, **Title: A–Z** and **Title: Z–A** sorting. Recently added rows use real provider timestamps; missing dates are left unknown and sort after dated titles under Newest.
- Movie details, recently opened films and Continue Watching.
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
docs/SIGNING.md
```

## Run locally

Install Flutter 3.35.7, JDK 17 and Android SDK 35+ with build tools. Then:

```sh
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter run
# Configure release signing first; see docs/SIGNING.md.
flutter build apk --release
```

The APK is written to `build/app/outputs/flutter-apk/app-release.apk`. The application ID is `com.streamline.iptv`, minimum Android API 24 (Android 7). Both phone and TV launchers can discover it.

The automated suite covers API/model parsing, provider dates and sorting, SQLite migration/account isolation, favorites/recent channels, resume thresholds, playback lifecycle/cleanup and phone/TV widget behavior. See [TESTING.md](docs/TESTING.md) for commands, screenshot capture and device checks.

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
