import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/design_system.dart';
import '../core/providers.dart';
import '../core/settings_controller.dart';
import '../data/app_settings.dart';
import '../data/models.dart';
import '../data/recommendations.dart';
import '../widgets/live_channel_preview.dart';
import '../widgets/parental_access.dart';
import '../widgets/status_view.dart';
import '../widgets/tv_controls.dart';
import '../widgets/tv_text_entry_dialog.dart';
import '../widgets/tv_reading_dialog.dart';
import '../widgets/tv_poster_browser.dart';
import '../widgets/tv_page_navigation.dart';
import '../widgets/tv_glass_theme.dart';
import '../widgets/tv_glass_hero.dart';
import '../widgets/tv_glass_guide.dart';
import '../widgets/tv_home_shelves.dart';
import 'app_updates_screen.dart';
import 'movie_detail_screen.dart';
import 'player_screen.dart';
import 'series_detail_screen.dart';
import 'settings_screen.dart';
import 'speed_test_screen.dart';
import 'tv_guide_screen.dart';

/// A dedicated television shell: no expanding sidebar or nested page/channel
/// scrolling. Each browsing column has a stable, explicit remote path.
class TvDashboardScreen extends ConsumerStatefulWidget {
  const TvDashboardScreen({super.key});
  @override
  ConsumerState<TvDashboardScreen> createState() => _TvDashboardScreenState();
}

