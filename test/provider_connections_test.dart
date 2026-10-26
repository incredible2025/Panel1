import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:streamline_iptv/core/provider_config.dart';
import 'package:streamline_iptv/data/models.dart';
import 'package:streamline_iptv/data/provider_connections.dart';
import 'package:streamline_iptv/data/xtream_api.dart';
import 'package:streamline_iptv/data/connection_diagnostics.dart';
import 'package:streamline_iptv/data/diagnostic_transport.dart';
import 'connection_diagnostics_test.dart' show FakeDiagnosticTransport;

class _RouteDiagnosticTransport extends FakeDiagnosticTransport {
  String? secureConnectError, secureTlsError, secureApiError;
  final ports = <int>[];
  @override
  Future<void> connect(String host, int port) async {
    ports.add(port);
    if (port == 443 && secureConnectError != null) {
      throw ProbeFailure(secureConnectError!);
    }
    await super.connect(host, port);
  }

  @override
  Future<void> tls(String host, int port) async {
    if (secureTlsError != null) throw ProbeFailure(secureTlsError!);
    await super.tls(host, port);
  }

  @override
  Future<ProbeResponse> get(Uri uri, {bool stream = false}) async {
    if (uri.scheme == 'https' && secureApiError != null) {
      throw ProbeFailure(secureApiError!);
    }
    return super.get(uri, stream: stream);
  }
}

const _live = MediaItem(id: '1', name: 'Live', kind: MediaKind.live);
final _credentials = portalCredentials('viewer', 'ssl-private-password');
Session _session() => Session(
  credentials: _credentials,
  userInfo: const {'auth': 1, 'status': 'Active'},
  serverInfo: const {},
);
http.Response _authorized() => http.Response(
  jsonEncode({
    'user_info': {'auth': 1, 'status': 'Active'},
    'server_info': {},
  }),
  200,
);

