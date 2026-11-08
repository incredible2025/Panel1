import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import '../data/app_settings.dart';
import 'playback_handle.dart';
import 'player_tracks.dart';

/// Android LibVLC owns a texture and closes its media before releasing it.
class VlcPlayback extends PlaybackHandle {
  VlcPlayback(this.uri) {
    unawaited(_ready.future.catchError((Object _) {}));
  }
  final Uri uri;
  static const _methods = MethodChannel('streamline/vlc');
  static const _events = EventChannel('streamline/vlc/events');
  static final _stream = _events.receiveBroadcastStream();
  double _volume = 1;
  int? _id;
  bool _dead = false;
  StreamSubscription<dynamic>? _subscription;
  PlayerTracks? _bridge;
  final _ready = Completer<void>();
  Future<void>? _release;
  Map<dynamic, dynamic> _snapshot = const {};

  @override
  Future<void> initialize() async {
    final id = await _methods.invokeMethod<int>('create', {
      'uri': uri.toString(),
      'decoding': decoding.name,
      'live': isLive,
      'subtitleSize': preferences.subtitleSize.round(),
      'subtitleBackground': preferences.subtitleBackground,
    });
    if (id == null) throw StateError('VLC unavailable');
    _id = id;
    if (_dead) {
      await _methods.invokeMethod<void>('dispose', {'id': id});
      return;
    }
    _subscription = _stream.listen(
      (raw) {
        if (_dead || raw is! Map || raw['id'] != _id) return;
        _snapshot = raw;
        final error = raw['error'] == true;
        value = VideoPlayerValue(
          duration: Duration(
            milliseconds: (raw['duration'] as num?)?.toInt() ?? 0,
          ),
          position: Duration(
            milliseconds: (raw['position'] as num?)?.toInt() ?? 0,
          ),
          isInitialized: raw['ready'] == true,
          isPlaying: raw['playing'] == true,
          isBuffering: raw['buffering'] == true,
          isCompleted: raw['completed'] == true,
          size: Size(
            (raw['width'] as num?)?.toDouble() ?? 0,
            (raw['height'] as num?)?.toDouble() ?? 0,
          ),
          errorDescription: error ? 'VLC playback unavailable.' : null,
        );
        _publishTracks();
        if (!_ready.isCompleted && (value.isInitialized || error)) {
          if (error) {
            _ready.completeError(StateError('VLC playback unavailable'));
          } else {
            _ready.complete();
          }
        }
      },
      onError: (Object _) {
        if (_dead) return;
        value = VideoPlayerValue.erroneous('VLC playback unavailable.');
        if (!_ready.isCompleted) {
          _ready.completeError(StateError('VLC unavailable'));
        }
      },
    );
    // Keep initial playback continuous when the caller will autoplay. All
    // probing stays muted; saved-position playback pauses before resume seeking.
    await _command('load');
    await _ready.future;
    if (pauseAfterLoading) await pause();
  }

  Future<void> _command(
    String method, [
    Map<String, Object?> extra = const {},
  ]) async {
    if (_dead || _id == null) return;
    await _methods.invokeMethod<void>(method, {'id': _id, ...extra});
  }

  @override
  Future<void> play() async {
    await _command('volume', {'volume': (_volume * 100).round()});
    await _command('play');
  }

  @override
  Future<void> pause() => _command('pause');
  @override
  Future<void> seekTo(Duration position) =>
      _command('seek', {'position': position.inMilliseconds});
  @override
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0, 1);
    await _command('volume', {'volume': (_volume * 100).round()});
  }

  void _publishTracks() {
    final bridge = _bridge;
    if (_dead || bridge == null || bridge.isDisposed) return;
    bridge.value = TrackSnapshot.fromNative(_snapshot['tracks']);
  }

  @override
  Future<void> attachTracks(
    PlayerTracks bridge,
    AppSettings preferences,
  ) async {
    await bridge.detach();
    if (_dead || bridge.isDisposed) return;
    _bridge = bridge;
    bridge.externalSelection = (type, key) async {
      if (_dead || !{'audio', 'text'}.contains(type)) return false;
      try {
        await _command('track', {'type': type, 'key': key});
        return true;
      } on PlatformException {
        return false;
      }
    };
    await _command('preferences', {
      'audioLanguage': preferences.audioLanguage,
      'subtitleLanguage': preferences.subtitleLanguage,
      'subtitles': preferences.subtitles,
      'stereo': preferences.stereo,
    });
    _publishTracks();
  }

  @override
  Widget buildView() =>
      _id == null ? const SizedBox.shrink() : Texture(textureId: _id!);

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
    _bridge = null;
    if (!_ready.isCompleted) {
      _ready.completeError(StateError('Playback closed'));
    }
    final closing = _id == null
        ? Future<void>.value()
        : _methods.invokeMethod<void>('dispose', {'id': _id});
    await Future.wait([
      closing,
      if (_subscription != null) _subscription!.cancel(),
    ]);
  }
}
