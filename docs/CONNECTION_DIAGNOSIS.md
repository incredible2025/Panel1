# Connection diagnosis

## Entry points and user flow

Settings → App & maintenance → Connection diagnosis. The sign-in form also opens diagnosis using the entered address/account details, without saving or signing in. The player error screen stops retries, saves progress and fully releases its player before opening diagnosis; Back from diagnosis returns to the underlying library. A stream sample is optional and never starts automatically.

Results show Passed, Warning, Failed or Not tested, a stable code, elapsed milliseconds, an explanation, possible causes where known, and actionable next steps. Failures expand automatically. Reports can be copied manually to the clipboard. Remote Select starts the focused action; normal Flutter focus traversal reaches actions and expandable cards. The list scrolls on mobile, TV and short landscape screens.

## Stages

1. **Device network:** Android ConnectivityManager snapshot. Absence of an active network or a detected sign-in portal stops provider requests. Missing/unconfirmed platform information produces a notice and allows independent provider tests to continue. No external connectivity-test endpoint is contacted by this feature.
2. **Server address:** use the same normalization as authentication. Only HTTP/HTTPS is accepted. No protocol, hostname or port is guessed beyond the app's existing HTTPS default for scheme-less URLs.
3. **DNS:** system resolution, with an eight-second limit; numeric IP inputs skip lookup. Returned addresses are counted by family, never exported. Resolver success does not establish server identity or rule out filtering.
4. **TCP:** connection to the configured hostname/port, then close. This does not establish API or video availability. The actual API is attempted independently even after a transient TCP probe failure.
5. **TLS:** a separate HTTPS handshake using normal certificate validation. HttpClient establishes the connection before returning the request, which is aborted before HTTP is sent. Force-close bounds a stalled handshake. HTTP configurations produce an unencrypted-connection warning instead.
6. **API:** credential-bearing GET to the configured player_api.php. Redirects are not followed. Valid JSON must include user_info. Raw bodies never reach the UI or report.
7. **Account:** auth flag, Active status when reported, and expiry relative to the device clock. Missing expiry does not imply a lifetime subscription. Inactive/unauthorized/expired accounts skip library and stream requests.
8. **Allowance:** report supplied active/max values only; absent/zero maximum is not invented as a finite limit. A full reported allowance warns and prevents an optional stream sample. Provider counts can lag after closing a player.
9. **Clock:** compare timestamp_now, if supplied, with the device clock. More than fifteen minutes of difference warns; either clock or a cached timestamp could be responsible.
10. **Library:** bounded category requests for live, VOD and series, independently. These check listing access, not every title or EPG entry. Empty listings warn. Explicit provider error objects and unsupported collections fail safely.
11. **Stream:** only a selected authorized item, optional request, max 64 KiB. Movie/episode requests use Range. Check for empty samples, HTML/JSON error responses and HLS header where indicated. A valid-looking sample is not a codec, subtitle, audio, throughput or continuous-playback guarantee. Redirected CDN endpoints are reported but not followed by this diagnostic.

Every planned stage receives a result. Prerequisite failures and cancellation produce explicit Not tested results, never implicit passes. Checks use fresh network requests rather than app caches and do not modify session state, watch history, preferences or DNS configuration.

## Implementation and privacy

- `lib/data/diagnostic_transport.dart`: injectable transport, Android network snapshot, bounded/cancellable Dart IO probes; no raw exception text crosses its error boundary.
- `lib/data/connection_diagnostics.dart`: diagnosis orchestration, curated error catalogue and private report model.
- `lib/features/connection_diagnosis_screen.dart`: manual start/stop, progress, expandable explanations and clipboard export. Leaving/backgrounding/account changes stop work; stale callbacks cannot overwrite a later run.
- `MainActivity.kt`: network-state method using ACCESS_NETWORK_STATE, with API 28 gating for Private DNS. No Wi-Fi name, public IP service, DNS-server address, VPN name or location permission is required.

Only the supplied provider and the system resolver are contacted. Android may perform its own system connectivity validation independently. The copied report contains curated descriptions and numeric counters/timings, not credentials, URLs, hostnames/IPs, stream paths, content titles, headers, provider-supplied messages or native error strings. Report data lives in the route's memory; sharing is a manual clipboard action.

This feature identifies observable failures. It cannot conclusively determine ISP blocking, distinguish every firewall from a provider outage, or guarantee a VPN is routing app traffic. Secure DNS and VPN configuration remain separate features.

## Verification

Unit tests simulate network and API states, malformed/oversized responses, status codes, limits, protected stream requests, HLS and cancellation. Local socket/HTTP tests verify body bounds, redirects, stalled bodies/handshakes and active-request cancellation. Widget tests cover phone/TV/landscape, remote Select, failure explanations, Stop, optional stream defaults and private clipboard output. A player regression verifies release before diagnosis and no background reconnect. Native compilation is checked in GitHub Actions before merging.
