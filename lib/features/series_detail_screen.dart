import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/design_system.dart';
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
    final tv = ref.watch(isTvProvider);
    final series = detail.asData?.value;
    final seasons = series?.seasons.keys.toList() ?? <String>[];
    seasons.sort((a, b) {
      final first = int.tryParse(a);
      final second = int.tryParse(b);
      return first != null && second != null
          ? first.compareTo(second)
          : a.compareTo(b);
    });
    final season = seasons.contains(_selectedSeason)
        ? _selectedSeason
        : seasons.firstOrNull;
    final episodes = series?.seasons[season] ?? <Episode>[];
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
                        series,
                        seasons.length,
                        tv,
                        wide,
                        horizontal,
                        compact: constraints.maxHeight < 500,
                      ),
                    ),
                    if (detail.isLoading)
                      const SliverToBoxAdapter(
                        child: StatusView(
                          title: 'Loading series',
                          loading: true,
                        ),
                      )
                    else if (detail.hasError)
                      SliverToBoxAdapter(
                        child: StatusView(
                          title: 'Could not load this series',
                          message: 'Check your connection and try again.',
                          onRetry: () =>
                              ref.invalidate(seriesDetailProvider(widget.item)),
                        ),
                      )
                    else ...[
                      SliverPadding(
                        padding: EdgeInsets.symmetric(horizontal: horizontal),
                        sliver: SliverToBoxAdapter(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Divider(color: AppColors.border, height: 1),
                              const SizedBox(height: 28),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Episodes',
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineSmall
                                          ?.copyWith(
                                            fontSize: wide ? 27 : 25,
                                            fontWeight: FontWeight.w500,
                                            color: AppColors.text,
                                            letterSpacing: -.7,
                                          ),
                                    ),
                                  ),
                                  Text(
                                    '${episodes.length} episode${episodes.length == 1 ? '' : 's'}',
                                    style: const TextStyle(
                                      color: AppColors.subdued,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              if (seasons.isNotEmpty)
                                SizedBox(
                                  height: 54,
                                  child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    clipBehavior: Clip.none,
                                    itemCount: seasons.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(width: 12),
                                    itemBuilder: (context, index) =>
                                        TvFocusCard(
                                          autofocus: tv && index == 0,
                                          selected: seasons[index] == season,
                                          borderRadius: 8,
                                          label: seasons[index] == '0'
                                              ? 'Specials'
                                              : 'Season ${seasons[index]}',
                                          onPressed: () => setState(
                                            () => _selectedSeason =
                                                seasons[index],
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 21,
                                              vertical: 15,
                                            ),
                                            child: Text(
                                              seasons[index] == '0'
                                                  ? 'Specials'
                                                  : 'Season ${seasons[index]}',
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: seasons[index] == season
                                                    ? AppColors.accent
                                                    : AppColors.muted,
                                              ),
                                            ),
                                          ),
                                        ),
                                  ),
                                ),
                              const SizedBox(height: 25),
                            ],
                          ),
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
                          padding: EdgeInsets.fromLTRB(
                            horizontal,
                            0,
                            horizontal,
                            20,
                          ),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _episode(episodes[index], series!, wide),
                              ),
                              childCount: episodes.length,
                            ),
                          ),
                        ),
                      if (series?.cast.trim().isNotEmpty == true)
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                            horizontal,
                            20,
                            horizontal,
                            0,
                          ),
                          sliver: SliverToBoxAdapter(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Divider(
                                  color: AppColors.border,
                                  height: 1,
                                ),
                                const SizedBox(height: 24),
                                const Eyebrow('CAST', color: AppColors.subdued),
                                const SizedBox(height: 14),
                                Text(
                                  series!.cast,
                                  style: const TextStyle(
                                    color: AppColors.muted,
                                    height: 1.8,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 56 + MediaQuery.paddingOf(context).bottom,
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
    SeriesDetail? series,
    int seasons,
    bool tv,
    bool wide,
    double horizontal, {
    required bool compact,
  }) {
    final backdrop = series?.backdropUrl.isNotEmpty == true
        ? series!.backdropUrl
        : widget.item.imageUrl;
    final rating = series?.rating.isNotEmpty == true
        ? series!.rating
        : widget.item.rating;
    return Stack(
      children: [
        const Positioned.fill(child: ColoredBox(color: AppColors.canvas)),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: wide ? 600 : 500,
          child: Artwork(
            url: backdrop,
            title: widget.item.name,
            fit: BoxFit.cover,
            icon: Icons.video_library_outlined,
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, .25, .65, 1],
                colors: [
                  AppColors.canvas.withValues(alpha: .08),
                  AppColors.canvas.withValues(alpha: .34),
                  AppColors.canvas.withValues(alpha: .92),
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
                          : 130
                    : 186),
            horizontal,
            36,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SizedBox(
                    width: wide
                        ? compact
                              ? 128
                              : 166
                        : 92,
                    child: _poster(),
                  ),
                  SizedBox(width: wide ? 34 : 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Eyebrow('SERIES'),
                        const SizedBox(height: 13),
                        Text(
                          widget.item.name,
                          style: Theme.of(context).textTheme.headlineLarge
                              ?.copyWith(
                                fontSize: wide ? (tv ? 48 : 44) : 31,
                                fontWeight: FontWeight.w600,
                                height: 1.06,
                                letterSpacing: wide ? -1.8 : -.9,
                                color: AppColors.text,
                              ),
                        ),
                        const SizedBox(height: 18),
                        Wrap(
                          spacing: 10,
                          runSpacing: 9,
                          children: [
                            if (series?.year.isNotEmpty == true)
                              MetaPill(series!.year),
                            if (rating.isNotEmpty)
                              MetaPill(rating, icon: Icons.star_rounded),
                            if (seasons > 0)
                              MetaPill(
                                '$seasons season${seasons == 1 ? '' : 's'}',
                              ),
                          ],
                        ),
                        if (series?.genre.isNotEmpty == true) ...[
                          const SizedBox(height: 14),
                          Text(
                            series!.genre,
                            style: const TextStyle(
                              fontSize: 13,
                              height: 1.5,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                        if (wide && series != null) ...[
                          const SizedBox(height: 22),
                          _synopsis(series, wide),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (!wide && series != null) ...[
                const SizedBox(height: 25),
                _synopsis(series, wide),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _synopsis(SeriesDetail series, bool wide) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 760),
    child: Text(
      series.plot.trim().isEmpty
          ? 'No synopsis supplied by your provider.'
          : series.plot,
      style: TextStyle(
        color: AppColors.muted,
        fontSize: wide ? 15 : 14,
        height: 1.8,
      ),
    ),
  );

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
        child: Artwork(
          url: widget.item.imageUrl,
          title: widget.item.name,
          icon: Icons.video_library_outlined,
        ),
      ),
    ),
  );

  Widget _episode(Episode episode, SeriesDetail series, bool wide) {
    final artwork = episode.imageUrl.isNotEmpty
        ? episode.imageUrl
        : series.backdropUrl.isNotEmpty
        ? series.backdropUrl
        : widget.item.imageUrl;
    return TvFocusCard(
      borderRadius: 10,
      label: 'Play episode ${episode.episodeNumber}: ${episode.title}',
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PlayerScreen(item: widget.item, episode: episode),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(wide ? 13 : 10),
        child: Row(
          children: [
            if (wide) ...[
              SizedBox(
                width: 42,
                child: Text(
                  episode.episodeNumber.toString().padLeft(2, '0'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.subdued,
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
            SizedBox(
              width: wide ? 164 : 96,
              height: wide ? 92 : 64,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: Artwork(
                  url: artwork,
                  title: episode.title,
                  icon: Icons.play_circle_outline,
                ),
              ),
            ),
            SizedBox(width: wide ? 24 : 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'EPISODE ${episode.episodeNumber.toString().padLeft(2, '0')}',
                    style: const TextStyle(
                      color: AppColors.accent,
                      letterSpacing: 1.5,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    episode.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: wide ? 18 : 14,
                      height: 1.25,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (wide) ...[
                    const SizedBox(height: 8),
                    Text(
                      episode.season == '0'
                          ? 'Specials'
                          : 'Season ${episode.season}',
                      style: const TextStyle(
                        color: AppColors.subdued,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(width: wide ? 24 : 10),
            Container(
              width: wide ? 44 : 32,
              height: wide ? 44 : 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
              ),
              child: Icon(
                Icons.play_arrow_rounded,
                size: wide ? 26 : 21,
                color: AppColors.accent,
              ),
            ),
            if (wide) const SizedBox(width: 14),
          ],
        ),
      ),
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
                child: Eyebrow('SERIES DETAILS', color: AppColors.muted),
              ),
              IconButton(
                onPressed: () =>
                    ref.invalidate(seriesDetailProvider(widget.item)),
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
