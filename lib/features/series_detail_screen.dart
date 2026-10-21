import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../data/models.dart';
import '../widgets/media_card.dart';
import '../widgets/status_view.dart';
import '../widgets/tv_focus_card.dart';
import 'player_screen.dart';

class SeriesDetailScreen extends ConsumerStatefulWidget {
  const SeriesDetailScreen({super.key, required this.item});

  final MediaItem item;

  @override
  ConsumerState<SeriesDetailScreen> createState() => _SeriesDetailScreenState();
}

class _SeriesDetailScreenState extends ConsumerState<SeriesDetailScreen> {
  String? _selectedSeason;

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(seriesDetailProvider(widget.item));
    final isTv = ref.watch(isTvProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Series details'),
        actions: [
          IconButton(
            onPressed: () => ref.invalidate(seriesDetailProvider(widget.item)),
            tooltip: 'Refresh details',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: detail.when(
          loading: () =>
              const StatusView(title: 'Loading series', loading: true),
          error: (_, __) => StatusView(
            title: 'Could not load this series',
            message: 'Check your connection and try again.',
            onRetry: () => ref.invalidate(seriesDetailProvider(widget.item)),
          ),
          data: (series) => LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth > 700;
              final seasons = series.seasons.keys.toList()
                ..sort((a, b) {
                  final an = int.tryParse(a);
                  final bn = int.tryParse(b);
                  return an != null && bn != null
                      ? an.compareTo(bn)
                      : a.compareTo(b);
                });
              final season = seasons.contains(_selectedSeason)
                  ? _selectedSeason
                  : seasons.firstOrNull;
              final episodes = series.seasons[season] ?? <Episode>[];
              return Padding(
                padding: EdgeInsets.fromLTRB(
                  isTv ? 32 : 20,
                  16,
                  isTv ? 32 : 20,
                  0,
                ),
                child: FocusTraversalGroup(
                  child: CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (wide)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: isTv ? 145 : 130,
                                    child: _poster(),
                                  ),
                                  const SizedBox(width: 26),
                                  Expanded(child: _description(series, isTv)),
                                ],
                              )
                            else
                              _description(series, isTv),
                            const SizedBox(height: 28),
                            const SectionHeading(
                              'Episodes',
                              subtitle: 'Choose a season, then settle in',
                            ),
                            if (seasons.isNotEmpty)
                              SizedBox(
                                height: 44,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: seasons.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(width: 10),
                                  itemBuilder: (context, index) => TvFocusCard(
                                    autofocus: isTv && index == 0,
                                    selected: seasons[index] == season,
                                    onPressed: () => setState(
                                      () => _selectedSeason = seasons[index],
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                        vertical: 11,
                                      ),
                                      child: Text(
                                        seasons[index] == '0'
                                            ? 'Specials'
                                            : 'Season ${seasons[index]}',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            const SizedBox(height: 18),
                          ],
                        ),
                      ),
                      if (episodes.isEmpty)
                        const SliverToBoxAdapter(
                          child: StatusView(
                            title: 'No episodes available',
                            message:
                                'Your provider has not added episodes for this season.',
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.only(bottom: 24),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _episode(episodes[index], wide),
                              ),
                              childCount: episodes.length,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _poster() => AspectRatio(
    aspectRatio: 2 / 3,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Artwork(
        url: widget.item.imageUrl,
        icon: Icons.video_library_outlined,
      ),
    ),
  );

  Widget _description(SeriesDetail series, bool isTv) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'SERIES',
        style: TextStyle(
          color: Color(0xFF54E1C1),
          fontSize: 11,
          letterSpacing: 2,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 10),
      Text(
        widget.item.name,
        style: Theme.of(context).textTheme.headlineLarge?.copyWith(
          fontSize: isTv ? 34 : 28,
          fontWeight: FontWeight.w800,
          height: 1.2,
        ),
      ),
      if (widget.item.rating.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text(
          '★ ${widget.item.rating}',
          style: const TextStyle(
            color: Color(0xFFFFC677),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
      const SizedBox(height: 16),
      Text(
        series.plot.trim().isEmpty
            ? 'No synopsis supplied by your provider.'
            : series.plot,
        style: const TextStyle(
          fontSize: 14,
          height: 1.65,
          color: Color(0xFFB9C7D5),
        ),
      ),
      if (series.cast.trim().isNotEmpty) ...[
        const SizedBox(height: 14),
        Text(
          'Cast: ${series.cast}',
          style: const TextStyle(
            fontSize: 12,
            height: 1.5,
            color: Color(0xFF91A4B9),
          ),
        ),
      ],
    ],
  );

  Widget _episode(Episode episode, bool wide) => TvFocusCard(
    label: 'Play episode ${episode.episodeNumber}: ${episode.title}',
    onPressed: () => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerScreen(item: widget.item, episode: episode),
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          SizedBox(
            width: wide ? 112 : 72,
            height: wide ? 66 : 52,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: Artwork(
                url: episode.imageUrl,
                icon: Icons.play_circle_outline,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'EPISODE ${episode.episodeNumber}',
                  style: const TextStyle(
                    color: Color(0xFF54E1C1),
                    fontSize: 10,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  episode.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const Icon(
            Icons.play_arrow_rounded,
            color: Color(0xFF54E1C1),
            size: 28,
          ),
        ],
      ),
    ),
  );
}
