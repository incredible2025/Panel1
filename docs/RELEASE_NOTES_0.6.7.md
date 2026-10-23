# Ultravpn-player 0.6.7

- Settings now includes a manual speed test for this device’s current connection: download, upload, median HTTP latency and jitter. Results identify Cloudflare as the test destination and distinguish an Internet speed estimate from the TV provider’s delivery performance.
- Start/Stop, remote navigation, copied results, partial-result notices and automatic cancellation on leaving, backgrounding or account changes. At most 26 MiB of transfer payload plus small replies and protocol overhead; the screen describes the data budget as up to 28 MB plus overhead. Requests time out after eight seconds and the whole run is limited to 60 seconds.
- Sign-in asks only for username and password. The operator-managed portal is embedded in the app. Settings and copied diagnostic reports do not expose provider URLs. Customer-facing diagnostics direct configuration issues to support.
- Unlimited/no-expiry subscriptions show **Doesn’t expire** for both expiry and time remaining. Supported formats include explicit unlimited/lifetime markers and Xtream’s explicit null expiry on an authorized active line. Missing or invalid expiry fields remain **Not supplied**; unlimited connection allowances do not imply unlimited subscription time. Valid timestamps take precedence and expired/inactive/unauthorized accounts remain rejected.

Existing saved accounts using the embedded portal keep their account IDs, history, collections and preferences. A saved account from another portal requires sign-in again; its password is not silently sent to the embedded service, and its local history remains stored separately.

The package ID, permanent release signing certificate and `Ultravpn-player.apk` filename are unchanged. Upload both APK files from `remote-update.zip` before replacing `update.json`.
