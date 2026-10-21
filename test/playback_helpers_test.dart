import 'package:flutter_test/flutter_test.dart';
import 'package:streamline_iptv/features/player_screen.dart';

void main() {
  group('playback seeking', () {
    test('clamps a rewind at the start and a forward seek at the end', () {
      const length = Duration(minutes: 2);
      expect(
        clampPlaybackPosition(const Duration(seconds: -10), length),
        Duration.zero,
      );
      expect(clampPlaybackPosition(const Duration(minutes: 3), length), length);
      expect(
        clampPlaybackPosition(const Duration(seconds: 45), length),
        const Duration(seconds: 45),
      );
    });

    test('unknown and invalid stream lengths never produce a seek target', () {
      expect(
        clampPlaybackPosition(const Duration(seconds: 30), Duration.zero),
        Duration.zero,
      );
      expect(
        clampPlaybackPosition(
          const Duration(seconds: 30),
          const Duration(seconds: -1),
        ),
        Duration.zero,
      );
    });
  });

  test('playback labels support full movies and invalid positions', () {
    expect(formatPlaybackTime(const Duration(seconds: 9)), '00:09');
    expect(
      formatPlaybackTime(const Duration(minutes: 62, seconds: 3)),
      '1:02:03',
    );
    expect(formatPlaybackTime(const Duration(seconds: -5)), '00:00');
  });
}
