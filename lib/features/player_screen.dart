import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../core/design_system.dart';
import '../core/providers.dart';
import '../core/player_tracks.dart';
import '../data/local_store.dart';
import '../data/models.dart';

/// Keeps every seek within a known, finite on-demand timeline.
Duration clampPlaybackPosition(Duration target, Duration duration) {
  if (duration.inMilliseconds <= 0) return Duration.zero;
  return Duration(
    milliseconds: target.inMilliseconds
        .clamp(0, duration.inMilliseconds)
        .toInt(),
  );
}

String formatPlaybackTime(Duration value) {
  final seconds = value.inSeconds < 0 ? 0 : value.inSeconds;
  final hours = seconds ~/ 3600;
  final minutes = (seconds ~/ 60) % 60;
  final remaining = seconds % 60;
  final mm = minutes.toString().padLeft(2, '0');
  final ss = remaining.toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
}

/// Native Android playback uses video_player's ExoPlayer implementation.
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({
    super.key,
    required this.item,
    this.episode,
    this.startPosition = Duration.zero,
    this.channels = const [],
    this.episodes = const [],
  });

  final MediaItem item;
  final Episode? episode;
  final Duration startPosition;
  final List<MediaItem> channels;
  final List<Episode> episodes;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with WidgetsBindingObserver {
  static const _platform = MethodChannel('streamline/platform');
  final _surfaceFocus = FocusNode(debugLabel: 'Video surface');
  final _playFocus = FocusNode(debugLabel: 'Player play pause');
  final _controllerReleases = Expando<Future<void>>('controller releases');
  final _recordedLiveControllers = Expando<bool>('recorded live controllers');
  late final LocalStore _store;
  late final Session? _session;
  late final List<MediaItem> _channels;
  late MediaItem _item;
  VideoPlayerController? _controller;
  Timer? _progressTimer;
  Timer? _retryTimer;
  Timer? _initializationTimer;
  Timer? _nextTimer;
  final _tracks = PlayerTracks();
  Episode? _episode;
  BoxFit _pictureFit = BoxFit.contain;
  int _retryCount = 0;
  int? _nextSeconds;
  bool _completionHandled = false;
  bool _advancing = false;
  bool _wantsPlayback = true;
  Duration _resumePosition = Duration.zero;
  DateTime? _bufferingSince;
  DateTime? _healthySince;
  Future<void> _historyWrites = Future<void>.value();
  Future<void> _channelHistoryWrites = Future<void>.value();
  int _generation = 0;
  int _channelIndex = 0;
  bool _loading = true;
  bool _exiting = false;
  bool _saveFailed = false;
  bool _appActive = true;
  String? _playbackError;
  double? _dragPosition;
  DateTime? _lastZap;

  bool get _isLive => _item.kind == MediaKind.live;
  bool get _tracksHistory =>
      _item.kind == MediaKind.movie ||
      (_item.kind == MediaKind.series && _episode != null);
  Episode? get _nextEpisode {
    final index = widget.episodes.indexWhere(
      (episode) => episode.id == _episode?.id,
    );
    return index >= 0 && index + 1 < widget.episodes.length
        ? widget.episodes[index + 1]
        : null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _store = ref.read(storeProvider);
    _session = ref.read(sessionProvider);
    _item = widget.item;
    _episode = widget.episode;
    _resumePosition = widget.startPosition;
    _channels = widget.channels
        .where((item) => item.kind == MediaKind.live)
        .toList();
    if (_isLive && !_channels.any((item) => item.id == _item.id)) {
      _channels.insert(0, _item);
    }
    _channelIndex = _channels.indexWhere((item) => item.id == _item.id);
    if (_channelIndex < 0) _channelIndex = 0;
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
    unawaited(_keepScreenOn(true));
    final session = _session;
    if (_item.kind == MediaKind.movie && session != null) {
      unawaited(
        _enqueueHistory(
          () => _store.recordOpened(session.accountId, widget.item),
        ),
      );
    }
    unawaited(_open(_item, startPosition: widget.startPosition));
    _progressTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(_persistProgress());
      _checkBuffering();
    });
  }

  Future<void> _keepScreenOn(bool enabled) async {
    try {
      await _platform.invokeMethod<void>('setKeepScreenOn', enabled);
    } on MissingPluginException {
      // Native window flags are unavailable in tests and on other platforms.
    } on PlatformException {
      // Screen-awake support must never prevent video playback or teardown.
    }
  }

  Future<void> _enqueueHistory(Future<void> Function() write) {
    // Serialize opens and progress updates so a slow earlier write cannot
    // overwrite a newer playback position or the movie's last-accessed time.
    _historyWrites = _historyWrites.then((_) async {
      try {
        await write();
        if (!mounted) return;
        ref.invalidate(historyProvider);
        ref.invalidate(seriesHistoryProvider);
        if (_saveFailed && !_exiting) setState(() => _saveFailed = false);
      } catch (_) {
        if (mounted && !_exiting) setState(() => _saveFailed = true);
      }
    });
    return _historyWrites;
  }

  Future<void> _persistProgress() {
    final controller = _controller;
    final session = _session;
    if (!_tracksHistory || session == null || controller == null) {
      return _historyWrites;
    }
    final value = controller.value;
    if (!value.isInitialized || value.duration.inMilliseconds <= 0) {
      return _historyWrites;
    }
    final position = clampPlaybackPosition(value.position, value.duration);
    final duration = value.duration;
    final item = _item;
    final episode = _episode;
    final next = _nextEpisode;
    return _enqueueHistory(
      () => episode != null && item.kind == MediaKind.series
          ? _store.saveEpisodeProgress(
              session.accountId,
              item,
              episode,
              positionMs: position.inMilliseconds,
              durationMs: duration.inMilliseconds,
              nextEpisode: next,
            )
          : _store.saveProgress(
              session.accountId,
              item,
              positionMs: position.inMilliseconds,
              durationMs: duration.inMilliseconds,
            ),
    );
  }

  bool _isCurrentChannelPlayback(
    VideoPlayerController controller,
    int generation,
    MediaItem item,
    Session session,
  ) {
    return mounted &&
        !_exiting &&
        generation == _generation &&
        identical(controller, _controller) &&
        item.kind == MediaKind.live &&
        _item == item &&
        ref.read(sessionProvider)?.accountId == session.accountId;
  }

  void _recordLivePlayback(
    VideoPlayerController controller,
    int generation,
    MediaItem item,
  ) {
    final session = _session;
    if (session == null ||
        !_isCurrentChannelPlayback(controller, generation, item, session) ||
        !controller.value.isInitialized ||
        !controller.value.isPlaying ||
        controller.value.hasError ||
        _recordedLiveControllers[controller] == true) {
      return;
    }
    _recordedLiveControllers[controller] = true;
    // Keep writes in playback order without holding up opening or zapping.
    // Capture the channel/account now; a later zap must not change either.
    // This accepted play event remains valid after another zap or route exit.
    _channelHistoryWrites = _channelHistoryWrites.then((_) async {
      try {
        await _store.recordChannelPlayed(session.accountId, item);
        if (mounted &&
            ref.read(sessionProvider)?.accountId == session.accountId) {
          ref.invalidate(recentChannelsProvider);
        }
      } catch (_) {
        // Recent-channel storage is optional; playback remains available.
      }
    });
  }

  Future<void> _release(VideoPlayerController controller) {
    final existing = _controllerReleases[controller];
    if (existing != null) return existing;
    final release = _disposeController(controller);
    _controllerReleases[controller] = release;
    return release;
  }

  Future<void> _disposeController(VideoPlayerController controller) async {
    controller.removeListener(_onControllerChanged);
    try {
      await controller.pause();
    } catch (_) {
      // An initialization can be interrupted by rapid channel navigation.
    }
    try {
      await controller.dispose();
    } catch (_) {
      // Teardown must not prevent an exit or another channel from opening.
    }
  }

  Future<void> _open(
    MediaItem item, {
    Duration startPosition = Duration.zero,
    Episode? episode,
  }) async {
    _retryTimer?.cancel();
    _initializationTimer?.cancel();
    _cancelNext();
    _bufferingSince = null;
    _healthySince = null;
    final generation = ++_generation;
    await _tracks.detach();
    if (!mounted || generation != _generation || _exiting) return;
    final previous = _controller;
    _controller = null;
    if (mounted) {
      setState(() {
        _item = item;
        if (episode != null) _episode = episode;
        _loading = true;
        _playbackError = null;
        _dragPosition = null;
      });
    }
    if (previous != null) await _release(previous);
    if (!mounted || generation != _generation || _exiting) return;

    VideoPlayerController? controller;
    try {
      final session = _session;
      if (session == null) {
        setState(() {
          _loading = false;
          _playbackError = 'Your session has ended. Sign in again to play.';
        });
        return;
      }
      final uri = ref
          .read(apiProvider)
          .streamUri(session, item, episode: _episode);
      controller = VideoPlayerController.networkUrl(
        uri,
        formatHint: uri.path.toLowerCase().endsWith('.m3u8')
            ? VideoFormat.hls
            : null,
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: false,
          allowBackgroundPlayback: false,
        ),
      );
      _controller = controller;
      controller.addListener(_onControllerChanged);
      await _initialize(controller);
      if (!mounted || generation != _generation || _exiting) {
        await _release(controller);
        return;
      }
      if (!_isLive && startPosition > Duration.zero) {
        await controller.seekTo(
          clampPlaybackPosition(startPosition, controller.value.duration),
        );
      }
      if (!mounted || generation != _generation || _exiting) return;
      if (_appActive && _wantsPlayback) await controller.play();
      if (!mounted || generation != _generation || _exiting) return;
      unawaited(_tracks.attach(controller));
      _recordLivePlayback(controller, generation, item);
      setState(() => _loading = false);
    } catch (_) {
      // Native playback exceptions often include the complete stream URI,
      // including Xtream credentials. Never expose those exception strings.
      if (mounted && generation == _generation && !_exiting) {
        setState(() {
          _loading = false;
          _playbackError =
              'This stream could not be played. Check your connection or try again.';
        });
      }
      if (controller != null) await _release(controller);
      if (mounted && generation == _generation && !_exiting) {
        _scheduleReconnect();
      }
    }
  }

  void _onControllerChanged() {
    if (!mounted || _exiting) return;
    final value = _controller?.value;
    if (value == null) return;
    if (value.isInitialized && !value.hasError) {
      _resumePosition = clampPlaybackPosition(value.position, value.duration);
      if (value.isPlaying && !value.isBuffering) {
        _healthySince ??= DateTime.now();
        if (DateTime.now().difference(_healthySince!).inSeconds >= 30) {
          _retryCount = 0;
        }
      } else {
        _healthySince = null;
      }
    }
    if (value.isCompleted &&
        !_advancing &&
        !_completionHandled &&
        _nextEpisode != null &&
        _appActive &&
        _wantsPlayback) {
      _startNextCountdown();
    }
    if (value.hasError && !_loading) _scheduleReconnect();
    setState(() {
      if (value.hasError) {
        _loading = false;
        _playbackError =
            'Playback stopped. Check your connection or try this stream again.';
      }
    });
  }

  Future<void> _pauseAndSave() async {
    _wantsPlayback = false;
    _retryTimer?.cancel();
    _cancelNext();
    final controller = _controller;
    // Capture position before pausing: another lifecycle callback may arrive
    // while the native pause request is still in flight.
    final saved = _persistProgress();
    if (controller != null && controller.value.isInitialized) {
      try {
        await controller.pause();
      } catch (_) {}
    }
    await saved;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_pauseAndSave());
    }
  }

  Future<void> _leave() async {
    if (_exiting) return;
    _exiting = true;
    _initializationTimer?.cancel();
    _retryTimer?.cancel();
    _cancelNext();
    _progressTimer?.cancel();
    await _pauseAndSave();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _togglePlayback() async {
    final controller = _controller;
    final generation = _generation;
    final item = _item;
    if (_exiting || controller == null || !controller.value.isInitialized) {
      return;
    }
    try {
      if (controller.value.isPlaying) {
        _wantsPlayback = false;
        _retryTimer?.cancel();
        _cancelNext();
        await controller.pause();
        await _persistProgress();
      } else if (_appActive) {
        _wantsPlayback = true;
        if (!_isLive &&
            controller.value.duration > Duration.zero &&
            controller.value.position >= controller.value.duration) {
          _completionHandled = false;
          await controller.seekTo(Duration.zero);
        }
        await controller.play();
        _recordLivePlayback(controller, generation, item);
      }
    } catch (_) {
      if (mounted && !_exiting) {
        setState(() => _playbackError = 'Playback is unavailable. Try again.');
      }
    }
  }

  Future<void> _seekTo(Duration position) async {
    final controller = _controller;
    if (_exiting ||
        _isLive ||
        controller == null ||
        !controller.value.isInitialized ||
        controller.value.duration <= Duration.zero) {
      return;
    }
    try {
      await controller.seekTo(
        clampPlaybackPosition(position, controller.value.duration),
      );
      await _persistProgress();
    } catch (_) {
      // A channel switch or exit can dispose a controller during a seek.
    }
  }

  void _seekRelative(int seconds) {
    final position = _controller?.value.position;
    if (position != null) {
      unawaited(_seekTo(position + Duration(seconds: seconds)));
    }
  }

  void _zap(int delta) {
    if (_exiting || !_isLive || _channels.length < 2) return;
    final now = DateTime.now();
    if (_lastZap != null && now.difference(_lastZap!).inMilliseconds < 250) {
      return;
    }
    _lastZap = now;
    _retryCount = 0;
    _wantsPlayback = true;
    _channelIndex = (_channelIndex + delta) % _channels.length;
    unawaited(_open(_channels[_channelIndex]));
  }

  void _retry() {
    if (_exiting) return;
    _retryCount = 0;
    _wantsPlayback = true;
    final value = _controller?.value;
    final position = value != null && value.isInitialized
        ? clampPlaybackPosition(value.position, value.duration)
        : _resumePosition;
    unawaited(_open(_item, startPosition: position));
  }

  Future<void> _initialize(VideoPlayerController controller) {
    final complete = Completer<void>();
    final timer = Timer(const Duration(seconds: 25), () {
      if (!complete.isCompleted) {
        complete.completeError(
          TimeoutException('Stream initialization timed out'),
        );
      }
    });
    _initializationTimer = timer;
    controller.initialize().then(
      (_) {
        timer.cancel();
        if (!complete.isCompleted) complete.complete();
      },
      onError: (Object error, StackTrace stack) {
        timer.cancel();
        if (!complete.isCompleted) complete.completeError(error, stack);
      },
    );
    return complete.future;
  }

  void _checkBuffering() {
    final value = _controller?.value;
    if (_loading ||
        !_appActive ||
        !_wantsPlayback ||
        value == null ||
        value.isCompleted) {
      return;
    }
    if (value.isBuffering) {
      _bufferingSince ??= DateTime.now();
      if (DateTime.now().difference(_bufferingSince!).inSeconds >= 20) {
        _scheduleReconnect();
        if (mounted) {
          setState(() => _playbackError = 'The stream stalled. Reconnecting…');
        }
      }
    } else {
      _bufferingSince = null;
    }
  }

  void _scheduleReconnect() {
    if (_retryTimer?.isActive == true ||
        !_appActive ||
        !_wantsPlayback ||
        _exiting ||
        _retryCount >= 3 ||
        ref.read(sessionProvider)?.accountId != _session?.accountId) {
      return;
    }
    final generation = _generation;
    final position = _resumePosition;
    final seconds = 2 << _retryCount;
    _retryCount++;
    _retryTimer = Timer(Duration(seconds: seconds), () async {
      if (!mounted ||
          _exiting ||
          !_appActive ||
          !_wantsPlayback ||
          generation != _generation) {
        return;
      }
      await _persistProgress();
      if (!mounted ||
          _exiting ||
          !_appActive ||
          !_wantsPlayback ||
          generation != _generation) {
        return;
      }
      unawaited(_open(_item, startPosition: position));
    });
  }

  void _cancelNext() {
    _nextTimer?.cancel();
    _nextSeconds = null;
  }

  void _startNextCountdown() {
    _completionHandled = true;
    _nextSeconds = 8;
    unawaited(_persistProgress());
    _nextTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _exiting || !_appActive) {
        _cancelNext();
        return;
      }
      if ((_nextSeconds ?? 0) <= 1) {
        unawaited(_advanceEpisode());
      } else {
        setState(() => _nextSeconds = _nextSeconds! - 1);
      }
    });
  }

  Future<void> _advanceEpisode() async {
    final next = _nextEpisode;
    if (next == null || _advancing || _exiting) return;
    _advancing = true;
    _cancelNext();
    await _persistProgress();
    if (!mounted || _exiting || !_appActive) {
      _advancing = false;
      return;
    }
    _completionHandled = false;
    _retryCount = 0;
    _resumePosition = Duration.zero;
    _wantsPlayback = true;
    await _open(_item, episode: next);
    _advancing = false;
  }

  Widget _extraControls() => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      children: [
        TextButton.icon(
          onPressed: () => _chooseTracks('audio'),
          icon: const Icon(Icons.audiotrack, size: 18),
          label: const Text('Audio'),
        ),
        TextButton.icon(
          onPressed: () => _chooseTracks('text'),
          icon: const Icon(Icons.subtitles_outlined, size: 18),
          label: const Text('Subtitles'),
        ),
        TextButton.icon(
          onPressed: () => setState(
            () => _pictureFit = _pictureFit == BoxFit.contain
                ? BoxFit.cover
                : _pictureFit == BoxFit.cover
                ? BoxFit.fill
                : BoxFit.contain,
          ),
          icon: const Icon(Icons.aspect_ratio, size: 18),
          label: Text(
            'Picture: ${_pictureFit == BoxFit.contain
                ? 'Fit'
                : _pictureFit == BoxFit.cover
                ? 'Fill'
                : 'Stretch'}',
          ),
        ),
        if (_nextEpisode != null)
          TextButton.icon(
            onPressed: () => unawaited(_advanceEpisode()),
            icon: const Icon(Icons.skip_next, size: 18),
            label: const Text('Next episode'),
          ),
      ],
    ),
  );

  Future<void> _chooseTracks(String type) async {
    final snapshot = _tracks.value;
    final tracks = snapshot.tracks
        .where((track) => track.type == type)
        .toList();
    final key = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(type == 'audio' ? 'Audio' : 'Subtitles'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!snapshot.available)
                  const Text('Track selection is unavailable for this player.')
                else ...[
                  ListTile(
                    title: Text(type == 'audio' ? 'Automatic' : 'Off'),
                    trailing:
                        (type == 'audio'
                            ? snapshot.audioAuto
                            : snapshot.textOff)
                        ? const Icon(Icons.check)
                        : null,
                    onTap: () => Navigator.pop(
                      context,
                      type == 'audio' ? 'auto' : 'off',
                    ),
                  ),
                  if (type == 'text')
                    ListTile(
                      title: const Text('Automatic'),
                      onTap: () => Navigator.pop(context, 'auto'),
                    ),
                  for (final track in tracks)
                    ListTile(
                      enabled: track.supported,
                      title: Text(track.label),
                      subtitle: !track.supported
                          ? const Text('Unsupported format')
                          : null,
                      trailing: track.selected ? const Icon(Icons.check) : null,
                      onTap: track.supported
                          ? () => Navigator.pop(context, track.key)
                          : null,
                    ),
                  if (tracks.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'No tracks of this type supplied by the stream.',
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    if (key == null || !mounted || _exiting) return;
    if (!await _tracks.select(type, key) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This track could not be selected. Reopen the menu to try again.',
          ),
        ),
      );
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      if (event is KeyDownEvent) unawaited(_leave());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaPlayPause ||
        key == LogicalKeyboardKey.space) {
      if (event is KeyDownEvent) unawaited(_togglePlayback());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaPlay) {
      final controller = _controller;
      if (event is KeyDownEvent &&
          controller != null &&
          !controller.value.isPlaying) {
        unawaited(_togglePlayback());
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaPause) {
      if (event is KeyDownEvent) unawaited(_pauseAndSave());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaTrackNext && _isLive) {
      _zap(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaTrackPrevious && _isLive) {
      _zap(-1);
      return KeyEventResult.handled;
    }
    if (!_surfaceFocus.hasPrimaryFocus) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (event is KeyDownEvent) {
        if (_playbackError != null) {
          _retry();
        } else {
          unawaited(_togglePlayback());
        }
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft && !_isLive) {
      _seekRelative(-10);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight && !_isLive) {
      _seekRelative(30);
      return KeyEventResult.handled;
    }
    if (_isLive && key == LogicalKeyboardKey.arrowUp) {
      _zap(-1);
      return KeyEventResult.handled;
    }
    if (_isLive && key == LogicalKeyboardKey.arrowDown) {
      _zap(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.contextMenu ||
        (!_isLive && key == LogicalKeyboardKey.arrowDown)) {
      _playFocus.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _progressTimer?.cancel();
    _retryTimer?.cancel();
    _nextTimer?.cancel();
    _initializationTimer?.cancel();
    _tracks.dispose();
    // Normal exits await this queue; this fallback also captures an unexpected
    // route removal without retaining access to Riverpod after disposal.
    unawaited(_persistProgress());
    _generation++;
    final controller = _controller;
    _controller = null;
    if (controller != null) unawaited(_release(controller));
    _surfaceFocus.dispose();
    _playFocus.dispose();
    unawaited(_keepScreenOn(false));
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tv = ref.watch(isTvProvider);
    final controller = _controller;
    final value = controller?.value;
    final ready = value?.isInitialized ?? false;
    final error = _playbackError;
    final title = _episode?.title ?? _item.name;
    final compact = MediaQuery.sizeOf(context).height < 460;

    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_leave());
      },
      child: Focus(
        autofocus: true,
        focusNode: _surfaceFocus,
        onKeyEvent: _onKey,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _surfaceFocus.requestFocus(),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (ready && controller != null && error == null)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onDoubleTap: () => unawaited(_togglePlayback()),
                    child: Center(
                      child: SizedBox.expand(
                        child: ClipRect(
                          child: FittedBox(
                            fit: _pictureFit,
                            child: SizedBox(
                              width: value!.size.width > 0
                                  ? value.size.width
                                  : 16,
                              height: value.size.height > 0
                                  ? value.size.height
                                  : 9,
                              child: VideoPlayer(controller),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ValueListenableBuilder<TrackSnapshot>(
                  valueListenable: _tracks,
                  builder: (context, tracks, _) => Positioned(
                    left: 24,
                    right: 24,
                    bottom: compact ? 175 : 230,
                    child: IgnorePointer(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final bytes in tracks.images)
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 120),
                              child: Image.memory(
                                bytes,
                                errorBuilder: (_, __, ___) =>
                                    const SizedBox.shrink(),
                              ),
                            ),
                          if (tracks.caption.isNotEmpty)
                            Text(
                              tracks.caption,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 22,
                                color: Colors.white,
                                backgroundColor: Colors.black87,
                                shadows: [
                                  Shadow(blurRadius: 3, color: Colors.black),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0xE3080A0D),
                          Color(0x23080A0D),
                          Color(0x10080A0D),
                          Color(0xF2080A0D),
                        ],
                        stops: [0, .28, .52, 1],
                      ),
                    ),
                  ),
                ),
                if (_loading && error == null)
                  _waitingIndicator(context, 'Opening stream'),
                if (error != null) _buildPlaybackError(context, error),
                if (ready && value!.isBuffering && !_loading && error == null)
                  _waitingIndicator(context, 'Buffering'),
                SafeArea(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: tv
                          ? 44
                          : compact
                          ? 22
                          : 20,
                      vertical: tv
                          ? 30
                          : compact
                          ? 12
                          : 20,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _playerHeader(context, title, tv, compact),
                        const Spacer(),
                        if (_nextSeconds != null)
                          Align(
                            alignment: Alignment.centerRight,
                            child: Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 12,
                                  children: [
                                    Text('Next episode in $_nextSeconds'),
                                    FilledButton(
                                      onPressed: () =>
                                          unawaited(_advanceEpisode()),
                                      child: const Text('Play next'),
                                    ),
                                    TextButton(
                                      onPressed: () => setState(_cancelNext),
                                      child: const Text('Cancel'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        if (_saveFailed)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.info_outline_rounded,
                                  color: AppColors.accent,
                                  size: 16,
                                ),
                                SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    'Playback progress could not be saved.',
                                    style: TextStyle(
                                      color: AppColors.accent,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (ready && error == null)
                          _buildControls(context, value!, tv),
                        if (ready && error == null) _extraControls(),
                        if (tv)
                          Padding(
                            padding: const EdgeInsets.only(top: 22),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.settings_remote_outlined,
                                  size: 14,
                                  color: AppColors.subdued,
                                ),
                                const SizedBox(width: 9),
                                Flexible(
                                  child: Text(
                                    error != null
                                        ? 'OK Retry   ·   Back Exit'
                                        : _isLive
                                        ? '↑ / ↓ Channel   ·   OK Play / pause   ·   Menu Controls'
                                        : '← / → Seek   ·   OK Play / pause   ·   ↓ Controls',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: AppColors.muted,
                                      fontSize: 11,
                                      letterSpacing: .3,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _playerHeader(
    BuildContext context,
    String title,
    bool tv,
    bool compact,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        IconButton(
          tooltip: 'Back',
          onPressed: () => unawaited(_leave()),
          icon: const Icon(Icons.arrow_back_rounded),
          style: _transportStyle(tv, compact: compact),
        ),
        SizedBox(width: tv ? 20 : 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (_isLive) ...[
                    Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                        color: AppColors.live,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 7),
                  ],
                  Text(
                    _isLive
                        ? 'LIVE TELEVISION'
                        : _episode == null
                        ? 'MOVIE'
                        : 'SERIES',
                    style: TextStyle(
                      color: _isLive ? AppColors.live : AppColors.accent,
                      letterSpacing: 2.2,
                      fontSize: compact ? 9 : 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                title,
                maxLines: compact ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppColors.text,
                  fontSize: tv
                      ? 30
                      : compact
                      ? 20
                      : 25,
                  height: 1.15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (_isLive && !compact) ...[
                const SizedBox(height: 7),
                Text(
                  'Channel ${_channelIndex + 1} / ${_channels.length}',
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 12,
                    letterSpacing: .25,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (MediaQuery.sizeOf(context).width >= 700) ...[
          const SizedBox(width: 24),
          const StreamlineMark(size: 25),
        ],
      ],
    );
  }

  Widget _waitingIndicator(BuildContext context, String label) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 32,
            child: MediaQuery.disableAnimationsOf(context)
                ? const Icon(
                    Icons.hourglass_empty_rounded,
                    color: AppColors.accent,
                    size: 28,
                  )
                : const CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.accent,
                  ),
          ),
          const SizedBox(height: 18),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 12,
              letterSpacing: .7,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaybackError(BuildContext context, String error) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.videocam_off_outlined,
                color: AppColors.accent,
                size: 34,
              ),
              const SizedBox(height: 20),
              const Eyebrow('PLAYBACK UNAVAILABLE'),
              const SizedBox(height: 12),
              Text(
                error,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.muted,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _retry,
                icon: const Icon(Icons.refresh_rounded, size: 19),
                label: const Text('Try again'),
              ),
              if (_retryTimer?.isActive == true)
                TextButton(
                  onPressed: () => setState(() {
                    _retryTimer?.cancel();
                    _wantsPlayback = false;
                  }),
                  child: Text('Cancel reconnect ($_retryCount/3)'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  ButtonStyle _transportStyle(bool tv, {bool compact = false}) {
    final dimension = tv
        ? 62.0
        : compact
        ? 44.0
        : 52.0;
    return ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size.square(dimension)),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? AppColors.subdued
            : AppColors.text,
      ),
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.focused)
            ? AppColors.accent.withValues(alpha: .2)
            : AppColors.surface.withValues(alpha: .45),
      ),
      side: WidgetStateProperty.resolveWith(
        (states) => BorderSide(
          color: states.contains(WidgetState.focused)
              ? AppColors.accent
              : AppColors.text.withValues(alpha: .12),
          width: states.contains(WidgetState.focused) ? 2 : 1,
        ),
      ),
      shape: const WidgetStatePropertyAll(CircleBorder()),
      iconSize: WidgetStatePropertyAll(tv ? 30 : 26),
    );
  }

  Widget _buildControls(BuildContext context, VideoPlayerValue value, bool tv) {
    final durationMs = value.duration.inMilliseconds;
    final positionMs = clampPlaybackPosition(
      value.position,
      value.duration,
    ).inMilliseconds;
    final hasTimeline = !_isLive && durationMs > 0;
    final position = (_dragPosition ?? positionMs.toDouble())
        .clamp(0, durationMs > 0 ? durationMs.toDouble() : 1.0)
        .toDouble();
    final compact = MediaQuery.sizeOf(context).height < 460;

    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: Focus(
        skipTraversal: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.arrowUp) {
            _surfaceFocus.requestFocus();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isLive) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 5,
                    height: 5,
                    decoration: const BoxDecoration(
                      color: AppColors.live,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'WATCHING LIVE',
                    style: TextStyle(
                      color: AppColors.text,
                      fontWeight: FontWeight.w600,
                      fontSize: 10,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
              SizedBox(height: compact ? 14 : 24),
            ],
            if (hasTimeline) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      formatPlaybackTime(
                        Duration(milliseconds: position.round()),
                      ),
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: .7,
                      ),
                    ),
                    Text(
                      formatPlaybackTime(value.duration),
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                        letterSpacing: .7,
                      ),
                    ),
                  ],
                ),
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  activeTrackColor: AppColors.accent,
                  inactiveTrackColor: AppColors.text.withValues(alpha: .18),
                  thumbColor: AppColors.text,
                  overlayColor: AppColors.accent.withValues(alpha: .15),
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 5,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 14,
                  ),
                  trackShape: const RectangularSliderTrackShape(),
                ),
                child: Slider(
                  value: position,
                  max: durationMs.toDouble(),
                  label: formatPlaybackTime(
                    Duration(milliseconds: position.round()),
                  ),
                  onChanged: (value) => setState(() => _dragPosition = value),
                  onChangeEnd: (value) {
                    setState(() => _dragPosition = null);
                    unawaited(_seekTo(Duration(milliseconds: value.round())));
                  },
                ),
              ),
              SizedBox(height: compact ? 2 : 10),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: _isLive ? 'Previous channel' : 'Rewind 10 seconds',
                  style: _transportStyle(tv, compact: compact),
                  onPressed: _isLive
                      ? _channels.length > 1
                            ? () => _zap(-1)
                            : null
                      : hasTimeline
                      ? () => _seekRelative(-10)
                      : null,
                  icon: Icon(_isLive ? Icons.skip_previous : Icons.replay_10),
                ),
                SizedBox(width: tv ? 28 : 20),
                FilledButton(
                  focusNode: _playFocus,
                  onPressed: () => unawaited(_togglePlayback()),
                  style: ButtonStyle(
                    minimumSize: WidgetStatePropertyAll(
                      Size(
                        tv ? 148 : 124,
                        tv
                            ? 66
                            : compact
                            ? 48
                            : 56,
                      ),
                    ),
                    padding: WidgetStatePropertyAll(
                      EdgeInsets.symmetric(
                        horizontal: tv ? 28 : 22,
                        vertical: compact ? 10 : 14,
                      ),
                    ),
                    shape: const WidgetStatePropertyAll(StadiumBorder()),
                    foregroundColor: const WidgetStatePropertyAll(
                      AppColors.canvas,
                    ),
                    backgroundColor: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.focused)
                          ? AppColors.text
                          : AppColors.accent,
                    ),
                    side: WidgetStateProperty.resolveWith(
                      (states) => BorderSide(
                        color: states.contains(WidgetState.focused)
                            ? AppColors.text
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        value.isPlaying ? Icons.pause : Icons.play_arrow,
                        size: tv ? 30 : 26,
                      ),
                      const SizedBox(width: 7),
                      Text(value.isPlaying ? 'Pause' : 'Play'),
                    ],
                  ),
                ),
                SizedBox(width: tv ? 28 : 20),
                IconButton(
                  tooltip: _isLive ? 'Next channel' : 'Forward 30 seconds',
                  style: _transportStyle(tv, compact: compact),
                  onPressed: _isLive
                      ? _channels.length > 1
                            ? () => _zap(1)
                            : null
                      : hasTimeline
                      ? () => _seekRelative(30)
                      : null,
                  icon: Icon(_isLive ? Icons.skip_next : Icons.forward_30),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
