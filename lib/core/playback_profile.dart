import '../data/app_settings.dart';
import '../data/models.dart';

class PlaybackProfile {
  const PlaybackProfile(this.engine, this.decoding);
  final PlayerEngine engine;
  final DecodingMode decoding;
  String get key => '${engine.name}:${decoding.name}';
  String get label => switch (engine) {
    PlayerEngine.native => 'ExoPlayer',
    PlayerEngine.compatibility => 'Compatibility · MPV',
    PlayerEngine.vlc => 'VLC',
  };
  String savedKey(AppSettings settings) =>
      '${settings.engine.name}/${settings.decoding.name}/$key';

  static List<PlaybackProfile> plan(
    AppSettings settings,
    MediaItem item, {
    required bool desktop,
  }) {
    PlaybackProfile profile(PlayerEngine engine, DecodingMode decoding) {
      if (desktop) engine = PlayerEngine.compatibility;
      if (engine == PlayerEngine.native && decoding == DecodingMode.software) {
        engine = PlayerEngine.compatibility;
      }
      return PlaybackProfile(engine, decoding);
    }

    final primary = profile(settings.engineFor(item), settings.decoding);
    final candidates = <PlaybackProfile>[primary];
    if (settings.automaticPlayerFallback) {
      // A learned choice belongs to the current defaults and never overrides an
      // explicit per-channel choice. Changing either default resets its effect.
      if (item.kind == MediaKind.live &&
          !settings.playerOverrides.containsKey(AppSettings.mediaKey(item))) {
        final saved = settings.successfulPlayers[AppSettings.mediaKey(item)];
        final prefix = '${settings.engine.name}/${settings.decoding.name}/';
        if (saved != null && saved.startsWith(prefix)) {
          final key = saved.substring(prefix.length);
          for (final engine in PlayerEngine.values) {
            for (final decoding in DecodingMode.values) {
              final learned = profile(engine, decoding);
              if (learned.key == key) candidates.insert(0, learned);
            }
          }
        }
      }
      candidates.add(profile(PlayerEngine.compatibility, settings.decoding));
      if (settings.decoding == DecodingMode.automatic) {
        candidates.add(
          profile(PlayerEngine.compatibility, DecodingMode.software),
        );
      }
      if (!desktop) {
        candidates.add(profile(PlayerEngine.native, settings.decoding));
        candidates.add(profile(PlayerEngine.vlc, settings.decoding));
        if (settings.decoding == DecodingMode.automatic) {
          candidates.add(profile(PlayerEngine.vlc, DecodingMode.software));
        }
      }
    }
    final seen = <String>{};
    return candidates.where((candidate) => seen.add(candidate.key)).toList();
  }
}

/// Only return allowlisted categories. Native errors can contain credentials.
String playbackFailure(String? raw) {
  final message = (raw ?? '')
      .replaceAll(RegExp(r'https?://[^\s]+'), '')
      .toLowerCase();
  if (RegExp(
    r'certificate|ssl|tls|403|401|404|http status|http error|network|socket|connection|host|timed out|timeout',
  ).hasMatch(message)) {
    return 'Connection or service error';
  }
  if (RegExp(
    r'decoder|mediacodec|codec|unsupported.*format|format.*unsupported|failed to.*decode',
  ).hasMatch(message)) {
    return 'Decoder or codec error';
  }
  return 'Playback error';
}
