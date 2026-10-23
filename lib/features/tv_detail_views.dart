import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/design_system.dart';
import '../data/models.dart';
import '../widgets/media_card.dart';
import '../widgets/my_list_button.dart';
import '../widgets/status_view.dart';
import '../widgets/tv_controls.dart';

class TvMovieView extends StatelessWidget {
  const TvMovieView({
    super.key,
    required this.item,
    required this.detail,
    required this.saved,
    required this.opening,
    required this.onPlay,
    required this.onReload,
  });
  final MediaItem item;
  final AsyncValue<MovieDetail> detail;
  final WatchEntry? saved;
  final bool opening;
  final VoidCallback onPlay, onReload;
  @override
  Widget build(BuildContext context) {
    final movie = detail.asData?.value;
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Artwork(
            url: movie?.backdropUrl ?? item.imageUrl,
            title: item.name,
            darken: .9,
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      TvControl(
                        label: 'Back',
                        onPressed: () => Navigator.maybePop(context),
                        child: const Row(
                          children: [
                            Icon(Icons.arrow_back),
                            SizedBox(width: 8),
                            Text('Back'),
                          ],
                        ),
                      ),
                      const SizedBox(width: 20),
                      const Expanded(
                        child: Text(
                          'MOVIE DETAILS',
                          style: TextStyle(
                            fontSize: 15,
                            letterSpacing: 2,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                      TvControl(
                        label: 'Refresh details',
                        onPressed: onReload,
                        child: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, size) => Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: (size.maxWidth * .23).clamp(150, 270),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Artwork(
                                url: item.imageUrl,
                                title: item.name,
                              ),
                            ),
                          ),
                          const SizedBox(width: 30),
                          Expanded(
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.name,
                                    style: const TextStyle(
                                      fontSize: 42,
                                      height: 1.05,
                                      fontWeight: FontWeight.w700,
                                      fontFamily: 'Streamline Display',
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    [
                                          movie?.year,
                                          movie?.genre,
                                          if ((movie?.rating ?? item.rating)
                                              .isNotEmpty)
                                            '★ ${movie?.rating ?? item.rating}',
                                          movie?.duration,
                                        ]
                                        .whereType<String>()
                                        .where((s) => s.isNotEmpty)
                                        .join('   ·   '),
                                    style: const TextStyle(
                                      fontSize: 18,
                                      color: AppColors.muted,
                                    ),
                                  ),
                                  const SizedBox(height: 22),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 12,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      TvControl(
                                        autofocus: true,
                                        onPressed: opening ? () {} : onPlay,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              saved == null
                                                  ? Icons.play_arrow
                                                  : Icons.history,
                                            ),
                                            const SizedBox(width: 10),
                                            Text(
                                              opening
                                                  ? 'Opening…'
                                                  : saved == null
                                                  ? 'Play movie'
                                                  : 'Resume movie',
                                            ),
                                          ],
                                        ),
                                      ),
                                      MyListButton(item: item),
                                    ],
                                  ),
                                  if (saved != null) ...[
                                    const SizedBox(height: 16),
                                    Text(
                                      'Continue from ${formatPlaybackTime(saved!.positionMs)}',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        color: AppColors.accent,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    LinearProgressIndicator(
                                      value: saved!.progress,
                                      minHeight: 4,
                                    ),
                                  ],
                                  const SizedBox(height: 24),
                                  if (detail.isLoading)
                                    const LinearProgressIndicator()
                                  else if (detail.hasError)
                                    TextButton(
                                      onPressed: onReload,
                                      child: const Text(
                                        'Details unavailable · Retry',
                                      ),
                                    )
                                  else
                                    Text(
                                      movie?.plot.isNotEmpty == true
                                          ? movie!.plot
                                          : 'Your provider has not supplied a synopsis.',
                                      style: const TextStyle(
                                        fontSize: 19,
                                        height: 1.55,
                                      ),
                                    ),
                                  if (movie?.cast.isNotEmpty == true)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 20),
                                      child: Text(
                                        'Cast  ${movie!.cast}',
                                        style: const TextStyle(
                                          fontSize: 17,
                                          height: 1.5,
                                          color: AppColors.muted,
                                        ),
                                      ),
                                    ),
                                  const SizedBox(height: 20),
                                ],
                              ),
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
        ],
      ),
    );
  }
}

