# Testing Streamline v0.2

The GitHub workflow checks formatting, runs Flutter analysis and executes **35 automated tests** before building the universal APK. The suite covers API/model parsing, SQLite persistence and account isolation, movie resume thresholds, playback ordering/lifecycle/cleanup, and phone/TV widgets. Playback tests use a fake video platform; real-provider streams and hardware remotes require the device checks below.

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

No provider credentials or running Android devices are included in this repository.

1. **Phone login:** install APK, enter an HTTPS provider URL and account, validate invalid-account retry then successful login. Relaunch and verify the session restores. Try a URL with a port or provider base path.
2. **Catalog:** open Live TV, Movies and Series; filter categories, search, refresh, and verify artwork fallback for missing images. Try a category with no entries.
3. **Live/EPG:** select a channel, check current and upcoming programs, play, switch previous/next channels rapidly, stop and reopen. Check a provider using HLS and one using MPEG-TS where available. Missing EPG must not block playback.
4. **Movie resume:** play beyond 5%, exit, confirm Continue Watching and recent order, then choose Resume. Exit and choose Start from Beginning. At 95% or later the film should remain recent and leave Continue Watching. Exactly 5% and 95% must not qualify.
5. **Series:** choose a series, switch season and play different episodes. Check numeric and string episode IDs and missing metadata.
6. **TV remote:** verify launcher banner, landscape layout, initial focus and visible focus outlines. Traverse categories/grids with D-pad; Select plays, media keys pause/play, video arrows seek or zap, Back returns with focus usable. Scroll to off-screen cards. Try a hardware remote.
7. **Lifecycle:** background and reopen during VOD; playback should pause and progress should persist. Interrupt the stream, retry, and navigate Back during initialization. Check no simultaneous audio after rapid channel switches.
8. **Account separation:** sign out, sign into another account and check that the previous account's history is absent. Returning to the original account restores its local history.
9. **Network:** disconnect during a request and during playback. Errors must not show usernames, passwords or full stream URLs. EPG can fall back to recent cached data; full offline playback is not supported.
10. **Premium interface:** inspect phone portrait/landscape and TV at normal and enlarged text settings. Check backdrop/title contrast, long titles, missing artwork, synopsis/cast scrolling, visible focus on season/episode cards and access to the final item in long lists. Enable reduced motion and verify navigation and controls still work.

## Practical limits

- Xtream providers vary in response shape, authentication rules, EPG timezone metadata, codecs and stream concurrency limits. Test against the intended provider.
- Flutter runs as an Android app on TV with native TV detection and Flutter focus navigation. Device-specific remote/IME behavior still needs a physical-device check.
- Hardware decoding is managed by ExoPlayer and Android; support varies by stream codec and device. DRM, catch-up TV, downloads, external subtitles, favorites, parental controls, and Chromecast are outside this first testing build.
- EPG stores a short preview, not a full XMLTV guide. Catalog lists require a network connection. A force-killed process may lose up to the latest five seconds of movie progress.
- Signing is for testing only. Uninstall may be needed between APKs built on different runners.
