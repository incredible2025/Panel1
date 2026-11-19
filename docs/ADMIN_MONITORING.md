# Management monitoring

The app overview shows public APK versions, reporting installations, update adoption and per-app alerts. Search by app name or identifier and use Needs attention to filter apps with active alerts. Activity counts retain their existing foreground heartbeat semantics.

Playback reports are scoped to the registered app and installation token. Reports contain fixed issue categories, player, decoding preference, content type, device model, Android version and installed build. API validation discards extra fields. Raw exception messages, content titles, account details and connection addresses are excluded from report payloads. Reports and inactive installations expire after 30 days through scheduled housekeeping.

Player initialization failures, player errors and buffering lasting at least 20 seconds produce automatic reports. Identical category/player/decoding combinations are suppressed for a minute. The client sends at most eight combinations a minute with at most two concurrent requests, and the endpoint accepts at most twelve requests per installation per minute. Reporting has bounded timeouts and never blocks playback. Delivery failures are best-effort. Counts represent received reports, not a measured playback failure rate.

Player options includes Report picture problem for green screens, audio without picture and pixelation. The user confirms sending the device report. These issues are labelled as user reports in the manager.

An uncaught Android Java exception while a player is active preserves a fixed context record. A later foreground launch reports it with its original app version, and clears it after the server acknowledges receipt. Records expire after seven days. Native signals, operating-system kills and failures before the handler is installed may produce no report. A crash recorded during playback does not prove the player caused it.

Operational health checks validate the public download manifest, stable APK availability and matching size, and HTTPS certificate validity and expiry. Checks run from the management server using certificate verification, bounded requests and no redirects. Certificate probes are shared by origin. Health snapshots older than five minutes are shown as unknown.

App alerts flag download/certificate failures, certificates approaching expiry, failed jobs from the last seven days, jobs pending longer than 15 minutes, five or more playback reports in 24 hours and installations remaining on older builds seven days after publication. Certificate warnings start during the final third of the certificate lifetime, bounded between one and 21 days, to support short-lived certificates. Health alerts refresh on page load. Online activity continues to refresh automatically. Alerts are displayed inside the authenticated dashboard.

Existing APKs continue to report activity as before. Playback reporting requires the updated native Android app. Windows and generic app variants are outside this integration.
