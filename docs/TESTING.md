# Device acceptance tests

The workflow runs API/model/storage tests and Flutter analysis before building the universal APK. Real-provider playback and remote behavior need device checks: no provider credentials or running Android devices are included in this repository.

1. **Phone login:** install APK, enter an HTTPS provider URL and account, validate invalid-account retry then successful login. Relaunch and verify the session restores. Try a URL with a port or provider base path.
2. **Catalog:** open Live TV, Movies and Series; filter categories, search, refresh, and verify artwork fallback for missing images. Try a category with no entries.
3. **Live/EPG:** select a channel, check current and upcoming programs, play, switch previous/next channels rapidly, stop and reopen. Check a provider using HLS and one using MPEG-TS where available. Missing EPG must not block playback.
4. **Movie resume:** play beyond 5%, exit, confirm Continue Watching and recent order, then choose Resume. Exit and choose Start from Beginning. At 95% or later the film should remain recent and leave Continue Watching. Exactly 5% and 95% must not qualify.
5. **Series:** choose a series, switch season and play different episodes. Check numeric and string episode IDs and missing metadata.
6. **TV remote:** verify launcher banner, landscape layout, initial focus and visible focus outlines. Traverse categories/grids with D-pad; Select plays, media keys pause/play, video arrows seek or zap, Back returns with focus usable. Scroll to off-screen cards. Try a hardware remote.
7. **Lifecycle:** background and reopen during VOD; playback should pause and progress should persist. Interrupt the stream, retry, and navigate Back during initialization. Check no simultaneous audio after rapid channel switches.
8. **Account separation:** sign out, sign into another account and check that the previous account's history is absent. Returning to the original account restores its local history.
9. **Network:** disconnect during a request and during playback. Errors must not show usernames, passwords or full stream URLs. EPG can fall back to recent cached data; full offline playback is not supported.

## Practical limits

- Xtream providers vary in response shape, authentication rules, EPG timezone metadata, codecs and stream concurrency limits. Test against the intended provider.
- Flutter runs as an Android app on TV with native TV detection and Flutter focus navigation. Device-specific remote/IME behavior still needs a physical-device check.
- Hardware decoding is managed by ExoPlayer and Android; support varies by stream codec and device. DRM, catch-up TV, downloads, external subtitles, favorites, parental controls, and Chromecast are outside this first testing build.
- EPG stores a short preview, not a full XMLTV guide. Catalog lists require a network connection. A force-killed process may lose up to the latest five seconds of movie progress.
- Signing is for testing only. Uninstall may be needed between APKs built on different runners.
