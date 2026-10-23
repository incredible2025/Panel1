import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/design_system.dart';
import '../core/providers.dart';
import '../core/settings_controller.dart';
import '../data/app_settings.dart';
import '../widgets/parental_access.dart';
import '../widgets/library_shelves.dart';
import '../widgets/live_channel_preview.dart';
import 'home_screen.dart';
import 'settings_screen.dart';
import '../data/models.dart';
import '../widgets/media_card.dart';
import '../widgets/status_view.dart';
import '../widgets/tv_focus_card.dart';
import '../widgets/tv_category_strip.dart';
import 'movie_detail_screen.dart';
import 'player_screen.dart';
import 'series_detail_screen.dart';
import 'tv_guide_screen.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  String _clock(DateTime value) => guideClock(value);
  MediaKind _kind = MediaKind.live;
  final _search = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'Library search');
  final _favoritesFocus = FocusNode(debugLabel: 'Favorites filter');
  final _categoryStripKey = GlobalKey<TvCategoryStripState>();
  final _navigationFocus = <String, FocusNode>{};
  final _scroll = ScrollController();
  final _liveHeroKey = GlobalKey();
  final _previewKey = GlobalKey<LiveChannelPreviewState>();
  final Map<MediaKind, String?> _category = {};
  final Map<MediaKind, CatalogSort> _sort = {};
  final Set<MediaKind> _browseAll = {};
  final Set<MediaKind> _myListOnly = {};
  final Set<String> _savingFavorites = {};
  MediaItem? _channel;
  String _destination = 'home';
  bool _restoring = true;
  bool _navExpanded = false;
  AppSettings get _preferences =>
      ref.read(settingsProvider).asData?.value ?? const AppSettings();
  @override
  void initState() {
    super.initState();
    unawaited(_restore());
  }

  Future<void> _restore() async {
    await ref.read(settingsProvider.notifier).ready;
    if (!mounted) return;
    final preferences = _preferences;
    setState(() {
      _destination =
          {
            'home',
            'live',
            'movie',
            'series',
            'settings',
          }.contains(preferences.lastSection)
          ? preferences.lastSection
          : 'home';
      _kind =
          MediaKind.values
              .where((kind) => kind.name == _destination)
              .firstOrNull ??
          MediaKind.live;
      for (final entry in preferences.lastCategories.entries) {
        final kind = MediaKind.values
            .where((kind) => kind.name == entry.key)
            .firstOrNull;
        if (kind != null) {
          _category[kind] = entry.value.isEmpty ? null : entry.value;
        }
      }
      _restoring = false;
    });
  }

  void _remember({MediaItem? item}) {
    unawaited(
      ref
          .read(settingsProvider.notifier)
          .update(
            (settings) => settings.patch({
              'lastSection': _destination,
              'lastCategories': {
                ...settings.lastCategories,
                _kind.name: _category[_kind] ?? '',
              },
              if (item?.kind == MediaKind.live) 'lastChannel': item!.id,
              if (item != null)
                'lastItems': {...settings.lastItems, item.kind.name: item.id},
            }),
          ),
    );
  }

  void _selectDestination(String value) {
    if (value == _destination) return;
    unawaited(_previewKey.currentState?.stop() ?? Future.value());
    setState(() {
      _destination = value;
      _search.clear();
    });
    _remember();
    _scrollToTop();
  }

  bool _favoritesOnly = false;

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    _favoritesFocus.dispose();
    for (final node in _navigationFocus.values) {
      node.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  FocusNode _navFocus(String destination) => _navigationFocus.putIfAbsent(
    destination,
    () => FocusNode(debugLabel: 'Navigation: $destination'),
  );

  void _focusCategories() {
    if (_categoryStripKey.currentState case final state?) {
      state.focusSelected();
    } else {
      _searchFocus.requestFocus();
    }
  }

  KeyEventResult _navigationKey(FocusNode node, KeyEvent event) {
    if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
        event.logicalKey == LogicalKeyboardKey.arrowRight &&
        {'live', 'movie', 'series'}.contains(_destination)) {
      _focusCategories();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _searchKey(FocusNode node, KeyEvent event) {
    if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
        event.logicalKey == LogicalKeyboardKey.arrowDown &&
        _categoryStripKey.currentState != null) {
      _focusCategories();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  String get _title => switch (_kind) {
    MediaKind.live => 'Live TV',
    MediaKind.movie => 'Movies',
    MediaKind.series => 'Series',
  };

  void _selectSection(MediaKind kind) {
    if (_kind == kind && _destination == kind.name) return;
    unawaited(_previewKey.currentState?.stop() ?? Future.value());
    setState(() {
      _kind = kind;
      _destination = kind.name;
      _search.clear();
    });
    _remember();
    _scrollToTop();
  }

  void _scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _scroll.jumpTo(0);
      } else {
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  Future<void> _showCategory(String? id) async {
    if (id != null &&
        _preferences.lockedCategories.contains(
          AppSettings.categoryKey(_kind, id),
        ) &&
        !await requestParentalAccess(
          context,
          ref,
          reason: 'Unlock this category',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _category[_kind] = id;
      _myListOnly.remove(_kind);
    });
    _remember();
    _scrollToTop();
  }

  void _showMyList() {
    setState(() {
      _category[_kind] = null;
      _search.clear();
      _browseAll.add(_kind);
      _myListOnly.add(_kind);
    });
    _scrollToTop();
  }

  void _showAll({CatalogSort? sort}) {
    setState(() {
      _browseAll.add(_kind);
      _myListOnly.remove(_kind);
      if (sort != null) _sort[_kind] = sort;
    });
    _scrollToTop();
  }

  Future<void> _toggleFavorite(MediaItem item) async {
    final session = ref.read(sessionProvider);
    if (session == null || _savingFavorites.contains(item.id)) return;
    final saved = ref.read(favoritesProvider).asData?.value ?? <MediaItem>[];
    final favorite = saved.any(
      (entry) => entry.id == item.id && entry.kind == item.kind,
    );
    setState(() => _savingFavorites.add(item.id));
    try {
      await ref
          .read(storeProvider)
          .setFavorite(session.accountId, item, !favorite);
      if (mounted) {
        ref.invalidate(favoritesProvider);
        await ref.read(favoritesProvider.future);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not update your favorite channels. Please try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _savingFavorites.remove(item.id));
    }
  }

  void _refresh() {
    ref.invalidate(itemsProvider(_kind));
    ref.invalidate(categoriesProvider(_kind));
    ref.invalidate(historyProvider);
    ref.invalidate(seriesHistoryProvider);
    ref.invalidate(favoritesProvider);
    ref.invalidate(recentChannelsProvider);
    if (_channel != null) ref.invalidate(epgProvider(_channel!.id));
  }

  Future<void> _open(
    MediaItem item, {
    List<MediaItem> channels = const [],
  }) async {
    if (!await allowMedia(context, ref, item) || !mounted) return;
    await _previewKey.currentState?.stop();
    if (!mounted) return;
    _remember(item: item);
    if (item.kind == MediaKind.live && channels.isEmpty) {
      channels = (ref.read(itemsProvider(MediaKind.live)).asData?.value ?? [])
          .where(
            (channel) =>
                !_preferences.hidden(channel) &&
                (ref.read(parentalSessionProvider) ||
                    !_preferences.locked(channel)),
          )
          .toList();
    }
    final Widget screen = switch (item.kind) {
      MediaKind.live => PlayerScreen(item: item, channels: channels),
      MediaKind.movie => MovieDetailScreen(item: item),
      MediaKind.series => SeriesDetailScreen(item: item),
    };
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => screen));
    if (mounted) {
      ref.invalidate(historyProvider);
      ref.invalidate(seriesHistoryProvider);
      ref.invalidate(recentChannelsProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTv = ref.watch(isTvProvider);
    final settings = ref.watch(settingsProvider);
    final unlocked = ref.watch(parentalSessionProvider);
    final preferences = settings.asData?.value ?? const AppSettings();
    if (settings.hasError) {
      return Scaffold(
        body: StatusView(
          title: 'Preferences unavailable',
          message:
              'Reload before browsing so parental protection remains active.',
          onRetry: () => ref.read(settingsProvider.notifier).reload(),
        ),
      );
    }
    if (_restoring || settings.isLoading) {
      return const Scaffold(
        body: StatusView(title: 'Preparing ULTRAVPN PLAYER', loading: true),
      );
    }
    final categories = ref.watch(categoriesProvider(_kind));
    final items = ref.watch(itemsProvider(_kind));
    final favoritesState = ref.watch(favoritesProvider);
    final favoriteIds =
        favoritesState.asData?.value
            .where((item) => item.kind == _kind)
            .map((item) => item.id)
            .toSet() ??
        <String>{};
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      bottomNavigationBar: isTv
          ? null
          : DecoratedBox(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: NavigationBar(
                height: 72,
                selectedIndex: const [
                  'home',
                  'live',
                  'movie',
                  'series',
                  'settings',
                ].indexOf(_destination),
                onDestinationSelected: (index) {
                  if (index == 0 || index == 4) {
                    _selectDestination(index == 0 ? 'home' : 'settings');
                  } else {
                    _selectSection(MediaKind.values[index - 1]);
                  }
                },
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home_rounded),
                    label: 'Home',
                  ),
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
                  NavigationDestination(
                    icon: Icon(Icons.settings_outlined),
                    selectedIcon: Icon(Icons.settings),
                    label: 'Settings',
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
                child: _destination == 'settings'
                    ? const SettingsScreen(embedded: true)
                    : _destination == 'home'
                    ? HomeScreen(
                        onOpen: (item) => _open(item),
                        onBrowse: _selectSection,
                        onSettings: () => _selectDestination('settings'),
                      )
                    : LayoutBuilder(
                        builder: (context, viewport) {
                          final margin = isTv
                              ? 32.0
                              : viewport.maxWidth > 700
                              ? 28.0
                              : 20.0;
                          final contentWidth = viewport.maxWidth - margin * 2;
                          final query = _search.text.trim().toLowerCase();
                          final selectedCategory = _category[_kind];
                          final browsing =
                              query.isEmpty &&
                              selectedCategory == null &&
                              !_browseAll.contains(_kind);
                          final library = CustomScrollView(
                            controller: _scroll,
                            key: PageStorageKey('dashboard-${_kind.name}'),
                            cacheExtent: viewport.maxHeight,
                            slivers: [
                              if (!isTv) ...[
                                SliverPadding(
                                  padding: EdgeInsets.fromLTRB(
                                    margin,
                                    isTv ? 25 : 20,
                                    margin,
                                    20,
                                  ),
                                  sliver: SliverToBoxAdapter(
                                    child: _header(isTv),
                                  ),
                                ),
                                SliverPadding(
                                  padding: EdgeInsets.fromLTRB(
                                    margin,
                                    0,
                                    margin,
                                    24,
                                  ),
                                  sliver: SliverToBoxAdapter(
                                    child: _toolbar(categories),
                                  ),
                                ),
                              ],
                              SliverPadding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: margin,
                                ),
                                sliver: SliverToBoxAdapter(
                                  child: AccountExpiryNotice(
                                    onAccount: () =>
                                        _selectDestination('settings'),
                                  ),
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
                                  if (((_kind == MediaKind.live &&
                                              _favoritesOnly) ||
                                          _myListOnly.contains(_kind)) &&
                                      favoritesState.isLoading) {
                                    return [
                                      _status(
                                        const StatusView(
                                          title: 'Loading favorite channels',
                                          loading: true,
                                        ),
                                      ),
                                    ];
                                  }
                                  if (((_kind == MediaKind.live &&
                                              _favoritesOnly) ||
                                          _myListOnly.contains(_kind)) &&
                                      favoritesState.hasError) {
                                    return [
                                      _status(
                                        StatusView(
                                          title:
                                              'Favorite channels are unavailable',
                                          message:
                                              'Please reload your saved channels.',
                                          onRetry: () =>
                                              ref.invalidate(favoritesProvider),
                                        ),
                                      ),
                                    ];
                                  }
                                  final matching = allItems
                                      .where(
                                        (item) =>
                                            !preferences.hidden(item) &&
                                            (unlocked ||
                                                !preferences.locked(item)) &&
                                            (_kind != MediaKind.live ||
                                                !_favoritesOnly ||
                                                favoriteIds.contains(
                                                  item.id,
                                                )) &&
                                            (!_myListOnly.contains(_kind) ||
                                                favoriteIds.contains(
                                                  item.id,
                                                )) &&
                                            (selectedCategory == null ||
                                                item.categoryId ==
                                                    selectedCategory) &&
                                            (query.isEmpty ||
                                                item.name
                                                    .toLowerCase()
                                                    .contains(query)),
                                      )
                                      .toList(growable: false);
                                  final filtered = _kind == MediaKind.live
                                      ? matching
                                      : sortMediaItems(
                                          matching,
                                          _sort[_kind] ??
                                              CatalogSort.recentlyAdded,
                                        );
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
                                        StatusView(
                                          title:
                                              _kind == MediaKind.live &&
                                                  _favoritesOnly &&
                                                  query.isEmpty &&
                                                  selectedCategory == null
                                              ? 'No favorite channels yet'
                                              : _myListOnly.contains(_kind)
                                              ? 'Your list is empty'
                                              : 'No matches found',
                                          message:
                                              _kind == MediaKind.live &&
                                                  _favoritesOnly
                                              ? 'Turn off Favorites and use the star beside a channel to save it.'
                                              : _myListOnly.contains(_kind)
                                              ? 'Open a movie or series and choose My List to save it here.'
                                              : 'Try another search or category.',
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
                              const SliverToBoxAdapter(
                                child: SizedBox(height: 32),
                              ),
                            ],
                          );
                          if (!isTv) return library;
                          // TV controls stay mounted while the content scrolls.
                          // Sidebar expansion must never replace their layout.
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding: EdgeInsets.fromLTRB(
                                  margin,
                                  20,
                                  margin,
                                  16,
                                ),
                                child: _header(true),
                              ),
                              Padding(
                                padding: EdgeInsets.fromLTRB(
                                  margin,
                                  0,
                                  margin,
                                  18,
                                ),
                                child: _toolbar(categories),
                              ),
                              Expanded(child: library),
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
      if (_kind == MediaKind.live)
        IconButton(
          tooltip: 'TV guide',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const TvGuideScreen()),
          ),
          icon: const Icon(Icons.calendar_view_week_rounded),
        ),
      IconButton(
        onPressed: _refresh,
        tooltip: 'Refresh library',
        icon: const Icon(Icons.refresh_rounded, size: 22),
      ),
      if (!isTv)
        IconButton(
          onPressed: () => _selectDestination('settings'),
          tooltip: 'Settings',
          icon: const Icon(Icons.settings_outlined, size: 23),
        ),
    ],
  );

  Widget _sidebar() => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onFocusChange: (focused) {
      if (mounted && _navExpanded != focused) {
        setState(() => _navExpanded = focused);
      }
    },
    child: AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 180),
      width: _navExpanded ? 208 : 84,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: .68),
        border: const Border(right: BorderSide(color: AppColors.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final expanded = constraints.maxWidth > 180;
          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 44,
                    child: Center(
                      child: StreamlineMark(size: 28, wordmark: expanded),
                    ),
                  ),
                  const SizedBox(height: 36),
                  for (final entry in [
                    ('home', Icons.home_outlined, 'Home'),
                    ('live', Icons.live_tv_outlined, 'Live TV'),
                    ('movie', Icons.movie_outlined, 'Movies'),
                    ('series', Icons.video_library_outlined, 'Series'),
                    ('settings', Icons.settings_outlined, 'Settings'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Tooltip(
                        message: entry.$3,
                        child: TvFocusCard(
                          key: ValueKey('navigation-${entry.$1}'),
                          focusNode: _navFocus(entry.$1),
                          onKeyEvent: _navigationKey,
                          label: entry.$3,
                          selected: _destination == entry.$1,
                          autofocus: _destination == entry.$1,
                          borderRadius: 12,
                          transparent: true,
                          onPressed: () {
                            final kind = MediaKind.values
                                .where((kind) => kind.name == entry.$1)
                                .firstOrNull;
                            if (kind == null) {
                              _selectDestination(entry.$1);
                            } else {
                              _selectSection(kind);
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 17,
                            ),
                            child: Row(
                              mainAxisAlignment: expanded
                                  ? MainAxisAlignment.start
                                  : MainAxisAlignment.center,
                              children: [
                                Icon(
                                  entry.$2,
                                  size: 23,
                                  color: _destination == entry.$1
                                      ? Theme.of(context).colorScheme.primary
                                      : AppColors.muted,
                                ),
                                if (expanded) ...[
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Text(
                                      entry.$3,
                                      style: TextStyle(
                                        color: _destination == entry.$1
                                            ? AppColors.text
                                            : AppColors.muted,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 40),
                  if (expanded)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Eyebrow(
                        'YOUR WORLD. ON SCREEN.',
                        color: AppColors.subdued,
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );

  Widget _toolbar(AsyncValue<List<Category>> categories) => LayoutBuilder(
    builder: (context, constraints) {
      final search = Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: ref.read(isTvProvider) ? _searchKey : null,
        child: TextField(
          controller: _search,
          focusNode: _searchFocus,
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
      final categoryControls = _kind != MediaKind.live
          ? filters
          : Row(
              children: [
                Expanded(child: filters),
                const SizedBox(width: 8),
                SizedBox(
                  height: 42,
                  child: TvFocusCard(
                    focusNode: _favoritesFocus,
                    onKeyEvent: (node, event) {
                      if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
                          event.logicalKey == LogicalKeyboardKey.arrowLeft &&
                          ref.read(isTvProvider)) {
                        _categoryStripKey.currentState?.focusLastFocused();
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    selected: _favoritesOnly,
                    transparent: true,
                    label: 'Favorites only',
                    borderRadius: 30,
                    onPressed: () {
                      setState(() => _favoritesOnly = !_favoritesOnly);
                      _scrollToTop();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 13),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _favoritesOnly
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            size: 17,
                            color: _favoritesOnly
                                ? AppColors.accent
                                : AppColors.muted,
                          ),
                          const SizedBox(width: 7),
                          Text(
                            'Favorites',
                            style: TextStyle(
                              fontSize: 12,
                              color: _favoritesOnly
                                  ? AppColors.accent
                                  : AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
      final searchControls = Row(
        children: [
          Expanded(child: search),
          if (_kind != MediaKind.live) ...[
            const SizedBox(width: 10),
            _sortControl(),
          ],
        ],
      );
      if (!ref.read(isTvProvider) && constraints.maxWidth > 760) {
        return Row(
          children: [
            SizedBox(
              width: _kind == MediaKind.live ? 280 : 400,
              child: searchControls,
            ),
            const SizedBox(width: 24),
            Expanded(child: categoryControls),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          searchControls,
          const SizedBox(height: 12),
          categoryControls,
        ],
      );
    },
  );

  Widget _sortControl() {
    final selected = _sort[_kind] ?? CatalogSort.recentlyAdded;
    final label = switch (selected) {
      CatalogSort.recentlyAdded => 'Newest',
      CatalogSort.titleAscending => 'A–Z',
      CatalogSort.titleDescending => 'Z–A',
    };
    return PopupMenuButton<CatalogSort>(
      tooltip: 'Sort library',
      initialValue: selected,
      onSelected: (value) {
        setState(() => _sort[_kind] = value);
        _scrollToTop();
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: CatalogSort.recentlyAdded,
          child: Text('Recently added'),
        ),
        PopupMenuItem(
          value: CatalogSort.titleAscending,
          child: Text('Title: A–Z'),
        ),
        PopupMenuItem(
          value: CatalogSort.titleDescending,
          child: Text('Title: Z–A'),
        ),
      ],
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sort_rounded, size: 18, color: AppColors.muted),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 5),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: AppColors.subdued,
            ),
          ],
        ),
      ),
    );
  }

  List<Category> _orderedCategories(List<Category> supplied) {
    final visible = supplied
        .where(
          (category) => !_preferences.hiddenCategories.contains(
            AppSettings.categoryKey(_kind, category.id),
          ),
        )
        .toList();
    final order = _preferences.categoryOrder[_kind.name] ?? [];
    int rank(Category category) {
      final index = order.indexOf(category.id);
      return index < 0 ? order.length + supplied.indexOf(category) : index;
    }

    visible.sort((a, b) => rank(a).compareTo(rank(b)));
    return visible;
  }

  Widget _categoryStrip(List<Category> supplied) {
    final categories = _orderedCategories(supplied);
    if (ref.read(isTvProvider)) {
      final listOnly = _myListOnly.contains(_kind);
      return TvCategoryStrip(
        key: _categoryStripKey,
        onUp: _searchFocus.requestFocus,
        onLeftBoundary: () => _navFocus(_destination).requestFocus(),
        onRightBoundary: _kind == MediaKind.live
            ? _favoritesFocus.requestFocus
            : null,
        choices: [
          TvCategoryChoice(
            id: '${_kind.name}:all',
            label: 'All',
            selected: !listOnly && _category[_kind] == null,
            onPressed: () => _showCategory(null),
          ),
          if (_kind != MediaKind.live)
            TvCategoryChoice(
              id: '${_kind.name}:list',
              label: 'My List',
              selected: listOnly,
              onPressed: _showMyList,
            ),
          for (final category in categories)
            TvCategoryChoice(
              id: '${_kind.name}:${category.id}',
              label: category.name,
              selected: !listOnly && _category[_kind] == category.id,
              onPressed: () => _showCategory(category.id),
            ),
        ],
      );
    }
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length + (_kind == MediaKind.live ? 1 : 2),
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final extra = _kind == MediaKind.live ? 1 : 2;
          final list = extra == 2 && index == 1;
          final category = index < extra ? null : categories[index - extra];
          final selected = list
              ? _myListOnly.contains(_kind)
              : !_myListOnly.contains(_kind) &&
                    _category[_kind] == category?.id;
          return TvFocusCard(
            key: ValueKey(
              '${_kind.name}:${list ? 'list' : category?.id ?? 'all'}',
            ),
            selected: selected,
            transparent: true,
            borderRadius: 30,
            onPressed: list ? _showMyList : () => _showCategory(category?.id),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              child: Text(
                list ? 'My List' : category?.name ?? 'All',
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
  }

  List<Widget> _catalogSlivers(
    List<MediaItem> items,
    bool isTv,
    double width,
    double margin,
    bool browsing,
  ) {
    final columns =
        (width / ((isTv ? 170 : 150) * (_preferences.largePosters ? 1.25 : 1)))
            .floor()
            .clamp(2, 8);
    final newest = sortMediaItems(items, CatalogSort.recentlyAdded);
    final dated = newest
        .where((item) => item.addedAt != null)
        .take(20)
        .toList(growable: false);
    final categories = _orderedCategories(
      ref.watch(categoriesProvider(_kind)).asData?.value ?? <Category>[],
    );
    final grouped = <String, List<MediaItem>>{};
    for (final item in items) {
      final group = grouped.putIfAbsent(item.categoryId, () => <MediaItem>[]);
      if (group.length < 20) group.add(item);
    }
    final rails = categories
        .where((category) => grouped[category.id]?.isNotEmpty == true)
        .take(5)
        .toList(growable: false);
    return [
      if (browsing)
        SliverPadding(
          padding: EdgeInsets.fromLTRB(margin, 0, margin, 20),
          sliver: SliverToBoxAdapter(
            child: _catalogHero(
              items
                      .where(
                        (item) => item.id == _preferences.lastItems[_kind.name],
                      )
                      .firstOrNull ??
                  newest.first,
              isTv,
              width,
            ),
          ),
        ),
      SliverPadding(
        padding: EdgeInsets.fromLTRB(margin, 0, margin, browsing ? 12 : 24),
        sliver: SliverToBoxAdapter(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _kind == MediaKind.movie
                          ? 'Browse movies'
                          : 'Browse series',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontSize: 22,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${items.length} titles in your library',
                      style: const TextStyle(
                        color: AppColors.subdued,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              TextButton.icon(
                onPressed: browsing
                    ? () => _showAll()
                    : () {
                        setState(() {
                          _browseAll.remove(_kind);
                          _myListOnly.remove(_kind);
                          _category[_kind] = null;
                          _search.clear();
                        });
                        _scrollToTop();
                      },
                icon: Icon(
                  browsing ? Icons.arrow_forward_rounded : Icons.home_outlined,
                  size: 17,
                ),
                label: Text(browsing ? 'Browse all' : 'Home'),
              ),
            ],
          ),
        ),
      ),
      if (browsing)
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: margin),
          sliver: SliverToBoxAdapter(child: _savedShelves(items, isTv)),
        ),
      if (_kind == MediaKind.movie && browsing)
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: margin),
          sliver: SliverToBoxAdapter(
            child: MovieRecommendations(
              catalog: items,
              onOpen: (item) => _open(item),
            ),
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
                        .where(
                          (entry) =>
                              entry.item.kind == MediaKind.movie &&
                              items.any((item) => item.id == entry.item.id),
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
      if (browsing)
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: margin),
          sliver: SliverToBoxAdapter(
            child: dated.isNotEmpty
                ? _posterRail(
                    _kind == MediaKind.movie
                        ? 'Recently added movies'
                        : 'Recently added series',
                    dated,
                    isTv,
                    onViewAll: () => _showAll(sort: CatalogSort.recentlyAdded),
                  )
                : Padding(
                    padding: const EdgeInsets.only(bottom: 30),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _sectionTitle(
                          _kind == MediaKind.movie
                              ? 'Recently added movies'
                              : 'Recently added series',
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          decoration: const BoxDecoration(
                            border: Border(
                              top: BorderSide(color: AppColors.border),
                              bottom: BorderSide(color: AppColors.border),
                            ),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.calendar_today_outlined,
                                size: 22,
                                color: AppColors.subdued,
                              ),
                              SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  'Your provider does not include added dates. Browse all titles or explore a category.',
                                  style: TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 12,
                                    height: 1.6,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      if (browsing)
        for (final category in rails)
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: margin),
            sliver: SliverToBoxAdapter(
              child: _posterRail(
                category.name,
                grouped[category.id]!,
                isTv,
                onViewAll: () => _showCategory(category.id),
              ),
            ),
          ),
      if (browsing)
        SliverPadding(
          padding: EdgeInsets.fromLTRB(margin, 8, margin, 8),
          sliver: SliverToBoxAdapter(
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _showAll(),
                icon: const Icon(Icons.grid_view_rounded, size: 18),
                label: Text(
                  _kind == MediaKind.movie
                      ? 'Browse all movies'
                      : 'Browse all series',
                ),
              ),
            ),
          ),
        ),
      if (!browsing)
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

  Widget _savedShelves(List<MediaItem> items, bool tv) {
    final saved = ref.watch(favoritesProvider).asData?.value ?? <MediaItem>[];
    final ids = saved
        .where((item) => item.kind == _kind)
        .map((item) => item.id)
        .toSet();
    final list = items.where((item) => ids.contains(item.id)).toList();
    final history = _kind == MediaKind.series
        ? ref.watch(seriesHistoryProvider).asData?.value ??
              <EpisodeWatchEntry>[]
        : <EpisodeWatchEntry>[];
    final seen = <String>{};
    final continuing = history
        .where((entry) => seen.add(entry.item.id))
        .where(
          (entry) =>
              entry.continueEpisode != null &&
              items.any((item) => item.id == entry.item.id),
        )
        .take(20)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (continuing.isNotEmpty) ...[
          _sectionTitle('Continue watching'),
          const SizedBox(height: 16),
          SizedBox(
            height: 242,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: continuing.length,
              separatorBuilder: (_, __) => const SizedBox(width: 16),
              itemBuilder: (context, index) {
                final entry = continuing[index];
                final episode = entry.continueEpisode!;
                return SizedBox(
                  width: tv ? 260 : 220,
                  child: TvFocusCard(
                    label: 'Continue ${entry.item.name}',
                    onPressed: () => _open(entry.item),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: 145,
                          child: Artwork(
                            url: entry.item.imageUrl,
                            title: entry.item.name,
                            fit: BoxFit.cover,
                          ),
                        ),
                        LinearProgressIndicator(
                          value: entry.canResume ? entry.progress : 0,
                          minHeight: 3,
                        ),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.item.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 7),
                              Text(
                                '${entry.canResume ? 'Resume' : 'Up next'} · S${episode.season} · E${episode.episodeNumber}',
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
          const SizedBox(height: 28),
        ],
        if (list.isNotEmpty)
          _posterRail('My List', list, tv, onViewAll: _showMyList),
      ],
    );
  }

  Widget _posterRail(
    String title,
    List<MediaItem> items,
    bool isTv, {
    required VoidCallback onViewAll,
  }) => MovieShelf(
    title: title,
    items: items,
    onOpen: (item) => _open(item),
    onViewAll: onViewAll,
  );

  Widget _catalogHero(MediaItem item, bool isTv, double width) =>
      FeatureBillboard(item: item, onPressed: () => _open(item));

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
        : channels
                  .where((item) => item.id == _preferences.lastChannel)
                  .firstOrNull ??
              channels.first;
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
    final showSaved =
        _search.text.trim().isEmpty &&
        _category[MediaKind.live] == null &&
        !_favoritesOnly;
    final available = {for (final item in channels) item.id: item};
    List<MediaItem> availableSaved(List<MediaItem> saved) => saved
        .where(
          (item) =>
              item.kind == MediaKind.live && available.containsKey(item.id),
        )
        .map((item) => available[item.id]!)
        .toList(growable: false);
    final favorites = showSaved
        ? sortMediaItems(
            availableSaved(
              ref.watch(favoritesProvider).asData?.value ?? <MediaItem>[],
            ),
            CatalogSort.titleAscending,
          )
        : <MediaItem>[];
    int rankFavorite(MediaItem item) {
      final index = _preferences.favoriteOrder.indexOf(
        AppSettings.mediaKey(item),
      );
      return index < 0 ? _preferences.favoriteOrder.length : index;
    }

    favorites.sort((a, b) => rankFavorite(a).compareTo(rankFavorite(b)));
    final recent = showSaved
        ? availableSaved(
            ref.watch(recentChannelsProvider).asData?.value ?? <MediaItem>[],
          )
        : <MediaItem>[];
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
      if (favorites.isNotEmpty || recent.isNotEmpty)
        SliverPadding(
          padding: EdgeInsets.fromLTRB(margin, 28, margin, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (favorites.isNotEmpty)
                  _channelRail('Favorite channels', favorites, channels, isTv),
                if (recent.isNotEmpty)
                  _channelRail(
                    'Recently viewed channels',
                    recent,
                    channels,
                    isTv,
                  ),
              ],
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

  Widget _channelRail(
    String title,
    List<MediaItem> items,
    List<MediaItem> channels,
    bool isTv,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(title, trailing: '${items.length}'),
        const SizedBox(height: 16),
        SizedBox(
          height: 98,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            cacheExtent: 600,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 13),
            itemBuilder: (context, index) {
              final item = items[index];
              return SizedBox(
                width: isTv ? 280 : 255,
                child: TvFocusCard(
                  borderRadius: 9,
                  label: 'Play ${item.name}',
                  onPressed: () {
                    setState(() => _channel = item);
                    _remember(item: item);
                    _open(item, channels: channels);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(15),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 48,
                          height: 45,
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
                            style: const TextStyle(
                              color: AppColors.text,
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ),
                        const SizedBox(width: 9),
                        const Icon(
                          Icons.play_arrow_rounded,
                          size: 22,
                          color: AppColors.accent,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );

  Widget _liveFeature(
    MediaItem item,
    List<MediaItem> channels,
    AsyncValue<List<EpgEntry>> epg,
    EpgEntry? programme,
    bool isTv,
  ) => LiveChannelPreview(
    key: _previewKey,
    item: item,
    programme: programme,
    onWatch: () => _open(item, channels: channels),
  );

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
      _remember(item: item);
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
          _favoriteButton(item),
        ],
      ),
    ),
  );

  Widget _favoriteButton(MediaItem item) {
    final favorite =
        ref
            .watch(favoritesProvider)
            .asData
            ?.value
            .any((entry) => entry.id == item.id && entry.kind == item.kind) ??
        false;
    return IconButton(
      onPressed: _savingFavorites.contains(item.id)
          ? null
          : () => _toggleFavorite(item),
      tooltip: favorite
          ? 'Remove ${item.name} from favorites'
          : 'Add ${item.name} to favorites',
      icon: Icon(
        favorite ? Icons.star_rounded : Icons.star_outline_rounded,
        size: 21,
        color: favorite ? AppColors.accent : AppColors.subdued,
      ),
    );
  }

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
}
