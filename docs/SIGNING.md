# Permanent Android release signing

The release key belongs to this app. Keep an encrypted offline backup of the entire private `.signing` folder, including the PKCS#12 keystore and its password JSON. Losing the key prevents updating existing installations. Neither file belongs in Git, release downloads or build artifacts.

## Initial setup

1. Run `scripts/create_release_key.ps1` with an installed JDK's `keytool`. It creates `.signing/streamline-release.p12`, `.signing/android-signing.json` and the public certificate. Running it again retains the existing key.
2. In this repository's **Settings → Secrets and variables → Actions**, create a repository secret named **ANDROID_SIGNING**. Its value is the complete contents of `.signing/android-signing.json`.
3. Back up the private folder in a secure location. The source repository intentionally excludes it.

The JSON contains `keystore` (Base64 PKCS#12), `storePassword`, `keyAlias` and `keyPassword`. GitHub encrypts the repository secret. Only the main-branch release job receives it; pull-request validation runs without signing credentials.

The release workflow decodes the key into a private runner directory, builds the APK, verifies its certificate against the committed public fingerprint and publishes `streamline.apk` to a versioned GitHub Release. Key files are removed from the runner after the job. A missing or invalid signing secret fails the release instead of substituting a disposable debug key.

## Local builds

Set `ANDROID_SIGNING_JSON` to the complete JSON contents in your local process, then run:

```sh
python scripts/configure_android_signing.py
flutter build apk --release
```

The generated `android/key.properties` and `android/signing` directory are ignored by Git. Debug builds (`flutter run`, `flutter build apk --debug`) do not need the release key.

## Updates and downloads

Each release must have a new version in `pubspec.yaml`, including an increasing Android build number. The workflow creates a matching `vX.Y.Z` release tag. It permits rerunning the same commit, but refuses to replace an existing version tag pointing to another commit.

The latest APK is available at:

`https://github.com/incredible2025/Panel1/releases/latest/download/streamline.apk`

The first permanently signed APK cannot replace an installed APK signed by a different disposable test key. Uninstalling the older testing build may be necessary once and removes its local data. Subsequent releases retain the application ID and signing certificate so they can update in place.
