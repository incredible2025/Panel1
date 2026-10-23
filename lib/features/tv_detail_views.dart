import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/design_system.dart';
import '../data/models.dart';
import '../widgets/media_card.dart';
import '../widgets/my_list_button.dart';
import '../widgets/status_view.dart';
import '../widgets/tv_controls.dart';
import '../widgets/tv_page_navigation.dart';
import '../widgets/tv_utility_scaffold.dart';
import '../widgets/tv_reading_dialog.dart';

class TvMovieView extends StatefulWidget {
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
  State<TvMovieView> createState() => _TvMovieViewState();
}

class _TvMovieViewState extends State<TvMovieView> {
  final _reading = FocusNode(debugLabel: 'Movie description');
  final _play = FocusNode(debugLabel: 'Movie play');
  @override
  void dispose() {
    _reading.dispose();
    _play.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final movie = widget.detail.asData?.value, saved = widget.saved;
    return TvUtilityScaffold(
      title: 'Movie details',
      onEnter: _play.requestFocus,
      hint:
          'Up / Left  Synopsis    Right  Play / My List    Up / Down  Read    OK  Select    Back  Return',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 205,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Artwork(
                url: widget.item.imageUrl,
                title: widget.item.name,
              ),
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 28,
                    height: 1.1,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  [
                    movie?.year,
                    movie?.genre,
                    if ((movie?.rating ?? widget.item.rating).isNotEmpty)
                      'Rating ${movie?.rating ?? widget.item.rating}',
                    movie?.duration,
                  ].whereType<String>().where((e) => e.isNotEmpty).join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: AppColors.muted),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: TvScrollPane(
                    label: 'Movie details, synopsis and cast',
                    focusNode: _reading,
                    onRight: _play.requestFocus,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.detail.isLoading)
                          const Text('Loading details…')
                        else if (widget.detail.hasError)
                          TextButton(
                            onPressed: widget.onReload,
                            child: const Text('Details unavailable · Retry'),
                          )
                        else
                          Text(
                            movie?.plot.isNotEmpty == true
                                ? movie!.plot
                                : 'Your provider has not supplied a synopsis.',
                            style: const TextStyle(fontSize: 15, height: 1.5),
                          ),
                        if (movie?.cast.isNotEmpty == true) ...[
                          const SizedBox(height: 18),
                          Text(
                            'Cast  ${movie!.cast}',
                            style: const TextStyle(
                              fontSize: 13,
                              height: 1.5,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (saved != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Continue from ${formatPlaybackTime(saved.positionMs)}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(value: saved.progress, minHeight: 3),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    TvControl(
                      focusNode: _play,
                      autofocus: true,
                      style: TvControlStyle.primary,
                      onKeyEvent: (_, event) {
                        if ((event is KeyDownEvent ||
                                event is KeyRepeatEvent) &&
                            [
                              LogicalKeyboardKey.arrowUp,
                              LogicalKeyboardKey.arrowDown,
                              LogicalKeyboardKey.arrowLeft,
                            ].contains(event.logicalKey)) {
                          _reading.requestFocus();
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      onPressed: widget.opening ? () {} : widget.onPlay,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            saved == null ? Icons.play_arrow : Icons.history,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            widget.opening
                                ? 'Opening…'
                                : saved == null
                                ? 'Play movie'
                                : 'Resume movie',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    MyListButton(item: widget.item),
                    const Spacer(),
                    TvControl(
                      label: 'Refresh details',
                      onPressed: widget.onReload,
                      child: const Icon(Icons.refresh, size: 18),
                    ),
                  ],
                ),
              ],
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
  final _info = FocusNode(debugLabel: 'Series information');
  @override
  void dispose() {
    _info.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final series = widget.detail.asData?.value;
    final saved = {for (final entry in widget.history) entry.episode.id: entry};
    return TvUtilityScaffold(
      title: widget.item.name,
      subtitle: [
        series?.year ?? '',
        series?.genre ?? '',
        if (series?.rating.isNotEmpty == true) 'Rating ${series!.rating}',
        '${widget.seasons.length} seasons',
      ].where((e) => e.isNotEmpty).join(' · '),
      onEnter: () => _seasons.currentState?.focusSelected(remember: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              TvControl(
                focusNode: _info,
                onPressed: () => showTvReadingDialog(
                  context,
                  'Series information',
                  Text(
                    series?.plot.isNotEmpty == true
                        ? series!.plot
                        : 'Your provider has not supplied a synopsis.',
                  ),
                ),
                onKeyEvent: (_, event) {
                  if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
                      event.logicalKey == LogicalKeyboardKey.arrowDown) {
                    _seasons.currentState?.focusSelected(remember: true);
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: const Text(
                  'Series information',
                  style: TextStyle(fontSize: 13),
                ),
              ),
              const SizedBox(width: 12),
              MyListButton(item: widget.item),
              if (widget.continuing != null) ...[
                const SizedBox(width: 12),
                TvControl(
                  onPressed: () => widget.onEpisode(widget.continuing!),
                  child: Text(
                    'Resume · S${widget.continuing!.season} E${widget.continuing!.episodeNumber}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
              const Spacer(),
              TvControl(
                label: 'Refresh series',
                onPressed: widget.onReload,
                child: const Icon(Icons.refresh, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Expanded(
            child: widget.detail.isLoading
                ? const StatusView(title: 'Loading episodes', loading: true)
                : widget.detail.hasError
                ? StatusView(
                    title: 'Episodes unavailable',
                    onRetry: widget.onReload,
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 190,
                        child: TvRemoteList(
                          key: _seasons,
                          label: 'Season',
                          autofocus: true,
                          fullRows: true,
                          dense: true,
                          titleSize: 15,
                          extent: 52,
                          onTop: _info.requestFocus,
                          onLeft: _info.requestFocus,
                          onRight: () => _episodes.currentState?.focusSelected(
                            remember: true,
                          ),
                          entries: [
                            for (final season in widget.seasons)
                              TvListEntry(
                                id: season,
                                title: season == '0'
                                    ? 'Specials'
                                    : 'Season $season',
                                selected: season == widget.season,
                                onPressed: () => widget.onSeason(season),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 22),
                      Expanded(
                        child: widget.episodes.isEmpty
                            ? const StatusView(
                                title: 'No episodes in this season',
                              )
                            : TvRemoteList(
                                key: _episodes,
                                label: 'Episode',
                                fullRows: true,
                                dense: true,
                                titleSize: 15,
                                extent: 64,
                                onLeft: () => _seasons.currentState
                                    ?.focusSelected(remember: true),
                                onRight: () {},
                                onTop: _info.requestFocus,
                                entries: [
                                  for (final episode in widget.episodes)
                                    TvListEntry(
                                      id: episode.id,
                                      title: episode.title,
                                      subtitle:
                                          saved[episode.id]?.watched == true
                                          ? 'Watched'
                                          : saved[episode.id]?.canResume == true
                                          ? 'Resume · ${formatPlaybackTime(saved[episode.id]!.positionMs).padLeft(5, '0')}'
                                          : 'Episode ${episode.episodeNumber}',
                                      selected:
                                          episode.id ==
                                          (widget.continuing?.id ??
                                              widget.episodes.first.id),
                                      leading: SizedBox(
                                        width: 76,
                                        height: 42,
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            5,
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
                              ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
