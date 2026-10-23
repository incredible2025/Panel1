import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

enum SpeedPhase { latency, download, upload, finished }

class SpeedMeasurement {
  const SpeedMeasurement(this.bytes, this.duration);
  final int bytes;
  final Duration duration;
  double? get mbps => bytes > 0 && duration.inMicroseconds > 0
      ? bytes * 8 / duration.inMicroseconds
      : null;
}

class SpeedResult {
  const SpeedResult({
    this.phase = SpeedPhase.latency,
    this.download,
    this.upload,
    this.latency,
    this.jitter,
    this.notices = const [],
    this.cancelled = false,
    this.timedOut = false,
  });
  final SpeedPhase phase;
  final double? download, upload, latency, jitter;
  final List<String> notices;
  final bool cancelled, timedOut;
  bool get hasMeasurements =>
      download != null || upload != null || latency != null;
  String toText() =>
      'Ultravpn-player speed test\n'
      'This device’s connection to Cloudflare; not a provider-stream test.\n'
      'Download: ${download?.toStringAsFixed(1) ?? 'Not measured'} Mbps\n'
      'Upload: ${upload?.toStringAsFixed(1) ?? 'Not measured'} Mbps\n'
      'HTTP latency: ${latency?.toStringAsFixed(0) ?? 'Not measured'} ms\n'
      'Jitter: ${jitter?.toStringAsFixed(0) ?? 'Not measured'} ms\n'
      '${cancelled ? 'Stopped by user.\n' : ''}${timedOut ? 'Test time limit reached.\n' : ''}'
      '${notices.join('\n')}';
}

class SpeedTestFailure implements Exception {
  const SpeedTestFailure(this.code);
  final String code;
  String get explanation => switch (code) {
    'timeout' => 'The test service did not finish responding in time.',
    'certificate' =>
      'The test service’s HTTPS certificate could not be verified. Check automatic date and time.',
    'network' =>
      'This device could not connect to the test service. Check Wi-Fi, mobile data or VPN and retry.',
    'http' =>
      'The test service rejected the request or redirected it. Retry later or use Connection diagnosis for the provider.',
    'response' =>
      'The test service returned an incomplete or unexpected response.',
    _ =>
      'The speed test could not complete. Retry or run Connection diagnosis.',
  };
}

abstract class SpeedTestTransport {
  Future<SpeedMeasurement> measure({required int bytes, bool upload = false});
  void close();
}

/// One HTTPS connection at a time, streamed payloads, fixed Cloudflare endpoints.
/// No provider credentials, stream URLs or result telemetry are sent.
class IoSpeedTestTransport implements SpeedTestTransport {
  IoSpeedTestTransport({this.timeout = const Duration(seconds: 8)}) {
    _client.connectionTimeout = timeout;
    _client.autoUncompress = false;
  }
  final Duration timeout;
  HttpClient _client = HttpClient();
  bool _closed = false;
  int _sequence = 0;
  static Uint8List _makePayload() {
    final random = Random();
    return Uint8List.fromList(
      List<int>.generate(32768, (_) => random.nextInt(256)),
    );
  }

  final _payload = _makePayload();

  @override
  Future<SpeedMeasurement> measure({
    required int bytes,
    bool upload = false,
  }) async {
    if (_closed) throw const SpeedTestFailure('cancelled');
    if (bytes < 0 || bytes > 16 * 1024 * 1024) throw ArgumentError.value(bytes);
    final timer = Stopwatch()..start();
    HttpClientRequest? request;
    try {
      return await (() async {
        final uri =
            Uri.https('speed.cloudflare.com', upload ? '/__up' : '/__down', {
              if (!upload) 'bytes': '$bytes',
              'cacheBust':
                  '${DateTime.now().microsecondsSinceEpoch}-${++_sequence}',
            });
        request = await _client.openUrl(upload ? 'POST' : 'GET', uri);
        unawaited(request!.done.then<void>((_) {}, onError: (Object _) {}));
        if (_closed) throw const SpeedTestFailure('cancelled');
        request!.followRedirects = false;
        request!.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
        request!.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
        request!.headers.set(
          HttpHeaders.userAgentHeader,
          'Ultravpn-player-SpeedTest',
        );
        if (upload) {
          request!.headers.contentType = ContentType.binary;
          request!.contentLength = bytes;
          for (var sent = 0; sent < bytes; sent += _payload.length) {
            if (_closed) throw const SpeedTestFailure('cancelled');
            request!.add(
              Uint8List.sublistView(
                _payload,
                0,
                min(_payload.length, bytes - sent),
              ),
            );
            await request!.flush();
          }
        }
        final response = await request!.close();
        if (_closed) throw const SpeedTestFailure('cancelled');
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw const SpeedTestFailure('http');
        }
        var received = 0;
        final cap = upload ? 65536 : bytes;
        await for (final chunk in response) {
          if (_closed) throw const SpeedTestFailure('cancelled');
          received += chunk.length;
          if (received > cap) throw const SpeedTestFailure('response');
        }
        if (!upload && received != bytes) {
          throw const SpeedTestFailure('response');
        }
        return SpeedMeasurement(upload ? bytes : received, timer.elapsed);
      })().timeout(timeout);
    } catch (error) {
      request?.abort();
      // Also interrupt a stalled response body. abort() alone only bounds the
      // request phase once a response stream has already been returned.
      _client.close(force: true);
      if (!_closed) {
        _client = HttpClient()..connectionTimeout = timeout;
        _client.autoUncompress = false;
      }
      if (_closed) throw const SpeedTestFailure('cancelled');
      if (error is SpeedTestFailure) rethrow;
      if (error is TimeoutException) throw const SpeedTestFailure('timeout');
      if (error is HandshakeException || error is CertificateException) {
        throw const SpeedTestFailure('certificate');
      }
      throw const SpeedTestFailure('network');
    }
  }

  @override
  void close() {
    _closed = true;
    _client.close(force: true);
  }
}

