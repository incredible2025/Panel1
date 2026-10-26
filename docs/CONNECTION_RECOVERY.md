# Connection selection

Android mobile, Android TV and Windows share the same connection manager. It
starts with the approved HTTPS root and permits one attempt at the approved HTTP
root after a socket reachability error or timeout. DNS failures, HTTP responses,
invalid payloads, account refusals and TLS/certificate errors do not cause a
downgrade. A certificate failure blocks further downgrades until the connection
preferences reset. No certificate validation callback is disabled.

API requests have a six-second header/connection deadline and a separate
25-second response-body deadline so large catalogues retain their reading time.
Timed-out requests are aborted before a second attempt. Managed API redirects
remain inside approved roots and cannot silently downgrade HTTPS. Every request
is attempted at most once per root; retries cannot add arbitrary providers.

API and playback selections are independent and memory-only. Playback makes a
six-second headers-only HEAD request before opening the native player. This
checks transport reachability and TLS without downloading a second video body.
An HTTP response to HEAD proves reachability only, not media availability: a
server may reject HEAD while supporting GET. Decoder/content failures do not
cause a blind protocol change. Existing bounded player reconnects preserve the
resume position, recheck the route and release the old controller first.

Successful selections have a five-minute cooldown. Android default-network and
link-property callbacks, Windows IP-interface notifications, application resume
and a new process reset the preference to HTTPS for new requests. These events
do not replace a healthy active stream. No interface address is sent to Dart in
the network-change notification. Old in-flight requests cannot overwrite a
newer remembered selection or a reset.

HTTP fallback is intentionally unencrypted. HTTPS remains preferred. Both roots
share a hostname, so this is protocol/port failover, not an independent DNS or
server backup and not a guarantee against ISP blocking.

Saved accounts from the exact retired destination migrate to the canonical
HTTPS root. The retired destination is recognized by a one-way digest rather
than embedded as a usable address. The permanent historical storage scope is
preserved for both approved roots and migrated accounts, keeping history,
favourites, PIN, settings and cache intact. Unrelated providers are not migrated.

Connection diagnosis records a separate fallback finding when an eligible
HTTPS transport failure is followed by a reachable configured HTTP port. Account,
catalogue and optional stream checks use the selected diagnostic transport.
Reports retain the primary failure and omit addresses and credentials.
