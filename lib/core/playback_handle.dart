import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;
import '../data/app_settings.dart';
import 'player_tracks.dart';

typedef PlaybackFactory = PlaybackHandle Function(Uri uri, PlayerEngine engine);
final playbackFactoryProvider = Provider<PlaybackFactory>(
  (ref) =>
      (uri, engine) => engine == PlayerEngine.compatibility
      ? CompatibilityPlayback(uri)
      : NativePlayback(uri),
);

abstract class PlaybackHandle extends ValueNotifier<VideoPlayerValue> {
  PlaybackHandle() : super(const VideoPlayerValue(duration: Duration.zero));
  Future<void> initialize();
  Future<void> play();
  Future<void> pause();
  Future<void> setVolume(double volume);
  Future<void> seekTo(Duration position);
  Future<void> attachTracks(PlayerTracks bridge, AppSettings preferences);
  Widget buildView();
  @override
  Future<void> dispose() async {
    super.dispose();
  }
}

class NativePlayback extends PlaybackHandle {
  NativePlayback(Uri uri)
    : controller = VideoPlayerController.networkUrl(
        uri,
        formatHint: uri.path.toLowerCase().endsWith('.m3u8')
            ? VideoFormat.hls
            : null,
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: false,
          allowBackgroundPlayback: false,
        ),
      ) {
    controller.addListener(_changed);
  }
  final VideoPlayerController controller;
  Future<void>? _release;
  bool _dead = false;
  void _changed() {
    if (!_dead) value = controller.value;
  }

  @override
  Future<void> initialize() => controller.initialize();
  @override
  Future<void> play() => controller.play();
  @override
  Future<void> pause() => controller.pause();
  @override
  Future<void> setVolume(double volume) => controller.setVolume(volume);
  @override
  Future<void> seekTo(Duration position) => controller.seekTo(position);
  @override
  Widget buildView() => VideoPlayer(controller);
  @override
  Future<void> attachTracks(
    PlayerTracks bridge,
    AppSettings preferences,
  ) async {
    await bridge.attach(controller);
    if (!_dead) await bridge.preferences(preferences);
  }

  @override
  Future<void> dispose() async {
    if (_release != null) {
      await _release;
      return;
    }
    _release = _dispose();
    try {
      await _release;
    } finally {
      super.dispose();
    }
  }

  Future<void> _dispose() async {
    _dead = true;
    controller.removeListener(_changed);
    try {
      await controller.dispose();
    } finally {
      /* Notifier teardown is owned by dispose(). */
    }
  }
}

/// Normalizes the compatibility engine into the same state used by the native
/// player. The UI, recovery policy and serialized history writes stay shared.
class CompatibilityPlayback extends PlaybackHandle {
  CompatibilityPlayback(this.uri);
  final Uri uri;
  late mk.Player _player;
  late mkv.VideoController _video;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  PlayerTracks? _bridge;
  AppSettings _preferences = const AppSettings();
  bool _created = false, _dead = false;
  bool _audioApplied = false, _textApplied = false;
  Future<void>? _release;
  final _mediaReady = Completer<void>();
  @override
  Future<void> initialize() async {
    unawaited(_mediaReady.future.catchError((Object _) {}));
    mk.MediaKit.ensureInitialized();
    if (_dead) return;
    _player = mk.Player(
      configuration: const mk.PlayerConfiguration(
        title: 'Streamline',
        logLevel: mk.MPVLogLevel.error,
        libass: true,
        libassAndroidFont: 'assets/fonts/Roboto-Regular.ttf',
        libassAndroidFontName: 'Roboto',
      ),
    );
    _created = true;
    _video = mkv.VideoController(_player);
    for (final stream in <Stream<dynamic>>[
      _player.stream.position,
      _player.stream.duration,
      _player.stream.playing,
      _player.stream.completed,
      _player.stream.buffering,
      _player.stream.width,
      _player.stream.height,
      _player.stream.videoParams,
      _player.stream.audioParams,
      _player.stream.track,
    ]) {
      _subscriptions.add(stream.listen((_) => _sync()));
    }
    _subscriptions.add(
      _player.stream.tracks.listen((_) {
        _sync();
        unawaited(_applyLanguages());
      }),
    );
    _subscriptions.add(
      _player.stream.error.listen((_) {
        if (!_dead) {
          if (!_mediaReady.isCompleted) {
            _mediaReady.completeError(
              StateError('Compatibility stream unavailable'),
            );
          }
          value = VideoPlayerValue.erroneous(
            'Compatibility playback is unavailable.',
          );
        }
      }),
    );
    await _player.open(mk.Media(uri.toString()), play: false);
    _sync();
    await _mediaReady.future;
    if (_dead) return;
    value = value.copyWith(isInitialized: true);
    _sync();
  }

  void _sync() {
    if (_dead || !_created || value.hasError) return;
    final state = _player.state;
    if (!_mediaReady.isCompleted &&
        (state.duration > Duration.zero ||
            (state.width ?? 0) > 0 ||
            state.tracks.audio.any(
              (track) => !{'auto', 'no'}.contains(track.id),
            ))) {
      _mediaReady.complete();
    }
    value = value.copyWith(
      duration: state.duration,
      position: state.position,
      isPlaying: state.playing,
      isCompleted: state.completed,
      isBuffering: state.buffering,
      size: Size(
        (state.width ?? 16).toDouble(),
        (state.height ?? 9).toDouble(),
      ),
    );
    _publishTracks();
  }

