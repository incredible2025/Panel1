import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../data/models.dart';

class PlayerTrack {
  const PlayerTrack({
    required this.key,
    required this.type,
    required this.label,
    required this.selected,
    required this.supported,
  });
  final String key;
  final String type;
  final String label;
  final bool selected;
  final bool supported;
}

class TrackSnapshot {
  const TrackSnapshot({
    this.available = false,
    this.tracks = const [],
    this.caption = '',
    this.images = const [],
    this.textOff = true,
    this.audioAuto = true,
  });
  final bool available;
  final List<PlayerTrack> tracks;
  final String caption;
  final List<Uint8List> images;
  final bool textOff;
  final bool audioAuto;
  factory TrackSnapshot.fromNative(dynamic raw) {
    final map = objectValue(raw);
    return TrackSnapshot(
      available: true,
      tracks: objectList(map['tracks'])
          .take(200)
          .map(
            (track) => PlayerTrack(
              key: textValue(track['key']),
              type: textValue(track['type']),
              label: textValue(track['label'], 'Track'),
              selected: track['selected'] == true,
              supported: track['supported'] == true,
            ),
          )
          .toList(),
      caption: textValue(map['caption']),
      images: map['images'] is List
          ? (map['images'] as List).whereType<Uint8List>().toList()
          : const [],
      textOff: map['textOff'] != false,
      audioAuto: map['audioAuto'] != false,
    );
  }
}

/// Isolates the pinned Android player's ID and app-scoped native track API.
class PlayerTracks extends ValueNotifier<TrackSnapshot> {
  PlayerTracks() : super(const TrackSnapshot());
  static const _methods = MethodChannel('streamline/player_tracks');
  static const _events = EventChannel('streamline/player_tracks/events');
  StreamSubscription<dynamic>? _subscription;
  int? _id;
  int _epoch = 0;
  bool _disposed = false;

  Future<void> attach(VideoPlayerController controller) async {
    final epoch = ++_epoch;
    _id = null;
    final previous = _subscription;
    _subscription = null;
    if (!_disposed) value = const TrackSnapshot();
    try {
      await previous?.cancel();
    } catch (_) {}
    if (_disposed || epoch != _epoch) return;
    // The upstream controller exposes this read-only ID for testing. The app
    // deliberately pins 2.10.1 and uses it only for its native track extension.
    // ignore: invalid_use_of_visible_for_testing_member
    final id = controller.playerId;
    if (_disposed || !controller.value.isInitialized || id < 0) return;
    try {
      final snapshot = await _methods.invokeMethod<dynamic>('snapshot', {
        'playerId': id,
      });
      if (_disposed || epoch != _epoch) return;
      _id = id;
      value = TrackSnapshot.fromNative(snapshot);
      _subscription = _events
          .receiveBroadcastStream({'playerId': id})
          .listen(
            (raw) {
              if (!_disposed && epoch == _epoch) {
                value = TrackSnapshot.fromNative(raw);
              }
            },
            onError: (Object _) {
              /* A lost track update never interrupts video. */
            },
          );
    } on MissingPluginException {
      /* Tests and non-Android targets have no native tracks. */
    } on PlatformException {
      /* Unavailable track metadata does not block playback. */
    }
  }

  Future<bool> select(String type, String key) async {
    final id = _id;
    final epoch = _epoch;
    if (id == null || _disposed || !{'audio', 'text'}.contains(type)) {
      return false;
    }
    try {
      final snapshot = await _methods.invokeMethod<dynamic>('select', {
        'playerId': id,
        'type': type,
        'key': key,
      });
      if (_disposed || epoch != _epoch) return false;
      value = TrackSnapshot.fromNative(snapshot);
      return true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> detach() async {
    _epoch++;
    _id = null;
    final subscription = _subscription;
    _subscription = null;
    if (!_disposed) value = const TrackSnapshot();
    try {
      await subscription?.cancel();
    } catch (_) {
      /* Disposed native player. */
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(detach());
    super.dispose();
  }
}