void main() {
  test(
    'diagnosis records the failed secure route and uses a reachable fallback for API and stream',
    () async {
      final transport = _RouteDiagnosticTransport()
        ..secureConnectError = 'refused';
      final report = await ConnectionDiagnostics(
        transport,
      ).run(_credentials, item: _live, testStream: true, streamPermitted: true);
      expect(transport.ports, [443, 80]);
      expect(
        report.checks.any((c) => c.finding.code == 'HTTP_FALLBACK_REACHABLE'),
        true,
      );
      expect(transport.uris.every((u) => u.scheme == 'http'), true);
      final text = report.toText();
      expect(text, contains('HTTP_FALLBACK_REACHABLE'));
      expect(text, isNot(contains(Uri.parse(providerPortalUrl).host)));
      expect(text, isNot(contains(_credentials.password)));
    },
  );
  test(
    'diagnosis never downgrades after a certificate failure, even if the API later times out',
    () async {
      final transport = _RouteDiagnosticTransport()
        ..secureTlsError = 'certificate'
        ..secureApiError = 'timeout';
      final report = await ConnectionDiagnostics(transport).run(_credentials);
      expect(transport.ports, [443]);
      expect(
        report.checks.singleWhere((c) => c.stage == 'fallback').finding.status,
        DiagnosticStatus.skipped,
      );
    },
  );
  test(
    'diagnosis retries a transport timeout but never an account refusal',
    () async {
      final transport = _RouteDiagnosticTransport()..secureApiError = 'timeout';
      final report = await ConnectionDiagnostics(transport).run(_credentials);
      expect(
        report.checks.any((c) => c.finding.code == 'HTTP_FALLBACK_REACHABLE'),
        true,
      );
      expect(transport.uris.every((u) => u.scheme == 'http'), true);
      final denied = _RouteDiagnosticTransport()..httpStatus = 401;
      final failure = await ConnectionDiagnostics(denied).run(_credentials);
      expect(
        failure.checks.singleWhere((c) => c.stage == 'fallback').finding.status,
        DiagnosticStatus.skipped,
      );
      expect(denied.uris.single.scheme, 'https');
    },
  );
  test(
    'media preflight requests headers only and leaves HTTP status handling to the player',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final methods = <String>[];
      final listener = server.listen((request) async {
        methods.add(request.method);
        request.response.statusCode = 405;
        await request.response.close();
      });
      try {
        await probeProviderStream(
          Uri.parse('http://127.0.0.1:${server.port}/live/demo/demo/1.ts'),
        );
        expect(methods, ['HEAD']);
      } finally {
        await listener.cancel();
        await server.close(force: true);
      }
    },
  );
  test(
    'HTTPS is preferred, connection refusal falls back once and retains the account key',
    () async {
      final calls = <Uri>[];
      final api = XtreamApi(
        client: MockClient((r) async {
          calls.add(r.url);
          if (r.url.scheme == 'https') {
            throw const SocketException('Connection refused');
          }
          return r.url.queryParameters.containsKey('action')
              ? http.Response('[]', 200)
              : _authorized();
        }),
      );
      addTearDown(api.dispose);
      final session = await api.authenticate(_credentials);
      expect(calls.map((u) => u.scheme), ['https', 'http']);
      expect(session.credentials.serverUrl, providerPortalUrl);
      expect(session.accountId, _session().accountId);
      await api.items(session, MediaKind.movie);
      expect(calls.last.scheme, 'http');
      expect(calls.last.queryParameters['password'], _credentials.password);
      api.resetConnectionPreferences();
      await api.items(session, MediaKind.live);
      expect(calls.skip(3).map((u) => u.scheme), ['https', 'http']);
    },
  );

  test('timed out API attempt has a bounded fallback', () async {
    final calls = <String>[];
    final api = XtreamApi(
      connectionTimeout: const Duration(milliseconds: 15),
      client: MockClient((r) async {
        calls.add(r.url.scheme);
        if (r.url.scheme == 'https') {
          await Future<void>.delayed(const Duration(milliseconds: 40));
        }
        return _authorized();
      }),
    );
    addTearDown(api.dispose);
    await api.authenticate(_credentials);
    expect(calls, ['https', 'http']);
    await Future<void>.delayed(const Duration(milliseconds: 45));
  });

  for (final error in [
    const HandshakeException('CERTIFICATE_VERIFY_FAILED'),
    const SocketException('Failed host lookup: private hostname'),
    http.ClientException('TLS certificate error'),
  ]) {
    test(
      'secure and DNS failures do not expose credentials to a fallback: ${error.runtimeType}',
      () async {
        final calls = <String>[];
        final api = XtreamApi(
          client: MockClient((r) async {
            calls.add(r.url.scheme);
            throw error;
          }),
        );
        addTearDown(api.dispose);
        await expectLater(
          api.authenticate(_credentials),
          throwsA(isA<XtreamApiException>()),
        );
        expect(calls, ['https']);
      },
    );
  }

  for (final status in [401, 403, 404, 429, 500, 502, 503]) {
    test('HTTP response $status is not a transport failure', () async {
      final calls = <String>[];
      final api = XtreamApi(
        client: MockClient((r) async {
          calls.add(r.url.scheme);
          return http.Response('{}', status);
        }),
      );
      addTearDown(api.dispose);
      await expectLater(
        api.authenticate(_credentials),
        throwsA(isA<XtreamApiException>()),
      );
      expect(calls, ['https']);
    });
  }

  for (final body in [
    '{"user_info":{"auth":0}}',
    '{"user_info":{"auth":1,"status":"Disabled"}}',
    '{"user_info":{"auth":1,"status":"Active","exp_date":"1"}}',
    '<html>Sign in</html>',
  ]) {
    test(
      'account and payload errors never trigger a downgrade: $body',
      () async {
        final calls = <String>[];
        final api = XtreamApi(
          client: MockClient((r) async {
            calls.add(r.url.scheme);
            return http.Response(body, 200);
          }),
        );
        addTearDown(api.dispose);
        await expectLater(
          api.authenticate(_credentials),
          throwsA(isA<XtreamApiException>()),
        );
        expect(calls, ['https']);
      },
    );
  }

  test(
    'playback can use HTTP while the healthy API keeps HTTPS for all media kinds',
    () async {
      final probes = <Uri>[];
      final requests = <Uri>[];
      final api = XtreamApi(
        client: MockClient((r) async {
          requests.add(r.url);
          return _authorized();
        }),
        streamProbe: (uri) async {
          probes.add(uri);
          if (uri.scheme == 'https') {
            throw TimeoutException('Media connection timeout');
          }
        },
      );
      addTearDown(api.dispose);
      final session = await api.authenticate(_credentials);
      for (final kind in MediaKind.values) {
        final uri = await api.prepareStreamUri(
          session,
          MediaItem(id: '4', name: 'Sample', kind: kind),
          episode: kind == MediaKind.series
              ? const Episode(
                  id: '8',
                  title: 'Episode',
                  season: '1',
                  episodeNumber: 1,
                )
              : null,
        );
        expect(uri.scheme, 'http');
        expect(uri.host, Uri.parse(providerFallbackUrl).host);
        expect(uri.pathSegments[1], _credentials.username);
        expect(uri.pathSegments[2], _credentials.password);
      }
      expect(probes.map((u) => u.scheme), ['https', 'http', 'http', 'http']);
      await api.authenticate(_credentials);
      expect(requests.map((u) => u.scheme), ['https', 'https']);
    },
  );

  test('media certificate failure is never retried through HTTP', () async {
    final probes = <String>[];
    final api = XtreamApi(
      streamProbe: (uri) async {
        probes.add(uri.scheme);
        throw const HandshakeException('certificate failure');
      },
    );
    addTearDown(api.dispose);
    await expectLater(
      api.prepareStreamUri(_session(), _live),
      throwsA(isA<HandshakeException>()),
    );
    expect(probes, ['https']);
  });

  test(
    'fallback expires and resets prefer HTTPS without interrupting an existing URI',
    () async {
      var now = DateTime.utc(2026, 10, 26);
      final manager = ProviderConnections(clock: () => now);
      final calls = <String>[];
      Future<String> connect(Uri uri) async {
        calls.add(uri.scheme);
        if (uri.scheme == 'https') {
          throw const SocketException('Connection refused');
        }
        return uri.scheme;
      }

      final base = Uri.parse(providerPortalUrl);
      expect(await manager.run(base, ProviderRoute.api, connect), 'http');
      now = now.add(const Duration(minutes: 2));
      expect(await manager.run(base, ProviderRoute.api, connect), 'http');
      now = now.add(const Duration(minutes: 4));
      expect(await manager.run(base, ProviderRoute.api, connect), 'http');
      expect(calls, ['https', 'http', 'http', 'https', 'http']);
      final selected = manager.preferred(ProviderRoute.playback);
      manager.reset();
      expect(selected.scheme, 'http');
      expect(manager.preferred(ProviderRoute.api).scheme, 'https');
    },
  );

  test(
    'a certificate problem locks out further downgrades until reset',
    () async {
      final manager = ProviderConnections();
      final base = Uri.parse(providerPortalUrl);
      await expectLater(
        manager.run(base, ProviderRoute.api, (uri) async {
          throw const HandshakeException('certificate');
        }),
        throwsA(isA<HandshakeException>()),
      );
      final calls = <String>[];
      await expectLater(
        manager.run(base, ProviderRoute.playback, (uri) async {
          calls.add(uri.scheme);
          throw const SocketException('Connection refused');
        }),
        throwsA(isA<SocketException>()),
      );
      expect(calls, ['https']);
      manager.reset();
      expect(
        await manager.run(base, ProviderRoute.api, (uri) async {
          if (uri.scheme == 'https') {
            throw const SocketException('Connection refused');
          }
          return uri.scheme;
        }),
        'http',
      );
    },
  );

  test(
    'old in-flight successes cannot replace a newer connection selection',
    () async {
      final manager = ProviderConnections();
      final slow = Completer<String>();
      final base = Uri.parse(providerPortalUrl);
      final first = manager.run(base, ProviderRoute.api, (uri) => slow.future);
      await manager.run(base, ProviderRoute.api, (uri) async {
        if (uri.scheme == 'https') {
          throw const SocketException('Connection refused');
        }
        return 'ok';
      });
      slow.complete('older');
      await first;
      expect(manager.preferred(ProviderRoute.api).scheme, 'http');
    },
  );

  test(
    'reset prevents an earlier request from persisting an old preference',
    () async {
      final manager = ProviderConnections();
      final gate = Completer<void>();
      final pending = manager.run(
        Uri.parse(providerPortalUrl),
        ProviderRoute.api,
        (uri) async {
          if (uri.scheme == 'https') {
            throw const SocketException('Connection refused');
          }
          await gate.future;
          return 'ok';
        },
      );
      await Future<void>.delayed(Duration.zero);
      manager.reset();
      gate.complete();
      await pending;
      expect(manager.preferred(ProviderRoute.api).scheme, 'https');
    },
  );

  for (final (index, location) in [
    'http://liquidmetal.vip/player_api.php',
    'https://other.example/player_api.php',
    'https://liquidmetal.vip:8443/player_api.php',
  ].indexed) {
    test(
      'redirect cannot downgrade or forward credentials to an unapproved destination, case $index',
      () async {
        final calls = <Uri>[];
        final api = XtreamApi(
          client: MockClient((r) async {
            calls.add(r.url);
            expect(r.followRedirects, false);
            return http.Response('', 302, headers: {'location': location});
          }),
        );
        addTearDown(api.dispose);
        await expectLater(
          api.authenticate(_credentials),
          throwsA(isA<XtreamApiException>()),
        );
        expect(calls.length, 1);
      },
    );
  }

  test(
    'unrelated providers are never redirected to operator roots or probed',
    () async {
      final calls = <Uri>[];
      final api = XtreamApi(
        client: MockClient((r) async {
          calls.add(r.url);
          return _authorized();
        }),
        streamProbe: (_) async {
          fail('No operator probe for unrelated accounts');
        },
      );
      addTearDown(api.dispose);
      final session = await api.authenticate(
        const Credentials(
          serverUrl: 'https://unrelated.example',
          username: 'user',
          password: 'secret',
        ),
      );
      expect(calls.single.host, 'unrelated.example');
      expect(
        (await api.prepareStreamUri(session, _live)).host,
        'unrelated.example',
      );
    },
  );
}
