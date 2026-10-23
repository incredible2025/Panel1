# Ultravpn-player 0.6.6

Connection diagnosis now explains observed DNS failures on the customer’s current network. On Android 10 and newer, separate IPv4 (A) and IPv6 (AAAA) queries capture DNS response codes, per-query timings and safe operating-system error codes. Explanations distinguish NXDOMAIN, SERVFAIL, REFUSED, timeouts, route failures and malformed responses. Observations appear separately from possible causes in the screen and copied report.

The network snapshot includes advertised DNS server count and Private DNS mode where Android exposes them, without disclosing resolver addresses. A hostname that has only IPv4 or only IPv6 records can pass. If one query fails but another returns an address, provider checks continue with a notice. Changing Wi-Fi/mobile/VPN during the DNS check discards its answers and asks for a rerun.

Queries use the device’s active network and configured resolver. Android 10+ checks bypass the local Android DNS cache; upstream caches may still apply. Android 7–9 retain bounded system resolution, but cannot expose exact DNS response codes through the public APIs used here. Timeouts and resolver errors cannot conclusively establish ISP blocking, DNSSEC failure or a domain’s status on other networks.

The app name and permanent Downloader filename remain `Ultravpn-player` and `Ultravpn-player.apk`. Package ID and permanent signing certificate are unchanged. The server ZIP contains that stable APK, `ultravpn-player-0.6.6.apk`, and its matching `update.json`. Upload both APK files first and replace `update.json` last.
