# Testing Streamline v0.4

The GitHub workflow checks formatting, runs Flutter analysis and executes the automated suite before building and publishing the universal testing APK. Tests cover API/model parsing, provider timestamps and sorting, SQLite migration/account isolation, favorites/recent channels, movie resume thresholds, playback ordering/lifecycle/cleanup, and phone/TV widgets. Playback tests use a fake video platform; real-provider streams and hardware remotes require device checks.

## Automated checks and visual previews

```sh
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

Capture the premium interface using the bundled fonts and abstract artwork fallbacks:

```sh
flutter test --dart-define=CAPTURE_UI=true test/ui_test.dart
```

Previews are written to `build/qa`. Tests exercise 390×844 phone portrait, 844×390 phone landscape and 1280×720 TV layouts, plus resume and series-selection states. To preview with representative artwork, set the `STREAMLINE_QA_ART` environment variable to a local image file, then run:

```sh
flutter test --dart-define=CAPTURE_UI=true --dart-define=CAPTURE_UI_ART=true test/ui_test.dart
```

The artwork transport is replaced only inside the test process. These fixtures are not a bundled media catalog. Compare the screenshots with the [visual system](PREMIUM_DESIGN.md), including title contrast, poster cropping, focus visibility and reachable controls.

## Device acceptance

The v0.4 physical-device checks below remain to be completed. No provider credentials or running Android devices are included in this repository. Download the direct APK from [GitHub Releases](https://github.com/incredible2025/Panel1/releases/latest/download/streamline.apk); it requires no ZIP extraction.

1. **Phone login:** install APK, enter an HTTPS provider URL and account, validate invalid-account retry then successful login. Relaunch and verify the session restores. Try a URL with a port or provider base path.
2. **Catalog:** open Live TV, Movies and Series; filter categories, search, refresh, and verify artwork fallback for missing images. Check the movie/series home shelves, no more than five category rows, and Browse all opening the full lazy grid. Try a category with no entries and scroll through a large catalog.
3. **Live/EPG:** select a channel, check current and upcoming programs, play, switch previous/next channels rapidly, stop and reopen. Check a provider using HLS and one using MPEG-TS where available. Missing EPG must not block playback.
4. **Movie resume:** play beyond 5%, exit, confirm Continue Watching and recent order, then choose Resume. Exit and choose Start from Beginning. At 95% or later the film should remain recent and leave Continue Watching. Exactly 5% and 95% must not qualify.
5. **Series:** choose a series, switch season and play different episodes. Check numeric and string episode IDs and missing metadata.
6. **TV remote:** verify launcher banner, landscape layout, initial focus and visible focus outlines. Traverse categories/grids with D-pad; Select plays, media keys pause/play, video arrows seek or zap, Back returns with focus usable. Scroll to off-screen cards. Try a hardware remote.
7. **Lifecycle:** background and reopen during VOD; playback should pause and progress should persist. Interrupt the stream, retry, and navigate Back during initialization. Check no simultaneous audio after rapid channel switches.
8. **Account separation:** sign out, sign into another account and check that the previous account's movie history, favorite channels and recent channels are absent. Returning to the original account restores those local collections.
9. **Network:** disconnect during a request and during playback. Errors must not show usernames, passwords or full stream URLs. EPG can fall back to recent cached data; full offline playback is not supported.
10. **Premium interface:** inspect phone portrait/landscape and TV at normal and enlarged text settings. Check backdrop/title contrast, long titles, missing artwork, synopsis/cast scrolling, visible focus on season/episode cards and access to the final item in long lists. Enable reduced motion and verify navigation and controls still work.
11. **Favorites/recent channels:** save and remove a channel using its star, enable the Favorites filter, relaunch and confirm persistence. Play more than twenty distinct channels; the recent shelf must retain the newest twenty, move replayed channels to the front and avoid duplicates. Selecting a channel or failing initialization must not add it. Repeat rapid zapping and Back while local writes are pending.
12. **Dates and sorting:** verify Newest, Title: A–Z and Title: Z–A against provider data, including mixed-case titles and tied timestamps. Recently added rows must use `added` or fallback `last_modified`, exclude undated titles and show an honest missing-date state when appropriate. Undated titles remain available through Browse all and appear last under Newest.
13. **Upgrade/signing:** the current testing key can differ between runners, so installing a newer testing APK may require uninstalling the older app and losing local data. Permanent signing is deferred. When two APKs share a certificate, verify saved login, favorites and history survive an in-place update; SQLite's v1/v2→v3 migration must preserve movie progress and EPG cache. See [SIGNING.md](SIGNING.md).

14. **Series:** resume halfway through an episode, restart it, complete it, cancel the eight-second countdown, then play next manually. Confirm automatic advancement crosses seasons and stops after the final episode. Reopen the app and verify the latest episode and watched markers.
15. **My List:** save/remove movies and series, relaunch and use each section's My List chip. Confirm live favorites stay separate.
16. **Full guide:** navigate channel and programme cells with D-pad, scroll across midnight and between dates, open descriptions and play live. Test providers with full EPG, short-only EPG and no EPG; check local time/DST, refresh, cached fallback and a long channel list.
17. **Player upgrades:** interrupt a playing stream and confirm at most three automatic reconnects. Pause/background/exit to cancel. Verify on-demand positions survive recovery; select alternate audio and text/bitmap subtitles from real streams, turn subtitles off and cycle Fit/Fill/Stretch on phone and TV.

## Practical limits

- Xtream providers vary in response shape, authentication rules, EPG timezone metadata, codecs and stream concurrency limits. Test against the intended provider.
- Flutter runs as an Android app on TV with native TV detection and Flutter focus navigation. Device-specific remote/IME behavior still needs a physical-device check.
- Hardware decoding is managed by ExoPlayer and Android; support varies by stream codec and device. DRM, catch-up TV, downloads, parental controls and Chromecast are outside this build.
- Full EPG availability depends on the provider. The grid labels limited and cached results, and offers live channel playback rather than catch-up. Catalog lists require a network connection. A force-killed process may lose up to the latest five seconds of progress.
- Audio/subtitle menus show tracks reported by ExoPlayer. Text and bitmap cues are rendered, but complex subtitle positioning and styling are not preserved.
- Permanent signing is optional and deferred. Testing builds can require reinstalling; stable updates need the same signing certificate and an increasing Android build number. See [SIGNING.md](SIGNING.md).
