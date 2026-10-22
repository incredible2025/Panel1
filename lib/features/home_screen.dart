import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/design_system.dart';
import '../core/providers.dart';
import '../core/settings_controller.dart';
import '../data/app_settings.dart';
import '../data/models.dart';
import '../widgets/library_shelves.dart';
import '../widgets/media_card.dart';
import '../widgets/status_view.dart';
import '../widgets/tv_focus_card.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({
    super.key,
    required this.onOpen,
    required this.onBrowse,
    required this.onSettings,
  });
  final ValueChanged<MediaItem> onOpen;
  final ValueChanged<MediaKind> onBrowse;
  final VoidCallback onSettings;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tv = ref.watch(isTvProvider);
    final s = ref.watch(settingsProvider).asData?.value ?? const AppSettings();
    final unlocked = ref.watch(parentalSessionProvider);
    bool visible(MediaItem item) =>
        !s.hidden(item) && (unlocked || !s.locked(item));
    final movieState = ref.watch(itemsProvider(MediaKind.movie));
    final seriesState = ref.watch(itemsProvider(MediaKind.series));
    final liveState = ref.watch(itemsProvider(MediaKind.live));
    final movies = sortMediaItems(
      (movieState.asData?.value ?? []).where(visible).toList(),
      CatalogSort.recentlyAdded,
    );
    final series = (seriesState.asData?.value ?? []).where(visible).toList();
    final channels = (liveState.asData?.value ?? []).where(visible).toList();
    final available = {
      for (final item in [...movies, ...series, ...channels])
        AppSettings.mediaKey(item): item,
    };
    final saved = (ref.watch(favoritesProvider).asData?.value ?? [])
        .where((item) => available.containsKey(AppSettings.mediaKey(item)))
        .map((item) => available[AppSettings.mediaKey(item)]!)
        .toList();
    final favoriteChannels = saved
        .where((item) => item.kind == MediaKind.live)
        .toList();
    int rank(MediaItem item) {
      final index = s.favoriteOrder.indexOf(AppSettings.mediaKey(item));
      return index < 0 ? s.favoriteOrder.length : index;
    }

    favoriteChannels.sort((a, b) => rank(a).compareTo(rank(b)));
    final history = (ref.watch(historyProvider).asData?.value ?? [])
        .where(
          (entry) =>
              entry.canResume &&
              available.containsKey(AppSettings.mediaKey(entry.item)),
        )
        .toList();
    final seenSeries = <String>{};
    final episodes = (ref.watch(seriesHistoryProvider).asData?.value ?? [])
        .where((entry) => seenSeries.add(entry.item.id))
        .where(
          (entry) =>
              entry.continueEpisode != null &&
              available.containsKey(AppSettings.mediaKey(entry.item)),
        )
        .toList();
    final featured = movies.firstOrNull ?? series.firstOrNull;
    final now = DateTime.now();
    final greeting = now.hour < 12
        ? 'A GOOD MORNING STARTS HERE'
        : now.hour < 18
        ? 'YOUR AFTERNOON, SORTED'
        : 'MAKE TONIGHT A GOOD ONE';
    return LayoutBuilder(
      builder: (context, constraints) {
        final margin = tv
            ? 38.0
            : constraints.maxWidth > 700
            ? 30.0
            : 20.0;
        return CustomScrollView(
          key: const PageStorageKey('home-scroll'),
          cacheExtent: constraints.maxHeight,
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(margin, tv ? 30 : 24, margin, 26),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    if (!tv) ...[
                      const StreamlineMark(size: 30),
                      const SizedBox(width: 14),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Eyebrow(greeting),
                          const SizedBox(height: 9),
                          Text(
                            'Find your next favourite.',
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(fontSize: tv ? 36 : 29),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Settings',
                      onPressed: onSettings,
                      icon: const Icon(Icons.settings_outlined),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: margin),
              sliver: SliverToBoxAdapter(
                child: AccountExpiryNotice(onAccount: onSettings),
              ),
            ),
            if (featured != null)
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  margin,
                  0,
                  margin,
                  s.compact ? 24 : 38,
                ),
                sliver: SliverToBoxAdapter(
                  child: FeatureBillboard(
                    item: featured,
                    onPressed: () => onOpen(featured),
                  ),
                ),
              ),
            if (featured == null && movieState.isLoading)
              const SliverToBoxAdapter(
                child: StatusView(title: 'Preparing your home', loading: true),
              ),
            if (movieState.hasError)
              SliverToBoxAdapter(
                child: StatusView(
                  title: 'Movies are unavailable',
                  message: 'Your other libraries are still available.',
                  onRetry: () => ref.invalidate(itemsProvider(MediaKind.movie)),
                ),
              ),
            if (history.isNotEmpty || episodes.isNotEmpty)
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: margin),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Continue watching',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontSize: tv ? 26 : 23,
                        ),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        height: 225,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          clipBehavior: Clip.none,
                          itemCount: history.length + episodes.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 18),
                          itemBuilder: (context, index) {
                            final movie = index < history.length
                                ? history[index]
                                : null;
                            final seriesEntry = movie == null
                                ? episodes[index - history.length]
                                : null;
                            final item =
                                available[AppSettings.mediaKey(
                                  movie?.item ?? seriesEntry!.item,
                                )]!;
                            final label = movie != null
                                ? '${((movie.durationMs - movie.positionMs) / 60000).ceil()} min left'
                                : '${seriesEntry!.canResume ? 'Resume' : 'Up next'} · S${seriesEntry.continueEpisode!.season} E${seriesEntry.continueEpisode!.episodeNumber}';
                            return SizedBox(
                              width: tv ? 300 : 250,
                              child: TvFocusCard(
                                label: 'Continue ${item.name}',
                                onPressed: () => onOpen(item),
                                borderRadius: 14,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    SizedBox(
                                      height: 140,
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          Artwork(
                                            url: item.imageUrl,
                                            title: item.name,
                                          ),
                                          const Center(
                                            child: Icon(
                                              Icons.play_circle_fill,
                                              color: Colors.white,
                                              size: 44,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    LinearProgressIndicator(
                                      value:
                                          movie?.progress ??
                                          (seriesEntry!.canResume
                                              ? seriesEntry.progress
                                              : 0),
                                      minHeight: 3,
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(13),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            label,
                                            style: const TextStyle(
                                              color: AppColors.muted,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      SizedBox(height: s.compact ? 24 : 38),
                    ],
                  ),
                ),
              ),
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: margin),
              sliver: SliverToBoxAdapter(
                child: MovieRecommendations(catalog: movies, onOpen: onOpen),
              ),
            ),
            if (movies.isNotEmpty)
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: margin),
                sliver: SliverToBoxAdapter(
                  child: MovieShelf(
                    title: movies.any((item) => item.addedAt != null)
                        ? 'Fresh to your library'
                        : 'Explore movies',
                    subtitle: movies.any((item) => item.addedAt != null)
                        ? 'Recently added by your provider'
                        : 'Available from your provider',
                    items:
                        (movies.any((item) => item.addedAt != null)
                                ? movies.where((item) => item.addedAt != null)
                                : movies)
                            .take(20)
                            .toList(),
                    onOpen: onOpen,
                    onViewAll: () => onBrowse(MediaKind.movie),
                  ),
                ),
              ),
            if (favoriteChannels.isNotEmpty)
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: margin),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Your favourite channels',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          TextButton(
                            onPressed: () => onBrowse(MediaKind.live),
                            child: const Text('Live TV'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 135,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          clipBehavior: Clip.none,
                          itemCount: favoriteChannels.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 16),
                          itemBuilder: (context, index) {
                            final channel = favoriteChannels[index];
                            return SizedBox(
                              width: 215,
                              child: TvFocusCard(
                                onPressed: () => onOpen(channel),
                                child: Padding(
                                  padding: const EdgeInsets.all(18),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Eyebrow('LIVE NOW'),
                                      const Spacer(),
                                      Text(
                                        channel.name,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleMedium,
                                      ),
                                      const SizedBox(height: 8),
                                      const Icon(Icons.play_arrow, size: 22),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 36),
                    ],
                  ),
                ),
              ),
            if (saved.any((item) => item.kind != MediaKind.live))
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: margin),
                sliver: SliverToBoxAdapter(
                  child: MovieShelf(
                    title: 'My List',
                    items: saved
                        .where((item) => item.kind != MediaKind.live)
                        .take(20)
                        .toList(),
                    onOpen: onOpen,
                  ),
                ),
              ),
            if (series.isNotEmpty)
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: margin),
                sliver: SliverToBoxAdapter(
                  child: MovieShelf(
                    title: 'Stories to settle into',
                    items: sortMediaItems(
                      series,
                      CatalogSort.recentlyAdded,
                    ).take(20).toList(),
                    onOpen: onOpen,
                    onViewAll: () => onBrowse(MediaKind.series),
                  ),
                ),
              ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(margin, 4, margin, 50),
              sliver: SliverToBoxAdapter(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final entry in [
                      (MediaKind.live, 'Explore Live TV', Icons.live_tv),
                      (MediaKind.movie, 'All movies', Icons.movie_outlined),
                      (
                        MediaKind.series,
                        'All series',
                        Icons.video_library_outlined,
                      ),
                    ])
                      OutlinedButton.icon(
                        onPressed: () => onBrowse(entry.$1),
                        icon: Icon(entry.$3),
                        label: Text(entry.$2),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class FeatureBillboard extends ConsumerWidget {
  const FeatureBillboard({
    super.key,
    required this.item,
    required this.onPressed,
  });
  final MediaItem item;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final movie = item.kind == MediaKind.movie
        ? ref.watch(movieDetailProvider(item)).asData?.value
        : null;
    final series = item.kind == MediaKind.series
        ? ref.watch(seriesDetailProvider(item)).asData?.value
        : null;
    final art = movie?.backdropUrl.isNotEmpty == true
        ? movie!.backdropUrl
        : series?.backdropUrl.isNotEmpty == true
        ? series!.backdropUrl
        : item.imageUrl;
    final plot = movie?.plot ?? series?.plot ?? '';
    final wide = MediaQuery.sizeOf(context).width > 800;
    return SizedBox(
      height: wide ? 430 : 450,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Artwork(
              url: art,
              title: item.name,
              alignment: Alignment.centerRight,
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    const Color(0xFF071324),
                    const Color(0xF0071324),
                    const Color(0x50071324),
                  ],
                  stops: const [0, .38, 1],
                ),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xF0071324)],
                  stops: [.2, 1],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(wide ? 38 : 25),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: SizedBox(
                  width: wide ? 570 : double.infinity,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 23,
                            height: 2,
                            color: AppColors.accent,
                          ),
                          const SizedBox(width: 10),
                          const Eyebrow('IN THE SPOTLIGHT'),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text(
                        item.name,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.displayMedium
                            ?.copyWith(
                              fontSize: wide ? 58 : 41,
                              height: 1.02,
                              letterSpacing: -1.3,
                            ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 6,
                        children: [
                          MetaPill(
                            item.kind == MediaKind.movie ? 'MOVIE' : 'SERIES',
                          ),
                          if (item.rating.isNotEmpty)
                            MetaPill(item.rating, icon: Icons.star_rounded),
                          if (movie?.year.isNotEmpty == true)
                            MetaPill(movie!.year),
                        ],
                      ),
                      if (plot.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          plot,
                          maxLines: wide ? 2 : 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFD0DCEB),
                            height: 1.6,
                            fontSize: 14,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: onPressed,
                        icon: const Icon(Icons.play_arrow),
                        label: Text(
                          item.kind == MediaKind.movie
                              ? 'Discover movie'
                              : 'Explore series',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 20,
              right: 22,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Text(
                  'STREAMLINE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
