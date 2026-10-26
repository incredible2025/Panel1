import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/design_system.dart';
import '../core/playback_handle.dart';
import '../core/providers.dart';
import '../core/settings_controller.dart';
import '../data/models.dart';
import 'media_card.dart';
import 'parental_access.dart';
import 'tv_controls.dart';

class LiveChannelPreview extends ConsumerStatefulWidget {
  const LiveChannelPreview({
    super.key,
    required this.item,
    required this.programme,
    required this.onWatch,
    this.compact = false,
  });
  final MediaItem item;
  final EpgEntry? programme;
  final VoidCallback onWatch;
  final bool compact;
  @override
  ConsumerState<LiveChannelPreview> createState() => LiveChannelPreviewState();
}

class LiveChannelPreviewState extends ConsumerState<LiveChannelPreview>
    with WidgetsBindingObserver {
  PlaybackHandle? _player;
  bool _opening = false;
  String? _error;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant LiveChannelPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id) unawaited(stop());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(stop());
  }

  Future<void> _releases = Future.value();
  Future<void> _drain() {
    final player = _player;
    _player = null;
    if (player != null) {
      _releases = _releases.then((_) async {
        try {
          await player.dispose();
        } catch (_) {}
      });
    }
    return _releases;
  }

  Future<void> stop() async {
    _generation++;
    _opening = false;
    if (mounted) setState(() {});
    await _drain();
  }

  Future<void> _start() async {
    if (_opening) return;
    final generation = ++_generation;
    setState(() {
      _opening = true;
      _error = null;
    });
    await _drain();
    if (!mounted || generation != _generation) return;
    if (!await allowMedia(context, ref, widget.item) ||
        !mounted ||
        generation != _generation) {
      if (mounted && generation == _generation) {
        setState(() => _opening = false);
      }
      return;
    }
    final session = ref.read(sessionProvider);
    if (session == null) {
      setState(() => _opening = false);
      return;
    }
    final preferences = ref.read(settingsProvider.notifier).current;
    final player = ref.read(playbackFactoryProvider)(
      ref.read(apiProvider).streamUri(session, widget.item),
      preferences.engineFor(widget.item),
    );
    _player = player;
    try {
      await player.initialize();
      if (!mounted || generation != _generation) return;
      await player.setVolume(0);
      if (!mounted || generation != _generation) return;
      await player.play();
      if (mounted && generation == _generation) {
        setState(() => _opening = false);
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _opening = false;
          _error = 'Preview unavailable. You can still open the channel.';
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _generation++;
    final player = _player;
    _player = null;
    if (player != null) unawaited(player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.compact
      ? _compact()
      : ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Artwork(
                url: widget.item.imageUrl,
                title: widget.item.name,
                icon: Icons.live_tv,
                fit: BoxFit.contain,
              ),
              if (_player != null)
                ValueListenableBuilder(
                  valueListenable: _player!,
                  builder: (_, value, __) =>
                      value.isInitialized && !value.hasError
                      ? FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: value.size.width > 0 ? value.size.width : 16,
                            height: value.size.height > 0
                                ? value.size.height
                                : 9,
                            child: _player!.buildView(),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              const IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xA0071B38),
                        Color(0x35071B38),
                        Color(0xFF071B38),
                      ],
                      stops: [0, .35, 1],
                    ),
                  ),
                ),
              ),
              if (_opening)
                const Center(child: CircularProgressIndicator(strokeWidth: 2)),
              Padding(
                padding: const EdgeInsets.all(25),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.circle,
                          color: AppColors.live,
                          size: 7,
                        ),
                        const SizedBox(width: 9),
                        const Eyebrow('LIVE TELEVISION'),
                        const Spacer(),
                        if (_player?.value.isPlaying == true)
                          const Icon(Icons.volume_off_outlined, size: 18),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      widget.item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      widget.programme?.title ?? widget.item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineLarge
                          ?.copyWith(
                            fontSize: ref.watch(isLargeScreenProvider)
                                ? 36
                                : 30,
                          ),
                    ),
                    const SizedBox(height: 12),
                    if (widget.programme != null)
                      Text(
                        widget.programme!.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                    if (_error != null)
                      Text(
                        _error!,
                        style: const TextStyle(
                          color: AppColors.danger,
                          fontSize: 12,
                        ),
                      ),
                    const SizedBox(height: 24),
                    Wrap(
                      spacing: 12,
                      runSpacing: 10,
                      children: [
                        FilledButton.icon(
                          onPressed: widget.onWatch,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Watch channel'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _opening
                              ? null
                              : _player?.value.isPlaying == true
                              ? stop
                              : _start,
                          icon: Icon(
                            _player?.value.isPlaying == true
                                ? Icons.stop_outlined
                                : Icons.picture_in_picture_alt,
                          ),
                          label: Text(
                            _player?.value.isPlaying == true
                                ? 'Stop preview'
                                : 'Preview',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );

  Widget _compact() => ClipRRect(
    borderRadius: BorderRadius.circular(10),
    child: Stack(
      fit: StackFit.expand,
      children: [
        Artwork(
          url: widget.item.imageUrl,
          title: widget.item.name,
          icon: Icons.live_tv,
          fit: BoxFit.contain,
        ),
        if (_player != null)
          ValueListenableBuilder(
            valueListenable: _player!,
            builder: (_, value, __) => value.isInitialized && !value.hasError
                ? FittedBox(
                    fit: BoxFit.contain,
                    child: SizedBox(
                      width: value.size.width > 0 ? value.size.width : 16,
                      height: value.size.height > 0 ? value.size.height : 9,
                      child: _player!.buildView(),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        if (_opening)
          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        Positioned(
          right: 7,
          bottom: 7,
          child: TvControl(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            onPressed: () {
              if (!_opening) {
                if (_player?.value.isPlaying == true) {
                  stop();
                } else {
                  _start();
                }
              }
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _player?.value.isPlaying == true
                      ? Icons.stop
                      : Icons.volume_off,
                  size: 17,
                ),
                const SizedBox(width: 5),
                Text(
                  _player?.value.isPlaying == true ? 'Stop preview' : 'Preview',
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),
          ),
        ),
        if (_error != null)
          const Positioned(
            top: 8,
            left: 8,
            right: 8,
            child: Text(
              'Preview unavailable',
              style: TextStyle(
                color: Colors.white,
                backgroundColor: Colors.black,
                fontSize: 14,
              ),
            ),
          ),
      ],
    ),
  );
}
