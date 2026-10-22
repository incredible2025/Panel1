# ULTRAVPN PLAYER 0.6.0

- Built-in online updater for Android phones and Android TV.
- App updates in Settings and before sign-in, plus a Home update notice.
- Optional automatic checks, manual checks and configurable HTTPS update hosting.
- Release notes, download progress, cancellation and retry.
- APK checksum, identity, version and signing compatibility checks before opening Android's installer.
- GitHub release tooling generates a matching update manifest for permanently signed releases.

This testing build uses the current temporary signing setup. Reliable in-place
updates require the permanent ANDROID_SIGNING secret to be enabled once. Testing
releases do not publish the official update feed. See docs/UPDATES.md.
