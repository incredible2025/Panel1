import 'package:flutter_test/flutter_test.dart';
import 'package:streamline_iptv/core/playback_profile.dart';
import 'package:streamline_iptv/data/app_settings.dart';
import 'package:streamline_iptv/data/models.dart';

void main() {
  const channel = MediaItem(id: '1', name: 'Channel', kind: MediaKind.live);
  test('old settings retain their engine and new choices survive storage', () {
    expect(
      AppSettings.fromJson({'engine': 'compatibility'}).engine,
      PlayerEngine.compatibility,
    );
    final settings = AppSettings.fromJson(
      const AppSettings(
        engine: PlayerEngine.vlc,
        decoding: DecodingMode.software,
        automaticPlayerFallback: false,
      ).toJson(),
    );
    expect(settings.engineFor(channel), PlayerEngine.vlc);
    expect(settings.decoding, DecodingMode.software);
    expect(settings.automaticPlayerFallback, false);
  });
  test(
    'learned playback follows defaults and explicit channel choices take precedence',
    () {
      final settings = AppSettings(
        successfulPlayers: {
          AppSettings.mediaKey(channel): 'native/automatic/vlc:software',
        },
      );
      expect(
        PlaybackProfile.plan(settings, channel, desktop: false).first.key,
        'vlc:software',
      );
      expect(
        PlaybackProfile.plan(
          settings.patch({'engine': 'compatibility'}),
          channel,
          desktop: false,
        ).first.key,
        'compatibility:automatic',
      );
      expect(
        PlaybackProfile.plan(
          settings.patch({
            'playerOverrides': {'live:1': 'native'},
          }),
          channel,
          desktop: false,
        ).first.key,
        'native:automatic',
      );
      final keys = PlaybackProfile.plan(
        settings,
        channel,
        desktop: false,
      ).map((p) => p.key).toList();
      expect(keys.toSet().length, keys.length);
      expect(keys.length, lessThanOrEqualTo(5));
    },
  );
  test('software selection and Windows plans use supported engines', () {
    const settings = AppSettings(decoding: DecodingMode.software);
    final plan = PlaybackProfile.plan(settings, channel, desktop: false);
    expect(plan.first.key, 'compatibility:software');
    expect(plan.every((p) => p.decoding == DecodingMode.software), true);
    final desktop = PlaybackProfile.plan(
      const AppSettings(engine: PlayerEngine.vlc),
      channel,
      desktop: true,
    );
    expect(desktop.every((p) => p.engine == PlayerEngine.compatibility), true);
  });
  test('diagnostic categories strip sensitive error details', () {
    expect(
      playbackFailure(
        'DecoderInitializationException https://secret.example/user/password',
      ),
      'Decoder or codec error',
    );
    expect(
      playbackFailure('HTTP 401 https://secret.example/user/password'),
      'Connection or service error',
    );
    expect(
      playbackFailure('TLS certificate verification failed'),
      'Connection or service error',
    );
  });
}
