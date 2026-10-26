import 'dart:async';

/// Decoder probing can report an error before falling back successfully.
/// Keep genuine failures fatal, but let observed frames/progress prove recovery.
class NativePlaybackRecovery {
  NativePlaybackRecovery(
    this.onFailure, {
    this.grace = const Duration(seconds: 2),
  });
  final void Function() onFailure;
  final Duration grace;
  Timer? _timer;
  Duration _position = Duration.zero;
  void signal(Duration position) {
    if (_timer != null) return;
    _position = position;
    _timer = Timer(grace, () {
      _timer = null;
      onFailure();
    });
  }

  void observe({
    required Duration position,
    required bool playing,
    required bool buffering,
    required bool videoOutput,
    required bool audioOnly,
  }) {
    if (_timer == null || buffering) return;
    final advancing =
        playing && position - _position >= const Duration(milliseconds: 100);
    if ((videoOutput && (!playing || advancing)) || (audioOnly && advancing)) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
