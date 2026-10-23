# Settings speed test

The manual speed test measures the current device-to-Cloudflare path, including any active VPN. It does not run in the cloud, measure every customer's connection collectively, contact the IPTV portal, or guarantee the provider's streaming speed. No test starts until the user chooses Start.

The custom Dart transport uses Cloudflare's documented `https://speed.cloudflare.com/__down` GET endpoint and `https://speed.cloudflare.com/__up` POST endpoint. It does not use Cloudflare's JavaScript measurement SDK, result-logging endpoint or packet-loss service. Cloudflare receives the client's public IP through ordinary test requests; provider credentials and viewing history are never sent.

One warmup request establishes DNS/TCP/TLS and is excluded from latency. Five zero-payload requests produce median HTTP latency and the mean absolute difference between consecutive samples as jitter. Download samples ramp through 1, 4 and 16 MiB; upload samples use 1 and 4 MiB of generated data. A completed sample lasting at least two seconds stops further ramping in that direction. The last completed sample is reported, including HTTP request overhead. This is a bounded single-connection estimate, not a multi-connection saturated-line benchmark or ICMP ping.

Maximum transfer payload is 21 MiB down + 5 MiB up. Upload response bodies are capped at 64 KiB each. Protocol overhead is additional. Each request is limited to eight seconds and the run to 60 seconds. Reads are streamed, redirects are refused and HTTPS certificates retain ordinary platform validation. Failed or truncated samples never become zero-speed success results; earlier completed estimates are retained with a notice. A stalled response force-closes its client before another phase can begin.

Stop, leaving the screen, backgrounding and account changes cancel active traffic and invalidate late callbacks. Results live only in screen memory and can be copied manually. Units are Mbps for throughput and milliseconds for latency/jitter; results from different times or destinations need not agree.

References: [Cloudflare speedtest endpoint documentation](https://github.com/cloudflare/speedtest), [Cloudflare speed test privacy information](https://speed.cloudflare.com/).