class TvSeriesView extends StatefulWidget {
  const TvSeriesView({
    super.key,
    required this.item,
    required this.detail,
    required this.seasons,
    required this.season,
    required this.episodes,
    required this.history,
    required this.continuing,
    required this.onSeason,
    required this.onEpisode,
    required this.onReload,
  });
  final MediaItem item;
  final AsyncValue<SeriesDetail> detail;
  final List<String> seasons;
  final String? season;
  final List<Episode> episodes;
  final List<EpisodeWatchEntry> history;
  final Episode? continuing;
  final ValueChanged<String> onSeason;
  final ValueChanged<Episode> onEpisode;
  final VoidCallback onReload;
  @override
  State<TvSeriesView> createState() => _TvSeriesViewState();
}

class _TvSeriesViewState extends State<TvSeriesView> {
  final _seasons = GlobalKey<TvRemoteListState>(),
      _episodes = GlobalKey<TvRemoteListState>();
  final _back = FocusNode(debugLabel: 'Series back');
  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final series = widget.detail.asData?.value;
    final saved = {for (final e in widget.history) e.episode.id: e};
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  TvControl(
                    focusNode: _back,
                    onPressed: () => Navigator.maybePop(context),
                    child: const Row(
                      children: [
                        Icon(Icons.arrow_back),
                        SizedBox(width: 7),
                        Text('Back'),
                      ],
                    ),
                  ),
                  const SizedBox(width: 22),
                  Expanded(
                    child: Text(
                      widget.item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 35,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Streamline Display',
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  MyListButton(item: widget.item),
                  if (widget.continuing != null) ...[
                    const SizedBox(width: 12),
                    TvControl(
                      onPressed: () => widget.onEpisode(widget.continuing!),
                      child: Text(
                        'Resume · S${widget.continuing!.season} E${widget.continuing!.episodeNumber}',
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 14),
              if (series != null)
                Text(
                  [
                    series.year,
                    series.genre,
                    '${widget.seasons.length} seasons',
                  ].where((s) => s.isNotEmpty).join('  ·  '),
                  style: const TextStyle(fontSize: 17, color: AppColors.muted),
                ),
              if (series?.plot.isNotEmpty == true)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    series!.plot,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      color: AppColors.muted,
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              Expanded(
                child: widget.detail.isLoading
                    ? const StatusView(title: 'Loading episodes', loading: true)
                    : widget.detail.hasError
                    ? StatusView(
                        title: 'Episodes unavailable',
                        onRetry: widget.onReload,
                      )
                    : Row(
                        children: [
                          SizedBox(
                            width: 205,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Text(
                                  'Seasons',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Expanded(
                                  child: TvRemoteList(
                                    key: _seasons,
                                    label: 'Season',
                                    autofocus: true,
                                    extent: 64,
                                    entries: [
                                      for (final season in widget.seasons)
                                        TvListEntry(
                                          id: season,
                                          title: season == '0'
                                              ? 'Specials'
                                              : 'Season $season',
                                          selected: season == widget.season,
                                          onPressed: () =>
                                              widget.onSeason(season),
                                        ),
                                    ],
                                    onTop: _back.requestFocus,
                                    onLeft: _back.requestFocus,
                                    onRight: () =>
                                        _episodes.currentState?.focusSelected(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 26),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  '${widget.episodes.length} episodes',
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Expanded(
                                  child: widget.episodes.isEmpty
                                      ? const StatusView(
                                          title: 'No episodes in this season',
                                        )
                                      : TvRemoteList(
                                          key: _episodes,
                                          label: 'Episode',
                                          extent: 92,
                                          entries: [
                                            for (final episode
                                                in widget.episodes)
                                              TvListEntry(
                                                id: episode.id,
                                                title: episode.title,
                                                subtitle:
                                                    saved[episode.id]
                                                            ?.watched ==
                                                        true
                                                    ? 'Watched'
                                                    : saved[episode.id]
                                                              ?.canResume ==
                                                          true
                                                    ? 'Resume · ${formatPlaybackTime(saved[episode.id]!.positionMs).padLeft(5, '0')}'
                                                    : 'Episode ${episode.episodeNumber}',
                                                selected:
                                                    episode.id ==
                                                    (widget.continuing?.id ??
                                                        widget
                                                            .episodes
                                                            .first
                                                            .id),
                                                leading: SizedBox(
                                                  width: 88,
                                                  height: 50,
                                                  child: ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          6,
                                                        ),
                                                    child: Artwork(
                                                      url: episode.imageUrl,
                                                      title: episode.title,
                                                    ),
                                                  ),
                                                ),
                                                onPressed: () =>
                                                    widget.onEpisode(episode),
                                              ),
                                          ],
                                          onLeft: () => _seasons.currentState
                                              ?.focusSelected(),
                                          onRight: () {},
                                          onTop: _back.requestFocus,
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