/// Bounded estimate, not a saturated multi-connection broadband benchmark.
/// At most 21 MiB down + 5 MiB up, small replies and protocol overhead.
class SpeedTestRunner {
  SpeedTestRunner(this.transport, {this.limit = const Duration(seconds: 60)});
  final SpeedTestTransport transport;
  final Duration limit;
  bool _cancelled = false, _timedOut = false, _started = false;
  void cancel() {
    _cancelled = true;
    transport.close();
  }

  Future<SpeedResult> run({void Function(SpeedResult)? onProgress}) async {
    if (_started) throw StateError('Create a new runner for each speed test.');
    _started = true;
    final deadline = Timer(limit, () {
      _timedOut = true;
      transport.close();
    });
    double? download, upload, latency, jitter;
    var phase = SpeedPhase.latency;
    final notices = <String>[];
    final timings = <double>[];
    bool getStopped() => _cancelled || _timedOut;
    SpeedResult snapshot() => SpeedResult(
      phase: phase,
      download: download,
      upload: upload,
      latency: latency,
      jitter: jitter,
      notices: List.unmodifiable(notices),
      cancelled: _cancelled,
      timedOut: _timedOut,
    );
    void emit() {
      if (!getStopped()) onProgress?.call(snapshot());
    }

    void failure(Object error, String direction) {
      if (getStopped()) return;
      final safe = error is SpeedTestFailure
          ? error
          : const SpeedTestFailure('unknown');
      notices.add('$direction: ${safe.explanation}');
    }

    Future<double?> bandwidth(bool sending) async {
      double? latest;
      for (final bytes
          in sending ? [1048576, 4194304] : [1048576, 4194304, 16777216]) {
        if (getStopped()) break;
        try {
          final measurement = await transport.measure(
            bytes: bytes,
            upload: sending,
          );
          if (getStopped()) break;
          if (measurement.bytes != bytes ||
              measurement.mbps == null ||
              !measurement.mbps!.isFinite) {
            throw const SpeedTestFailure('response');
          }
          latest = measurement.mbps;
          if (sending) {
            upload = latest;
          } else {
            download = latest;
          }
          emit();
          if (measurement.duration >= const Duration(seconds: 2)) break;
        } catch (error) {
          failure(error, sending ? 'Upload' : 'Download');
          break;
        }
      }
      return latest;
    }

    try {
      emit();
      // The first request warms DNS/TCP/TLS; it is excluded from latency.
      await transport.measure(bytes: 0);
      for (var i = 0; i < 5 && !getStopped(); i++) {
        try {
          final sample = await transport.measure(bytes: 0);
          if (getStopped()) break;
          timings.add(sample.duration.inMicroseconds / 1000);
          final sorted = timings.toList()..sort();
          final mid = sorted.length ~/ 2;
          latency = sorted.length.isOdd
              ? sorted[mid]
              : (sorted[mid - 1] + sorted[mid]) / 2;
          if (timings.length > 1) {
            var differences = 0.0;
            for (var j = 1; j < timings.length; j++) {
              differences += (timings[j] - timings[j - 1]).abs();
            }
            jitter = differences / (timings.length - 1);
          }
          emit();
        } catch (error) {
          failure(error, 'Latency');
          break;
        }
      }
      if (!getStopped()) {
        phase = SpeedPhase.download;
        emit();
        download = await bandwidth(false);
      }
      if (!getStopped()) {
        phase = SpeedPhase.upload;
        emit();
        upload = await bandwidth(true);
      }
    } catch (error) {
      failure(error, 'Test service');
    } finally {
      deadline.cancel();
      transport.close();
    }
    phase = SpeedPhase.finished;
    return snapshot();
  }
}
