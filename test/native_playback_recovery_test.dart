import 'package:flutter_test/flutter_test.dart';
import 'package:streamline_iptv/core/native_playback_recovery.dart';

void main() {
  testWidgets(
    'decoded video and an advancing clock recover a decoder probe error',
    (tester) async {
      var failures = 0;
      final recovery = NativePlaybackRecovery(() => failures++);
      recovery.signal(Duration.zero);
      await tester.pump(const Duration(milliseconds: 200));
      recovery.observe(
        position: const Duration(milliseconds: 300),
        playing: true,
        buffering: false,
        videoOutput: true,
        audioOnly: false,
      );
      await tester.pump(const Duration(seconds: 3));
      expect(failures, 0);
      recovery.dispose();
    },
  );
  testWidgets('an advancing audio clock cannot hide a missing video output', (
    tester,
  ) async {
    var failures = 0;
    final recovery = NativePlaybackRecovery(() => failures++);
    recovery.signal(Duration.zero);
    recovery.observe(
      position: const Duration(seconds: 1),
      playing: true,
      buffering: false,
      videoOutput: false,
      audioOnly: false,
    );
    await tester.pump(const Duration(seconds: 3));
    expect(failures, 1);
  });
  testWidgets(
    'real failures expire and repeated errors cannot extend the deadline',
    (tester) async {
      var failures = 0;
      final recovery = NativePlaybackRecovery(() => failures++);
      recovery.signal(Duration.zero);
      await tester.pump(const Duration(seconds: 1));
      recovery.signal(Duration.zero);
      await tester.pump(const Duration(milliseconds: 1100));
      expect(failures, 1);
    },
  );
  testWidgets('a paused decoded frame can complete initial hardware fallback', (
    tester,
  ) async {
    var failures = 0;
    final recovery = NativePlaybackRecovery(() => failures++);
    recovery.signal(Duration.zero);
    recovery.observe(
      position: Duration.zero,
      playing: false,
      buffering: false,
      videoOutput: true,
      audioOnly: false,
    );
    await tester.pump(const Duration(seconds: 3));
    expect(failures, 0);
    recovery.dispose();
  });
  testWidgets('disposal cancels an outstanding recovery deadline', (
    tester,
  ) async {
    var failures = 0;
    final recovery = NativePlaybackRecovery(() => failures++);
    recovery.signal(Duration.zero);
    recovery.dispose();
    await tester.pump(const Duration(seconds: 3));
    expect(failures, 0);
  });
}
