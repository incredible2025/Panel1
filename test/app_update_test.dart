import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streamline_iptv/core/update_controller.dart';
import 'package:streamline_iptv/data/app_update.dart';

Map<String, dynamic> manifest({int code = 9}) => {
  'schemaVersion': 1,
  'applicationId': 'com.streamline.iptv',
  'versionName': '0.6.1',
  'versionCode': code,
  'minSdk': 24,
  'apkUrl': 'https://updates.example/app.apk',
  'sizeBytes': 3,
  'sha256': sha256.convert([1, 2, 3]).toString(),
  'releaseNotes': 'New features',
};
AppUpdate candidate({int code = 9}) =>
    AppUpdate.parse(jsonEncode(manifest(code: code)));

class FakePlatform implements UpdatePlatform {
  bool allowed = false, requested = false;
  bool automatic = true;
  DateTime? checked;
  int installs = 0, validations = 0;
  Object? validationError;
  @override
  Future<UpdateDevice> load() async => UpdateDevice(
    version: '0.6.0',
    code: 8,
    sdk: 30,
    directory: '/private/updates',
    url: defaultUpdateUrl,
    automatic: automatic,
    lastCheck: checked,
  );
  @override
  Future<void> preferences(
    String url,
    bool automatic,
    DateTime? checked,
  ) async {
    this.automatic = automatic;
    this.checked = checked;
  }

  @override
  Future<void> validate(String path, AppUpdate update) async {
    validations++;
    if (validationError != null) throw validationError!;
  }

  @override
  Future<bool> canInstall() async => allowed;
  @override
  Future<void> requestInstallPermission() async {
    requested = true;
  }

  @override
  Future<void> install(String path, AppUpdate update) async {
    installs++;
  }
}

class FakeTransport extends UpdateTransport {
  AppUpdate next = candidate();
  int checks = 0;
  Object? failure;
  Completer<String>? pending;
  bool cancelled = false;
  @override
  Future<AppUpdate> check(String url) async {
    checks++;
    if (failure != null) throw failure!;
    return next;
  }

  @override
  Future<String> download(
    AppUpdate update,
    String directory,
    void Function(int) progress,
  ) async {
    progress(3);
    return pending == null ? '$directory/update.apk' : pending!.future;
  }

  @override
  void cancel() {
    cancelled = true;
    if (pending != null && !pending!.isCompleted) {
      pending!.completeError(const UpdateFailure('Cancelled'));
    }
  }
}

