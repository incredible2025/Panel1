import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/design_system.dart';
import '../core/providers.dart';
import '../data/models.dart';
import '../widgets/media_card.dart';
import '../widgets/status_view.dart';
import '../widgets/tv_focus_card.dart';
import 'movie_detail_screen.dart';
import 'player_screen.dart';
import 'series_detail_screen.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  MediaKind _kind = MediaKind.live;
  final _search = TextEditingController();
  final _liveHeroKey = GlobalKey();
  final Map<MediaKind, String?> _category = {};
  MediaItem? _channel;
  bool _signingOut = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String get _title => switch (_kind) {
    MediaKind.live => 'Live TV',
    MediaKind.movie => 'Movies',
    MediaKind.series => 'Series',
  };

  void _selectSection(MediaKind kind) {
    if (_kind == kind) return;
    setState(() {
      _kind = kind;
      _search.clear();
    });
  }

  void _refresh() {
    ref.invalidate(itemsProvider(_kind));
    ref.invalidate(categoriesProvider(_kind));
    ref.invalidate(historyProvider);
    if (_channel != null) ref.invalidate(epgProvider(_channel!.id));
  }

  Future<void> _open(
    MediaItem item, {
    List<MediaItem> channels = const [],
  }) async {
    final Widget screen = switch (item.kind) {
      MediaKind.live => PlayerScreen(item: item, channels: channels),
      MediaKind.movie => MovieDetailScreen(item: item),
      MediaKind.series => SeriesDetailScreen(item: item),
    };
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => screen));
    if (mounted) ref.invalidate(historyProvider);
  }

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'Your watch history stays on this device for the next time you sign in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _signingOut = true);
    try {
      await ref.read(storeProvider).clearSession();
      if (mounted) ref.read(sessionProvider.notifier).state = null;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not sign out. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTv = ref.watch(isTvProvider);
    final categories = ref.watch(categoriesProvider(_kind));
    final items = ref.watch(itemsProvider(_kind));
    return Scaffold(
      backgroundColor: AppColors.canvas,
      bottomNavigationBar: isTv
          ? null
          : DecoratedBox(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: NavigationBar(
                height: 72,
                selectedIndex: MediaKind.values.indexOf(_kind),
                onDestinationSelected: (index) =>
                    _selectSection(MediaKind.values[index]),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.live_tv_outlined),
                    selectedIcon: Icon(Icons.live_tv),
                    label: 'Live TV',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.movie_outlined),
                    selectedIcon: Icon(Icons.movie),
                    label: 'Movies',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.video_library_outlined),
                    selectedIcon: Icon(Icons.video_library),
                    label: 'Series',
                  ),
                ],
              ),
            ),
      body: SafeArea(
        child: FocusTraversalGroup(
          child: Row(
            children: [
              if (isTv) _sidebar(),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, viewport) {
                    final margin = isTv
                        ? 32.0
                        : viewport.maxWidth > 700
                        ? 28.0
                        : 20.0;
                    final contentWidth = viewport.maxWidth - margin * 2;
                    final query = _search.text.trim().toLowerCase();
                    final selectedCategory = _category[_kind];
                    final browsing = query.isEmpty && selectedCategory == null;
                    return CustomScrollView(
                      key: PageStorageKey('dashboard-${_kind.name}'),
                      cacheExtent: viewport.maxHeight,
                      slivers: [
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                            margin,
                            isTv ? 25 : 20,
                            margin,
                            20,
                          ),
                          sliver: SliverToBoxAdapter(child: _header(isTv)),
                        ),
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(margin, 0, margin, 24),
                          sliver: SliverToBoxAdapter(
                            child: _toolbar(categories),
                          ),
                        ),
                        ...items.when(
                          loading: () => [
                            _status(
                              const StatusView(
                                title: 'Loading your library',
                                loading: true,
                              ),
                            ),
                          ],
                          error: (_, __) => [
                            _status(
                              StatusView(
                                title: 'Your library is unavailable',
                                message:
                                    'Check your connection or refresh your provider.',
                                icon: Icons.wifi_off_rounded,
                                onRetry: _refresh,
                              ),
                            ),
                          ],
                          data: (allItems) {
                            final filtered = allItems
                                .where(
                                  (item) =>
                                      (selectedCategory == null ||
                                          item.categoryId ==
                                              selectedCategory) &&
                                      (query.isEmpty ||
                                          item.name.toLowerCase().contains(
                                            query,
                                          )),
                                )
                                .toList(growable: false);
                            if (allItems.isEmpty) {
                              return [
                                _status(
                                  StatusView(
                                    title:
                                        'No ${_title.toLowerCase()} available',
                                    message:
                                        'Your provider has not supplied content in this section.',
                                    onRetry: _refresh,
                                  ),
                                ),
                              ];
                            }
                            if (filtered.isEmpty) {
                              return [
                                _status(
                                  const StatusView(
                                    title: 'No matches found',
                                    message: 'Try another search or category.',
                                    icon: Icons.search_off,
                                  ),
                                ),
                              ];
                            }
                            if (_kind == MediaKind.live) {
                              return _liveSlivers(
                                filtered,
                                isTv,
                                contentWidth,
                                margin,
                              );
                            }
                            return _catalogSlivers(
                              filtered,
                              isTv,
                              contentWidth,
                              margin,
                              browsing,
                            );
                          },
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 32)),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _status(Widget child) =>
      SliverFillRemaining(hasScrollBody: false, child: child);

  Widget _header(bool isTv) => Row(
    children: [
      if (!isTv) ...[const StreamlineMark(size: 30), const SizedBox(width: 12)],
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isTv) ...[
              const Eyebrow('YOUR LIBRARY'),
              const SizedBox(height: 7),
            ],
            Text(
              _title,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontSize: isTv ? 32 : 28,
                fontWeight: FontWeight.w600,
                letterSpacing: -.8,
              ),
            ),
          ],
        ),
      ),
      IconButton(
        onPressed: _refresh,
        tooltip: 'Refresh library',
        icon: const Icon(Icons.refresh_rounded, size: 22),
      ),
      if (!isTv)
        IconButton(
          onPressed: _signingOut ? null : _signOut,
          tooltip: 'Sign out',
          icon: const Icon(Icons.person_outline_rounded, size: 23),
        ),
    ],
  );

  Widget _sidebar() => Container(
    width: 196,
    decoration: const BoxDecoration(
      color: AppColors.surface,
      border: Border(right: BorderSide(color: AppColors.border)),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 30, 20, 24),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: StreamlineMark(size: 28, wordmark: true),
                  ),
                  const SizedBox(height: 48),
                  const Padding(
                    padding: EdgeInsets.only(left: 14, bottom: 16),
                    child: Eyebrow('BROWSE'),
                  ),
                  for (final entry in [
                    (MediaKind.live, Icons.live_tv_outlined, 'Live TV'),
                    (MediaKind.movie, Icons.movie_outlined, 'Movies'),
                    (MediaKind.series, Icons.video_library_outlined, 'Series'),
                  ]) ...[
                    TvFocusCard(
                      selected: _kind == entry.$1,
                      autofocus: entry.$1 == MediaKind.live,
                      transparent: true,
                      borderRadius: 10,
                      onPressed: () => _selectSection(entry.$1),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 16,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              entry.$2,
                              size: 22,
                              color: _kind == entry.$1
                                  ? AppColors.accent
                                  : AppColors.muted,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                entry.$3,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: _kind == entry.$1
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: _kind == entry.$1
                                      ? AppColors.text
                                      : AppColors.muted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 7),
                  ],
                  const Spacer(),
                  const SizedBox(height: 44),
                  const Divider(color: AppColors.border, height: 1),
                  const SizedBox(height: 20),
                  const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Eyebrow('ANDROID TV'),
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: _signingOut ? null : _signOut,
                    icon: const Icon(Icons.logout_rounded, size: 17),
                    label: const Text('Sign out'),
                    style: TextButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      foregroundColor: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _toolbar(AsyncValue<List<Category>> categories) => LayoutBuilder(
    builder: (context, constraints) {
      final search = TextField(
        controller: _search,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: 'Search ${_title.toLowerCase()}',
          prefixIcon: const Icon(Icons.search_rounded, size: 21),
          suffixIcon: _search.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  onPressed: () => setState(_search.clear),
                  icon: const Icon(Icons.close, size: 19),
                ),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
      );
      final filters = categories.when(
        data: _categoryStrip,
        loading: () => const SizedBox(
          height: 42,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Loading categories…',
              style: TextStyle(color: AppColors.subdued, fontSize: 12),
            ),
          ),
        ),
        error: (_, __) => SizedBox(
          height: 42,
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Categories unavailable',
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ),
              TextButton(
                onPressed: () => ref.invalidate(categoriesProvider(_kind)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
      if (constraints.maxWidth > 760) {
        return Row(
          children: [
            SizedBox(width: 280, child: search),
            const SizedBox(width: 24),
            Expanded(child: filters),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [search, const SizedBox(height: 12), filters],
      );
    },
  );

  Widget _categoryStrip(List<Category> categories) => SizedBox(
    height: 42,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: categories.length + 1,
      separatorBuilder: (_, __) => const SizedBox(width: 8),
      itemBuilder: (context, index) {
        final category = index == 0 ? null : categories[index - 1];
        final selected = _category[_kind] == category?.id;
        return TvFocusCard(
          selected: selected,
          transparent: true,
          borderRadius: 30,
          onPressed: () => setState(() => _category[_kind] = category?.id),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Text(
              category?.name ?? 'All',
              style: TextStyle(
                color: selected ? AppColors.accent : AppColors.muted,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        );
      },
    ),
  );

  List<Widget> _catalogSlivers(
    List<MediaItem> items,
    bool isTv,
    double width,
    double margin,
    bool browsing,
  ) {
    final columns = (width / (isTv ? 165 : 150)).floor().clamp(2, 8);
    return [
      if (browsing)
        SliverPadding(
          padding: EdgeInsets.fromLTRB(margin, 0, margin, 32),
          sliver: SliverToBoxAdapter(
            child: _catalogHero(items.first, isTv, width),
          ),
        ),
      if (_kind == MediaKind.movie && browsing)
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: margin),
          sliver: SliverToBoxAdapter(
            child: ref
                .watch(historyProvider)
                .when(
                  data: (history) {
                    final movies = history
                        .where((entry) => entry.item.kind == MediaKind.movie)
                        .toList(growable: false);
                    final continuing = movies
                        .where((entry) => entry.canResume)
                        .toList(growable: false);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (continuing.isNotEmpty)
                          _historyRow(
                            'Continue watching',
                            continuing,
                            isTv,
                            continueWatching: true,
                          ),
                        if (movies.isNotEmpty)
                          _historyRow('Recently watched', movies, isTv),
                      ],
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => ref.invalidate(historyProvider),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Reload watch history'),
                    ),
                  ),
                ),
          ),
        ),
      SliverPadding(
        padding: EdgeInsets.fromLTRB(margin, 0, margin, 18),
        sliver: SliverToBoxAdapter(
          child: _sectionTitle(
            _kind == MediaKind.movie ? 'Browse movies' : 'Discover series',
            trailing: '${items.length} titles',
          ),
        ),
      ),
      SliverPadding(
        padding: EdgeInsets.symmetric(horizontal: margin),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            childAspectRatio: .60,
            crossAxisSpacing: isTv ? 20 : 14,
            mainAxisSpacing: 24,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) => MediaCard(
              item: items[index],
              onPressed: () => _open(items[index]),
            ),
            childCount: items.length,
          ),
        ),
      ),
    ];
  }

  Widget _catalogHero(MediaItem item, bool isTv, double width) {
    String artwork = item.imageUrl;
    String plot = '';
    String genre = '';
    String rating = item.rating;
    String year = '';
    if (item.kind == MediaKind.movie) {
      final detail = ref.watch(movieDetailProvider(item)).asData?.value;
      if (detail != null) {
        artwork = detail.backdropUrl.isNotEmpty
            ? detail.backdropUrl
            : item.imageUrl;
        plot = detail.plot;
        genre = detail.genre;
        rating = detail.rating.isNotEmpty ? detail.rating : rating;
        year = detail.year;
      }
    } else {
      final detail = ref.watch(seriesDetailProvider(item)).asData?.value;
      if (detail != null) {
        artwork = detail.backdropUrl.isNotEmpty
            ? detail.backdropUrl
            : item.imageUrl;
        plot = detail.plot;
        genre = detail.genre;
        rating = detail.rating.isNotEmpty ? detail.rating : rating;
        year = detail.year;
      }
    }
    final wide = width > 650;
    return SizedBox(
      height: wide ? 420 : 410,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Artwork(
              url: artwork,
              title: item.name,
              icon: item.kind == MediaKind.movie
                  ? Icons.movie_outlined
                  : Icons.video_library_outlined,
              alignment: wide
                  ? Alignment.centerRight
                  : const Alignment(.25, -.3),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: wide ? Alignment.centerLeft : Alignment.bottomCenter,
                  end: wide ? Alignment.centerRight : Alignment.topCenter,
                  colors: [
                    AppColors.canvas.withValues(alpha: .98),
                    AppColors.canvas.withValues(alpha: .72),
                    AppColors.canvas.withValues(alpha: .02),
                  ],
                  stops: const [0, .48, 1],
                ),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x10000000),
                    Color(0x00000000),
                    Color(0x55000000),
                  ],
                ),
              ),
            ),
            Positioned(
              left: wide ? 32 : 22,
              right: wide ? width * .37 : 22,
              bottom: wide ? 30 : 24,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Eyebrow(
                    item.kind == MediaKind.movie
                        ? 'FROM YOUR MOVIE LIBRARY'
                        : 'FROM YOUR SERIES LIBRARY',
                    color: AppColors.accent,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontSize: wide ? 42 : 34,
                      fontWeight: FontWeight.w600,
                      height: 1.04,
                      letterSpacing: -1.1,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 12,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (rating.isNotEmpty) _rating(rating),
                      if (year.isNotEmpty)
                        Text(
                          year,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      if (genre.isNotEmpty)
                        Text(
                          genre.split(',').take(2).join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                  if (plot.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      plot,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 13,
                        height: 1.6,
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  FilledButton.icon(
                    onPressed: () => _open(item),
                    icon: const Icon(Icons.play_arrow_rounded, size: 21),
                    label: Text(
                      item.kind == MediaKind.movie
                          ? 'View movie'
                          : 'Explore series',
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 23,
                        vertical: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.canvas.withValues(alpha: .65),
                  border: Border.all(
                    color: AppColors.text.withValues(alpha: .15),
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  item.kind == MediaKind.movie ? 'FILM' : 'SERIES',
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 9,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _historyRow(
    String title,
    List<WatchEntry> entries,
    bool isTv, {
    bool continueWatching = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 32),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(title, trailing: '${entries.length}'),
        const SizedBox(height: 18),
        SizedBox(
          height: continueWatching ? (isTv ? 195 : 183) : (isTv ? 240 : 220),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            cacheExtent: 600,
            itemCount: entries.length,
            separatorBuilder: (_, __) => const SizedBox(width: 16),
            itemBuilder: (context, index) {
              final entry = entries[index];
              if (!continueWatching) {
                return SizedBox(
                  width: isTv ? 138 : 125,
                  child: MediaCard(
                    item: entry.item,
                    onPressed: () => _open(entry.item),
                  ),
                );
              }
              return SizedBox(
                width: isTv ? 300 : 270,
                child: TvFocusCard(
                  label: 'Resume ${entry.item.name}',
                  borderRadius: 10,
                  onPressed: () => _open(entry.item),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Artwork(
                              url: entry.item.imageUrl,
                              title: entry.item.name,
                            ),
                            const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Color(0x00000000),
                                    Color(0xCC000000),
                                  ],
                                ),
                              ),
                            ),
                            Positioned(
                              left: 14,
                              bottom: 13,
                              right: 14,
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.play_circle_outline_rounded,
                                    color: AppColors.text,
                                    size: 30,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      '${((entry.durationMs - entry.positionMs) / 60000).ceil()} min left',
                                      style: const TextStyle(
                                        color: AppColors.text,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      LinearProgressIndicator(
                        value: entry.progress,
                        minHeight: 2,
                        color: AppColors.accent,
                        backgroundColor: AppColors.border,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 13,
                        ),
                        child: Text(
                          entry.item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 13,
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
      ],
    ),
  );

  List<Widget> _liveSlivers(
    List<MediaItem> channels,
    bool isTv,
    double width,
    double margin,
  ) {
    final selected = channels.any((item) => item.id == _channel?.id)
        ? _channel!
        : channels.first;
    final epg = ref.watch(epgProvider(selected.id));
    final entries = epg.asData?.value ?? <EpgEntry>[];
    final now = DateTime.now();
    EpgEntry? programme;
    for (final entry in entries) {
      if (entry.start.isBefore(now) && entry.end.isAfter(now)) {
        programme = entry;
        break;
      }
    }
    final upcoming = entries
        .where((entry) => entry.start.isAfter(now))
        .take(4)
        .toList(growable: false);
    final split = width > 850;
    return [
      SliverPadding(
        padding: EdgeInsets.symmetric(horizontal: margin),
        sliver: SliverToBoxAdapter(
          child: KeyedSubtree(
            key: _liveHeroKey,
            child: split
                ? SizedBox(
                    height: 470,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 7,
                          child: _liveFeature(
                            selected,
                            channels,
                            epg,
                            programme,
                            isTv,
                          ),
                        ),
                        const SizedBox(width: 26),
                        Expanded(
                          flex: 5,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _sectionTitle(
                                'Channel guide',
                                trailing: '${channels.length}',
                              ),
                              const SizedBox(height: 14),
                              Expanded(
                                child: ListView.separated(
                                  key: const PageStorageKey(
                                    'live-channel-list',
                                  ),
                                  cacheExtent: 500,
                                  itemCount: channels.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 7),
                                  itemBuilder: (context, index) => _channelRow(
                                    channels[index],
                                    index,
                                    selected,
                                    isTv,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                : SizedBox(
                    height: isTv ? 470 : 430,
                    child: _liveFeature(
                      selected,
                      channels,
                      epg,
                      programme,
                      isTv,
                    ),
                  ),
          ),
        ),
      ),
      if (upcoming.isNotEmpty)
        SliverPadding(
          padding: EdgeInsets.fromLTRB(margin, 28, margin, 0),
          sliver: SliverToBoxAdapter(child: _upNext(upcoming)),
        ),
      if (!split) ...[
        SliverPadding(
          padding: EdgeInsets.fromLTRB(margin, 30, margin, 18),
          sliver: SliverToBoxAdapter(
            child: _sectionTitle(
              'Channel guide',
              trailing: '${channels.length} channels',
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: margin),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _channelRow(channels[index], index, selected, isTv),
              ),
              childCount: channels.length,
            ),
          ),
        ),
      ],
    ];
  }

  Widget _liveFeature(
    MediaItem item,
    List<MediaItem> channels,
    AsyncValue<List<EpgEntry>> epg,
    EpgEntry? programme,
    bool isTv,
  ) {
    final now = DateTime.now();
    final total = programme == null
        ? 0
        : programme.end.difference(programme.start).inSeconds;
    final elapsed = programme == null
        ? 0
        : now.difference(programme.start).inSeconds;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              right: -30,
              top: -30,
              bottom: 60,
              width: 320,
              child: Opacity(
                opacity: .12,
                child: Artwork(
                  url: item.imageUrl,
                  title: item.name,
                  icon: Icons.live_tv_outlined,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomLeft,
                  end: Alignment.topRight,
                  colors: [
                    AppColors.canvas.withValues(alpha: .92),
                    AppColors.surfaceRaised.withValues(alpha: .2),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(isTv ? 28 : 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: AppColors.live,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'ON AIR',
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 2,
                          color: AppColors.live,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Flexible(
                        child: Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Eyebrow(
                    programme == null
                        ? 'LIVE CHANNEL'
                        : '${_clock(programme.start)} — ${_clock(programme.end)}',
                    color: AppColors.accent,
                  ),
                  const SizedBox(height: 11),
                  Text(
                    programme?.title ?? item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      fontSize: isTv ? 36 : 30,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -.7,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (programme?.description.isNotEmpty == true)
                    Text(
                      programme!.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                        height: 1.6,
                      ),
                    )
                  else
                    Text(
                      epg.isLoading
                          ? 'Loading programme guide…'
                          : epg.hasError
                          ? 'Programme guide unavailable'
                          : 'No programme details supplied by your provider.',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                        height: 1.6,
                      ),
                    ),
                  const SizedBox(height: 19),
                  if (programme != null && total > 0) ...[
                    LinearProgressIndicator(
                      value: (elapsed / total).clamp(0.0, 1.0),
                      minHeight: 2,
                      color: AppColors.accent,
                      backgroundColor: AppColors.border,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _clock(now),
                          style: const TextStyle(
                            color: AppColors.subdued,
                            fontSize: 10,
                          ),
                        ),
                        Text(
                          '${programme.end.difference(now).inMinutes.clamp(0, 999)} min remaining',
                          style: const TextStyle(
                            color: AppColors.subdued,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _open(item, channels: channels),
                          icon: const Icon(Icons.play_arrow_rounded, size: 23),
                          label: const Text(
                            'Watch channel',
                            style: TextStyle(fontSize: 13),
                          ),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 15,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton.outlined(
                        onPressed: () => ref.invalidate(epgProvider(item.id)),
                        tooltip: 'Refresh programme guide',
                        icon: const Icon(Icons.refresh_rounded, size: 21),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _channelRow(
    MediaItem item,
    int index,
    MediaItem selected,
    bool isTv,
  ) => TvFocusCard(
    selected: item.id == selected.id,
    transparent: true,
    borderRadius: 8,
    label: item.name,
    onPressed: () {
      setState(() => _channel = item);
      if (!isTv) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final target = _liveHeroKey.currentContext;
          if (mounted && target != null) {
            Scrollable.ensureVisible(
              target,
              alignment: .1,
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 200),
            );
          }
        });
      }
    },
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 14),
      child: Row(
        children: [
          SizedBox(
            width: 25,
            child: Text(
              (index + 1).toString().padLeft(2, '0'),
              style: const TextStyle(color: AppColors.subdued, fontSize: 10),
            ),
          ),
          Container(
            width: 42,
            height: 36,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: AppColors.canvas,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Artwork(
              url: item.imageUrl,
              title: item.name,
              icon: Icons.live_tv_outlined,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Text(
              item.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: item.id == selected.id
                    ? FontWeight.w600
                    : FontWeight.w400,
                fontSize: 13,
                color: item.id == selected.id
                    ? AppColors.text
                    : AppColors.muted,
              ),
            ),
          ),
          const SizedBox(width: 9),
          Icon(
            item.id == selected.id
                ? Icons.graphic_eq_rounded
                : Icons.chevron_right_rounded,
            color: item.id == selected.id
                ? AppColors.accent
                : AppColors.subdued,
            size: 18,
          ),
        ],
      ),
    ),
  );

  Widget _upNext(List<EpgEntry> entries) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Eyebrow('UP NEXT'),
      const SizedBox(height: 15),
      SizedBox(
        height: 76,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: entries.length,
          separatorBuilder: (_, __) => const SizedBox(width: 24),
          itemBuilder: (context, index) {
            final entry = entries[index];
            return Container(
              width: 235,
              padding: const EdgeInsets.only(left: 16),
              decoration: const BoxDecoration(
                border: Border(left: BorderSide(color: AppColors.border)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_clock(entry.start)} — ${_clock(entry.end)}',
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    entry.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ],
  );

  Widget _sectionTitle(String title, {String? trailing}) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontSize: 21,
            fontWeight: FontWeight.w500,
            letterSpacing: -.4,
          ),
        ),
      ),
      if (trailing != null) ...[
        const SizedBox(width: 12),
        Text(
          trailing,
          style: const TextStyle(color: AppColors.subdued, fontSize: 11),
        ),
      ],
    ],
  );

  Widget _rating(String value) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(Icons.star_rounded, size: 14, color: AppColors.accent),
      const SizedBox(width: 4),
      Text(
        value,
        style: const TextStyle(
          color: AppColors.accent,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );

  String _clock(DateTime value) {
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}
