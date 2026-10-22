# Remote app updates

From 0.6.1, App updates uses only the HTTPS address you supply. There is no
preset host or official-update button. Until an address is saved, the screen
shows **Set up remote updates** and makes no automatic requests. An upgrade
clears the previous preset address and its last-attempt time, while keeping
custom server addresses.

## First setup

1. Choose an HTTPS host with a valid public TLS certificate. The JSON and APK
   must be publicly downloadable without signing in.
2. Download **remote-update.zip** from the app release, then extract it.
3. Upload both files to the same folder, for example:

   ```text
   https://yourdomain.com/updates/update.json
   https://yourdomain.com/updates/ultravpn-player-0.6.1.apk
   ```

4. In **Settings > App updates > Remote update address**, enter the full JSON
   address: `https://yourdomain.com/updates/update.json`.
5. Choose **Save address**, then **Check for updates**. A device already on that
   version correctly says it is up to date. The next higher version code is
   offered as an update.

The saved address is app-wide and survives sign-out. It is separate from IPTV
server/login details. Save an empty address to turn off remote updates.
Automatic checks run on opening/resuming at most once per 12 hours. Users can
also check manually. Downloads and Android installation approval remain manual.

## Each subsequent release

1. Build the new app with a higher version name and version code, using the
   **same permanent signing key**. The repository workflow builds and publishes
   a fresh remote-update.zip after changes/version updates are merged to main.
2. Extract the ZIP. Upload the new, versioned APK first.
3. Replace the server's update.json with the one from that same package **last**,
   preferably using an atomic rename. Keep the JSON address unchanged.
4. Leave the previous versioned APK available for users already downloading it.

Example after the next update:

```text
updates/
  update.json                       # replace with each release
  ultravpn-player-0.6.1.apk          # keep previous APKs
  ultravpn-player-0.6.2.apk          # upload before replacing JSON
```

There is no need to enter new server details on each device. The ZIP contains
the correct version, actual APK size and SHA-256. Do not manually change those
values or replace an APK while keeping an old manifest. Disable long-lived
caching for update.json. This is a periodic update check, not an instantaneous
push to apps that are closed.

## Manifest format

The package's relative apkUrl resolves next to the downloaded JSON file, so you
can upload the same ZIP contents to your chosen domain without editing it.
Absolute HTTPS APK addresses remain supported. HTTPS redirects are followed
up to five times; relative APK paths use the final manifest location.

```json
{
  "schemaVersion": 1,
  "applicationId": "com.streamline.iptv",
  "versionName": "0.6.1",
  "versionCode": 9,
  "minSdk": 24,
  "apkUrl": "ultravpn-player-0.6.1.apk",
  "sizeBytes": 100000000,
  "sha256": "replace-with-the-real-64-character-apk-sha256",
  "releaseNotes": "What changed in this release."
}
```

This example is illustrative; upload the generated JSON from the ZIP with the
matching APK. The JSON limit is 64 KiB; the APK limit is 512 MiB.

For custom manual builds, generate the matching JSON using Python 3.11+ and
Android build-tools:

```sh
python scripts/create_update_manifest.py --apk ultravpn-player-0.6.1.apk \
  --aapt /path/to/android/build-tools/36.0.0/aapt2 \
  --apk-url ultravpn-player-0.6.1.apk \
  --notes docs/RELEASE_NOTES_0.6.1.md --output update.json
```

## Signing, installation and errors

Hosting on your own server does not change Android's signing requirement.
All releases must use the same permanent key for updates that keep account,
preferences and watch history. See [SIGNING.md](SIGNING.md). The prepared key
still needs the one-time ANDROID_SIGNING setup for repository builds; it is not
committed or included in a download. Temporary testing keys from different
runners cannot reliably update each other. Migrating a testing installation can
require uninstalling; uninstalling clears local app data. The updater never
uninstalls anything.

The app verifies APK size/SHA-256, then Android checks package ID, minimum SDK,
actual version code and matching signing certificates again before installation.
The system installer performs final signature verification. Current signing
certificate(s) must match; signing-key rotation is not supported.

Only cache/updates/ is shared with the Android installer through a private
FileProvider. Android 8+ requires Allow from this source once and installer
approval for every update. Device administrators can restrict sideloading.
No IPTV credentials or viewing history are sent to the update host.

Errors distinguish unreachable servers, HTTP status, invalid JSON, incompatible
Android versions, storage failures, changed/incomplete APKs, wrong apps, signing
mismatches and installer restrictions. A 404 after configuring your server means
that exact JSON or APK URL is missing; verify the full address and uploaded files.
Downloads restart after interruption; Android can clear cache. Returning from
the installer does not claim success: the installed version after restart
confirms it.

Before broad rollout, test two consecutive permanently signed builds on a phone
and D-pad TV, verify history survives, and test cancellation and restricted
sideloading. Automated tests cannot approve the physical Android installer.
