import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/app_version.dart';
import 'diagnostic_transport.dart';
import 'models.dart';
import 'xtream_api.dart';

enum DiagnosticStatus { passed, warning, failed, skipped }

class DiagnosticFinding {
  const DiagnosticFinding(
    this.code,
    this.summary,
    this.description, {
    this.status = DiagnosticStatus.failed,
    this.causes = const [],
    this.steps = const [],
  });
  final String code, summary, description;
  final DiagnosticStatus status;
  final List<String> causes, steps;
}

class DiagnosticCheck {
  const DiagnosticCheck(this.stage, this.finding, this.elapsedMs);
  final String stage;
  final DiagnosticFinding finding;
  final int elapsedMs;
  String get title => diagnosticStages[stage] ?? 'Connection check';
}

const diagnosticStages = {
  'network': 'Device network',
  'server': 'Server address',
  'dns': 'Provider DNS lookup',
  'tcp': 'Provider server connection',
  'tls': 'HTTPS security',
  'api': 'Provider API response',
  'account': 'Account authorization',
  'limits': 'Connection allowance',
  'clock': 'Device clock comparison',
  'live': 'Live TV categories',
  'movies': 'Movie categories',
  'series': 'Series categories',
  'stream': 'Selected stream delivery',
};

class DiagnosticReport {
  const DiagnosticReport(this.started, this.checks, {this.cancelled = false});
  final DateTime started;
  final List<DiagnosticCheck> checks;
  final bool cancelled;
  int get failed =>
      checks.where((c) => c.finding.status == DiagnosticStatus.failed).length;
  int get warnings =>
      checks.where((c) => c.finding.status == DiagnosticStatus.warning).length;
  String get summary => cancelled
      ? 'Diagnosis stopped'
      : failed > 0
      ? '$failed check${failed == 1 ? ' needs' : 's need'} attention'
      : warnings > 0
      ? 'Checks completed with $warnings notice${warnings == 1 ? '' : 's'}'
      : 'All completed checks passed';

  // Only curated descriptions enter the report. Never include provider response
  // text, URLs, IPs, credentials, media titles, headers or native exception text.
  String toText() {
    final out = StringBuffer('Streamline connection diagnosis\n')
      ..writeln('Version: $appVersion')
      ..writeln('UTC: ${started.toUtc().toIso8601String()}')
      ..writeln(summary)
      ..writeln(
        'Private: server addresses, credentials and viewing titles omitted.',
      )
      ..writeln(
        'Timings are individual probes, not a speed test. A timeout does not prove ISP blocking.',
      );
    for (final check in checks) {
      final f = check.finding;
      out
        ..writeln(
          '\n${check.title}: ${f.status.name.toUpperCase()} [${f.code}] (${check.elapsedMs} ms)',
        )
        ..writeln(f.summary)
        ..writeln(f.description);
      for (final cause in f.causes) {
        out.writeln('Possible cause: $cause');
      }
      for (final step in f.steps) {
        out.writeln('Try: $step');
      }
    }
    return out.toString();
  }
}

