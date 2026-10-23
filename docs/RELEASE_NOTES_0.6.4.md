# ULTRAVPN PLAYER 0.6.4

- Update-path verification release: version 0.6.4, Android build 12.
- Uses the same permanent Android signing key and app ID as 0.6.3 (build 11).
- Player features and settings remain the same as 0.6.3 so the update test isolates downloading and installation.

## Test from the installed 0.6.3 app

1. Keep the permanently signed 0.6.3 app installed on the phone or TV.
2. Extract this release's `remote-update.zip`.
3. Upload `ultravpn-player-0.6.4.apk` into `https://ultra-vpn.store/dl/app/` first. Keep older versioned APKs available.
4. Replace `https://ultra-vpn.store/dl/app/update.json` with the JSON from the same ZIP last. Clear any server/CDN cache for the JSON.
5. Open Settings > App updates > Check for updates. Manual checks bypass the automatic twelve-hour check interval.
6. Confirm version 0.6.4 is offered, download it, and approve the Android installer. Do not uninstall 0.6.3 for this test.
7. Reopen the app and confirm Installed shows 0.6.4 (12), your account/settings/history remain, and another update check reports up to date.

Changing server files makes an update available; downloads and Android installation approval remain manual. Merely opening or downloading the APK from GitHub does not test the app's remote updater. Devices still running older disposable-key testing builds must first migrate manually to a permanently signed baseline.
