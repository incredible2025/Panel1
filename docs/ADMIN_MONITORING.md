# Management monitoring

The app overview shows public APK versions, reporting installations, update adoption and per-app alerts. Search by app name or identifier and use Needs attention to filter apps with active alerts. Activity counts retain their existing foreground heartbeat semantics.

Playback reports are scoped to the registered app and installation token. Version 2 adds session IDs, monotonic elapsed time, device occurrence time, sequence numbers and approved technical evidence. Evidence can include a native error code, HTTP status, codec/profile, resolution, frame rate, bitrate, actual decoder, buffering, dropped frames and connection-type indicators. Availability varies by player. Nested fields are strictly validated. Raw exception messages, content titles, account details and connection addresses are excluded. Reports and inactive installations expire after 30 days.

Player initialization failures, player errors and buffering lasting at least 20 seconds produce automatic reports. Start, progress, fallback and close events connect attempts within a viewing session. Pause/background intervals reset buffering duration. A bounded serial queue sends at most 24 distinct event combinations per minute. The endpoint accepts 40 requests per installation per minute for version 2 and twelve for legacy reports. Reporting uses bounded timeouts and never holds stream teardown. Delivery is best effort.

Session statistics count distinct sessions with a received start event. Error incidence includes recovered failures. Recovery is advancing playback after the latest reported error, and does not establish picture quality. Filters select complete matching sessions, including later recovery with another engine. Reports without a start or timeline remain visible while being excluded from session rates. Legacy reports retain their original summary data.

The dashboard provides filters, a per-installation pseudonym, support-reference lookup, timelines, evidence and curated next steps. Guidance distinguishes confirmed observations, player-reported observations, likely causes and undetermined causes. HTTP codes alone do not establish the account rule or network policy responsible for a refusal.

Player options includes Report picture problem for green screens, audio without picture and pixelation. The user confirms sending the device report. These issues are labelled as user reports in the manager.

Connection diagnosis includes a user-confirmed Send to support action on mobile and TV. It transmits check codes, outcomes and timings from the affected device. Diagnostic prose, addresses and account data stay local. A support reference links the diagnosis to playback when opened from the player. Standalone diagnoses receive their own reference and do not enter playback-start statistics.

An uncaught Android Java exception while a player is active preserves a fixed context record, original occurrence time and session ID. Fixed codes distinguish out-of-memory, illegal-state, linkage and other uncaught exceptions. A later foreground launch reports the original app version and clears the record after acknowledgement. Records expire after seven days. Native signals, operating-system kills and failures before handler installation may produce no report. Context does not prove the player caused a crash.

Operational health checks validate the public download manifest, stable APK availability and matching size, and HTTPS certificate validity and expiry. Checks run from the management server using certificate verification, bounded requests and no redirects. Certificate probes are shared by origin. Health snapshots older than five minutes are shown as unknown.

App alerts flag download/certificate failures, certificates approaching expiry, failed jobs from the last seven days, jobs pending longer than 15 minutes, five or more playback reports in 24 hours and installations remaining on older builds seven days after publication. Certificate warnings start during the final third of the certificate lifetime, bounded between one and 21 days, to support short-lived certificates. Health alerts refresh on page load. Online activity continues to refresh automatically. Alerts are displayed inside the authenticated dashboard.

Existing APKs continue to report activity as before. Playback reporting requires the updated native Android app. Windows and generic app variants are outside this integration.
