import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:streamline_iptv/data/connection_diagnostics.dart';
import 'package:streamline_iptv/data/diagnostic_transport.dart';
import 'package:streamline_iptv/data/dns_lookup.dart';
import 'package:streamline_iptv/data/models.dart';

const credentials = Credentials(
  serverUrl: 'https://private-provider.example:8443/portal',
  username: 'private-user+&',
  password: 'private-pass?&/',
);
const channel = MediaItem(
  id: 'private-channel',
  name: 'Private title',
  kind: MediaKind.live,
  containerExtension: 'm3u8',
);
final now = DateTime.utc(2026, 10, 22, 12);

class FakeDiagnosticTransport implements DiagnosticTransport {
  DeviceNetwork device = const DeviceNetwork(
    connected: true,
    validated: true,
    vpn: false,
    privateDns: true,
    transports: ['Wi-Fi'],
  );
  final failures = <String, String>{};
  final calls = <String>[];
  final uris = <Uri>[];
  bool closed = false;
  Completer<void>? dnsGate;
  DnsLookupResult? dnsResult;
  Map<String, dynamic> user = {
    'auth': 1,
    'status': 'Active',
    'active_cons': '0',
    'max_connections': '1',
    'exp_date':
        now.add(const Duration(days: 30)).millisecondsSinceEpoch ~/ 1000,
  };
  int httpStatus = 200;
  String? apiBody;
  String categoryBody =
      '[{"category_id":"1","category_name":"Private category"}]';
  ProbeResponse sample = ProbeResponse(
    200,
    utf8.encode('#EXTM3U\n#EXTINF:6,\nsegment.ts\n'),
    contentType: 'application/vnd.apple.mpegurl',
  );
  void check(String stage) {
    calls.add(stage);
    if (failures[stage] != null) throw ProbeFailure(failures[stage]!);
  }

  @override
  Future<DeviceNetwork> network() async {
    check('network');
    return device;
  }

  @override
  Future<DnsLookupResult> lookup(String host) async {
    check('dns');
    await dnsGate?.future;
    return dnsResult ??
        DnsLookupResult([InternetAddress('127.0.0.1'), InternetAddress('::1')]);
  }

  @override
  Future<void> connect(String host, int port) async {
    check('tcp');
  }

  @override
  Future<void> tls(String host, int port) async {
    check('tls');
  }

  @override
  Future<ProbeResponse> get(Uri uri, {bool stream = false}) async {
    uris.add(uri);
    check(stream ? 'stream' : uri.queryParameters['action'] ?? 'api');
    if (stream) return sample;
    if (uri.queryParameters.containsKey('action')) {
      return ProbeResponse(200, utf8.encode(categoryBody));
    }
    return ProbeResponse(
      httpStatus,
      utf8.encode(
        apiBody ??
            jsonEncode({
              'user_info': user,
              'server_info': {
                'timestamp_now': now.millisecondsSinceEpoch ~/ 1000,
              },
            }),
      ),
    );
  }

  @override
  void close() {
    closed = true;
  }
}

DiagnosticCheck at(DiagnosticReport report, String stage) =>
    report.checks.singleWhere((c) => c.stage == stage);

Future<DiagnosticReport> diagnose(
  FakeDiagnosticTransport transport, {
  Credentials input = credentials,
  bool stream = false,
  bool permitted = true,
}) => ConnectionDiagnostics(
  transport,
  now: () => now,
).run(input, item: channel, testStream: stream, streamPermitted: permitted);

