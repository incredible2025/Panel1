# ULTRAVPN PLAYER 0.6.1

- Remote updates use your own configurable HTTPS address.
- Removed the preset update host and the Use official updates button.
- Unconfigured updates show setup guidance and make no automatic requests.
- Old default addresses are cleared during upgrade; custom server addresses are preserved.
- Download remote-update.zip, extract it and upload both files to your server.
- Portable update manifests resolve the versioned APK relative to update.json.
- Existing APK integrity, identity and signing checks remain in place.

Use the same permanent release signing key for every update. Current testing
builds may require a one-time migration, which can clear local data if uninstalled.
