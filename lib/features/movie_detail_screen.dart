import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/design_system.dart';
import '../core/providers.dart';
import '../data/models.dart';
import '../widgets/parental_access.dart';
import '../widgets/media_card.dart';
import '../widgets/my_list_button.dart';
import '../widgets/status_view.dart';
import 'player_screen.dart' show PlayerScreen;
import 'tv_detail_views.dart';

class MovieDetailScreen extends ConsumerStatefulWidget {
  const MovieDetailScreen({super.key, required this.item});

  final MediaItem item;

  @override
  ConsumerState<MovieDetailScreen> createState() => _MovieDetailScreenState();
}

class _MovieDetailScreenState extends ConsumerState<MovieDetailScreen> {
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _recordOpened();
    });
  }

  Future<void> _recordOpened() async {
    if (!await allowMedia(context, ref, widget.item) || !mounted) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      await ref
          .read(storeProvider)
          .recordOpened(session.accountId, widget.item);
      if (mounted) ref.invalidate(historyProvider);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not update your recently watched films.'),
          ),
        );
      }
    }
  }

  Future<void> _play() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final session = ref.read(sessionProvider);
      if (session == null) return;
      final history = await ref.read(storeProvider).history(session.accountId);
      WatchEntry? saved;
      for (final entry in history) {
        if (entry.item.id == widget.item.id &&
            entry.item.kind == MediaKind.movie &&
            entry.canResume) {
          saved = entry;
          break;
        }
      }
      if (!mounted) return;
      Duration start = Duration.zero;
      if (saved != null) {
        final progress = saved;
        final answer = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            icon: const Icon(Icons.history_rounded, color: AppColors.accent),
            title: const Text('Pick up where you left off?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.item.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 14),
                LinearProgressIndicator(
                  value: progress.progress,
                  minHeight: 3,
                  color: AppColors.accent,
                  backgroundColor: AppColors.border,
                ),
                const SizedBox(height: 12),
                Text(
                  '${formatPlaybackTime(progress.positionMs)} watched of ${formatPlaybackTime(progress.durationMs)}',
                  style: const TextStyle(color: AppColors.muted, height: 1.5),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Start from beginning'),
              ),
              FilledButton(
                autofocus: true,
                onPressed: () => Navigator.pop(context, true),
                child: Text(
                  'Resume from ${formatPlaybackTime(progress.positionMs)}',
                ),
              ),
            ],
          ),
        );
        if (answer == null || !mounted) return;
        if (answer) start = Duration(milliseconds: progress.positionMs);
      }
      if (!mounted) return;
      final playableItem =
          ref.read(movieDetailProvider(widget.item)).asData?.value.item ??
          widget.item;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              PlayerScreen(item: playableItem, startPosition: start),
        ),
      );
      if (mounted) ref.invalidate(historyProvider);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open this movie. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final protection = protectedLibraryView(context, ref, widget.item);
    if (protection != null) return protection;
    final detail = ref.watch(movieDetailProvider(widget.item));
    final history = ref.watch(historyProvider).asData?.value ?? <WatchEntry>[];
    WatchEntry? saved;
    for (final entry in history) {
      if (entry.item.id == widget.item.id &&
          entry.item.kind == MediaKind.movie &&
          entry.canResume) {
        saved = entry;
        break;
      }
    }
    final tv = ref.watch(isTvProvider);
    if (tv) {
      return TvMovieView(
        item: widget.item,
        detail: detail,
        saved: saved,
        opening: _opening,
        onPlay: _play,
        onReload: () => ref.invalidate(movieDetailProvider(widget.item)),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 760;
          final horizontal = tv
              ? 64.0
              : wide
              ? 44.0
              : 24.0;
          return Stack(
            children: [
              FocusTraversalGroup(
                child: CustomScrollView(
                  cacheExtent: constraints.maxHeight,
                  slivers: [
                    SliverToBoxAdapter(
                      child: _hero(
                        detail.asData?.value,
                        saved,
                        tv,
                        wide,
                        horizontal,
                        compact: constraints.maxHeight < 500,
                      ),
                    ),
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        horizontal,
                        0,
                        horizontal,
                        56 + MediaQuery.paddingOf(context).bottom,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1180),
                            child: detail.when(
                              loading: () => const Padding(
                                padding: EdgeInsets.symmetric(vertical: 36),
                                child: LinearProgressIndicator(
                                  minHeight: 2,
                                  color: AppColors.accent,
                                ),
                              ),
                              error: (_, __) => StatusView(
                                title: 'Movie details are unavailable',
                                message:
                                    'You can still try playing this title.',
                                onRetry: () => ref.invalidate(
                                  movieDetailProvider(widget.item),
                                ),
                              ),
                              data: (movie) => _story(movie, wide),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _chrome(horizontal),
            ],
          );
        },
      ),
    );
  }

  Widget _hero(
    MovieDetail? movie,
    WatchEntry? saved,
    bool tv,
    bool wide,
    double horizontal, {
    required bool compact,
  }) {
    final backdrop = movie?.backdropUrl.isNotEmpty == true
        ? movie!.backdropUrl
        : widget.item.imageUrl;
    final rating = movie?.rating.isNotEmpty == true
        ? movie!.rating
        : widget.item.rating;
    final posterWidth = wide ? (compact ? 146.0 : 210.0) : 98.0;
    return Stack(
      children: [
        Positioned.fill(child: ColoredBox(color: AppColors.canvas)),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: wide ? 650 : 510,
          child: Artwork(
            url: backdrop,
            fit: BoxFit.cover,
            title: widget.item.name,
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, .22, .62, 1],
                colors: [
                  AppColors.canvas.withValues(alpha: .1),
                  AppColors.canvas.withValues(alpha: .36),
                  AppColors.canvas.withValues(alpha: .91),
                  AppColors.canvas,
                ],
              ),
            ),
          ),
        ),
        if (wide)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    AppColors.canvas.withValues(alpha: .78),
                    AppColors.canvas.withValues(alpha: .12),
                  ],
                ),
              ),
            ),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            horizontal,
            MediaQuery.paddingOf(context).top +
                (wide
                    ? compact
                          ? 100
                          : 136
                    : 194),
            horizontal,
            40,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      SizedBox(width: posterWidth, child: _poster()),
                      SizedBox(width: wide ? 36 : 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Eyebrow('MOVIE'),
                            const SizedBox(height: 13),
                            Text(
                              widget.item.name,
                              style: Theme.of(context).textTheme.headlineLarge
                                  ?.copyWith(
                                    fontSize: wide ? (tv ? 48 : 44) : 31,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.text,
                                    letterSpacing: wide ? -1.8 : -.9,
                                    height: 1.06,
                                  ),
                            ),
                            const SizedBox(height: 18),
                            Wrap(
                              spacing: 10,
                              runSpacing: 9,
                              children: [
                                if (movie?.year.isNotEmpty == true)
                                  MetaPill(movie!.year),
                                if (rating.isNotEmpty)
                                  MetaPill(rating, icon: Icons.star_rounded),
                                if (movie?.duration.isNotEmpty == true)
                                  MetaPill(
                                    movie!.duration,
                                    icon: Icons.schedule_rounded,
                                  ),
                              ],
                            ),
                            if (movie?.genre.isNotEmpty == true) ...[
                              const SizedBox(height: 14),
                              Text(
                                movie!.genre,
                                style: const TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 13,
                                  height: 1.5,
                                ),
                              ),
                            ],
                            if (wide) ...[
                              const SizedBox(height: 28),
                              Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: [
                                  _playButton(saved, tv),
                                  MyListButton(item: widget.item),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (!wide) ...[
                    const SizedBox(height: 30),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _playButton(saved, tv),
                        MyListButton(item: widget.item),
                      ],
                    ),
                  ],
                  if (saved != null) ...[
                    const SizedBox(height: 28),
                    _continueCard(saved, wide),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _poster() => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(7),
      border: Border.all(color: AppColors.text.withValues(alpha: .16)),
      boxShadow: const [
        BoxShadow(color: Colors.black54, blurRadius: 36, offset: Offset(0, 16)),
      ],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: AspectRatio(
        aspectRatio: 2 / 3,
        child: Artwork(url: widget.item.imageUrl, title: widget.item.name),
      ),
    ),
  );

  Widget _playButton(WatchEntry? saved, bool tv) => FilledButton.icon(
    autofocus: tv,
    onPressed: _opening ? null : _play,
    icon: _opening
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.muted,
            ),
          )
        : const Icon(Icons.play_arrow_rounded, size: 27),
    label: Text(saved != null ? 'Resume movie' : 'Play movie'),
    style: FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 17),
      minimumSize: const Size(208, 56),
      textStyle: const TextStyle(
        fontFamily: 'Glass Sans',
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _continueCard(WatchEntry saved, bool wide) {
    final remaining = saved.durationMs - saved.positionMs;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: wide ? 24 : 18, vertical: 19),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: .7),
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.history_rounded, color: AppColors.accent, size: 27),
          const SizedBox(width: 17),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Continue your story',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text,
                        ),
                      ),
                    ),
                    if (wide)
                      Text(
                        '${formatPlaybackTime(remaining)} remaining',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 11),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: saved.progress,
                    minHeight: 3,
                    color: AppColors.accent,
                    backgroundColor: AppColors.border,
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  '${formatPlaybackTime(saved.positionMs)} of ${formatPlaybackTime(saved.durationMs)}${wide ? '' : '  ·  ${formatPlaybackTime(remaining)} left'}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _story(MovieDetail movie, bool wide) {
    final synopsis = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Eyebrow('THE STORY', color: AppColors.subdued),
        const SizedBox(height: 16),
        Text(
          movie.plot.trim().isEmpty
              ? 'No synopsis supplied by your provider.'
              : movie.plot,
          style: TextStyle(
            fontSize: wide ? 17 : 15,
            height: 1.8,
            color: AppColors.muted,
          ),
        ),
      ],
    );
    final cast = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Eyebrow('CAST', color: AppColors.subdued),
        const SizedBox(height: 16),
        Text(
          movie.cast,
          style: const TextStyle(
            fontSize: 14,
            height: 1.8,
            color: AppColors.muted,
          ),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(color: AppColors.border, height: 1),
        const SizedBox(height: 30),
        if (wide && movie.cast.trim().isNotEmpty)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 7, child: synopsis),
              const SizedBox(width: 70),
              Expanded(flex: 3, child: cast),
            ],
          )
        else ...[
          synopsis,
          if (movie.cast.trim().isNotEmpty) ...[
            const SizedBox(height: 30),
            cast,
          ],
        ],
      ],
    );
  }

  Widget _chrome(double horizontal) => Positioned(
    top: 0,
    left: 0,
    right: 0,
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.canvas.withValues(alpha: .88),
            AppColors.canvas.withValues(alpha: 0),
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(horizontal - 8, 12, horizontal - 8, 22),
          child: Row(
            children: [
              IconButton(
                onPressed: () => Navigator.maybePop(context),
                tooltip: 'Back',
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Eyebrow('MOVIE DETAILS', color: AppColors.muted),
              ),
              IconButton(
                onPressed: () =>
                    ref.invalidate(movieDetailProvider(widget.item)),
                tooltip: 'Refresh details',
                icon: const Icon(Icons.refresh_rounded, color: AppColors.muted),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