  void _publishTracks() {
    final bridge = _bridge;
    if (_dead || !_created || bridge == null || bridge.isDisposed) return;
    final state = _player.state;
    String label(dynamic track) => [
      track.title ?? track.language ?? 'Track ${track.id}',
      if (track.codec != null) track.codec,
      if (track.channelscount != null) '${track.channelscount} ch',
    ].join(' · ');
    final selectedVideo = state.tracks.video
        .where((track) => track.id == state.track.video.id)
        .firstOrNull;
    final selectedAudio = state.tracks.audio
        .where((track) => track.id == state.track.audio.id)
        .firstOrNull;
    bridge.value = TrackSnapshot(
      available: true,
      tracks: [
        for (final track in state.tracks.audio.where(
          (track) => !{'auto', 'no'}.contains(track.id),
        ))
          PlayerTrack(
            key: track.id,
            type: 'audio',
            label: label(track),
            language: canonicalLanguage(track.language ?? ''),
            selected: state.track.audio.id == track.id,
            supported: true,
          ),
        for (final track in state.tracks.subtitle.where(
          (track) => !{'auto', 'no'}.contains(track.id),
        ))
          PlayerTrack(
            key: track.id,
            type: 'text',
            label: label(track),
            language: track.language ?? '',
            selected: state.track.subtitle.id == track.id,
            supported: true,
          ),
      ],
      textOff: state.track.subtitle.id == 'no',
      audioAuto: state.track.audio.id == 'auto',
      videoCodec: selectedVideo?.codec ?? '',
      audioCodec: selectedAudio?.codec ?? '',
      decoder: selectedVideo?.decoder ?? '',
      audioChannels: selectedAudio?.channelscount ?? 0,
    );
  }

  Future<void> _applyLanguages() async {
    if (_dead || !_created || _bridge == null) return;
    final tracks = _player.state.tracks;
    bool language(String? value, String wanted) =>
        wanted.isNotEmpty &&
        canonicalLanguage(value ?? '') == canonicalLanguage(wanted);
    final audio = tracks.audio
        .where((track) => !{'auto', 'no'}.contains(track.id))
        .toList();
    if (!_audioApplied && audio.isNotEmpty) {
      _audioApplied = true;
      final matching =
          audio
              .where(
                (track) =>
                    (_preferences.audioLanguage.isEmpty ||
                        language(track.language, _preferences.audioLanguage)) &&
                    (!_preferences.stereo || (track.channelscount ?? 99) <= 2),
              )
              .firstOrNull ??
          audio
              .where(
                (track) => language(track.language, _preferences.audioLanguage),
              )
              .firstOrNull;
      if (matching != null &&
          (_preferences.stereo || _preferences.audioLanguage.isNotEmpty)) {
        await _player.setAudioTrack(matching);
      }
    }
    final text = tracks.subtitle
        .where((track) => !{'auto', 'no'}.contains(track.id))
        .toList();
    if (!_textApplied && (!_preferences.subtitles || text.isNotEmpty)) {
      _textApplied = true;
      await _player.setSubtitleTrack(
        !_preferences.subtitles
            ? mk.SubtitleTrack.no()
            : text
                      .where(
                        (track) => language(
                          track.language,
                          _preferences.subtitleLanguage,
                        ),
                      )
                      .firstOrNull ??
                  text.first,
      );
    }
  }

  @override
  Future<void> attachTracks(
    PlayerTracks bridge,
    AppSettings preferences,
  ) async {
    if (_dead) return;
    await bridge.detach();
    if (_dead || bridge.isDisposed) return;
    _preferences = preferences;
    _audioApplied = false;
    _textApplied = false;
    _bridge = bridge;
    bridge.externalSelection = (type, key) async {
      if (_dead) return false;
      try {
        if (type == 'audio') {
          _audioApplied = true;
          await _player.setAudioTrack(
            key == 'auto'
                ? mk.AudioTrack.auto()
                : _player.state.tracks.audio.firstWhere(
                    (track) => track.id == key,
                  ),
          );
        } else {
          _textApplied = true;
          await _player.setSubtitleTrack(
            key == 'off'
                ? mk.SubtitleTrack.no()
                : key == 'auto'
                ? mk.SubtitleTrack.auto()
                : _player.state.tracks.subtitle.firstWhere(
                    (track) => track.id == key,
                  ),
          );
        }
        _publishTracks();
        return true;
      } catch (_) {
        return false;
      }
    };
    final platform = _player.platform;
    if (platform is mk.NativePlayer) {
      try {
        await platform.setProperty(
          'sub-font-size',
          preferences.subtitleSize.round().toString(),
        );
        await platform.setProperty(
          'sub-back-color',
          preferences.subtitleBackground ? '0/0/0/0.65' : '0/0/0/0',
        );
      } catch (_) {
        /* Engine defaults remain available when a property is unsupported. */
      }
    }
    await _applyLanguages();
    _publishTracks();
  }

  @override
  Future<void> play() => _player.play();
  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume * 100);
  @override
  Future<void> pause() async {
    if (_created && !_dead) await _player.pause();
  }

  @override
  Future<void> seekTo(Duration position) => _player.seek(position);
  @override
  Widget buildView() => mkv.Video(
    controller: _video,
    controls: mkv.NoVideoControls,
    wakelock: false,
    subtitleViewConfiguration: const mkv.SubtitleViewConfiguration(
      visible: false,
    ),
  );
  @override
  Future<void> dispose() async {
    if (_release != null) {
      await _release;
      return;
    }
    _release = _dispose();
    try {
      await _release;
    } finally {
      super.dispose();
    }
  }

  Future<void> _dispose() async {
    _dead = true;
    if (_created && !_mediaReady.isCompleted) {
      _mediaReady.completeError(StateError('Playback closed'));
    }
    _bridge = null;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    try {
      if (_created) await _player.dispose();
    } finally {
      /* Notifier teardown is owned by dispose(). */
    }
  }
}
