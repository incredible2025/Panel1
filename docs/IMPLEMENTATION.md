# Architecture

`main.dart` opens SQLite, restores the encrypted session and asks the native Android platform whether this is a television. It overrides the root Riverpod providers before rendering the application. `app.dart` selects Login or Dashboard from session state.

The data layer has no UI dependencies. `XtreamApi` normalizes provider URLs, sends bounded HTTP requests, parses mixed provider types and builds credential-encoded playback URLs. `LocalStore` stores session data in encrypted storage, with account-scoped SQLite tables for JSON EPG cache and movie history. Account identity hashes normalized server URL and username so password changes retain progress.

Riverpod providers expose catalogs, categories, movie/series details, EPG and history. The dashboard filters catalogs locally and uses lazy grids/list builders. Phone navigation uses bottom tabs; native TV mode uses a navigation rail, visible focus cards and directional traversal. Poster cards scroll into view when focused.

The player uses Android ExoPlayer through Flutter video_player. A generation counter rejects stale stream initialization during channel zapping. Progress writes are serialized, and Back awaits the final snapshot before popping the route. Lifecycle interruption pauses playback. The player MethodChannel toggles Android's screen-on flag while the playback route exists.

Movie history stores media metadata, position and total duration in milliseconds, and last access time. Recently Watched sorts this data by last access. Continue Watching filters the same records to progress strictly above five percent and below ninety-five percent; the movie detail screen queries current storage before presenting Resume or Start from Beginning.

GitHub Actions checks formatting, analysis and automated tests, then compiles a universal release-mode APK signed with the runner's debug key for sideload testing. Production signing is a separate deployment concern.
