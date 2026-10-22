import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:streamline_iptv/data/diagnostic_transport.dart';

void main() {
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
