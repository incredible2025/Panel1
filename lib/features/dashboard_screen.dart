import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    if (item.kind == MediaKind.live) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PlayerScreen(item: item, channels: channels),
        ),
      );
    } else if (item.kind == MediaKind.movie) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => MovieDetailScreen(item: item)),
      );
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => SeriesDetailScreen(item: item)),
      );
    }
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
      bottomNavigationBar: isTv
          ? null
          : NavigationBar(
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
      body: SafeArea(
        child: FocusTraversalGroup(
          child: Row(
            children: [
              if (isTv) _sidebar(),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    isTv ? 28 : 18,
                    isTv ? 22 : 14,
                    isTv ? 28 : 18,
                    0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _header(isTv),
                      const SizedBox(height: 18),
                      TextField(
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'Search ${_title.toLowerCase()}',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _search.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear search',
                                  onPressed: () => setState(_search.clear),
                                  icon: const Icon(Icons.close),
                                ),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 14),
                      categories.when(
                        data: (value) => _categoryStrip(value),
                        loading: () => const SizedBox(
                          height: 42,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Loading categories…',
                              style: TextStyle(color: Color(0xFF91A4B9)),
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
                                  style: TextStyle(color: Color(0xFF91A4B9)),
                                ),
                              ),
                              TextButton(
                                onPressed: () =>
                                    ref.invalidate(categoriesProvider(_kind)),
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Expanded(
                        child: items.when(
                          loading: () => const StatusView(
                            title: 'Loading your library',
                            loading: true,
                          ),
                          error: (_, __) => StatusView(
                            title: 'Your library is unavailable',
                            message:
                                'Check your connection or try refreshing your provider.',
                            icon: Icons.wifi_off_rounded,
                            onRetry: _refresh,
                          ),
                          data: (allItems) {
                            final query = _search.text.trim().toLowerCase();
                            final selectedCategory = _category[_kind];
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
                              return StatusView(
                                title: 'No ${_title.toLowerCase()} available',
                                message:
                                    'Your provider has not supplied any content in this section.',
                                onRetry: _refresh,
                              );
                            }
                            if (filtered.isEmpty) {
                              return const StatusView(
                                title: 'No matches found',
                                message: 'Try another search or category.',
                                icon: Icons.search_off,
                              );
                            }
                            if (_kind == MediaKind.live) {
                              return _liveLibrary(filtered, isTv);
                            }
                            return _posterLibrary(
                              filtered,
                              isTv,
                              showHistory:
                                  query.isEmpty && selectedCategory == null,
                            );
                          },
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
    );
  }

  Widget _header(bool isTv) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isTv ? 'YOUR ENTERTAINMENT, TOGETHER' : 'STREAMLINE',
              style: const TextStyle(
                color: Color(0xFF54E1C1),
                fontSize: 10,
                letterSpacing: 2.3,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              _title,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                fontSize: isTv ? 30 : 28,
              ),
            ),
          ],
        ),
      ),
      IconButton(
        onPressed: _refresh,
        tooltip: 'Refresh library',
        icon: const Icon(Icons.refresh_rounded),
      ),
      if (!isTv)
        IconButton(
          onPressed: _signingOut ? null : _signOut,
          tooltip: 'Sign out',
          icon: const Icon(Icons.logout_rounded),
        ),
    ],
  );

  Widget _sidebar() => Container(
    width: 184,
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 20),
    decoration: const BoxDecoration(
      color: Color(0xFF0D1625),
      border: Border(right: BorderSide(color: Color(0xFF1D2C3D))),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          children: [
            Icon(
              Icons.play_circle_fill_rounded,
              color: Color(0xFF54E1C1),
              size: 28,
            ),
            SizedBox(width: 8),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  'STREAMLINE',
                  style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 44),
        for (final entry in [
          (MediaKind.live, Icons.live_tv, 'Live TV'),
          (MediaKind.movie, Icons.movie_outlined, 'Movies'),
          (MediaKind.series, Icons.video_library_outlined, 'Series'),
        ]) ...[
          TvFocusCard(
            selected: _kind == entry.$1,
            autofocus: entry.$1 == MediaKind.live,
            onPressed: () => _selectSection(entry.$1),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
              child: Row(
                children: [
                  Icon(
                    entry.$2,
                    size: 21,
                    color: _kind == entry.$1
                        ? const Color(0xFF54E1C1)
                        : const Color(0xFF91A4B9),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      entry.$3,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        const Spacer(),
        const Text(
          'ANDROID TV',
          style: TextStyle(
            fontSize: 10,
            color: Color(0xFF668093),
            letterSpacing: 1.7,
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _signingOut ? null : _signOut,
          icon: const Icon(Icons.logout_rounded, size: 17),
          label: const Text('Sign out'),
        ),
      ],
    ),
  );

  Widget _categoryStrip(List<Category> categories) => SizedBox(
    height: 42,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: categories.length + 1,
      separatorBuilder: (_, __) => const SizedBox(width: 8),
      itemBuilder: (context, index) {
        final category = index == 0 ? null : categories[index - 1];
        return TvFocusCard(
          selected: _category[_kind] == category?.id,
          borderRadius: 22,
          onPressed: () => setState(() => _category[_kind] = category?.id),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Text(
              category?.name ?? 'All',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        );
      },
    ),
  );

  Widget _posterLibrary(
    List<MediaItem> items,
    bool isTv, {
    required bool showHistory,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / (isTv ? 156 : 140))
            .floor()
            .clamp(2, 8);
        return CustomScrollView(
          key: PageStorageKey('library-${_kind.name}'),
          // Build the next screenful of focus targets before remote traversal.
          cacheExtent: constraints.maxHeight,
          slivers: [
            if (_kind == MediaKind.movie && showHistory)
              SliverToBoxAdapter(
                child: ref
                    .watch(historyProvider)
                    .when(
                      data: (history) {
                        final movies = history
                            .where(
                              (entry) => entry.item.kind == MediaKind.movie,
                            )
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
                                'Your next scene is waiting',
                                continuing,
                                isTv,
                                showProgress: true,
                              ),
                            if (movies.isNotEmpty)
                              _historyRow(
                                'Recently watched',
                                'Films you opened recently',
                                movies,
                                isTv,
                              ),
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
            SliverToBoxAdapter(
              child: SectionHeading(
                _kind == MediaKind.movie
                    ? 'Browse movies'
                    : 'Discover your next series',
                subtitle: '${items.length} titles',
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.only(bottom: 24),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  childAspectRatio: .60,
                  crossAxisSpacing: isTv ? 16 : 12,
                  mainAxisSpacing: 16,
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
          ],
        );
      },
    );
  }

  Widget _historyRow(
    String title,
    String subtitle,
    List<WatchEntry> history,
    bool isTv, {
    bool showProgress = false,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SectionHeading(title, subtitle: subtitle),
      SizedBox(
        height: isTv ? 240 : 220,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(bottom: 10),
          itemCount: history.length,
          separatorBuilder: (_, __) => const SizedBox(width: 14),
          itemBuilder: (context, index) => SizedBox(
            width: isTv ? 140 : 125,
            child: MediaCard(
              item: history[index].item,
              progress: showProgress ? history[index].progress : null,
              onPressed: () => _open(history[index].item),
            ),
          ),
        ),
      ),
      const SizedBox(height: 16),
    ],
  );

  Widget _liveLibrary(List<MediaItem> channels, bool isTv) {
    final selected = channels.any((item) => item.id == _channel?.id)
        ? _channel!
        : channels.first;
    final list = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            '${channels.length} channels',
            style: const TextStyle(color: Color(0xFF91A4B9), fontSize: 12),
          ),
        ),
        Expanded(
          child: ListView.separated(
            key: const PageStorageKey('live-channels'),
            padding: const EdgeInsets.only(bottom: 16),
            itemCount: channels.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final item = channels[index];
              return TvFocusCard(
                selected: item.id == selected.id,
                onPressed: () => setState(() => _channel = item),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 50,
                        height: 42,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(7),
                          child: Artwork(
                            url: item.imageUrl,
                            icon: Icons.live_tv,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          item.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        (index + 1).toString().padLeft(2, '0'),
                        style: const TextStyle(
                          color: Color(0xFF668093),
                          fontSize: 12,
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
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > 700;
        final preview = _livePreview(selected, channels, compact: !wide);
        Widget content(double height) {
          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 5, child: list),
                const SizedBox(width: 22),
                Expanded(flex: 6, child: preview),
              ],
            );
          }
          return Column(
            children: [
              Expanded(child: list),
              SizedBox(height: height > 480 ? 220 : 156, child: preview),
              const SizedBox(height: 12),
            ],
          );
        }

        // Landscape phones still need room for the programme guide and controls.
        if (constraints.maxHeight < 320) {
          return SingleChildScrollView(
            child: SizedBox(height: 400, child: content(400)),
          );
        }
        return content(constraints.maxHeight);
      },
    );
  }

  Widget _livePreview(
    MediaItem item,
    List<MediaItem> channels, {
    required bool compact,
  }) {
    final epg = ref.watch(epgProvider(item.id));
    return Container(
      margin: EdgeInsets.only(bottom: compact ? 0 : 16),
      padding: EdgeInsets.all(compact ? 14 : 22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF15393F), Color(0xFF121D2E)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF2A5057)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (!compact) ...[
                SizedBox(
                  width: 64,
                  height: 50,
                  child: Artwork(
                    url: item.imageUrl,
                    icon: Icons.live_tv,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '● LIVE NOW',
                      style: TextStyle(
                        color: Color(0xFF54E1C1),
                        fontSize: 10,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: compact ? 16 : 23,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (compact) ...[
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: () => _open(item, channels: channels),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Watch'),
                ),
              ],
            ],
          ),
          SizedBox(height: compact ? 10 : 24),
          Expanded(
            child: epg.when(
              loading: () => const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              error: (_, __) => Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Programme guide unavailable',
                      style: TextStyle(color: Color(0xFF91A4B9), fontSize: 12),
                    ),
                  ),
                  IconButton(
                    onPressed: () => ref.invalidate(epgProvider(item.id)),
                    tooltip: 'Retry programme guide',
                    icon: const Icon(Icons.refresh, size: 19),
                  ),
                ],
              ),
              data: (entries) {
                if (entries.isEmpty) {
                  return const Align(
                    alignment: Alignment.topLeft,
                    child: Text(
                      'No programme guide supplied for this channel.',
                      style: TextStyle(color: Color(0xFF91A4B9), fontSize: 12),
                    ),
                  );
                }
                final now = DateTime.now();
                final upcoming = entries
                    .where((entry) => entry.end.isAfter(now))
                    .take(compact ? 1 : 5)
                    .toList();
                final visible = upcoming.isEmpty
                    ? entries.take(compact ? 1 : 5).toList()
                    : upcoming;
                return ListView.separated(
                  itemCount: visible.length,
                  separatorBuilder: (_, __) =>
                      const Divider(color: Color(0xFF2A414D), height: 24),
                  itemBuilder: (context, index) {
                    final entry = visible[index];
                    final current =
                        entry.start.isBefore(now) && entry.end.isAfter(now);
                    final total = entry.end.difference(entry.start).inSeconds;
                    final elapsed = now.difference(entry.start).inSeconds;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '${_clock(entry.start)} – ${_clock(entry.end)}${current ? '  •  On now' : ''}',
                          style: TextStyle(
                            fontSize: 11,
                            color: current
                                ? const Color(0xFF54E1C1)
                                : const Color(0xFF91A4B9),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          entry.title,
                          maxLines: compact ? 1 : 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (!compact && entry.description.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            entry.description,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              height: 1.5,
                              color: Color(0xFF91A4B9),
                            ),
                          ),
                        ],
                        if (!compact && current && total > 0) ...[
                          const SizedBox(height: 12),
                          LinearProgressIndicator(
                            value: (elapsed / total).clamp(0.0, 1.0),
                            minHeight: 3,
                            backgroundColor: const Color(0xFF29424C),
                          ),
                        ],
                      ],
                    );
                  },
                );
              },
            ),
          ),
          if (!compact) ...[
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => _open(item, channels: channels),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 13),
                child: Text('Watch channel'),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Use ↑ / ↓ in the player to change channels',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF78969F), fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  String _clock(DateTime date) {
    final local = date.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}