DiagnosticFinding diagnosticFailure(String code, {int? httpStatus}) {
  if (httpStatus != null) {
    if (httpStatus >= 300 && httpStatus < 400) {
      return const DiagnosticFinding(
        'HTTP_REDIRECT',
        'The server redirected this request',
        'The diagnosis did not follow the redirect, so credentials were not forwarded to another destination.',
        status: DiagnosticStatus.warning,
        causes: [
          'The provider changed its address.',
          'A login portal or provider gateway is redirecting requests.',
        ],
        steps: [
          'Ask the provider for its current direct server URL.',
          'Check for a Wi-Fi sign-in page.',
        ],
      );
    }
    return switch (httpStatus) {
      401 => const DiagnosticFinding(
        'HTTP_401',
        'The server requires valid authorization',
        'The server returned HTTP 401. This response alone does not identify whether the username, password or subscription is at fault.',
        causes: [
          'Incorrect account details.',
          'An expired session or provider access rule.',
        ],
        steps: [
          'Check your login details.',
          'Ask the provider to confirm account access.',
        ],
      ),
      403 => const DiagnosticFinding(
        'HTTP_403',
        'The server refused this request',
        'The server returned HTTP 403. A provider firewall, account restriction or gateway policy may deny access; this is not proof of an ISP block.',
        causes: [
          'An account, IP, country or VPN restriction at the provider.',
          'A provider security rule.',
        ],
        steps: [
          'Confirm permitted connections and networks with your provider.',
          'Compare another connection if available.',
        ],
      ),
      404 => const DiagnosticFinding(
        'HTTP_404',
        'This endpoint was not found',
        'The server responded, but the requested API endpoint or stream does not exist at this address.',
        causes: [
          'An incorrect server path or port.',
          'A removed channel or title.',
        ],
        steps: [
          'Check the exact server URL supplied by the provider.',
          'Refresh the library or try another title.',
        ],
      ),
      405 => const DiagnosticFinding(
        'HTTP_405',
        'The server does not accept this request',
        'The endpoint rejected the GET method used by the Xtream API and the delivery test.',
        steps: ['Confirm this is an Xtream Codes-compatible server URL.'],
      ),
      408 || 504 => const DiagnosticFinding(
        'HTTP_TIMEOUT',
        'The server or gateway timed out',
        'An HTTP timeout response came from the server or its gateway. The provider may be slow or unable to reach its stream source.',
        steps: [
          'Wait briefly and retry.',
          'Try a different channel.',
          'Contact the provider if the problem persists.',
        ],
      ),
      410 => const DiagnosticFinding(
        'HTTP_410',
        'This content is no longer available',
        'The server explicitly reported that the requested resource has been removed.',
        steps: [
          'Refresh the library.',
          'Ask your provider whether the title or channel is still available.',
        ],
      ),
      416 => const DiagnosticFinding(
        'HTTP_416',
        'The server rejected the sample range',
        'The bounded movie/episode test requested only the first 64 KiB. The server did not accept that byte range; normal playback may still work.',
        status: DiagnosticStatus.warning,
        steps: ['Try playback in the normal player.'],
      ),
      429 => const DiagnosticFinding(
        'HTTP_429',
        'Too many requests',
        'The provider is limiting requests. Repeatedly running diagnosis or refreshing the library can extend the restriction.',
        steps: [
          'Stop repeated retries and wait before trying again.',
          'Ask the provider about request limits.',
        ],
      ),
      >= 500 => DiagnosticFinding(
        'HTTP_$httpStatus',
        'The provider reported a server error',
        'HTTP $httpStatus was returned by the provider or an upstream gateway. Your device reached an HTTP server, but it could not complete the request.',
        steps: const [
          'Retry later.',
          'Contact the provider if several channels or library sections fail.',
        ],
      ),
      _ => DiagnosticFinding(
        'HTTP_$httpStatus',
        'Unexpected HTTP response',
        'The endpoint returned HTTP $httpStatus rather than a successful response.',
        steps: const [
          'Check the provider URL and account.',
          'Give the provider this error code if it persists.',
        ],
      ),
    };
  }
  return switch (code) {
    'dns_failed' => const DiagnosticFinding(
      'DNS_FAILED',
      'The provider name could not be resolved',
      'The system resolver did not return a usable address for the provider hostname.',
      causes: [
        'A misspelled hostname.',
        'The provider domain or the current DNS resolver is unavailable.',
        'DNS-based filtering may be involved.',
      ],
      steps: [
        'Check the server spelling.',
        'Try another network.',
        'If the address is correct, check Android Private DNS settings or ask the provider.',
      ],
    ),
    'dns_timeout' => const DiagnosticFinding(
      'DNS_TIMEOUT',
      'DNS lookup took too long',
      'The system resolver did not finish within eight seconds. This identifies a lookup timeout, not its underlying cause.',
      steps: [
        'Check the internet connection.',
        'Retry once or compare another network.',
        'Check Android Private DNS configuration.',
      ],
    ),
    'timeout' => const DiagnosticFinding(
      'CONNECTION_TIMEOUT',
      'The connection took too long',
      'The probe did not finish within eight seconds. Slow routing, an unavailable server, congestion or filtering can cause this; it does not prove an ISP block.',
      steps: [
        'Retry once.',
        'Compare another network.',
        'Ask the provider whether its server is available.',
      ],
    ),
    'refused' => const DiagnosticFinding(
      'CONNECTION_REFUSED',
      'The connection was refused',
      'A connection attempt was explicitly rejected. The configured port may be closed or the service may be stopped.',
      steps: [
        'Check the server port and HTTP/HTTPS scheme.',
        'Ask the provider to verify the endpoint.',
      ],
    ),
    'unreachable' => const DiagnosticFinding(
      'NETWORK_UNREACHABLE',
      'No route to the provider',
      'The device reported that the destination network or host could not be reached.',
      steps: [
        'Check Wi-Fi or Ethernet.',
        'Check VPN routing if one is in use.',
        'Try another network.',
      ],
    ),
    'certificate' => const DiagnosticFinding(
      'TLS_CERTIFICATE',
      'HTTPS certificate verification failed',
      'The connection could not establish the provider’s identity using the normal certificate trust checks.',
      causes: [
        'An expired, untrusted or mismatched server certificate.',
        'An incorrect device date or time.',
        'A network sign-in page or interception.',
      ],
      steps: [
        'Enable automatic date and time.',
        'Complete Wi-Fi sign-in if required.',
        'Ask the provider to fix its HTTPS certificate. Do not disable certificate checks.',
      ],
    ),
    'tls_handshake' => const DiagnosticFinding(
      'TLS_HANDSHAKE',
      'The HTTPS handshake failed',
      'The client and server could not establish a secure TLS session.',
      causes: [
        'HTTPS is not supported on the configured port.',
        'An incompatible TLS configuration or interrupted connection.',
      ],
      steps: [
        'Use the exact HTTPS address and port supplied by the provider.',
        'Ask the provider to check TLS support.',
      ],
    ),
    'response_too_large' => const DiagnosticFinding(
      'RESPONSE_TOO_LARGE',
      'The API response exceeded the diagnosis limit',
      'Reading stopped at 512 KiB to keep this check bounded. A large valid response may still work in the library.',
      status: DiagnosticStatus.warning,
      steps: [
        'Try opening the library section.',
        'Check the server URL if this should be a small account response.',
      ],
    ),
    'http_protocol' => const DiagnosticFinding(
      'HTTP_PROTOCOL',
      'The server returned an incomplete or invalid HTTP response',
      'The connection ended unexpectedly or the HTTP response could not be read.',
      steps: [
        'Retry once.',
        'Check the server scheme and port.',
        'Contact the provider if it continues.',
      ],
    ),
    'socket' => const DiagnosticFinding(
      'CONNECTION_INTERRUPTED',
      'The network connection failed',
      'The operating system reported a socket failure. The exact cause cannot safely be determined from this error alone.',
      steps: [
        'Check your network and VPN.',
        'Try another network or contact the provider.',
      ],
    ),
    'invalid_json' => const DiagnosticFinding(
      'INVALID_JSON',
      'The API did not return valid JSON',
      'The server responded, but its body was not a valid Xtream JSON response. HTML login pages, incorrect URLs and server errors can cause this.',
      steps: [
        'Check the provider address and path.',
        'Complete any Wi-Fi sign-in.',
        'Ask the provider to verify player_api.php.',
      ],
    ),
    _ => const DiagnosticFinding(
      'CHECK_UNAVAILABLE',
      'This check could not be completed',
      'The diagnosis encountered an unexpected failure. Private native error text has been omitted.',
      steps: ['Run the check again.', 'Restart the app if it persists.'],
    ),
  };
}

