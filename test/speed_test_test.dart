import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:streamline_iptv/data/speed_test.dart';

class FakeSpeedTransport implements SpeedTestTransport {
  final calls = <({int bytes, bool upload})>[];
  final delays = <int>[100, 10, 20, 30, 20, 10];
  bool closed = false;
  bool failLargeDownload = false;
  bool failWarmup = false;
  bool fast = false;
  Completer<SpeedMeasurement>? gate;
  @override
  Future<SpeedMeasurement> measure({
    required int bytes,
    bool upload = false,
  }) async {
    calls.add((bytes: bytes, upload: upload));
    if (gate != null) {
      return gate!.future;
    }
    if (failWarmup || failLargeDownload && bytes == 4194304 && !upload) {
      throw const SpeedTestFailure('timeout');
    }
    return SpeedMeasurement(
      bytes,
      bytes == 0
          ? Duration(milliseconds: delays[calls.length - 1])
          : Duration(
              milliseconds: fast || bytes == 1048576 && !upload ? 100 : 2000,
            ),
    );
  }

  @override
  void close() {
    closed = true;
    if (gate != null && !gate!.isCompleted) {
      gate!.completeError(const SpeedTestFailure('cancelled'));
    }
  }
}

void main() {
  test(
    'median latency excludes warmup, jitter uses adjacent samples and transfer speeds use bits per second',
    () async {
      final t = FakeSpeedTransport();
      final progress = <SpeedResult>[];
      final r = await SpeedTestRunner(t).run(onProgress: progress.add);
      expect(r.latency, 20);
      expect(r.jitter, 10);
      expect(r.download, closeTo(16.777216, .00001));
      expect(r.upload, closeTo(4.194304, .00001));
      expect(t.calls.where((c) => c.bytes > 0).map((c) => c.bytes), [
        1048576,
        4194304,
        1048576,
      ]);
      expect(
        progress.map((s) => s.phase),
        containsAll([
          SpeedPhase.latency,
          SpeedPhase.download,
          SpeedPhase.upload,
        ]),
      );
      expect(r.notices, isEmpty);
      expect(t.closed, true);
    },
  );
  test(
    'fast connection tests ramp within the advertised payload budget',
    () async {
      final t = FakeSpeedTransport()..fast = true;
      final r = await SpeedTestRunner(t).run();
      expect(t.calls.where((c) => c.bytes > 0).length, 5);
      expect(t.calls.fold<int>(0, (total, c) => total + c.bytes), 26 * 1048576);
      expect(r.download, isNotNull);
      expect(r.upload, isNotNull);
    },
  );
  test(
    'failed larger sample retains the completed estimate and reports partial results',
    () async {
      final t = FakeSpeedTransport()..failLargeDownload = true;
      final r = await SpeedTestRunner(t).run();
      expect(r.download, closeTo(83.88608, .0001));
      expect(r.upload, isNotNull);
      expect(r.notices.single, contains('Download:'));
      expect(r.toText(), isNot(contains('http')));
    },
  );
  test(
    'unreachable service never invents zero or successful speed values',
    () async {
      final t = FakeSpeedTransport()..failWarmup = true;
      final r = await SpeedTestRunner(t).run();
      expect(r.hasMeasurements, false);
      expect(r.notices, isNotEmpty);
      expect(t.calls.length, 1);
      expect(r.toText(), contains('Not measured'));
    },
  );
  test(
    'cancel interrupts pending measurement and prevents later transfers or progress',
    () async {
      final t = FakeSpeedTransport()..gate = Completer<SpeedMeasurement>();
      final runner = SpeedTestRunner(t);
      final progress = <SpeedResult>[];
      final future = runner.run(onProgress: progress.add);
      runner.cancel();
      final r = await future;
      expect(r.cancelled, true);
      expect(t.calls.length, 1);
      expect(progress.length, 1);
      expect(t.closed, true);
    },
  );
  test(
    'overall deadline stops a stalled measurement without claiming a full result',
    () async {
      final t = FakeSpeedTransport()..gate = Completer<SpeedMeasurement>();
      final r = await SpeedTestRunner(
        t,
        limit: const Duration(milliseconds: 20),
      ).run();
      expect(r.timedOut, true);
      expect(r.cancelled, false);
      expect(t.closed, true);
      expect(r.hasMeasurements, false);
    },
  );
}
