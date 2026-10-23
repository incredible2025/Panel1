import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:streamline_iptv/data/diagnostic_transport.dart';
import 'package:streamline_iptv/data/dns_lookup.dart';

class _CertificateFailureClient implements HttpClient {
  @override
  set connectionTimeout(Duration? value) {}
  @override
  Future<HttpClientRequest> getUrl(
    Uri url,
  ) async => throw const HandshakeException(
    'Handshake error in client',
    OSError(
      'CERTIFICATE_VERIFY_FAILED private-pass https://private-provider.example',
      1,
    ),
  );
  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const platform = MethodChannel('streamline/platform');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(platform, null));

  test(
    'native DNS uses this lookup host, bounded deadline and unique cancellation ID',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(platform, (call) async {
        calls.add(call);
        if (call.method == 'dnsDiagnosis') {
          return {
            'mode': 'android',
            'cacheBypassed': true,
            'addresses': <String>[],
            'queries': [
              {'family': 'A', 'rcode': 3},
              {'family': 'AAAA', 'rcode': 3},
            ],
          };
        }
        return null;
      });
      final t = IoDiagnosticTransport(useNativeDns: true);
      final result = await t.lookup('private-provider.example');
      await Future<void>.delayed(Duration.zero);
      expect(result.androidResolver, true);
      expect(result.observations.first.responseCode, 3);
      expect(calls.first.arguments['host'], 'private-provider.example');
      expect(calls.first.arguments['timeoutMs'], 8000);
      final firstId = calls.first.arguments['id'];
      expect(calls.last.arguments['id'], firstId);
      await t.lookup('second.example');
      expect(
        calls.where((c) => c.method == 'dnsDiagnosis').last.arguments['id'],
        isNot(firstId),
      );
      t.close();
    },
  );

  test(
    'closing a native DNS run cancels only its ID and rejects its late answer',
    () async {
      final gate = Completer<Object?>();
      String? id, cancelled;
      messenger.setMockMethodCallHandler(platform, (call) async {
        if (call.method == 'dnsDiagnosis') {
          id = call.arguments['id'] as String;
          return gate.future;
        }
        cancelled = call.arguments['id'] as String;
        return null;
      });
      final t = IoDiagnosticTransport(useNativeDns: true);
      final lookup = t.lookup('private.example');
      final assertion = expectLater(
        lookup,
        throwsA(isA<ProbeFailure>().having((e) => e.code, 'code', 'cancelled')),
      );
      await Future<void>.delayed(Duration.zero);
      t.close();
      await Future<void>.delayed(Duration.zero);
      expect(cancelled, id);
      gate.complete({
        'addresses': ['192.0.2.1'],
      });
      await assertion;
    },
  );

  test(
    'missing native implementation falls back to bounded system lookup',
    () async {
      messenger.setMockMethodCallHandler(
        platform,
        (call) async => throw MissingPluginException(),
      );
      final t = IoDiagnosticTransport(
        useNativeDns: true,
        systemLookup: (host) async => [InternetAddress('192.0.2.1')],
      );
      final result = await t.lookup('private.example');
      expect(result.androidResolver, false);
      expect(result.addresses.length, 1);
      expect(result.observations.first.responseCode, isNull);
      t.close();
    },
  );

  test(
    'native bridge errors omit details and do not silently use a different resolver',
    () async {
      messenger.setMockMethodCallHandler(platform, (call) async {
        if (call.method == 'dnsDiagnosis') {
          throw PlatformException(
            code: 'secret',
            message: 'private-pass private.example',
          );
        }
        return null;
      });
      var fallback = false;
      final t = IoDiagnosticTransport(
        useNativeDns: true,
        systemLookup: (_) async {
          fallback = true;
          return [];
        },
      );
      final result = await t.lookup('private.example');
      expect(fallback, false);
      expect(result.observations.single.error, DnsError.system);
      expect(result.observations.single.evidence, isNot(contains('private')));
      t.close();
    },
  );

  test(
    'network snapshot retains DNS context but omits resolver names and addresses',
    () async {
      messenger.setMockMethodCallHandler(
        platform,
        (call) async => {
          'connected': true,
          'validated': true,
          'privateDns': false,
          'privateDnsStrict': true,
          'dnsServerCount': 2,
          'privateDnsServerName': 'secret.example',
          'dnsServers': ['192.0.2.1'],
        },
      );
      final t = IoDiagnosticTransport();
      final network = await t.network();
      expect(network.privateDnsStrict, true);
      expect(network.dnsServerCount, 2);
      t.close();
    },
  );

  test('fallback retains numeric OS code but never raw error text', () async {
    final t = IoDiagnosticTransport(
      useNativeDns: false,
      systemLookup: (host) async => throw const SocketException(
        'private-pass private.example',
        osError: OSError('private-pass', 7),
      ),
    );
    final result = await t.lookup('private.example');
    expect(result.observations.single.osCode, 7);
    expect(result.observations.single.evidence, isNot(contains('private')));
    expect(result.observations.single.error, DnsError.system);
    t.close();
  });

  test(
    'system DNS lookup is bounded and reports timeout without a response code',
    () async {
      final gate = Completer<List<InternetAddress>>();
      final t = IoDiagnosticTransport(
        useNativeDns: false,
        timeout: const Duration(milliseconds: 20),
        systemLookup: (_) => gate.future,
      );
      final result = await t.lookup('private.example');
      expect(result.observations.single.error, DnsError.timeout);
      expect(result.observations.single.responseCode, isNull);
      gate.complete([]);
      t.close();
    },
  );
  test(
    'nested OS certificate errors are classified without exposing their private text',
    () async {
      await HttpOverrides.runZoned(() async {
        final transport = IoDiagnosticTransport();
        addTearDown(transport.close);
        await expectLater(
          transport.tls('private-provider.example', 443),
          throwsA(
            isA<ProbeFailure>()
                .having((e) => e.code, 'code', 'certificate')
                .having(
                  (e) => e.toString(),
                  'private text',
                  isNot(contains('private-pass')),
                ),
          ),
        );
      }, createHttpClient: (_) => _CertificateFailureClient());
    },
  );
  test(
    'real HTTP probe caps a stream and never follows credential redirects',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final paths = <String>[];
      final requests = server.listen((request) async {
        paths.add(request.uri.path);
        if (request.uri.path == '/redirect') {
          request.response.statusCode = 302;
          request.response.headers.set(
            'Location',
            '/leak?password=private-pass',
          );
        } else {
          request.response.add(List.filled(100000, 71));
        }
        await request.response.close();
      });
      final t = IoDiagnosticTransport();
      addTearDown(() async {
        t.close();
        await requests.cancel();
        await server.close(force: true);
      });
      Uri uri(String path) =>
          Uri(scheme: 'http', host: '127.0.0.1', port: server.port, path: path);
      final sample = await t.get(uri('/sample'), stream: true);
      expect(sample.bytes.length, IoDiagnosticTransport.streamLimit);
      final redirect = await t.get(uri('/redirect'));
      expect(redirect.status, 302);
      expect(redirect.bytes, isEmpty);
      expect(paths, ['/sample', '/redirect']);
    },
  );

  test('oversized API body is stopped rather than kept in memory', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = server.listen((request) async {
      request.response.add(
        utf8.encode('x' * (IoDiagnosticTransport.apiLimit + 100)),
      );
      try {
        await request.response.close();
      } catch (_) {}
    });
    final t = IoDiagnosticTransport();
    addTearDown(() async {
      t.close();
      await requests.cancel();
      await server.close(force: true);
    });
    final uri = Uri(scheme: 'http', host: '127.0.0.1', port: server.port);
    await expectLater(
      t.get(uri),
      throwsA(
        isA<ProbeFailure>().having((e) => e.code, 'code', 'response_too_large'),
      ),
    );
  });

  test('HTTP body stalls are bounded and transport remains closable', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = server.listen((request) async {
      request.response.write('partial');
      try {
        await request.response.flush();
      } catch (_) {}
    });
    final t = IoDiagnosticTransport(timeout: const Duration(milliseconds: 200));
    addTearDown(() async {
      t.close();
      await requests.cancel();
      await server.close(force: true);
    });
    final uri = Uri(scheme: 'http', host: '127.0.0.1', port: server.port);
    await expectLater(
      t.get(uri),
      throwsA(isA<ProbeFailure>().having((e) => e.code, 'code', 'timeout')),
    );
  });

  test(
    'a TLS handshake that never responds is bounded and force closed',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <Socket>[];
      final requests = server.listen((socket) {
        sockets.add(socket);
        socket.listen((_) {}, onError: (_) {});
      });
      final t = IoDiagnosticTransport(
        timeout: const Duration(milliseconds: 200),
      );
      addTearDown(() async {
        t.close();
        for (final s in sockets) {
          s.destroy();
        }
        await requests.cancel();
        await server.close();
      });
      await expectLater(
        t.tls('127.0.0.1', server.port),
        throwsA(isA<ProbeFailure>().having((e) => e.code, 'code', 'timeout')),
      );
    },
  );

  test(
    'closing a running HTTP probe interrupts it and no private URL enters error text',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final arrived = Completer<void>();
      final requests = server.listen((request) {
        arrived.complete();
      });
      final t = IoDiagnosticTransport();
      addTearDown(() async {
        t.close();
        await requests.cancel();
        await server.close(force: true);
      });
      final uri = Uri(
        scheme: 'http',
        host: '127.0.0.1',
        port: server.port,
        path: '/private-pass',
      );
      final future = t.get(uri);
      final assertion = expectLater(
        future,
        throwsA(
          isA<ProbeFailure>()
              .having((e) => e.code, 'code', 'cancelled')
              .having(
                (e) => e.toString(),
                'safe text',
                isNot(contains('private-pass')),
              ),
        ),
      );
      await arrived.future;
      t.close();
      await assertion;
    },
  );
}