class Headers implements HttpHeaders {
  Headers([this.values = const {}]);
  final Map<String, String> values;
  @override
  String? value(String name) => values[name];
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Response extends Stream<List<int>> implements HttpClientResponse {
  Response(
    this.chunks, {
    this.statusCode = 200,
    this.contentLength = -1,
    Map<String, String> headers = const {},
  }) : headers = Headers(headers);
  final Stream<List<int>> chunks;
  @override
  final int statusCode, contentLength;
  @override
  final HttpHeaders headers;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => chunks.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Request implements HttpClientRequest {
  Request(this.response);
  final Response response;
  @override
  final HttpHeaders headers = Headers();
  @override
  bool followRedirects = true;
  @override
  Future<HttpClientResponse> close() async => response;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Client implements HttpClient {
  Client(this.responses);
  final List<Response> responses;
  final List<Uri> urls = [];
  @override
  Duration? connectionTimeout;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    urls.add(url);
    return Request(responses.removeAt(0));
  }

  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Response bytes(List<int> value, {int length = -1}) =>
    Response(Stream.value(value), contentLength: length);

void main() {
  test('manifest round trip and uppercase SHA-256', () {
    final data = manifest()..['sha256'] = manifest()['sha256'].toUpperCase();
    expect(AppUpdate.parse(jsonEncode(data)).sha256, candidate().sha256);
    expect(candidate().code, 9);
  });
  for (final mutation in <Map<String, dynamic>>[
    {'schemaVersion': 2},
    {'applicationId': 'com.other.app'},
    {'versionCode': '9'},
    {'versionCode': 0},
    {'sizeBytes': maxApkBytes + 1},
    {'sizeBytes': 0},
    {'sha256': '1234'},
    {'minSdk': 23},
    {'apkUrl': 'http://example/app.apk'},
    {'apkUrl': 'https://user:pass@example/app.apk'},
    {'apkUrl': 'file:///app.apk'},
    {'versionName': ''},
  ]) {
    test(
      'reject manifest ${mutation.keys.first}: ${mutation.values.first}',
      () {
        expect(
          () => AppUpdate.parse(jsonEncode({...manifest(), ...mutation})),
          throwsA(isA<UpdateFailure>()),
        );
      },
    );
  }
  test('malformed JSON and unsafe update feed addresses are rejected', () {
    for (final value in ['null', '[]', '{broken', '{}']) {
      expect(() => AppUpdate.parse(value), throwsA(isA<UpdateFailure>()));
    }
    for (final value in [
      'http://example',
      'https://',
      'https://user@example',
      'https://example/#fragment',
    ]) {
      expect(() => updateUri(value), throwsA(isA<UpdateFailure>()));
    }
  });
  test('no downgrade and no unnecessary download', () async {
    final platform = FakePlatform(),
        transport = FakeTransport()..next = candidate(code: 8);
    final c = UpdateController(platform, transport);
    addTearDown(c.dispose);
    await c.check();
    expect(c.stage, UpdateStage.current);
    expect(c.update, null);
    await c.download();
    expect(platform.validations, 0);
    transport.next = candidate(code: 7);
    await c.check();
    expect(c.update, null);
  });
  test(
    'automatic checks throttle successes and failures; manual retry bypasses throttle',
    () async {
      final platform = FakePlatform(),
          transport = FakeTransport()..failure = const UpdateFailure('Offline');
      final c = UpdateController(platform, transport);
      addTearDown(c.dispose);
      await c.autoCheck();
      await c.autoCheck();
      expect(transport.checks, 1);
      expect(c.stage, UpdateStage.failed);
      expect(c.error, 'Offline');
      transport.failure = null;
      await c.check();
      expect(transport.checks, 2);
      expect(c.stage, UpdateStage.available);
      await c.autoCheck();
      expect(transport.checks, 2);
    },
  );
  test('automatic opt out and HTTPS preference validation', () async {
    final platform = FakePlatform()..automatic = false,
        transport = FakeTransport();
    final c = UpdateController(platform, transport);
    addTearDown(c.dispose);
    await c.autoCheck();
    expect(transport.checks, 0);
    expect(await c.save('http://unsafe', true), false);
    expect(platform.automatic, false);
    expect(await c.save('https://own.example/update.json', true), true);
    expect(c.url, 'https://own.example/update.json');
    expect(c.lastCheck, null);
  });
  test('incompatible Android version explains the reason', () async {
    final transport = FakeTransport()
      ..next = AppUpdate.parse(jsonEncode({...manifest(), 'minSdk': 31}));
    final c = UpdateController(FakePlatform(), transport);
    addTearDown(c.dispose);
    await c.check();
    expect(c.stage, UpdateStage.failed);
    expect(c.error, contains('API 31'));
  });
  test(
    'permission flow revalidates and never claims installation succeeded',
    () async {
      final platform = FakePlatform(),
          c = UpdateController(platform, FakeTransport());
      addTearDown(c.dispose);
      await c.check();
      await c.download();
      expect(c.stage, UpdateStage.ready);
      await c.install();
      expect(c.stage, UpdateStage.permission);
      expect(platform.requested, true);
      expect(platform.installs, 0);
      platform.allowed = true;
      await c.install();
      expect(c.stage, UpdateStage.installer);
      expect(platform.installs, 1);
      expect(platform.validations, 3);
    },
  );
  test('signing mismatch never opens installer', () async {
    final platform = FakePlatform()
      ..validationError = PlatformException(
        code: 'verification',
        message: 'Different signing key',
      );
    final c = UpdateController(platform, FakeTransport());
    addTearDown(c.dispose);
    await c.check();
    await c.download();
    await c.install();
    expect(c.stage, UpdateStage.failed);
    expect(c.error, 'Different signing key');
    expect(platform.installs, 0);
  });
  test('cancelling a download enables retry', () async {
    final transport = FakeTransport()..pending = Completer<String>();
    final c = UpdateController(FakePlatform(), transport);
    addTearDown(c.dispose);
    await c.check();
    final download = c.download();
    c.cancel();
    await download;
    expect(c.stage, UpdateStage.failed);
    transport.pending = null;
    await c.download();
    expect(c.stage, UpdateStage.ready);
  });
  group('bounded HTTPS transport', () {
    late Directory directory;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp(
        'ultravpn-update-test-',
      );
    });
    tearDown(() async {
      await directory.delete(recursive: true);
    });
    test('valid streamed download verifies hash and leaves only APK', () async {
      final client = Client([
        bytes([1, 2, 3], length: 3),
      ]);
      final transport = UpdateTransport(clientFactory: () => client);
      final progress = <int>[];
      final path = await transport.download(
        candidate(),
        directory.path,
        progress.add,
      );
      expect(await File(path).readAsBytes(), [1, 2, 3]);
      expect(progress.last, 3);
      expect(await File('${directory.path}/update.part').exists(), false);
    });
    for (final content in [
      [1, 2],
      [1, 2, 4],
      [1, 2, 3, 4],
    ]) {
      test(
        'truncated, altered or oversized APK is deleted: $content',
        () async {
          final transport = UpdateTransport(
            clientFactory: () => Client([bytes(content)]),
          );
          await expectLater(
            transport.download(candidate(), directory.path, (_) {}),
            throwsA(isA<UpdateFailure>()),
          );
          expect(await directory.list().toList(), isEmpty);
        },
      );
    }
    test('declared size mismatch is rejected', () async {
      final transport = UpdateTransport(
        clientFactory: () => Client([
          bytes([1, 2, 3], length: 4),
        ]),
      );
      await expectLater(
        transport.download(candidate(), directory.path, (_) {}),
        throwsA(isA<UpdateFailure>()),
      );
    });
    test(
      'HTTPS redirect accepted; downgrade to HTTP rejected before request',
      () async {
        final client = Client([
          Response(
            const Stream.empty(),
            statusCode: 302,
            headers: {'location': 'https://cdn.example/manifest'},
          ),
          bytes(utf8.encode(jsonEncode(manifest()))),
        ]);
        expect(
          (await UpdateTransport(
            clientFactory: () => client,
          ).check(defaultUpdateUrl)).code,
          9,
        );
        expect(client.urls.last.host, 'cdn.example');
        final unsafe = Client([
          Response(
            const Stream.empty(),
            statusCode: 302,
            headers: {'location': 'http://cdn.example/manifest'},
          ),
        ]);
        await expectLater(
          UpdateTransport(clientFactory: () => unsafe).check(defaultUpdateUrl),
          throwsA(isA<UpdateFailure>()),
        );
        expect(unsafe.urls.length, 1);
      },
    );
    test('manifest bounded to 64 KB and 404 never means up to date', () async {
      for (final response in [
        bytes(List.filled(65537, 32)),
        Response(const Stream.empty(), statusCode: 404),
      ]) {
        await expectLater(
          UpdateTransport(
            clientFactory: () => Client([response]),
          ).check(defaultUpdateUrl),
          throwsA(isA<UpdateFailure>()),
        );
      }
    });
  });
}
