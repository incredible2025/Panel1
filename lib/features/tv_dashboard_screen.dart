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
import '../widgets/media_card.dart';
import '../widgets/parental_access.dart';
import '../widgets/status_view.dart';
import '../widgets/tv_controls.dart';
import '../widgets/tv_poster_browser.dart';
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
  final _channels = GlobalKey<TvRemoteListState>();
  final _grid = GlobalKey<TvPosterBrowserState>();
  final _preview = GlobalKey<LiveChannelPreviewState>();
  final _watch = FocusNode(debugLabel: 'Watch now');
  final _hero = FocusNode(debugLabel: 'Featured title');
  final _top = <String, FocusNode>{};
  final _category = <MediaKind, String?>{};
  String _section = 'home', _query = '', _liveFilter = 'all';
  MediaItem? _channel, _pendingChannel;
  CatalogSort _sort = CatalogSort.recentlyAdded;
  bool _ready = false, _opening = false;
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
      _ready = true;
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _channelFocusTimer?.cancel();
    _watch.dispose();
    _hero.dispose();
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
      _query = '';
      if (section != 'live') _liveFilter = 'all';
    });
    _remember();
  }

  bool _enterPage() {
    if (_section == 'home') {
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

  KeyEventResult _topKey(FocusNode node, KeyEvent event) {
    if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
        event.logicalKey == LogicalKeyboardKey.arrowDown) {
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
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _TvSearchDialog(
        title:
            'Search ${_section == 'live'
                ? 'channels'
                : _section == 'series'
                ? 'series'
                : 'movies'}',
        initial: _query,
      ),
    );
    if (result != null && mounted) setState(() => _query = result.trim());
  }

  Future<void> _sortMenu() async {
    final result = await showDialog<CatalogSort>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Sort titles'),
        children: [
          for (final entry in [
            (CatalogSort.recentlyAdded, 'Recently added'),
            (CatalogSort.titleAscending, 'Title · A to Z'),
            (CatalogSort.titleDescending, 'Title · Z to A'),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, entry.$1),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(entry.$2, style: const TextStyle(fontSize: 20)),
              ),
            ),
        ],
      ),
    );
    if (result != null && mounted) setState(() => _sort = result);
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
    return PopScope(
      canPop: _section == 'home',
      onPopInvokedWithResult: (popped, result) {
        if (!popped) {
          _sectionTo('home');
          _nav('home').requestFocus();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF070D18),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, box) {
              final compact = box.maxWidth < 1050;
              return Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 20 : 32,
                  12,
                  compact ? 20 : 32,
                  10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: compact ? 100 : 146,
                          child: const FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: StreamlineMark(size: 28, wordmark: true),
                          ),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Row(
                            children: [
                              for (final entry in [
                                ('home', 'Home', Icons.home_rounded),
                                ('live', 'Live TV', Icons.live_tv),
                                ('movie', 'Movies', Icons.movie_outlined),
                                (
                                  'series',
                                  'Series',
                                  Icons.video_library_outlined,
                                ),
                                ('list', 'My List', Icons.bookmark_outline),
                                (
                                  'settings',
                                  'Settings',
                                  Icons.settings_outlined,
                                ),
                              ])
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(right: 7),
                                    child: TvControl(
                                      focusNode: _nav(entry.$1),
                                      autofocus: _section == entry.$1,
                                      selected: _section == entry.$1,
                                      label: entry.$2,
                                      onFocused: () => _sectionTo(entry.$1),
                                      onKeyEvent: _topKey,
                                      onPressed: () => _sectionTo(entry.$1),
                                      padding: EdgeInsets.symmetric(
                                        vertical: compact ? 13 : 16,
                                        horizontal: 6,
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          if (!compact) ...[
                                            Icon(entry.$3, size: 20),
                                            const SizedBox(width: 8),
                                          ],
                                          Flexible(
                                            child: Text(
                                              entry.$2,
                                              maxLines: 1,
                                              style: TextStyle(
                                                fontSize: compact ? 16 : 18,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Expanded(
                      child: switch (_section) {
                        'home' => _home(),
                        'settings' => _settingsHome(info),
                        'list' => _saved(),
                        _ => _library(compact),
                      },
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            info?.expiring == true
                                ? 'Account ${info!.remainingDays! <= 0 ? 'expired' : 'expires in ${info.remainingDays} days'} · Open Settings'
                                : '↑ Navigation    ← → Browse    OK Select    Back Home',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: info?.expiring == true
                                  ? AppColors.danger
                                  : AppColors.muted,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        Text(
                          guideClock(DateTime.now()),
                          style: const TextStyle(
                            fontSize: 16,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _heading(
    String title,
    String subtitle, {
    List<Widget> actions = const [],
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 30,
                  fontFamily: 'Streamline Display',
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subtitle.isNotEmpty)
                Text(
                  subtitle,
                  style: const TextStyle(color: AppColors.muted, fontSize: 16),
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
      label: label,
      onPressed: action,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 21),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 16)),
        ],
      ),
    ),
  );
  Widget _panel(String title, Widget child, {String? count}) => Container(
    decoration: BoxDecoration(
      color: const Color(0xFF0C1626),
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(16),
    ),
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 3, 4, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (count != null)
                Text(
                  count,
                  style: const TextStyle(fontSize: 15, color: AppColors.muted),
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
    supplied.sort((a, b) {
      int rank(Category c) {
        final i = order.indexOf(c.id);
        return i < 0 ? order.length : i;
      }

      return rank(a).compareTo(rank(b));
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
        title: 'All',
        selected: _category[_kind] == null && _liveFilter == 'all',
        leading: const Icon(Icons.grid_view, size: 19),
        onPressed: () => _chooseCategory(null),
      ),
      if (_kind == MediaKind.live) ...[
        TvListEntry(
          id: 'favorites',
          title: 'Favorites',
          selected: _liveFilter == 'favorites',
          leading: const Icon(Icons.star_outline, size: 19),
          onPressed: () => _chooseCategory(null, filter: 'favorites'),
        ),
        TvListEntry(
          id: 'recent',
          title: 'Recently viewed',
          selected: _liveFilter == 'recent',
          leading: const Icon(Icons.history, size: 19),
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
    return Column(
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
            _action(
              _query.isEmpty ? 'Search' : 'Clear search',
              _query.isEmpty ? Icons.search : Icons.close,
              _query.isEmpty ? _search : () => setState(() => _query = ''),
            ),
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
                width: compact ? 188 : 230,
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
                          extent: 57,
                          onLeft: () => _nav(_section).requestFocus(),
                          onTop: () => _nav(_section).requestFocus(),
                          onRight: () {
                            if (_kind == MediaKind.live) {
                              _channels.currentState?.focusSelected();
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
                    : _kind == MediaKind.live
                    ? _live(matching, compact, ids)
                    : TvPosterBrowser(
                        key: _grid,
                        items: matching,
                        onOpen: _open,
                        onLeft: () => _categories.currentState?.focusSelected(
                          remember: true,
                        ),
                        onTop: () => _nav(_section).requestFocus(),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _live(List<MediaItem> channels, bool compact, Set<String> favorites) {
    final selected =
        channels.where((e) => e.id == _channel?.id).firstOrNull ??
        channels.where((e) => e.id == _settings.lastChannel).firstOrNull ??
        channels.first;
    final epg = ref.watch(epgProvider(selected.id));
    final programmes = epg.asData?.value ?? <EpgEntry>[];
    final now = DateTime.now();
    final current = programmes
        .where((e) => !e.start.isAfter(now) && e.end.isAfter(now))
        .firstOrNull;
    final next = programmes.where((e) => e.start.isAfter(now)).firstOrNull;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 5,
          child: _panel(
            'Channels',
            TvRemoteList(
              key: _channels,
              label: 'Channel',
              extent: compact ? 66 : 75,
              entries: [
                for (var i = 0; i < channels.length; i++)
                  TvListEntry(
                    id: channels[i].id,
                    title: channels[i].name,
                    subtitle:
                        'Channel ${(i + 1).toString().padLeft(3, '0')}${favorites.contains(AppKey.item(channels[i])) ? ' · ★' : ''}',
                    leading: SizedBox(
                      width: 33,
                      height: 33,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: Artwork(
                          url: channels[i].imageUrl,
                          title: channels[i].name,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    selected: selected.id == channels[i].id,
                    onFocused: () {
                      _pendingChannel = channels[i];
                      _channelFocusTimer?.cancel();
                      _channelFocusTimer = Timer(
                        const Duration(milliseconds: 250),
                        () {
                          if (mounted &&
                              _section == 'live' &&
                              _channel?.id != channels[i].id) {
                            setState(() => _channel = channels[i]);
                          }
                        },
                      );
                    },
                    onPressed: () => _open(channels[i], channels: channels),
                  ),
              ],
              onLeft: () =>
                  _categories.currentState?.focusSelected(remember: true),
              onRight: () {
                _channelFocusTimer?.cancel();
                if (_pendingChannel != null) {
                  setState(() => _channel = _pendingChannel);
                }
                _watch.requestFocus();
              },
              onTop: () => _nav('live').requestFocus(),
            ),
            count: '${channels.length}',
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: compact ? 5 : 6,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                  _channels.currentState?.focusSelected(remember: true);
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: compact ? 110 : 165,
                      child: LiveChannelPreview(
                        key: _preview,
                        compact: true,
                        item: selected,
                        programme: current,
                        onWatch: () => _open(selected, channels: channels),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      selected.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      current?.title ?? 'Programme information unavailable',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 19,
                        color: AppColors.text,
                      ),
                    ),
                    if (current != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        '${guideClock(current.start)} – ${guideClock(current.end)}',
                        style: const TextStyle(
                          fontSize: 15,
                          color: AppColors.muted,
                        ),
                      ),
                      const SizedBox(height: 7),
                      LinearProgressIndicator(
                        value:
                            ((now.difference(current.start).inSeconds) /
                                    current.end
                                        .difference(current.start)
                                        .inSeconds)
                                .clamp(0, 1),
                        minHeight: 3,
                      ),
                    ],
                    if (next != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          'Next · ${next.title}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    TvControl(
                      focusNode: _watch,
                      onPressed: () => _open(selected, channels: channels),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.play_arrow),
                          SizedBox(width: 8),
                          Text('Watch now'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 9),
                    TvControl(
                      onPressed: () => _favorite(selected),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            favorites.contains(AppKey.item(selected))
                                ? Icons.star
                                : Icons.star_outline,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              favorites.contains(AppKey.item(selected))
                                  ? 'Remove favorite'
                                  : 'Save favorite',
                              style: const TextStyle(fontSize: 16),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (current?.description.isNotEmpty == true)
                      Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: Text(
                          current!.description,
                          style: const TextStyle(
                            fontSize: 16,
                            color: AppColors.muted,
                            height: 1.4,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _rail(
    String title,
    List<MediaItem> items, {
    Map<String, double> progress = const {},
  }) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 13),
          SizedBox(
            height: 285,
            child: TvPosterBrowser(
              items: items.take(24).toList(),
              horizontal: true,
              progress: progress,
              onOpen: _open,
              onLeft: () => _nav('home').requestFocus(),
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
    return LayoutBuilder(
      builder: (context, size) => SingleChildScrollView(
        key: const PageStorageKey('tv-home'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (featured != null)
              Container(
                height: (size.maxHeight * .64).clamp(285, 350),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.border),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned(
                      left: size.maxWidth * .38,
                      right: 0,
                      top: 0,
                      bottom: 0,
                      child: Artwork(
                        url: detail?.backdropUrl.isNotEmpty == true
                            ? detail!.backdropUrl
                            : featured.imageUrl,
                        title: featured.name,
                      ),
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Color(0xFF101C2D),
                            Color(0xF9101C2D),
                            Color(0x36101C2D),
                          ],
                          stops: [0, .43, 1],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(26),
                      child: SizedBox(
                        width: size.maxWidth * .6,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: SizedBox(
                            width: size.maxWidth * .62,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text(
                                  'YOUR NEXT MOVIE NIGHT',
                                  style: TextStyle(
                                    color: AppColors.accent,
                                    letterSpacing: 2,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  featured.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 43,
                                    height: 1.04,
                                    fontFamily: 'Streamline Display',
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (detail?.genre.isNotEmpty == true)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(
                                      '${detail!.year}   ${detail.genre}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        color: AppColors.muted,
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    TvControl(
                                      focusNode: _hero,
                                      onPressed: () => _open(featured),
                                      child: const Row(
                                        children: [
                                          Icon(Icons.play_arrow),
                                          SizedBox(width: 8),
                                          Text('View details'),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    TvControl(
                                      onPressed: () {
                                        _sectionTo('live');
                                        _nav('live').requestFocus();
                                      },
                                      child: const Text('Live TV'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              TvControl(
                focusNode: _hero,
                onPressed: () {
                  _sectionTo('live');
                  _nav('live').requestFocus();
                },
                child: const Padding(
                  padding: EdgeInsets.all(36),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Welcome home', style: TextStyle(fontSize: 40)),
                      SizedBox(height: 16),
                      Text('Browse Live TV', style: TextStyle(fontSize: 22)),
                    ],
                  ),
                ),
              ),
            _rail(
              'Continue watching',
              continuing.map((e) => available[AppKey.item(e.item)]!).toList(),
              progress: {
                for (final e in continuing) AppKey.item(e.item): e.progress,
              },
            ),
            _rail(
              'Continue watching series',
              continuingSeries
                  .map((e) => available[AppKey.item(e.item)]!)
                  .toList(),
            ),
            for (final recommendation in recommendations.take(2))
              _rail(recommendation.title, recommendation.items),
            _rail(
              movies.any((e) => e.addedAt != null)
                  ? 'Recently added movies'
                  : 'Movies from your provider',
              movies,
            ),
            _rail(
              'Recently watched',
              history.map((e) => available[AppKey.item(e.item)]!).toList(),
            ),
            _rail('Series to discover', series),
            if (moviesState.hasError)
              TextButton(
                onPressed: () => ref.invalidate(itemsProvider(MediaKind.movie)),
                child: const Text('Reload movies'),
              ),
            const SizedBox(height: 20),
          ],
        ),
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
                  extent: 77,
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
          child: SingleChildScrollView(
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.account_circle_outlined,
                    size: 44,
                    color: AppColors.accent,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    ref.watch(sessionProvider)?.credentials.username ?? '',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'SUBSCRIPTION',
                    style: TextStyle(
                      fontSize: 14,
                      letterSpacing: 1.5,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    info?.status ?? 'Not supplied',
                    style: const TextStyle(fontSize: 22),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'EXPIRY',
                    style: TextStyle(
                      fontSize: 14,
                      letterSpacing: 1.5,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    info?.expiryLabel ?? 'Not supplied',
                    style: const TextStyle(fontSize: 22),
                  ),
                  const SizedBox(height: 22),
                  TvControl(
                    focusNode: _watch,
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const SpeedTestScreen(),
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.speed),
                        SizedBox(width: 10),
                        Text('Speed test'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TvControl(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const AppUpdatesScreen(),
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.system_update),
                        SizedBox(width: 10),
                        Text('App updates'),
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

class _TvSearchDialog extends StatefulWidget {
  const _TvSearchDialog({required this.title, required this.initial});
  final String title, initial;
  @override
  State<_TvSearchDialog> createState() => _TvSearchDialogState();
}

class _TvSearchDialogState extends State<_TvSearchDialog> {
  late final _controller = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 480,
      child: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.search,
        onSubmitted: (v) => Navigator.pop(context, v),
        decoration: const InputDecoration(
          hintText: 'Enter a title or channel name',
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text),
        child: const Text('Search'),
      ),
    ],
  );
}
