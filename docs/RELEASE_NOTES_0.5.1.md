# Streamline 0.5.1

## Understand connection failures

Connection diagnosis is available from Settings, sign-in, and the player error screen. Run it manually to see a live sequence of checks and a result for every stage:

- Android's current network, internet-validation, captive-portal, VPN, Private DNS and metered indicators where available.
- Provider URL syntax, system DNS resolution and IPv4/IPv6 counts, TCP port reachability and normal HTTPS certificate verification.
- Xtream account response format, authorization/status, expiry, reported connection allowance and a device/provider clock comparison when a server timestamp is supplied.
- Live TV, movie and series category endpoints checked separately.
- An optional selected-stream delivery sample from the player error screen. The player is stopped and released first. Stream testing is off by default, rechecks parental access, and is skipped if the provider reports the connection allowance is already in use.

Each failed check expands with a plain-language explanation, possible causes and practical next steps. Specific descriptions cover DNS failure/timeouts, refused/unreachable/interrupted connections, TLS/certificate failures, invalid JSON, unsupported/empty listings, account restrictions, HTTP redirects and common HTTP errors including 401, 403, 404, 405, 408, 410, 416, 429 and server/gateway failures.

Copy a private report containing version, UTC start time, stage results, stable error codes, probe timings and the same explanations. It excludes provider addresses/IPs, credentials, media titles, headers, raw provider responses and native exception text. Reports remain in memory until the screen closes; nothing is automatically uploaded or sent.

## Bounded, transparent checks

- Network probes have an eight-second limit, including stalled response bodies and TLS handshakes. Stop, leaving the screen or backgrounding cancels diagnosis and prevents later credential requests.
- API bodies are limited to 512 KiB. An oversized valid listing may still work in the normal library and is described accordingly.
- Stream sampling reads at most 64 KiB, then closes the connection. Movie/episode samples request a byte range. HLS segments are not fetched. This is a delivery check, not decoding, bandwidth measurement or sustained playback testing.
- Redirects are reported rather than followed with credentials. Invalid HTTPS certificates are never accepted.
- Missing provider fields and unperformed checks are explicitly marked. A timeout is never presented as proof of an ISP block.
- Android Private DNS/VPN indicators describe the system snapshot; they do not verify DNS-provider trust, tunnel routing or protection. This release does not configure Secure DNS or include a VPN.

Sign-in now retains the API's safe error explanation instead of replacing every failure with a generic login message. The player error content scrolls on shorter displays.

Download **streamline.apk** for Android phones and Android TV (Android 7.0+). Permanent signing remains deferred. Provider-specific errors, network-state indicators and physical TV remotes still need testing on the intended devices.