void main() {
  test(
    'complete diagnosis separates transport, account, allowance and all category endpoints without opening video',
    () async {
      final t = FakeDiagnosticTransport();
      final r = await diagnose(t);
      expect(r.checks.length, diagnosticStages.length);
      expect(r.failed, 0);
      expect(r.warnings, 0);
      expect(at(r, 'stream').finding.status, DiagnosticStatus.skipped);
      expect(at(r, 'dns').finding.description, contains('1 IPv4 and 1 IPv6'));
      expect(t.calls, [
        'network',
        'dns',
        'tcp',
        'tls',
        'api',
        'get_live_categories',
        'get_vod_categories',
        'get_series_categories',
      ]);
      expect(t.uris.first.path, '/portal/player_api.php');
      expect(t.uris.first.queryParameters['password'], credentials.password);
      expect(t.closed, true);
    },
  );

  test(
    'report omits identifiers, credentials and untrusted provider fields',
    () async {
      final t = FakeDiagnosticTransport();
      t.user['status'] = 'private-pass?&/';
      t.user['message'] =
          'https://private-provider.example/secret?password=private-pass';
      final text = (await diagnose(t)).toText();
      for (final secret in [
        'private-user',
        'private-pass',
        'private-provider',
        'Private title',
        'Private category',
        'private-channel',
        'player_api.php?',
      ]) {
        expect(text, isNot(contains(secret)), reason: secret);
      }
      expect(text, contains('ACCOUNT_INACTIVE'));
    },
  );

  test('invalid URL marks all unperformed stages skipped', () async {
    final t = FakeDiagnosticTransport();
    final r = await diagnose(
      t,
      input: const Credentials(
        serverUrl: 'ftp://wrong',
        username: 'u',
        password: 'p',
      ),
    );
    expect(at(r, 'server').finding.code, 'SERVER_INVALID');
    expect(at(r, 'account').finding.status, DiagnosticStatus.skipped);
    expect(r.checks.length, diagnosticStages.length);
    expect(t.calls, ['network']);
    expect(t.closed, true);
  });

  for (final captive in [false, true]) {
    test(
      captive
          ? 'captive portal skips credentials and downstream requests'
          : 'offline device skips provider requests',
      () async {
        final t = FakeDiagnosticTransport()
          ..device = DeviceNetwork(connected: captive, captivePortal: captive);
        final r = await diagnose(t);
        expect(
          at(r, 'network').finding.code,
          captive ? 'NETWORK_SIGN_IN' : 'DEVICE_OFFLINE',
        );
        expect(t.uris, isEmpty);
        expect(at(r, 'api').finding.status, DiagnosticStatus.skipped);
      },
    );
  }

  test(
    'unavailable Android state warns but provider probes still run',
    () async {
      final t = FakeDiagnosticTransport()..device = const DeviceNetwork();
      final r = await diagnose(t);
      expect(at(r, 'network').finding.status, DiagnosticStatus.warning);
      expect(at(r, 'account').finding.code, 'ACCOUNT_ACTIVE');
    },
  );

  for (final error in ['dns_failed', 'dns_timeout']) {
    test('$error stops downstream probes and explains DNS limits', () async {
      final t = FakeDiagnosticTransport()..failures['dns'] = error;
      final r = await diagnose(t);
      expect(at(r, 'dns').finding.status, DiagnosticStatus.failed);
      expect(at(r, 'tcp').finding.status, DiagnosticStatus.skipped);
      expect(t.uris, isEmpty);
      expect(r.checks.length, diagnosticStages.length);
    });
  }

  test(
    'numeric addresses bypass DNS and HTTP is explicitly unencrypted',
    () async {
      final t = FakeDiagnosticTransport();
      final r = await diagnose(
        t,
        input: const Credentials(
          serverUrl: 'http://127.0.0.1:8080',
          username: 'u',
          password: 'p',
        ),
      );
      expect(t.calls, isNot(contains('dns')));
      expect(t.calls, isNot(contains('tls')));
      expect(at(r, 'dns').finding.code, 'DNS_NOT_REQUIRED');
      expect(at(r, 'tls').finding.code, 'HTTP_UNENCRYPTED');
    },
  );

  test(
    'refused TCP is not labelled an ISP block and HTTP can succeed independently',
    () async {
      final t = FakeDiagnosticTransport()..failures['tcp'] = 'refused';
      final r = await diagnose(t);
      expect(at(r, 'tcp').finding.code, 'CONNECTION_REFUSED');
      expect(at(r, 'tls').finding.status, DiagnosticStatus.skipped);
      expect(at(r, 'api').finding.code, 'API_RESPONDED');
      expect(r.toText(), contains('does not prove ISP blocking'));
    },
  );

  test(
    'certificate failure advises date/time and certificate repair, without bypass',
    () async {
      final t = FakeDiagnosticTransport()..failures['tls'] = 'certificate';
      final r = await diagnose(t);
      expect(at(r, 'tls').finding.code, 'TLS_CERTIFICATE');
      expect(
        at(r, 'tls').finding.steps.join(' '),
        contains('Do not disable certificate checks'),
      );
    },
  );

  for (final status in [
    301,
    401,
    403,
    404,
    405,
    408,
    410,
    416,
    429,
    500,
    503,
    504,
  ]) {
    test(
      'HTTP $status has a specific safe explanation and stops account inference',
      () async {
        final t = FakeDiagnosticTransport()..httpStatus = status;
        final r = await diagnose(t);
        expect(at(r, 'api').finding.description, isNotEmpty);
        expect(at(r, 'api').finding.steps, isNotEmpty);
        expect(at(r, 'api').finding.code, isNot('CHECK_UNAVAILABLE'));
        expect(at(r, 'account').finding.status, DiagnosticStatus.skipped);
        expect(t.uris.length, 1);
      },
    );
  }

  for (final body in [
    '<html>private-pass</html>',
    '{oops',
    '[]',
    '{"hello":"private-pass"}',
  ]) {
    test(
      'malformed or wrong API body is described without echoing it: ${body.length}',
      () async {
        final t = FakeDiagnosticTransport()..apiBody = body;
        final r = await diagnose(t);
        expect(at(r, 'api').finding.status, DiagnosticStatus.failed);
        expect(r.toText(), isNot(contains('private-pass')));
        expect(at(r, 'account').finding.status, DiagnosticStatus.skipped);
      },
    );
  }

  for (final state in ['denied', 'expired', 'disabled']) {
    test('$state account does not issue library or stream requests', () async {
      final t = FakeDiagnosticTransport();
      if (state == 'denied') t.user['auth'] = 0;
      if (state == 'expired') {
        t.user['exp_date'] =
            now.subtract(const Duration(days: 1)).millisecondsSinceEpoch ~/
            1000;
      }
      if (state == 'disabled') t.user['status'] = 'Disabled';
      final r = await diagnose(t, stream: true);
      expect(at(r, 'account').finding.status, DiagnosticStatus.failed);
      expect(at(r, 'live').finding.status, DiagnosticStatus.skipped);
      expect(t.calls, isNot(contains('stream')));
    });
  }

  test(
    'reported allowance in use skips optional stream instead of opening another session',
    () async {
      final t = FakeDiagnosticTransport()..user['active_cons'] = '1';
      final r = await diagnose(t, stream: true);
      expect(at(r, 'limits').finding.code, 'LIMIT_REACHED');
      expect(at(r, 'stream').finding.status, DiagnosticStatus.skipped);
      expect(t.calls, isNot(contains('stream')));
    },
  );

  test('missing allowance is not invented as a finite limit', () async {
    final t = FakeDiagnosticTransport()..user.remove('max_connections');
    final r = await diagnose(t, stream: true);
    expect(at(r, 'limits').finding.status, DiagnosticStatus.warning);
    expect(at(r, 'stream').finding.code, 'STREAM_SAMPLE_RECEIVED');
  });

  test(
    'library failures remain separate and other sections continue',
    () async {
      final t = FakeDiagnosticTransport()
        ..failures['get_live_categories'] = 'timeout';
      final r = await diagnose(t);
      expect(at(r, 'live').finding.code, 'CONNECTION_TIMEOUT');
      expect(at(r, 'movies').finding.code, 'LIBRARY_READY');
      expect(at(r, 'series').finding.code, 'LIBRARY_READY');
    },
  );

  test('empty categories warn and do not claim every title works', () async {
    final t = FakeDiagnosticTransport()..categoryBody = '[]';
    final r = await diagnose(t);
    expect(at(r, 'movies').finding.code, 'LIBRARY_EMPTY');
    expect(at(r, 'movies').finding.status, DiagnosticStatus.warning);
  });

  test('protected or unauthorized selected title cannot be probed', () async {
    final t = FakeDiagnosticTransport();
    final r = await diagnose(t, stream: true, permitted: false);
    expect(at(r, 'stream').finding.status, DiagnosticStatus.skipped);
    expect(t.calls, isNot(contains('stream')));
  });

  test(
    'valid HLS sample explicitly excludes segment, codec and speed guarantees',
    () async {
      final t = FakeDiagnosticTransport();
      final r = await diagnose(t, stream: true);
      expect(at(r, 'stream').finding.code, 'STREAM_SAMPLE_RECEIVED');
      expect(
        at(r, 'stream').finding.description,
        contains('Playlist segments were not fetched'),
      );
      expect(at(r, 'stream').finding.description, contains('not a bandwidth'));
      expect(t.calls.where((c) => c == 'stream').length, 1);
    },
  );

  for (final body in [
    '',
    '<html>private-pass</html>',
    '{"error":"private-pass"}',
    'not an hls playlist',
  ]) {
    test(
      'bad stream sample receives safe delivery explanation: ${body.length}',
      () async {
        final t = FakeDiagnosticTransport()
          ..sample = ProbeResponse(200, utf8.encode(body));
        final r = await diagnose(t, stream: true);
        expect(at(r, 'stream').finding.status, DiagnosticStatus.failed);
        expect(r.toText(), isNot(contains('private-pass')));
      },
    );
  }

  test(
    'cancellation prevents subsequent credential requests and fills skipped stages',
    () async {
      final gate = Completer<void>();
      final t = FakeDiagnosticTransport()..dnsGate = gate;
      final runner = ConnectionDiagnostics(t, now: () => now);
      final future = runner.run(credentials);
      await Future<void>.delayed(Duration.zero);
      expect(t.calls, contains('dns'));
      runner.cancel();
      gate.complete();
      final r = await future;
      expect(r.cancelled, true);
      expect(t.uris, isEmpty);
      expect(r.checks.length, diagnosticStages.length);
      expect(at(r, 'api').finding.status, DiagnosticStatus.skipped);
      expect(t.closed, true);
    },
  );

  test('all low-level failure types provide actionable safe descriptions', () {
    for (final code in [
      'dns_failed',
      'dns_timeout',
      'timeout',
      'refused',
      'unreachable',
      'certificate',
      'tls_handshake',
      'response_too_large',
      'http_protocol',
      'socket',
      'unexpected-secret',
    ]) {
      final f = diagnosticFailure(code);
      expect(f.description, isNotEmpty);
      expect(f.steps, isNotEmpty);
      expect(f.description, isNot(contains('unexpected-secret')));
    }
  });
}
