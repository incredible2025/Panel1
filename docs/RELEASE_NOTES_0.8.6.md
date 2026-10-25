# Ultravpn-player 0.8.6

The embedded service address is now http://167.235.169.168. New sign-ins, API requests, pre-login connection diagnosis and generated Live TV/movie/episode stream URLs use this address. Customers still enter only their username and password; the address remains hidden in the app.

Existing sessions for the specifically approved previous portal migrate to the new IP automatically. Account storage identity remains stable so watch progress, favourites, settings, parental PIN and cache are retained across migration, account refresh and subsequent sign-ins. The previous domain is kept only for migration and storage identity. Unrelated provider sessions are not migrated.

An unauthenticated check from the development computer reached the new API endpoint and received HTTP 401. This confirms reachability from that connection; it does not verify customer credentials or playback on a customer's network. Automated checks exercise migration, data retention, API/stream address selection and hidden-address UI behavior.

Version 0.8.6, Android build 26. App identity, permanent signing certificate and Ultravpn-player.apk remain compatible. Upload both APKs from remote-update.zip first, then update.json.