class _TvDashboardScreenState extends ConsumerState<TvDashboardScreen> {
  final _categories = GlobalKey<TvRemoteListState>();
  final _guide = GlobalKey<TvGlassGuideState>();
  final _grid = GlobalKey<TvPosterBrowserState>();
  final _preview = GlobalKey<LiveChannelPreviewState>();
  final _watch = FocusNode(debugLabel: 'Watch now');
  final _options = FocusNode(debugLabel: 'Live options');
  final _hero = FocusNode(debugLabel: 'Featured title');
  final _searchFocus = FocusNode(debugLabel: 'Search');
  final _top = <String, FocusNode>{};
  final _category = <MediaKind, String?>{};
  String _section = 'home', _query = '', _liveFilter = 'all';
  MediaItem? _channel;
  CatalogSort _sort = CatalogSort.recentlyAdded;
  bool _ready = false, _opening = false, _catalog = false;
  int _programmeColumn = 0;
  Timer? _clock;
  Timer? _channelFocusTimer;
  AppSettings get _settings =>
      ref.read(settingsProvider).asData?.value ?? const AppSettings();
  MediaKind get _kind => _section == 'series'
      ? MediaKind.series
      : _section == 'movie' || _section == 'list'
      ? MediaKind.movie
      : MediaKind.live;
  FocusNode _nav(String id) =>
      _top.putIfAbsent(id, () => FocusNode(debugLabel: 'Navigation: $id'));
  @override
  void initState() {
    super.initState();
    _restore();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _restore() async {
    await ref.read(settingsProvider.notifier).ready;
    if (!mounted) return;
    final s = _settings;
    setState(() {
      _section =
          {
            'home',
            'live',
            'movie',
            'series',
            'list',
            'settings',
          }.contains(s.lastSection)
          ? s.lastSection
          : 'home';
      for (final k in MediaKind.values) {
        _category[k] = (s.lastCategories[k.name]?.isNotEmpty ?? false)
            ? s.lastCategories[k.name]
            : null;
      }
      _catalog = _category[_kind] != null;
      _ready = true;
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _channelFocusTimer?.cancel();
    _watch.dispose();
    _options.dispose();
    _hero.dispose();
    _searchFocus.dispose();
    for (final n in _top.values) {
      n.dispose();
    }
    super.dispose();
  }

  void _remember({MediaItem? item}) {
    unawaited(
      ref
          .read(settingsProvider.notifier)
          .update(
            (s) => s.patch({
              'lastSection': _section,
              'lastCategories': {
                ...s.lastCategories,
                _kind.name: _category[_kind] ?? '',
              },
              if (item != null)
                'lastItems': {...s.lastItems, item.kind.name: item.id},
              if (item?.kind == MediaKind.live) 'lastChannel': item!.id,
            }),
          ),
    );
  }

  void _sectionTo(String section) {
    if (_section == section) return;
    _channelFocusTimer?.cancel();
    unawaited(_preview.currentState?.stop() ?? Future<void>.value());
    setState(() {
      _section = section;
      _catalog = _category[_kind] != null;
      _query = '';
      if (section != 'live') _liveFilter = 'all';
    });
    _remember();
  }

  bool _enterPage() {
    if (_section == 'home' ||
        ((_section == 'movie' || _section == 'series') && !_catalog)) {
      _hero.requestFocus();
      return _hero.context != null;
    } else if (_section == 'list') {
      _grid.currentState?.focusFirst();
      return _grid.currentState != null;
    } else {
      _categories.currentState?.focusSelected();
      return _categories.currentState != null;
    }
  }

  KeyEventResult _topKey(String destination, KeyEvent event) {
    if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
        event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (destination != _section) {
        _sectionTo(destination);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _enterPage();
        });
        return KeyEventResult.handled;
      }
      return _enterPage() ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _toolbarKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _nav(_section).requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      return _enterPage() ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    return KeyEventResult.ignored;
  }

  bool _visible(MediaItem item) =>
      !_settings.hidden(item) &&
      (ref.read(parentalSessionProvider) || !_settings.locked(item));
  Future<void> _chooseCategory(String? id, {String filter = 'all'}) async {
    _channelFocusTimer?.cancel();
    if (id != null &&
        _settings.lockedCategories.contains(
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
    await _preview.currentState?.stop();
    if (!mounted) return;
    setState(() {
      _category[_kind] = id;
      _liveFilter = filter;
      _channel = null;
      _programmeColumn = 0;
    });
    _remember();
  }

  Future<void> _open(
    MediaItem item, {
    List<MediaItem> channels = const [],
  }) async {
    if (_opening) return;
    _opening = true;
    try {
      if (!await allowMedia(context, ref, item) || !mounted) return;
      await _preview.currentState?.stop();
      if (!mounted) return;
      _remember(item: item);
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => switch (item.kind) {
            MediaKind.live => PlayerScreen(item: item, channels: channels),
            MediaKind.movie => MovieDetailScreen(item: item),
            MediaKind.series => SeriesDetailScreen(item: item),
          },
        ),
      );
      if (mounted) {
        ref.invalidate(historyProvider);
        ref.invalidate(seriesHistoryProvider);
        ref.invalidate(recentChannelsProvider);
      }
    } finally {
      _opening = false;
    }
  }

  Future<void> _favorite(MediaItem item) async {
    final account = ref.read(sessionProvider)?.accountId;
    if (account == null) return;
    try {
      final saved =
          ref.read(favoritesProvider).asData?.value.any((e) => e == item) ??
          false;
      await ref.read(storeProvider).setFavorite(account, item, !saved);
      if (mounted) ref.invalidate(favoritesProvider);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save this channel. Please retry.'),
          ),
        );
      }
    }
  }

  Future<void> _search() async {
    final section = switch (_section) {
      'live' => 'live',
      'series' => 'series',
      _ => 'movie',
    };
    final controller = TextEditingController(text: _query);
    final route = DialogRoute<bool>(
      context: context,
      builder: (_) => TvTextEntryDialog(
        controller: controller,
        label:
            'Search ${section == 'live'
                ? 'channels'
                : section == 'series'
                ? 'series'
                : 'movies'}',
      ),
    );
    final committed = await Navigator.of(context).push(route);
    await route.completed;
    final result = committed == true ? controller.text : null;
    controller.dispose();
    if (result != null && mounted) {
      setState(() {
        _section = section;
        _catalog = true;
        _query = result.trim();
      });
      _remember();
    }
  }

  Future<void> _sortMenu() async {
    final choice = await showTvMenu(context, 'Sort titles', {
      CatalogSort.recentlyAdded.name: 'Recently added',
      CatalogSort.titleAscending.name: 'Title · A to Z',
      CatalogSort.titleDescending.name: 'Title · Z to A',
    });
    final result = CatalogSort.values
        .where((sort) => sort.name == choice)
        .firstOrNull;
    if (result != null && mounted) {
      setState(() {
        _sort = result;
        _catalog = true;
      });
    }
  }

  void _refresh() {
    ref.invalidate(itemsProvider(_kind));
    ref.invalidate(categoriesProvider(_kind));
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    ref.watch(parentalSessionProvider);
    if (!_ready || settings.isLoading) {
      return const Scaffold(
        body: StatusView(title: 'Preparing your TV', loading: true),
      );
    }
    if (settings.hasError) {
      return Scaffold(
        body: StatusView(
          title: 'Preferences unavailable',
          onRetry: () => ref.read(settingsProvider.notifier).reload(),
        ),
      );
    }
    final account = ref.watch(sessionProvider);
    final info = account == null ? null : AccountInfo(account);
    return TvGlassScope(
      child: Theme(
        data: TvGlass.theme(Theme.of(context)),
        child: PopScope(
          canPop: _section == 'home',
          onPopInvokedWithResult: (popped, result) {
            if (!popped) {
              if (_catalog && (_section == 'movie' || _section == 'series')) {
                setState(() {
                  _catalog = false;
                  _category[_kind] = null;
                  _query = '';
                });
                _remember();
              } else {
                _sectionTo('home');
              }
              _nav(_section).requestFocus();
            }
          },
          child: Scaffold(
            backgroundColor: TvGlass.canvas,
            body: SafeArea(
              child: LayoutBuilder(
                builder: (context, box) {
                  // Match the approved 1024-wide artwork at 540p, 720p and 1080p.
                  final height = box.maxHeight * 1024 / box.maxWidth;
                  return SizedBox.expand(
                    child: FittedBox(
                      fit: BoxFit.contain,
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                        width: 1024,
                        height: height,
                        child: TvGlassBackdrop(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _glassHeader(),
                              Expanded(
                                child: switch (_section) {
                                  'home' => _home(),
                                  'settings' => Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 26,
                                    ),
                                    child: _settingsHome(info),
                                  ),
                                  'list' => Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 26,
                                    ),
                                    child: _saved(),
                                  ),
                                  _ => _library(true),
                                },
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 26,
                                ),
                                child: SizedBox(
                                  height: 38,
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          info?.expiring == true
                                              ? 'Account ${info!.remainingDays! <= 0 ? 'expired' : 'expires in ${info.remainingDays} days'} · Open Settings'
                                              : 'D-pad  Browse     OK  Details / watch     Back  Home',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: info?.expiring == true
                                                ? AppColors.danger
                                                : TvGlass.muted,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        guideClock(DateTime.now()),
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: TvGlass.muted,
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
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _glassHeader() => Container(
    height: 64,
    padding: const EdgeInsets.symmetric(horizontal: 26),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Color(0x12FFFFFF))),
    ),
    child: Row(
      children: [
        const SizedBox(
          width: 120,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: StreamlineMark(size: 25, wordmark: true),
          ),
        ),
        const SizedBox(width: 28),
        for (final entry in [
          ('home', 'Home'),
          ('live', 'Live TV'),
          ('movie', 'Movies'),
          ('series', 'Series'),
          ('list', 'My List'),
        ])
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: TvControl(
              style: TvControlStyle.navigation,
              focusNode: _nav(entry.$1),
              autofocus: _section == entry.$1,
              selected: _section == entry.$1,
              label: entry.$2,
              onKeyEvent: (_, event) => _topKey(entry.$1, event),
              onPressed: () => _sectionTo(entry.$1),
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 12),
              child: Text(entry.$2, style: const TextStyle(fontSize: 13)),
            ),
          ),
        const Spacer(),
        TvControl(
          style: TvControlStyle.navigation,
          focusNode: _searchFocus,
          onKeyEvent: _toolbarKey,
          label: 'Search',
          onPressed: _search,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: const Text('Search', style: TextStyle(fontSize: 11)),
        ),
        const SizedBox(width: 12),
        TvControl(
          style: TvControlStyle.navigation,
          focusNode: _nav('settings'),
          autofocus: _section == 'settings',
          selected: _section == 'settings',
          onKeyEvent: (_, event) => _topKey('settings', event),
          label: 'Settings',
          onPressed: () => _sectionTo('settings'),
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 12),
          child: const Text('Settings', style: TextStyle(fontSize: 11)),
        ),
      ],
    ),
  );

  Widget _heading(
    String title,
    String subtitle, {
    List<Widget> actions = const [],
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 25,
                  fontFamily: 'Glass Sans',
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subtitle.isNotEmpty)
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: TvGlass.muted, fontSize: 11),
                ),
            ],
          ),
        ),
        ...actions,
      ],
    ),
  );
  Widget _action(
    String label,
    IconData icon,
    VoidCallback action, {
    FocusNode? node,
  }) => Padding(
    padding: const EdgeInsets.only(left: 9),
    child: TvControl(
      focusNode: node,
      onKeyEvent: _toolbarKey,
      label: label,
      onPressed: action,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      ),
    ),
  );
  Widget _panel(String title, Widget child, {String? count}) => Container(
    padding: EdgeInsets.zero,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 5, 0, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1.2,
                    color: TvGlass.muted,
                  ),
                ),
              ),
              if (count != null)
                Text(
                  count,
                  style: const TextStyle(fontSize: 10, color: TvGlass.muted),
                ),
            ],
          ),
        ),
        Expanded(child: child),
      ],
    ),
  );
  Widget _state(String message, {VoidCallback? retry}) =>
      StatusView(title: message, onRetry: retry);

  Widget _library(bool compact) {
    final state = ref.watch(itemsProvider(_kind));
    final categoryState = ref.watch(categoriesProvider(_kind));
    final favorites =
        ref.watch(favoritesProvider).asData?.value ?? <MediaItem>[];
    final ids = favorites.map(AppKey.item).toSet();
    final recent =
        ref.watch(recentChannelsProvider).asData?.value ?? <MediaItem>[];
    final recentIds = recent.map((e) => e.id).toSet();
    final supplied = (categoryState.asData?.value ?? <Category>[])
        .where(
          (c) => !_settings.hiddenCategories.contains(
            AppSettings.categoryKey(_kind, c.id),
          ),
        )
        .toList();
    final order = _settings.categoryOrder[_kind.name] ?? <String>[];
    final providerOrder = {
      for (var i = 0; i < supplied.length; i++) supplied[i].id: i,
    };
    supplied.sort((a, b) {
      int rank(Category c) {
        final i = order.indexOf(c.id);
        return i < 0 ? order.length : i;
      }

      final byPreference = rank(a).compareTo(rank(b));
      return byPreference != 0
          ? byPreference
          : providerOrder[a.id]!.compareTo(providerOrder[b.id]!);
    });
    final all = (state.asData?.value ?? <MediaItem>[]).where(_visible).toList();
    final matching = all
        .where(
          (e) =>
              (_category[_kind] == null || e.categoryId == _category[_kind]) &&
              e.name.toLowerCase().contains(_query.toLowerCase()) &&
              (_kind != MediaKind.live ||
                  _liveFilter == 'all' ||
                  _liveFilter == 'favorites' && ids.contains(AppKey.item(e)) ||
                  _liveFilter == 'recent' && recentIds.contains(e.id)),
        )
        .toList();
    if (_kind != MediaKind.live) {
      matching.setAll(0, sortMediaItems(matching, _sort));
    }
    final categories = <TvListEntry>[
      TvListEntry(
        id: 'all',
        title: _kind == MediaKind.live ? 'All channels' : 'All',
        selected: _category[_kind] == null && _liveFilter == 'all',
        trailing: '${all.length}',
        onPressed: () => _chooseCategory(null),
      ),
      if (_kind == MediaKind.live) ...[
        TvListEntry(
          id: 'favorites',
          title: 'Favorites',
          selected: _liveFilter == 'favorites',
          trailing:
              '${favorites.where((e) => e.kind == MediaKind.live).length}',
          onPressed: () => _chooseCategory(null, filter: 'favorites'),
        ),
        TvListEntry(
          id: 'recent',
          title: 'Recently viewed',
          selected: _liveFilter == 'recent',
          trailing: '${recent.length}',
          onPressed: () => _chooseCategory(null, filter: 'recent'),
        ),
      ],
      for (final c in supplied)
        TvListEntry(
          id: c.id,
          title: c.name,
          selected: _category[_kind] == c.id,
          leading:
              _settings.lockedCategories.contains(
                AppSettings.categoryKey(_kind, c.id),
              )
              ? const Icon(Icons.lock_outline, size: 17)
              : null,
          onPressed: () => _chooseCategory(c.id),
        ),
    ];
    final filterName =
        supplied.where((c) => c.id == _category[_kind]).firstOrNull?.name ??
        (_liveFilter == 'favorites'
            ? 'Favorites'
            : _liveFilter == 'recent'
            ? 'Recently viewed'
            : 'All categories');
    if (_kind == MediaKind.live) {
      return _glassLiveLibrary(state, categoryState, categories, matching);
    }
    if (!_catalog && _query.isEmpty) {
      if (state.isLoading) {
        return const StatusView(title: 'Loading your library', loading: true);
      }
      if (state.hasError) return _state('Library unavailable', retry: _refresh);
      return _cinemaLibrary(all, supplied);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 14, 26, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading(
            _kind == MediaKind.live
                ? 'Live TV'
                : _kind == MediaKind.movie
                ? 'Movies'
                : 'Series',
            _query.isEmpty
                ? '$filterName · ${matching.length} ${_kind == MediaKind.live ? 'channels' : 'titles'}'
                : 'Search: $_query · ${matching.length} results',
            actions: [
              if (_kind == MediaKind.live)
                _action(
                  'TV guide',
                  Icons.calendar_view_week,
                  () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const TvGuideScreen(),
                    ),
                  ),
                )
              else
                _action(
                  switch (_sort) {
                    CatalogSort.recentlyAdded => 'Newest',
                    CatalogSort.titleAscending => 'A–Z',
                    CatalogSort.titleDescending => 'Z–A',
                  },
                  Icons.sort,
                  _sortMenu,
                ),
              if (!compact) _action('Refresh', Icons.refresh, _refresh),
            ],
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 136,
                  child: _panel(
                    'Categories',
                    categoryState.hasError
                        ? _state(
                            'Unavailable',
                            retry: () =>
                                ref.invalidate(categoriesProvider(_kind)),
                          )
                        : TvRemoteList(
                            key: _categories,
                            label: 'Category',
                            entries: categories,
                            extent: TvGlass.rowHeight,
                            dense: true,
                            onLeft: () => _nav(_section).requestFocus(),
                            onTop: () => _nav(_section).requestFocus(),
                            onRight: () {
                              if (_kind == MediaKind.live) {
                                _guide.currentState?.focusSelected();
                              } else {
                                _grid.currentState?.focusFirst();
                              }
                            },
                          ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: state.isLoading
                      ? const StatusView(
                          title: 'Loading your library',
                          loading: true,
                        )
                      : state.hasError
                      ? _state('Library unavailable', retry: _refresh)
                      : matching.isEmpty
                      ? _state('No matches found')
                      : TvPosterBrowser(
                          key: _grid,
                          largePosters: _settings.largePosters,
                          items: matching,
                          onOpen: _open,
                          onLeft: () => _categories.currentState?.focusSelected(
                            remember: true,
                          ),
                          onTop: _searchFocus.requestFocus,
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _glassLiveLibrary(
    AsyncValue<List<MediaItem>> state,
    AsyncValue<List<Category>> categoryState,
    List<TvListEntry> categories,
    List<MediaItem> channels,
  ) {
    final selected =
        channels.where((e) => e.id == _channel?.id).firstOrNull ??
        channels.where((e) => e.id == _settings.lastChannel).firstOrNull ??
        channels.firstOrNull;
    final epg = selected == null ? null : ref.watch(epgProvider(selected.id));
    final slots = glassGuideSlots(epg?.asData?.value ?? [], DateTime.now());
    final entry = slots[_programmeColumn];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stack(
          children: [
            TvGlassHero(
              title: entry?.title ?? selected?.name ?? 'Live TV',
              eyebrow: selected == null
                  ? 'Live TV'
                  : 'Live TV / ${selected.name}',
              imageUrl: selected?.imageUrl ?? '',
              metadata: entry == null
                  ? '${channels.length} channels · $_liveFilter'
                  : '${_programmeColumn == 0 ? 'LIVE' : 'UPCOMING'}  ${guideClock(entry.start)} – ${guideClock(entry.end)}',
              description: entry?.description.isNotEmpty == true
                  ? entry!.description
                  : epg?.isLoading == true
                  ? 'Loading programme information…'
                  : 'No programme guide available',
            ),
            if (selected != null)
              Positioned(
                right: 26,
                bottom: 13,
                child: Focus(
                  canRequestFocus: false,
                  skipTraversal: true,
                  onKeyEvent: (_, event) {
                    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
                      return KeyEventResult.ignored;
                    }
                    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                      if (_watch.hasFocus) {
                        _options.requestFocus();
                      } else {
                        _guide.currentState?.focusSelected(remember: true);
                      }
                      return KeyEventResult.handled;
                    }
                    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                      if (_options.hasFocus) {
                        _watch.requestFocus();
                      }
                      return KeyEventResult.handled;
                    }
                    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                      _guide.currentState?.focusSelected(remember: true);
                      return KeyEventResult.handled;
                    }
                    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                      _nav('live').requestFocus();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TvControl(
                        focusNode: _options,
                        onPressed: () => _liveOptions(selected, channels),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        child: const Text(
                          'Options',
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
                      const SizedBox(width: 10),
                      TvControl(
                        style: TvControlStyle.primary,
                        focusNode: _watch,
                        onPressed: () => _open(selected, channels: channels),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 13,
                          vertical: 8,
                        ),
                        child: const Text(
                          'Watch now',
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(26, 4, 26, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 136,
                  padding: const EdgeInsets.only(right: 14),
                  decoration: const BoxDecoration(
                    border: Border(right: BorderSide(color: Color(0x12FFFFFF))),
                  ),
                  child: _panel(
                    'CATEGORIES',
                    categoryState.hasError
                        ? _state(
                            'Unavailable',
                            retry: () => ref.invalidate(
                              categoriesProvider(MediaKind.live),
                            ),
                          )
                        : TvRemoteList(
                            key: _categories,
                            label: 'Category',
                            dense: true,
                            entries: categories,
                            extent: TvGlass.rowHeight,
                            onLeft: () => _nav('live').requestFocus(),
                            onTop: () => _nav('live').requestFocus(),
                            onRight: () => _guide.currentState?.focusSelected(),
                          ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: state.isLoading
                      ? const StatusView(
                          title: 'Loading channels',
                          loading: true,
                        )
                      : state.hasError
                      ? _state('Channels unavailable', retry: _refresh)
                      : selected == null
                      ? _state('No matches found')
                      : TvGlassGuide(
                          key: _guide,
                          channels: channels,
                          selectedId: selected.id,
                          onLeft: () => _categories.currentState?.focusSelected(
                            remember: true,
                          ),
                          onRight: _options.requestFocus,
                          onTop: _searchFocus.requestFocus,
                          onOpen: (item) => _open(item, channels: channels),
                          onProgramme: (item, programme) =>
                              _programmeDetails(item, programme, channels),
                          onFocused: (item, column) {
                            _channelFocusTimer?.cancel();
                            _channelFocusTimer = Timer(
                              const Duration(milliseconds: 120),
                              () {
                                if (mounted && _section == 'live') {
                                  setState(() {
                                    _channel = item;
                                    _programmeColumn = column;
                                  });
                                }
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _liveOptions(MediaItem item, List<MediaItem> channels) async {
    final favorite =
        ref.read(favoritesProvider).asData?.value.contains(item) ?? false;
    final choice = await showTvMenu(context, item.name, {
      '0': 'Preview',
      '1': favorite ? 'Remove favourite' : 'Save favourite',
      '2': 'Full TV guide',
      '3': 'Refresh channels',
    });
    final result = int.tryParse(choice ?? '');
    if (!mounted || result == null) return;
    _options.requestFocus();
    switch (result) {
      case 0:
        await _livePreview(item, channels);
      case 1:
        await _favorite(item);
      case 2:
        await Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => const TvGuideScreen()),
        );
      case 3:
        _refresh();
    }
  }

  Future<void> _livePreview(MediaItem item, List<MediaItem> channels) =>
      showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog(
          child: SizedBox(
            width: 580,
            height: 320,
            child: LiveChannelPreview(
              key: _preview,
              item: item,
              programme: null,
              onWatch: () {
                Navigator.pop(dialogContext);
                _open(item, channels: channels);
              },
            ),
          ),
        ),
      );

  Future<void> _programmeDetails(
    MediaItem item,
    EpgEntry entry,
    List<MediaItem> channels,
  ) async {
    final watch = await showTvReadingDialog(
      context,
      entry.title,
      Text(
        '${guideClock(entry.start)} – ${guideClock(entry.end)}\n\n${entry.description.isEmpty ? 'No description supplied by your provider.' : entry.description}',
      ),
      actionLabel: 'Watch live channel',
    );
    if (watch == true && mounted) await _open(item, channels: channels);
  }

  Widget _rail(
    String title,
    List<MediaItem> items, {
    Map<String, double> progress = const {},
    bool primary = false,
  }) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 16, 26, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 128,
            child: TvPosterBrowser(
              key: primary ? _grid : null,
              largePosters: _settings.largePosters,
              items: items.take(24).toList(),
              horizontal: true,
              progress: progress,
              onOpen: _open,
              onLeft: () => _nav(_section).requestFocus(),
              onTop: _hero.requestFocus,
            ),
          ),
        ],
      ),
    );
  }

  Widget _home() {
    final moviesState = ref.watch(itemsProvider(MediaKind.movie));
    final movies = sortMediaItems(
      (moviesState.asData?.value ?? []).where(_visible).toList(),
      CatalogSort.recentlyAdded,
    );
    final series =
        (ref.watch(itemsProvider(MediaKind.series)).asData?.value ?? [])
            .where(_visible)
            .toList();
    final live = (ref.watch(itemsProvider(MediaKind.live)).asData?.value ?? [])
        .where(_visible)
        .toList();
    final available = {
      for (final item in [...movies, ...series, ...live])
        AppKey.item(item): item,
    };
    final history = (ref.watch(historyProvider).asData?.value ?? [])
        .where((e) => available.containsKey(AppKey.item(e.item)))
        .toList();
    final continuing = history.where((e) => e.canResume).toList();
    final episodeHistory =
        (ref.watch(seriesHistoryProvider).asData?.value ??
                <EpisodeWatchEntry>[])
            .where(
              (e) =>
                  e.continueEpisode != null &&
                  available.containsKey(AppKey.item(e.item)),
            )
            .toList();
    final seriesSeen = <String>{};
    final continuingSeries = episodeHistory
        .where((e) => seriesSeen.add(e.item.id))
        .toList();
    final featured = movies.firstOrNull ?? series.firstOrNull;
    final detail = featured?.kind == MediaKind.movie
        ? ref.watch(movieDetailProvider(featured!)).asData?.value
        : null;
    final recommendations = _settings.recommendations
        ? recommendMovies(movies, history)
        : <RecommendationShelf>[];
    final shelves = <TvHomeShelf>[
      if (continuing.isNotEmpty)
        TvHomeShelf(
          'Continue watching',
          continuing.map((e) => available[AppKey.item(e.item)]!).toList(),
          progress: {
            for (final e in continuing) AppKey.item(e.item): e.progress,
          },
        ),
      if (continuingSeries.isNotEmpty)
        TvHomeShelf(
          'Continue watching series',
          continuingSeries.map((e) => available[AppKey.item(e.item)]!).toList(),
          progress: {
            for (final e in continuingSeries)
              if (e.canResume) AppKey.item(e.item): e.progress,
          },
        ),
      for (final recommendation in recommendations.take(2))
        TvHomeShelf(recommendation.title, recommendation.items),
      TvHomeShelf(
        movies.any((e) => e.addedAt != null)
            ? 'Recently added movies'
            : 'Movies from your provider',
        movies,
      ),
      TvHomeShelf(
        'Recently watched',
        history.map((e) => available[AppKey.item(e.item)]!).toList(),
      ),
      TvHomeShelf('Series to discover', series),
    ];
    return TvHomeShelves(
      shelves: shelves,
      hero: (height) =>
          _featuredHero(featured, detail, 'Selected for you', height: height),
      heroFocus: _hero,
      largePosters: _settings.largePosters,
      onTop: () => _nav('home').requestFocus(),
      onOpen: _open,
      emptyMessage: moviesState.hasError
          ? 'Movies are unavailable. Open Movies to retry, or browse Live TV.'
          : moviesState.isLoading
          ? 'Loading your library…'
          : 'No films or series are available. Browse Live TV from the navigation above.',
    );
  }

  Widget _featuredHero(
    MediaItem? item,
    MovieDetail? detail,
    String eyebrow, {
    double height = 220,
  }) {
    if (item == null) {
      return SizedBox(
        height: height,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 26,
            vertical: height <= 160 ? 16 : 26,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Welcome home',
                style: TextStyle(
                  fontSize: height <= 160 ? 28 : 36,
                  height: 1.1,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
              TvControl(
                focusNode: _hero,
                onPressed: () {
                  _sectionTo('live');
                  _nav('live').requestFocus();
                },
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 8,
                ),
                child: const Text(
                  'Browse Live TV',
                  style: TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final resume = (ref.watch(historyProvider).asData?.value ?? <WatchEntry>[])
        .any((e) => e.item == item && e.canResume);
    return Stack(
      children: [
        TvGlassHero(
          title: item.name,
          eyebrow: eyebrow,
          imageUrl: detail?.backdropUrl.isNotEmpty == true
              ? detail!.backdropUrl
              : item.imageUrl,
          cinema: true,
          height: height,
          metadata: [
            if (detail?.year.isNotEmpty == true) detail!.year,
            if (detail?.genre.isNotEmpty == true) detail!.genre,
            if (item.rating.isNotEmpty) 'Rating ${item.rating}',
          ].join(' · '),
          description: detail?.plot ?? '',
          action: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TvControl(
                style: TvControlStyle.primary,
                focusNode: _hero,
                onPressed: () => _open(item),
                padding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.play_arrow, size: 13),
                    const SizedBox(width: 6),
                    Text(
                      resume ? 'Resume watching' : 'View details',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_section == 'movie' || _section == 'series')
          Positioned(
            top: 13,
            right: 26,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _action(
                  switch (_sort) {
                    CatalogSort.recentlyAdded => 'Newest',
                    CatalogSort.titleAscending => 'A–Z',
                    CatalogSort.titleDescending => 'Z–A',
                  },
                  Icons.sort,
                  _sortMenu,
                ),
                _action('Browse all', Icons.grid_view, _browseCatalog),
              ],
            ),
          ),
      ],
    );
  }

  void _browseCatalog() {
    setState(() => _catalog = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _categories.currentState?.focusSelected();
    });
  }

  Widget _cinemaLibrary(List<MediaItem> all, List<Category> categories) {
    final items = sortMediaItems(all, _sort);
    final featured = items.firstOrNull;
    final detail = featured?.kind == MediaKind.movie
        ? ref.watch(movieDetailProvider(featured!)).asData?.value
        : null;
    final history = (ref.watch(historyProvider).asData?.value ?? <WatchEntry>[])
        .where((e) => all.contains(e.item))
        .toList();
    final continuing = history.where((e) => e.canResume).toList();
    final recent = items.where((e) => e.addedAt != null).toList();
    final recommendations =
        _kind == MediaKind.movie && _settings.recommendations
        ? recommendMovies(items, history)
        : <RecommendationShelf>[];
    final name = _kind == MediaKind.series ? 'Series' : 'Movies';
    return SingleChildScrollView(
      key: PageStorageKey('tv-landing-$_section'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _featuredHero(featured, detail, '$name / Recently added'),
          _rail(
            recent.isNotEmpty ? 'Recently added' : '$name from your provider',
            recent.isNotEmpty ? recent : items,
            primary: true,
          ),
          for (final recommendation in recommendations.take(2))
            _rail(recommendation.title, recommendation.items),
          if (continuing.isNotEmpty)
            _rail(
              'Continue watching',
              continuing.map((e) => e.item).toList(),
              progress: {
                for (final e in continuing) AppKey.item(e.item): e.progress,
              },
            ),
          if (history.isNotEmpty)
            _rail('Recently watched', history.map((e) => e.item).toList()),
          if (categories.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(26, 16, 26, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Explore genres',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      for (final category in categories.take(6))
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: TvControl(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 9,
                              ),
                              onPressed: () async {
                                await _chooseCategory(category.id);
                                if (mounted) _browseCatalog();
                              },
                              child: Text(
                                category.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _saved() {
    final saved = ref.watch(favoritesProvider);
    final movies = ref.watch(itemsProvider(MediaKind.movie));
    final series = ref.watch(itemsProvider(MediaKind.series));
    final all = [
      ...movies.asData?.value ?? <MediaItem>[],
      ...series.asData?.value ?? <MediaItem>[],
    ];
    final available = {
      for (final item in all.where(_visible)) AppKey.item(item): item,
    };
    final items = (saved.asData?.value ?? [])
        .where((e) => available.containsKey(AppKey.item(e)))
        .map((e) => available[AppKey.item(e)]!)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading('My List', 'Your saved movies and series'),
        Expanded(
          child: saved.isLoading || movies.isLoading || series.isLoading
              ? const StatusView(title: 'Loading My List', loading: true)
              : saved.hasError || movies.hasError || series.hasError
              ? _state(
                  'My List unavailable',
                  retry: () {
                    ref.invalidate(favoritesProvider);
                    ref.invalidate(itemsProvider(MediaKind.movie));
                    ref.invalidate(itemsProvider(MediaKind.series));
                  },
                )
              : items.isEmpty
              ? _state('Save movies and series from their detail pages')
              : TvPosterBrowser(
                  key: _grid,
                  largePosters: _settings.largePosters,
                  items: items,
                  onOpen: _open,
                  onLeft: () => _nav('list').requestFocus(),
                  onTop: () => _nav('list').requestFocus(),
                ),
        ),
      ],
    );
  }

  Widget _settingsHome(AccountInfo? info) {
    final pin = ref.watch(pinConfiguredProvider);
    if (pin.isLoading) {
      return const StatusView(title: 'Checking protection', loading: true);
    }
    if (pin.hasError) {
      return _state(
        'Protection unavailable',
        retry: () => ref.invalidate(pinConfiguredProvider),
      );
    }
    if (pin.asData?.value == true && !ref.watch(parentalSessionProvider)) {
      return _state(
        'Settings are protected',
        retry: () => requestParentalAccess(context, ref),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _heading('Settings', 'Make your TV experience yours'),
              Expanded(
                child: TvRemoteList(
                  key: _categories,
                  label: 'Settings',
                  extent: 58,
                  dense: true,
                  onTop: () => _nav('settings').requestFocus(),
                  onLeft: () => _nav('settings').requestFocus(),
                  onRight: _watch.requestFocus,
                  entries: [
                    for (final e in [
                      (
                        0,
                        'Playback',
                        'Player, picture and controls',
                        Icons.play_circle_outline,
                      ),
                      (
                        1,
                        'Audio & subtitles',
                        'Language, sound and captions',
                        Icons.graphic_eq,
                      ),
                      (
                        2,
                        'Appearance',
                        'Theme and accessibility',
                        Icons.palette_outlined,
                      ),
                      (
                        3,
                        'Library & parental controls',
                        'Categories, favorites and PIN',
                        Icons.shield_outlined,
                      ),
                      (
                        4,
                        'Your account',
                        'Status, expiry and connections',
                        Icons.account_circle_outlined,
                      ),
                      (
                        5,
                        'App & maintenance',
                        'Updates, diagnosis and storage',
                        Icons.settings_outlined,
                      ),
                    ])
                      TvListEntry(
                        id: '${e.$1}',
                        title: e.$2,
                        subtitle: e.$3,
                        leading: Icon(e.$4),
                        selected: e.$1 == 0,
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => SettingsScreen(groupIndex: e.$1),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 24),
        Expanded(
          flex: 4,
          child: TvPageNavigation(
            enabled: true,
            autofocus: false,
            onLeft: () =>
                _categories.currentState?.focusSelected(remember: true),
            onTop: () => _nav('settings').requestFocus(),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: TvGlass.panel,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.account_circle_outlined,
                    size: 30,
                    color: TvGlass.accent,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    ref.watch(sessionProvider)?.credentials.username ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 19),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'SUBSCRIPTION',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.3,
                      color: TvGlass.muted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    info?.status ?? 'Not supplied',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 17),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'EXPIRY',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.3,
                      color: TvGlass.muted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    info?.expiryLabel ?? 'Not supplied',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 17),
                  ),
                  const Spacer(),
                  TvControl(
                    focusNode: _watch,
                    reveal: false,
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const SpeedTestScreen(),
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.speed, size: 19),
                        SizedBox(width: 10),
                        Text('Speed test', style: TextStyle(fontSize: 14)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  TvControl(
                    reveal: false,
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const AppUpdatesScreen(),
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.system_update, size: 19),
                        SizedBox(width: 10),
                        Text('App updates', style: TextStyle(fontSize: 14)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