class ConnectionDiagnostics {
  ConnectionDiagnostics(this.transport, {DateTime Function()? now})
    : now = now ?? DateTime.now;
  final DiagnosticTransport transport;
  final DateTime Function() now;
  bool _cancelled = false, _used = false;
  void cancel() {
    _cancelled = true;
    transport.close();
  }

  Future<DiagnosticReport> run(
    Credentials credentials, {
    MediaItem? item,
    Episode? episode,
    bool testStream = false,
    bool streamPermitted = false,
    void Function(DiagnosticReport report)? onProgress,
  }) async {
    if (_used) throw StateError('Create a new diagnosis for each run.');
    _used = true;
    final started = now();
    final checks = <DiagnosticCheck>[];
    DiagnosticReport snapshot() => DiagnosticReport(
      started,
      List.unmodifiable(checks),
      cancelled: _cancelled,
    );
    void add(String stage, DiagnosticFinding finding, [int elapsed = 0]) {
      if (_cancelled) return;
      checks.add(DiagnosticCheck(stage, finding, elapsed));
      onProgress?.call(snapshot());
    }

    void skip(String stage, String reason) => add(
      stage,
      DiagnosticFinding(
        'NOT_TESTED',
        'Not tested',
        reason,
        status: DiagnosticStatus.skipped,
      ),
    );
    Future<T?> probe<T>(
      String stage,
      Future<T> Function() action,
      DiagnosticFinding Function(T value) success,
    ) async {
      if (_cancelled) return null;
      final watch = Stopwatch()..start();
      try {
        final value = await action();
        add(stage, success(value), watch.elapsedMilliseconds);
        return value;
      } catch (error) {
        final code = error is ProbeFailure ? error.code : 'unexpected';
        add(stage, diagnosticFailure(code), watch.elapsedMilliseconds);
        return null;
      }
    }

    dynamic json(ProbeResponse response) {
      try {
        var body = utf8.decode(response.bytes);
        if (body.startsWith('\uFEFF')) body = body.substring(1);
        return jsonDecode(body);
      } catch (_) {
        throw const ProbeFailure('invalid_json');
      }
    }

    bool httpOk(ProbeResponse r) => r.status >= 200 && r.status < 300;
    Future<void> perform() async {
      final network = await probe('network', transport.network, (n) {
        final detail = [
          if (n.transports.isNotEmpty)
            'Connection: ${n.transports.join(', ')}.',
          n.vpn == null
              ? 'VPN status unavailable.'
              : n.vpn!
              ? 'Android reports a VPN on the active network; this does not verify its routing or protection.'
              : 'No VPN reported on the active network.',
          n.privateDns == null
              ? 'Private DNS status unavailable on this device.'
              : n.privateDns!
              ? 'Android reports Private DNS active; this does not hide the stream server IP.'
              : 'Android does not report Private DNS active.',
          if (n.metered == true) 'This connection is metered.',
        ].join(' ');
        if (n.connected == false) {
          return DiagnosticFinding(
            'DEVICE_OFFLINE',
            'No active network',
            'Android reports no active network. $detail',
            steps: const [
              'Reconnect Wi-Fi or Ethernet, or enable mobile data.',
              'Run diagnosis again after reconnecting.',
            ],
          );
        }
        if (n.captivePortal) {
          return DiagnosticFinding(
            'NETWORK_SIGN_IN',
            'This network needs sign-in',
            'Android detected a captive portal. $detail',
            steps: const [
              'Open Android network settings and complete Wi-Fi sign-in.',
            ],
          );
        }
        return DiagnosticFinding(
          n.validated == true ? 'NETWORK_VALIDATED' : 'NETWORK_UNCONFIRMED',
          n.validated == true
              ? 'Android reports internet access'
              : 'Internet access is not confirmed by Android',
          '$detail Network validation is a system snapshot, not a guarantee that this provider is reachable. Provider tests continue separately.',
          status: n.validated == true
              ? DiagnosticStatus.passed
              : DiagnosticStatus.warning,
          steps: n.validated == true
              ? const []
              : const ['Check Wi-Fi sign-in if provider tests also fail.'],
        );
      });
      Uri base;
      try {
        base = normalizeServerUri(credentials.serverUrl);
        add(
          'server',
          DiagnosticFinding(
            'SERVER_VALID',
            'Server address is valid',
            'An ${base.scheme.toUpperCase()} address with a valid host was supplied. Its spelling and ownership are not verified by syntax checks.',
            status: DiagnosticStatus.passed,
          ),
        );
      } catch (_) {
        add(
          'server',
          const DiagnosticFinding(
            'SERVER_INVALID',
            'The server address is invalid',
            'Use the HTTP or HTTPS server URL supplied by your provider, including its port and path when required.',
            steps: [
              'Check the address for spaces, missing hostname or an unsupported scheme.',
            ],
          ),
        );
        return;
      }
      if (network?.connected == false || network?.captivePortal == true) return;
      final literal = InternetAddress.tryParse(base.host);
      List<InternetAddress>? addresses;
      if (literal != null) {
        addresses = [literal];
        add(
          'dns',
          const DiagnosticFinding(
            'DNS_NOT_REQUIRED',
            'The server uses a numeric IP address',
            'No hostname lookup is needed. Changing DNS will not change the destination IP.',
            status: DiagnosticStatus.passed,
          ),
        );
      } else {
        addresses = await probe('dns', () => transport.lookup(base.host), (
          list,
        ) {
          if (list.isEmpty) return diagnosticFailure('dns_failed');
          final v4 = list
              .where((a) => a.type == InternetAddressType.IPv4)
              .length;
          final v6 = list
              .where((a) => a.type == InternetAddressType.IPv6)
              .length;
          return DiagnosticFinding(
            'DNS_RESOLVED',
            'The provider hostname resolved',
            '$v4 IPv4 and $v6 IPv6 address(es) returned by the system resolver. Resolution does not verify ownership or rule out filtering later in the connection.',
            status: DiagnosticStatus.passed,
          );
        });
      }
      if (addresses == null || addresses.isEmpty || _cancelled) return;
      final tcp = await probe(
        'tcp',
        () async {
          await transport.connect(base.host, base.port);
          return true;
        },
        (_) => const DiagnosticFinding(
          'TCP_CONNECTED',
          'The server accepted a connection',
          'A TCP connection succeeded on the configured port. This does not yet verify the API, account or video stream.',
          status: DiagnosticStatus.passed,
        ),
      );
      if (base.scheme == 'https') {
        if (tcp == null) {
          skip(
            'tls',
            'The TCP connection did not succeed. The API request will still be attempted independently.',
          );
        } else {
          await probe(
            'tls',
            () async {
              await transport.tls(base.host, base.port);
              return true;
            },
            (_) => const DiagnosticFinding(
              'TLS_VERIFIED',
              'HTTPS certificate verification passed',
              'The TLS handshake passed normal system certificate verification for the configured hostname. This test never accepts an invalid certificate.',
              status: DiagnosticStatus.passed,
            ),
          );
        }
      } else {
        add(
          'tls',
          const DiagnosticFinding(
            'HTTP_UNENCRYPTED',
            'This provider connection uses HTTP',
            'The configured API and generated stream URLs use unencrypted HTTP. This diagnosis will use the same address; it will not guess another port or change your provider.',
            status: DiagnosticStatus.warning,
            steps: [
              'Ask the provider for a supported HTTPS URL. HTTPS does not hide the destination IP.',
            ],
          ),
        );
      }
      if (_cancelled) return;
      if (credentials.username.trim().isEmpty || credentials.password.isEmpty) {
        skip(
          'api',
          'Enter a username and password to test the provider API and account.',
        );
        return;
      }
      Uri endpoint([String? action]) => base.replace(
        pathSegments: [
          ...base.pathSegments.where((s) => s.isNotEmpty),
          'player_api.php',
        ],
        queryParameters: {
          'username': credentials.username.trim(),
          'password': credentials.password,
          if (action != null) 'action': action,
        },
      );
      Map<String, dynamic>? payload;
      final response = await probe('api', () => transport.get(endpoint()), (r) {
        if (!httpOk(r)) return diagnosticFailure('http', httpStatus: r.status);
        final decoded = json(r);
        if (decoded is! Map || decoded['user_info'] is! Map) {
          return const DiagnosticFinding(
            'API_FORMAT',
            'The response is not an Xtream account',
            'Valid JSON was received, but it does not contain the expected user_info account object.',
            steps: [
              'Check the server URL.',
              'Confirm Xtream Codes support with the provider.',
            ],
          );
        }
        payload = objectValue(decoded);
        return const DiagnosticFinding(
          'API_RESPONDED',
          'The Xtream API responded',
          'A valid account-response structure was returned. Account authorization is checked separately below.',
          status: DiagnosticStatus.passed,
        );
      });
      if (response == null || payload == null || _cancelled) return;
      final user = objectValue(payload!['user_info']);
      final authorized = user['auth'] == true || textValue(user['auth']) == '1';
      final status = textValue(user['status']).toLowerCase();
      final expiry = intValue(user['exp_date']);
      var usable = authorized && (status.isEmpty || status == 'active');
      if (!authorized) {
        add(
          'account',
          const DiagnosticFinding(
            'ACCOUNT_DENIED',
            'The provider did not authorize this account',
            'The API returned auth=0 or did not report successful authorization. This alone cannot distinguish incorrect credentials from another account restriction.',
            steps: [
              'Re-enter your username and password.',
              'Ask the provider to confirm the account is enabled.',
            ],
          ),
        );
      } else if (expiry > 0 && expiry <= now().millisecondsSinceEpoch ~/ 1000) {
        usable = false;
        add(
          'account',
          const DiagnosticFinding(
            'ACCOUNT_EXPIRED',
            'The reported subscription has expired',
            'The provider expiry timestamp is in the past according to this device’s clock. An incorrect device clock can affect this result.',
            steps: [
              'Enable automatic date and time.',
              'Renew or confirm the expiry with your provider.',
            ],
          ),
        );
      } else if (status.isNotEmpty && status != 'active') {
        add(
          'account',
          const DiagnosticFinding(
            'ACCOUNT_INACTIVE',
            'The provider reports an inactive account',
            'Authorization succeeded, but the reported status is not Active. The provider may have suspended, disabled or expired the subscription.',
            steps: ['Contact the provider to confirm account status.'],
          ),
        );
      } else {
        final soon =
            expiry > 0 &&
            expiry - now().millisecondsSinceEpoch ~/ 1000 <= 7 * 86400;
        add(
          'account',
          DiagnosticFinding(
            soon ? 'ACCOUNT_EXPIRING' : 'ACCOUNT_ACTIVE',
            soon
                ? 'The subscription expires within seven days'
                : 'Account authorization passed',
            '${status.isEmpty ? 'The provider did not supply a status label.' : 'The provider reports Active.'} ${expiry <= 0 ? 'No usable expiry date was supplied; this does not confirm a lifetime subscription.' : 'An expiry timestamp was supplied.'}',
            status: soon || status.isEmpty
                ? DiagnosticStatus.warning
                : DiagnosticStatus.passed,
            steps: soon
                ? const [
                    'Check the expiry date in Settings and arrange renewal if required.',
                  ]
                : const [],
          ),
        );
      }
      final active = int.tryParse(textValue(user['active_cons']));
      final max = int.tryParse(textValue(user['max_connections']));
      final limitReached =
          active != null &&
          active >= 0 &&
          max != null &&
          max > 0 &&
          active >= max;
      add(
        'limits',
        DiagnosticFinding(
          limitReached ? 'LIMIT_REACHED' : 'LIMIT_CHECK',
          limitReached
              ? 'The reported connection allowance is in use'
              : 'Connection allowance checked',
          active == null || active < 0 || max == null || max <= 0
              ? 'The provider did not supply a usable finite allowance and active count. A missing or zero maximum is not treated as a confirmed limit.'
              : 'The provider reports $active active connection(s) out of $max. Counts may lag after closing a stream.',
          status:
              limitReached ||
                  active == null ||
                  active < 0 ||
                  max == null ||
                  max <= 0
              ? DiagnosticStatus.warning
              : DiagnosticStatus.passed,
          steps: limitReached
              ? const [
                  'Close other players/devices using this account.',
                  'Wait for the provider’s count to update, then retry.',
                ]
              : const [],
        ),
      );
      final server = objectValue(payload!['server_info']);
      final serverTime = intValue(server['timestamp_now']);
      if (serverTime > 0) {
        final difference = (now().millisecondsSinceEpoch ~/ 1000 - serverTime)
            .abs();
        add(
          'clock',
          DiagnosticFinding(
            difference > 900 ? 'CLOCK_DIFFERENCE' : 'CLOCK_CLOSE',
            difference > 900
                ? 'Device and provider clocks differ by over 15 minutes'
                : 'Device and provider clocks are close',
            'This compares a provider timestamp to the device clock. The provider timestamp may itself be inaccurate or stale; this does not independently verify either clock.',
            status: difference > 900
                ? DiagnosticStatus.warning
                : DiagnosticStatus.passed,
            steps: difference > 900
                ? const [
                    'Enable automatic date and time.',
                    'Ask the provider to check its clock if yours is correct.',
                  ]
                : const [],
          ),
        );
      } else {
        skip('clock', 'No usable server timestamp was supplied.');
      }
      if (!usable || _cancelled) return;
      for (final entry in const {
        'live': 'get_live_categories',
        'movies': 'get_vod_categories',
        'series': 'get_series_categories',
      }.entries) {
        if (_cancelled) break;
        await probe(entry.key, () => transport.get(endpoint(entry.value)), (r) {
          if (!httpOk(r)) {
            return diagnosticFailure('http', httpStatus: r.status);
          }
          final decoded = json(r);
          if (decoded is Map && decoded.containsKey('error')) {
            return const DiagnosticFinding(
              'LIBRARY_DENIED',
              'The provider could not return this listing',
              'The response contains a provider error. Its private text is omitted; this section may be unavailable or not included in the account.',
              steps: [
                'Ask the provider to confirm access to this library section.',
              ],
            );
          }
          final valid = decoded is List
              ? decoded.every((v) => v is Map)
              : decoded is Map && decoded.values.every((v) => v is Map);
          if (!valid) {
            return const DiagnosticFinding(
              'LIBRARY_FORMAT',
              'The listing response is not supported',
              'The endpoint responded, but did not return a category collection. This section may be unsupported or denied by the provider.',
              steps: [
                'Ask the provider whether this library section is included.',
              ],
            );
          }
          final length = decoded is List
              ? decoded.length
              : (decoded as Map).length;
          return DiagnosticFinding(
            length == 0 ? 'LIBRARY_EMPTY' : 'LIBRARY_READY',
            length == 0
                ? 'The provider returned no categories'
                : 'Category listing responded',
            '$length category record(s) received. This checks the listing endpoint, not every channel or title.',
            status: length == 0
                ? DiagnosticStatus.warning
                : DiagnosticStatus.passed,
            steps: length == 0
                ? const ['Confirm the subscription includes this section.']
                : const [],
          );
        });
      }
      if (!testStream) {
        skip(
          'stream',
          'Stream testing is optional and was not requested. No video stream was opened.',
        );
      } else if (!streamPermitted || item == null) {
        skip(
          'stream',
          'No authorized selected title was supplied. Choose a channel or title from the player to test delivery.',
        );
      } else if (limitReached) {
        skip(
          'stream',
          'The reported connection allowance is already in use. Close other sessions before testing.',
        );
      } else if (!_cancelled) {
        Uri? uri;
        try {
          final api = XtreamApi();
          try {
            uri = api.streamUri(
              Session(
                credentials: credentials,
                userInfo: user,
                serverInfo: server,
              ),
              item,
              episode: episode,
            );
          } finally {
            api.dispose();
          }
        } catch (_) {
          add(
            'stream',
            const DiagnosticFinding(
              'STREAM_ADDRESS',
              'No playable stream address is available',
              'An episode or stream identifier is missing. Select an episode for series playback.',
              steps: ['Refresh the library and select a playable title.'],
            ),
          );
        }
        if (uri != null) {
          await probe('stream', () => transport.get(uri!, stream: true), (r) {
            if (!httpOk(r)) {
              return diagnosticFailure('http', httpStatus: r.status);
            }
            if (r.bytes.isEmpty) {
              return const DiagnosticFinding(
                'STREAM_EMPTY',
                'The stream returned no data',
                'A successful HTTP response contained no sample data. The source may be offline or the provider may have ended the connection.',
                steps: [
                  'Try another channel or title.',
                  'Contact the provider.',
                ],
              );
            }
            final sample = utf8
                .decode(r.bytes.take(4096).toList(), allowMalformed: true)
                .trimLeft()
                .toLowerCase();
            if (sample.startsWith('<!doctype html') ||
                sample.startsWith('<html') ||
                r.contentType == 'text/html' ||
                sample.startsWith('{')) {
              return const DiagnosticFinding(
                'STREAM_NOT_VIDEO',
                'The stream returned a page or error response',
                'The sample resembles HTML or JSON rather than video or an HLS playlist. Private server response text has been omitted.',
                steps: [
                  'Check account and connection limits.',
                  'Try another channel.',
                  'Ask the provider to check the source.',
                ],
              );
            }
            final hls =
                uri!.path.toLowerCase().endsWith('.m3u8') ||
                r.contentType.contains('mpegurl');
            if (hls &&
                !sample
                    .replaceFirst('\ufeff', '')
                    .trimLeft()
                    .startsWith('#extm3u')) {
              return const DiagnosticFinding(
                'HLS_INVALID',
                'The HLS playlist header is missing',
                'The selected URL indicates HLS, but the returned sample does not start with #EXTM3U.',
                steps: [
                  'Refresh the channel and try again.',
                  'Ask the provider to verify the playlist.',
                ],
              );
            }
            return DiagnosticFinding(
              'STREAM_SAMPLE_RECEIVED',
              hls ? 'An HLS playlist sample arrived' : 'Stream data arrived',
              'Received ${r.bytes.length} byte(s), capped at 64 KiB. ${hls ? 'Playlist segments were not fetched.' : 'The sample was not decoded.'} This is not a bandwidth, codec, audio, subtitle or sustained-playback test. Playback can still fail after this check.',
              status: DiagnosticStatus.passed,
              steps: const [
                'If playback still fails, try the other player in Settings and inspect Playback diagnostics.',
              ],
            );
          });
        }
      }
      return;
    }

    try {
      await perform();
    } finally {
      transport.close();
      // A prerequisite failure must never make downstream checks look passed.
      for (final stage in diagnosticStages.keys) {
        if (!checks.any((c) => c.stage == stage)) {
          checks.add(
            DiagnosticCheck(
              stage,
              DiagnosticFinding(
                'NOT_TESTED',
                'Not tested',
                _cancelled
                    ? 'Diagnosis was stopped before this stage completed.'
                    : 'A prerequisite did not complete successfully or this stage was not requested.',
                status: DiagnosticStatus.skipped,
              ),
              0,
            ),
          );
        }
      }
      onProgress?.call(snapshot());
    }
    return snapshot();
  }
}
