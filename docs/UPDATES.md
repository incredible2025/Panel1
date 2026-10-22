# Online app updates

ULTRAVPN PLAYER 0.6.0 adds **Settings > App updates**, also available before sign-in.
The Home screen and login show an update notice when a newer version is found.
Automatic checks run on opening/resuming the app, at most once per 12 hours.
Users can disable them or check manually at any time. No automatic APK downloads
or silent installs happen; playback is not interrupted by a dialog.

## Publish with GitHub

The default feed is:
`https://github.com/incredible2025/Panel1/releases/latest/download/update.json`

1. Enable the permanent `ANDROID_SIGNING` repository secret using [SIGNING.md](SIGNING.md).
2. Make the app changes and increase **both** `versionName` and `versionCode` in
   `pubspec.yaml` (for example `0.6.1+9`). Update `lib/core/app_version.dart` too.
3. Add release notes at `docs/RELEASE_NOTES_0.6.1.md`, then merge to `main`.
4. Actions tests and builds the APK, verifies signing, derives `update.json` from
   the actual APK, and publishes the manifest with the APK and checksum.
5. Installed apps discover it on their next check. The user chooses Download,
   then Install. This is a periodic online check, not an instantaneous push service.

**Testing releases:** without `ANDROID_SIGNING`, Actions still publishes an APK
for manual testing, but deliberately does not publish `update.json`. A fresh
temporary key on each runner cannot reliably update existing installations. The
app reports an unpublished feed as HTTP 404, not as "up to date". The GitHub
connector cannot configure Actions secrets; the prepared private JSON must be
added once through repository settings. Never commit it or attach it to a release.

An older testing installation may need a one-time migration to the permanent
key. The updater refuses a different certificate and never uninstalls anything.
Uninstalling clears local accounts, preferences and watch history. Android has
no safe way for this updater to preserve private data across incompatible keys.
Once a permanent key is enabled, keep it backed up and use it for every release.

## Host on your own server

Use an HTTPS server with a valid public TLS certificate and anonymously readable
APK/JSON URLs. In App updates, save your HTTPS manifest address. That preference
is app-wide and survives sign-out; it is separate from IPTV account credentials.
Protected Settings still requires the parental PIN. Before sign-in, App updates
is available without an IPTV account.

Upload the versioned APK first; publish the manifest last, preferably by an atomic
rename. Do not replace bytes at an already published APK URL. Disable long-lived
JSON caching. Downloads follow up to five HTTPS redirects and allow at most
512 MiB; the JSON limit is 64 KiB. Allow enough free cache storage for the APK.
Interrupted downloads restart from the beginning; downloaded files are not
restored after process termination. Android can clear cache, in which case
download again. No IPTV credentials or watch history are sent to the update host.

Generate a matching manifest on a machine with Android build-tools/Python 3.11+:

```sh
python scripts/create_update_manifest.py --apk ultravpn-player.apk \
  --aapt /path/to/android/build-tools/36.0.0/aapt2 \
  --apk-url https://updates.example.com/0.6.1/ultravpn-player.apk \
  --notes docs/RELEASE_NOTES_0.6.1.md --output update.json
```

Schema (hash and size must describe the real APK):

```json
{
  "schemaVersion": 1,
  "applicationId": "com.streamline.iptv",
  "versionName": "0.6.1",
  "versionCode": 9,
  "minSdk": 24,
  "apkUrl": "https://updates.example.com/0.6.1/ultravpn-player.apk",
  "sizeBytes": 100000000,
  "sha256": "replace-with-64-hex-character-apk-sha256",
  "releaseNotes": "What changed in this release."
}
```

## Installation and error handling

The app checks download size/SHA-256, then Android checks the APK package ID,
minimum SDK, actual version code and matching current signing certificates.
Native checks run again immediately before installation. The system installer
performs the final APK signature verification. Signing key rotation is not
supported by this updater; use the same current certificate(s).

Only `cache/updates/` is exposed through a private, non-exported FileProvider with
temporary read access to the Android installer. No shared-storage permission is
requested. Android 8+ requires "Allow from this source" once, followed by the
normal installer approval on every update. Some managed or restricted TVs do not
permit sideloading; their policy must be changed by the device administrator.

The UI distinguishes unreachable servers, HTTP errors, invalid manifests,
unsupported Android versions, full storage, incomplete/changed APKs, wrong apps,
signing mismatches and installer restrictions. Errors do not sign users out or
change their existing app. Returning from an installer does not claim success:
the installed version shown after restart confirms the result.

Device verification still required before broad rollout: install two consecutive
builds with the permanent key on a phone and a D-pad TV, approve unknown sources,
verify history survives the upgrade, cancel/retry installation, and test a device
whose administrator disables sideloading. Automated tests cannot approve the
Android system installer on a physical device.
