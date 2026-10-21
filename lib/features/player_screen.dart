import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../core/providers.dart';
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
  });

  final MediaItem item;
  final Episode? episode;
  final Duration startPosition;
  final List<MediaItem> channels;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with WidgetsBindingObserver {
  static const _platform = MethodChannel('streamline/platform');
  final _surfaceFocus = FocusNode(debugLabel: 'Video surface');
  final _playFocus = FocusNode(debugLabel: 'Player play pause');
  final _controllerReleases = Expando<Future<void>>('controller releases');
  late final LocalStore _store;
  late final Session? _session;
  late final List<MediaItem> _channels;
  late MediaItem _item;
  VideoPlayerController? _controller;
  Timer? _progressTimer;
  Future<void> _historyWrites = Future<void>.value();
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
  bool get _tracksHistory => widget.item.kind == MediaKind.movie;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _store = ref.read(storeProvider);
    _session = ref.read(sessionProvider);
    _item = widget.item;
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
    if (_tracksHistory && session != null) {
      unawaited(
        _enqueueHistory(
          () => _store.recordOpened(session.accountId, widget.item),
        ),
      );
    }
    unawaited(_open(_item, startPosition: widget.startPosition));
    _progressTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(_persistProgress());
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
    return _enqueueHistory(
      () => _store.saveProgress(
        session.accountId,
        widget.item,
        positionMs: position.inMilliseconds,
        durationMs: duration.inMilliseconds,
      ),
    );
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
  }) async {
    final generation = ++_generation;
    final previous = _controller;
    _controller = null;
    if (mounted) {
      setState(() {
        _item = item;
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
          .streamUri(session, item, episode: widget.episode);
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
      await controller.initialize();
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
      if (_appActive) await controller.play();
      if (!mounted || generation != _generation || _exiting) return;
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
    }
  }

  void _onControllerChanged() {
    if (!mounted || _exiting) return;
    final value = _controller?.value;
    if (value == null) return;
    setState(() {
      if (value.hasError) {
        _loading = false;
        _playbackError =
            'Playback stopped. Check your connection or try this stream again.';
      }
    });
  }

  Future<void> _pauseAndSave() async {
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
    _progressTimer?.cancel();
    await _pauseAndSave();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _togglePlayback() async {
    final controller = _controller;
    if (_exiting || controller == null || !controller.value.isInitialized) {
      return;
    }
    try {
      if (controller.value.isPlaying) {
        await controller.pause();
        await _persistProgress();
      } else if (_appActive) {
        if (!_isLive &&
            controller.value.duration > Duration.zero &&
            controller.value.position >= controller.value.duration) {
          await controller.seekTo(Duration.zero);
        }
        await controller.play();
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
    _channelIndex = (_channelIndex + delta) % _channels.length;
    unawaited(_open(_channels[_channelIndex]));
  }

  void _retry() {
    if (_exiting) return;
    final value = _controller?.value;
    final position = value != null && value.isInitialized
        ? clampPlaybackPosition(value.position, value.duration)
        : widget.startPosition;
    unawaited(_open(_item, startPosition: position));
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
    final title = widget.episode?.title ?? _item.name;

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
                      child: AspectRatio(
                        aspectRatio: value!.aspectRatio > 0
                            ? value.aspectRatio
                            : 16 / 9,
                        child: VideoPlayer(controller),
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
                          Color(0xC9000000),
                          Colors.transparent,
                          Colors.transparent,
                          Color(0xE6000000),
                        ],
                        stops: [0, 0.25, 0.55, 1],
                      ),
                    ),
                  ),
                ),
                if (_loading && error == null)
                  const Center(child: CircularProgressIndicator()),
                if (error != null)
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline, size: 42),
                            const SizedBox(height: 16),
                            Text(error, textAlign: TextAlign.center),
                            const SizedBox(height: 20),
                            FilledButton.icon(
                              onPressed: _retry,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Try again'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (ready && value!.isBuffering && !_loading && error == null)
                  const Center(child: CircularProgressIndicator()),
                SafeArea(
                  child: Padding(
                    padding: EdgeInsets.all(tv ? 28 : 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              tooltip: 'Back',
                              onPressed: () => unawaited(_leave()),
                              icon: const Icon(Icons.arrow_back),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleLarge,
                                  ),
                                  if (_isLive)
                                    Text(
                                      'LIVE  •  Channel ${_channelIndex + 1} of ${_channels.length}',
                                      style: const TextStyle(
                                        color: Color(0xFF54E1C1),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        if (_saveFailed)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'Playback progress could not be saved.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Color(0xFFFFC66D)),
                            ),
                          ),
                        if (ready && error == null)
                          _buildControls(context, value!, tv),
                        if (tv)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              error != null
                                  ? 'OK Retry   •   Back Exit'
                                  : _isLive
                                  ? '↑ / ↓ Channel   •   OK Play / pause   •   Menu Controls'
                                  : '← / → Seek   •   OK Play / pause   •   ↓ Controls',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall,
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
            if (hasTimeline) ...[
              Slider(
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      formatPlaybackTime(
                        Duration(milliseconds: position.round()),
                      ),
                    ),
                    Text(formatPlaybackTime(value.duration)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_isLive)
                  IconButton(
                    tooltip: 'Previous channel',
                    iconSize: tv ? 36 : 30,
                    onPressed: _channels.length > 1 ? () => _zap(-1) : null,
                    icon: const Icon(Icons.skip_previous),
                  )
                else
                  IconButton(
                    tooltip: 'Rewind 10 seconds',
                    iconSize: tv ? 36 : 30,
                    onPressed: hasTimeline ? () => _seekRelative(-10) : null,
                    icon: const Icon(Icons.replay_10),
                  ),
                const SizedBox(width: 24),
                FilledButton(
                  focusNode: _playFocus,
                  onPressed: () => unawaited(_togglePlayback()),
                  style: ButtonStyle(
                    padding: const WidgetStatePropertyAll(EdgeInsets.all(16)),
                    side: WidgetStateProperty.resolveWith((states) {
                      return BorderSide(
                        color: states.contains(WidgetState.focused)
                            ? Colors.white
                            : Colors.transparent,
                        width: 3,
                      );
                    }),
                  ),
                  child: Icon(
                    value.isPlaying ? Icons.pause : Icons.play_arrow,
                    size: tv ? 36 : 30,
                    semanticLabel: value.isPlaying ? 'Pause' : 'Play',
                  ),
                ),
                const SizedBox(width: 24),
                if (_isLive)
                  IconButton(
                    tooltip: 'Next channel',
                    iconSize: tv ? 36 : 30,
                    onPressed: _channels.length > 1 ? () => _zap(1) : null,
                    icon: const Icon(Icons.skip_next),
                  )
                else
                  IconButton(
                    tooltip: 'Forward 30 seconds',
                    iconSize: tv ? 36 : 30,
                    onPressed: hasTimeline ? () => _seekRelative(30) : null,
                    icon: const Icon(Icons.forward_30),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
