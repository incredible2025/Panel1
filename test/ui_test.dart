import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streamline_iptv/app.dart';
import 'package:streamline_iptv/core/design_system.dart';
import 'package:streamline_iptv/core/providers.dart';
import 'package:streamline_iptv/core/provider_config.dart';
import 'package:streamline_iptv/data/local_store.dart';
import 'package:streamline_iptv/data/models.dart';
import 'package:streamline_iptv/data/app_settings.dart';
import 'package:streamline_iptv/data/xtream_api.dart';
import 'package:streamline_iptv/features/movie_detail_screen.dart';
import 'package:streamline_iptv/features/settings_screen.dart';
import 'package:streamline_iptv/features/series_detail_screen.dart';
import 'package:streamline_iptv/widgets/media_card.dart';
import 'package:streamline_iptv/widgets/tv_focus_card.dart';
import 'package:streamline_iptv/widgets/tv_controls.dart';
import 'package:streamline_iptv/widgets/tv_poster_browser.dart';

import 'support/qa_artwork.dart';

const _qaArtwork = bool.fromEnvironment('CAPTURE_UI_ART')
    ? 'https://artwork.example/sample.jpg'
    : '';

const _account = Session(
  credentials: Credentials(
    serverUrl: 'https://provider.example',
    username: 'viewer',
    password: 'test-only',
  ),
  userInfo: {'auth': 1, 'status': 'Active'},
  serverInfo: {},
);
final _film = MediaItem(
  id: '10',
  name: 'Zephyr',
  kind: MediaKind.movie,
  categoryId: 'drama',
  rating: '8.2',
  imageUrl: _qaArtwork,
  addedAt: DateTime.utc(2026, 10, 18),
);
final _otherFilm = MediaItem(
  id: '11',
  name: 'Night Shift',
  kind: MediaKind.movie,
  categoryId: 'action',
  rating: '7.6',
  imageUrl: _qaArtwork,
  addedAt: DateTime.utc(2026, 10, 22),
);
const _undatedFilm = MediaItem(
  id: '12',
  name: 'Amber Road',
  kind: MediaKind.movie,
  categoryId: 'action',
  imageUrl: _qaArtwork,
);
const _channel = MediaItem(id: '1', name: 'World News', kind: MediaKind.live);
const _sportsChannel = MediaItem(
  id: '2',
  name: 'Arena Sports',
  kind: MediaKind.live,
);
const _series = MediaItem(
  id: '20',
  name: 'The Coast',
  kind: MediaKind.series,
  imageUrl: _qaArtwork,
);

class _MemoryStore implements LocalStore {
  AppSettings preferences = const AppSettings(lastSection: 'live');
  @override
  Future<AppSettings> readSettings(String accountId) async => preferences;
  @override
  Future<void> saveSettings(String accountId, AppSettings settings) async {
    preferences = settings;
  }

  @override
  Future<bool> hasPin(String accountId) async => parentalPin != null;
  String? parentalPin;
  @override
  Future<int> verifyPin(String accountId, String pin) async =>
      parentalPin == pin ? 0 : -1;
  @override
  Future<void> setPin(String accountId, String pin) async {
    parentalPin = pin;
  }

  @override
  Future<void> removePin(String accountId) async {
    parentalPin = null;
  }

  @override
  Future<void> clearCache(String accountId) async {}
  @override
  Future<List<EpisodeWatchEntry>> seriesHistory(String accountId) async =>
      episodeEntries;
  List<EpisodeWatchEntry> episodeEntries = [];
  @override
  Future<void> saveEpisodeProgress(
    String accountId,
    MediaItem item,
    Episode episode, {
    required int positionMs,
    required int durationMs,
    Episode? nextEpisode,
  }) async {}
  Session? savedSession;
  List<WatchEntry> entries = [];
  List<MediaItem> favoriteItems = [];
  List<MediaItem> recentItems = [];
  int favoriteWrites = 0;

  @override
  Future<List<MediaItem>> favorites(String accountId) async =>
      List.of(favoriteItems);
  @override
  Future<void> setFavorite(
    String accountId,
    MediaItem item,
    bool favorite,
  ) async {
    favoriteWrites++;
    favoriteItems.removeWhere(
      (entry) => entry.id == item.id && entry.kind == item.kind,
    );
    if (favorite) favoriteItems.add(item);
  }

  @override
  Future<List<MediaItem>> recentChannels(String accountId) async =>
      List.of(recentItems);
  @override
  Future<void> recordChannelPlayed(String accountId, MediaItem item) async {
    if (item.kind != MediaKind.live) return;
    recentItems.removeWhere((entry) => entry.id == item.id);
    recentItems.insert(0, item);
    recentItems = recentItems.take(20).toList();
  }

  @override
  Future<Session?> readSession() async => savedSession;
  @override
  Future<void> saveSession(Session session) async {
    savedSession = session;
  }

  @override
  Future<void> clearSession() async {
    savedSession = null;
  }

  @override
  Future<List<WatchEntry>> history(String accountId) async => List.of(entries);
  @override
  Future<void> recordOpened(String accountId, MediaItem item) async {
    if (entries.any((entry) => entry.item.id == item.id)) return;
    entries.insert(
      0,
      WatchEntry(
        item: item,
        positionMs: 0,
        durationMs: 0,
        lastAccessed: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> saveProgress(
    String accountId,
    MediaItem item, {
    required int positionMs,
    required int durationMs,
  }) async {
    entries.removeWhere((entry) => entry.item.id == item.id);
    entries.insert(
      0,
      WatchEntry(
        item: item,
        positionMs: positionMs,
        durationMs: durationMs,
        lastAccessed: DateTime.now(),
      ),
    );
  }

  @override
  Future<dynamic> cachedJson(
    String accountId,
    String key, {
    Duration maxAge = const Duration(hours: 6),
  }) async => null;
  @override
  Future<void> cacheJson(String accountId, String key, dynamic data) async {}
  @override
  Future<void> close() async {}
}

class _TestApi extends XtreamApi {
  int authenticationCount = 0;
  Map<String, dynamic>? refreshedInfo;
  @override
  Future<Session> authenticate(Credentials credentials) async {
    authenticationCount++;
    return Session(
      credentials: credentials,
      userInfo: refreshedInfo ?? _account.userInfo,
      serverInfo: {},
    );
  }
}

Future<void> _pumpApp(
  WidgetTester tester, {
  required _MemoryStore store,
  bool tv = false,
  bool signedIn = true,
  Widget? screen,
  _TestApi? api,
  Size? viewport,
  List<MediaItem>? movies,
  List<MediaItem>? liveChannels,
  List<MediaItem>? seriesItems,
  Map<MediaKind, List<Category>>? suppliedCategories,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize =
      viewport ?? (tv ? const Size(1280, 720) : const Size(390, 844));
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final now = DateTime.now();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storeProvider.overrideWithValue(store),
        sessionProvider.overrideWith((ref) => signedIn ? _account : null),
        isTvProvider.overrideWithValue(tv),
        if (api != null) apiProvider.overrideWithValue(api),
        categoriesProvider.overrideWith(
          (ref, kind) async =>
              suppliedCategories?[kind] ??
              (kind == MediaKind.movie
                  ? const [
                      Category(id: 'drama', name: 'Drama'),
                      Category(id: 'action', name: 'Action'),
                    ]
                  : const []),
        ),
        itemsProvider.overrideWith(
          (ref, kind) async => switch (kind) {
            MediaKind.live => liveChannels ?? const [_channel, _sportsChannel],
            MediaKind.movie => movies ?? [_film, _otherFilm, _undatedFilm],
            MediaKind.series => seriesItems ?? const [_series],
          },
        ),
        epgProvider.overrideWith(
          (ref, id) async => [
            EpgEntry(
              title: 'The World Today',
              description: 'Headlines and stories from around the world.',
              start: now.subtract(const Duration(minutes: 15)),
              end: now.add(const Duration(minutes: 15)),
            ),
          ],
        ),
        movieDetailProvider.overrideWith(
          (ref, item) async => MovieDetail(
            item: MediaItem(
              id: item.id,
              name: item.name,
              kind: item.kind,
              containerExtension: 'mkv',
              imageUrl: item.imageUrl,
            ),
            plot:
                'A journey across a quiet landscape becomes an unforgettable adventure.',
            cast: 'Alex Morgan, Jamie Lee',
            genre: 'Drama',
            rating: '8.2',
            duration: '1:40:00',
            backdropUrl: _qaArtwork,
            year: '2024',
          ),
        ),
        seriesDetailProvider.overrideWith(
          (ref, item) async => SeriesDetail(
            item: item,
            plot: 'Life unfolds in a small coastal town.',
            backdropUrl: _qaArtwork,
            year: '2023',
            genre: 'Drama',
            rating: '8.4',
            seasons: const {
              '1': [
                Episode(
                  id: '21',
                  title: 'First Light',
                  season: '1',
                  episodeNumber: 1,
                  imageUrl: _qaArtwork,
                ),
              ],
              '2': [
                Episode(
                  id: '22',
                  title: 'New Horizons',
                  season: '2',
                  episodeNumber: 1,
                  imageUrl: _qaArtwork,
                ),
              ],
            },
          ),
        ),
      ],
      child: RepaintBoundary(
        key: const ValueKey('qa-surface'),
        child: screen == null
            ? const StreamlineApp()
            : MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: StreamlineTheme.dark,
                home: screen,
              ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

// Optional visual QA: flutter test --dart-define=CAPTURE_UI=true test/ui_test.dart.
Future<void> _screenshot(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('CAPTURE_UI')) return;
  // Wait for the exact asset/resize variants used by the visible branding.
  // Image decoding is asynchronous and can outlive pumpAndSettle's fake clock.
  final captureContext = tester.element(
    find.byKey(const ValueKey('qa-surface')),
  );
  final assets = tester
      .widgetList<Image>(find.byType(Image))
      .map((widget) => widget.image)
      .where((provider) => provider is AssetImage || provider is ResizeImage)
      .toList();
  await tester.runAsync(() async {
    for (final provider in assets) {
      await precacheImage(provider, captureContext);
    }
  });
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('qa-surface')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory('build/qa').create(recursive: true);
    await File('build/qa/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

FocusNode _cardFocus(WidgetTester tester, Finder label) {
  final detector = find
      .ancestor(of: label, matching: find.byType(FocusableActionDetector))
      .first;
  return tester.widget<FocusableActionDetector>(detector).focusNode!;
}

Finder _rail(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(Column)).first;

Future<void> _reveal(WidgetTester tester, Finder target) async {
  final pageScroll = find.byType(CustomScrollView).evaluate().isEmpty
      ? find.byType(Scrollable).first
      : find
            .descendant(
              of: find.byType(CustomScrollView).first,
              matching: find.byType(Scrollable),
            )
            .first;
  // A rail can be unbuilt above or below the current viewport.
  tester.state<ScrollableState>(pageScroll).position.jumpTo(0);
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    target,
    250,
    scrollable: pageScroll,
    maxScrolls: 40,
  );
  await tester.pumpAndSettle();
  await Scrollable.ensureVisible(tester.element(target), alignment: .35);
  await tester.pumpAndSettle();
}

List<String> _gridTitles(WidgetTester tester) {
  final tv = tester
      .widgetList<TvPosterBrowser>(find.byType(TvPosterBrowser))
      .where((w) => !w.horizontal)
      .firstOrNull;
  if (tv != null) return tv.items.map((e) => e.name).toList();
  return tester
      .widgetList<MediaCard>(
        find.descendant(
          of: find.byType(SliverGrid),
          matching: find.byType(MediaCard),
        ),
      )
      .map((card) => card.item.name)
      .toList();
}

Future<void> _remoteSort(
  WidgetTester tester,
  String currentLabel,
  int stepsFromNewest,
) async {
  final trigger = find.text(currentLabel);
  await tester.ensureVisible(trigger);
  Focus.of(tester.element(trigger)).requestFocus();
  await tester.pumpAndSettle();
  await tester.sendKeyEvent(LogicalKeyboardKey.select);
  await tester.pumpAndSettle();
  final newestOption = find.text('Recently added');
  expect(newestOption, findsOneWidget);
  Focus.of(tester.element(newestOption)).requestFocus();
  await tester.pumpAndSettle();
  for (var step = 0; step < stepsFromNewest; step++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
  }
  await tester.sendKeyEvent(LogicalKeyboardKey.select);
  await tester.pumpAndSettle();
}

void _uiTest(String description, WidgetTesterCallback callback) {
  testWidgets(description, (tester) async {
    try {
      await tester.runAsync(() async {
        await installQaArtwork();
        if (!const bool.fromEnvironment('CAPTURE_UI_ART')) return;
        // Decode outside the test's fake clock so captures use loaded artwork.
        final ready = Completer<void>();
        final stream = NetworkImage(
          _qaArtwork,
        ).resolve(ImageConfiguration.empty);
        final listener = ImageStreamListener(
          (image, _) {
            image.dispose();
            if (!ready.isCompleted) ready.complete();
          },
          onError: (Object error, StackTrace? stack) {
            if (!ready.isCompleted) ready.completeError(error, stack);
          },
        );
        stream.addListener(listener);
        try {
          await ready.future;
        } finally {
          stream.removeListener(listener);
        }
      });
      await callback(tester);
    } finally {
      // The framework checks painting globals before suite teardown runs.
      restoreQaArtwork();
    }
  });
}

void main() {
  for (final size in [const Size(960, 540), const Size(1280, 720)]) {
    for (final section in ['home', 'live', 'movie', 'series', 'settings']) {
      _uiTest('TV redesign visual $section fits ${size.width} x ${size.height}', (
        tester,
      ) async {
        final store = _MemoryStore()
          ..preferences = AppSettings(lastSection: section);
        final categories = List.generate(
          12,
          (i) => Category(
            id: 'c$i',
            name:
                '${['Entertainment', 'Sports', 'Movies', 'Documentaries'][i % 4]} ${i + 1}',
          ),
        );
        List<MediaItem> titles(MediaKind kind) => List.generate(
          20,
          (i) => MediaItem(
            id: '${kind.name}-$i',
            name: kind == MediaKind.live
                ? ['World News', 'Arena Sports', 'Cinema One', 'Nature HD'][i %
                      4]
                : [
                    'The Last Horizon',
                    'Midnight City',
                    'Ocean of Stars',
                    'The Quiet Shore',
                  ][i % 4],
            kind: kind,
            categoryId: 'c${i % 12}',
            imageUrl: _qaArtwork,
            rating: kind == MediaKind.live ? '' : '8.2',
            addedAt: DateTime.utc(2026, 10, 20),
          ),
        );
        await _pumpApp(
          tester,
          store: store,
          tv: true,
          viewport: size,
          movies: titles(MediaKind.movie),
          liveChannels: titles(MediaKind.live),
          seriesItems: titles(MediaKind.series),
          suppliedCategories: {
            for (final kind in MediaKind.values) kind: categories,
          },
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(NavigationBar), findsNothing);
        expect(find.byType(TvControl), findsWidgets);
        expect(find.byType(TextField), findsNothing);
        await _screenshot(tester, 'tv-redesign-$section-${size.width.toInt()}');
      });
    }
  }

  _uiTest('TV movie details keep resume, synopsis and My List reachable', (
    tester,
  ) async {
    final store = _MemoryStore()
      ..entries = [
        WatchEntry(
          item: _film,
          positionMs: 600000,
          durationMs: 6000000,
          lastAccessed: DateTime.now(),
        ),
      ];
    await _pumpApp(
      tester,
      store: store,
      tv: true,
      screen: MovieDetailScreen(item: _film),
      viewport: const Size(960, 540),
    );
    expect(find.text('Resume movie'), findsOneWidget);
    expect(find.text('My List'), findsOneWidget);
    expect(find.textContaining('A journey'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _screenshot(tester, 'tv-redesign-movie-detail');
  });

  _uiTest(
    'TV search is deliberate and filters without displaying a server URL',
    (tester) async {
      await _pumpApp(tester, store: _MemoryStore(), tv: true);
      _cardFocus(tester, find.text('Movies')).requestFocus();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      _cardFocus(tester, find.text('Search')).requestFocus();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Zephyr');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(_gridTitles(tester), ['Zephyr']);
      expect(find.textContaining('provider.example'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  _uiTest(
    'TV Settings preserves parental protection before showing account details',
    (tester) async {
      final store = _MemoryStore()
        ..parentalPin = '1234'
        ..preferences = const AppSettings(lastSection: 'settings');
      await _pumpApp(tester, store: store, tv: true);
      expect(find.text('Settings are protected'), findsOneWidget);
      expect(find.text('viewer'), findsNothing);
      expect(find.text('Speed test'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  setUpAll(() async {
    if (!const bool.fromEnvironment('CAPTURE_UI')) return;
    await (FontLoader('Streamline Sans')
          ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Roboto-Medium.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf')))
        .load();
    await (FontLoader('Streamline Display')
          ..addFont(rootBundle.load('assets/fonts/RobotoCondensed-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/RobotoCondensed-Bold.ttf')))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final tv in [false, true]) {
    _uiTest(
      '${tv ? 'TV' : 'Phone'} Home shows personal recommendations with cinema-style shelves',
      (tester) async {
        const suggested = MediaItem(
          id: '13',
          name: 'Quiet Harbour',
          kind: MediaKind.movie,
          categoryId: 'drama',
          rating: '8.6',
          imageUrl: _qaArtwork,
        );
        final store = _MemoryStore()
          ..preferences = const AppSettings(lastSection: 'home')
          ..favoriteItems = [_otherFilm, _channel]
          ..entries = [
            WatchEntry(
              item: _film,
              positionMs: 600000,
              durationMs: 6000000,
              lastAccessed: DateTime.now(),
            ),
          ];
        await _pumpApp(
          tester,
          store: store,
          tv: tv,
          movies: [_film, _otherFilm, _undatedFilm, suggested],
        );
        expect(
          find.text(tv ? 'View details' : 'Find your next favourite.'),
          findsOneWidget,
        );
        await _screenshot(tester, tv ? 'v5-tv-home' : 'v5-phone-home');
        await _reveal(tester, find.text('Because you watched Zephyr'));
        expect(find.text('Quiet Harbour'), findsWidgets);
        await _screenshot(
          tester,
          tv ? 'v5-tv-recommendations' : 'v5-phone-recommendations',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  _uiTest('Settings saves player, controls, audio and subtitle choices', (
    tester,
  ) async {
    final store = _MemoryStore();
    await _pumpApp(tester, store: store, screen: const SettingsScreen());
    await tester.tap(find.text('Default player'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compatibility · media_kit'));
    await tester.pumpAndSettle();
    expect(store.preferences.engine, PlayerEngine.compatibility);
    await tester.tap(find.text('Hide player controls'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('After 8 seconds'));
    await tester.pumpAndSettle();
    expect(store.preferences.controlsSeconds, 8);
    await tester.ensureVisible(find.text('Preferred audio language'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Preferred audio language'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(store.preferences.audioLanguage, 'en');
    await tester.ensureVisible(find.text('Subtitles by default'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Subtitles by default'));
    await tester.pumpAndSettle();
    expect(store.preferences.subtitles, true);
    expect(tester.takeException(), isNull);
  });

  for (final tv in [false, true]) {
    _uiTest(
      '${tv ? 'TV' : 'Phone'} Settings displays account information and premium grouped controls',
      (tester) async {
        final store = _MemoryStore();
        await _pumpApp(
          tester,
          store: store,
          tv: tv,
          screen: const SettingsScreen(),
        );
        await _screenshot(tester, tv ? 'v5-tv-settings' : 'v5-phone-settings');
        await tester.ensureVisible(find.text('Expiry date'));
        await tester.pumpAndSettle();
        expect(find.text('Not supplied'), findsWidgets);
        expect(find.text('viewer'), findsOneWidget);
        expect(find.text('Provider'), findsNothing);
        expect(find.textContaining('https://provider.example'), findsNothing);
        expect(find.textContaining('liquidmetal.vip'), findsNothing);
        expect(find.text('test-only'), findsNothing);
        await _screenshot(tester, tv ? 'v5-tv-account' : 'v5-phone-account');
        expect(tester.takeException(), isNull);
      },
    );
  }

  _uiTest(
    'account refresh updates expiry and counts without losing preferences',
    (tester) async {
      final store = _MemoryStore()
        ..preferences = const AppSettings(controlsSeconds: 8);
      final expiry = DateTime.now().add(const Duration(days: 3));
      final api = _TestApi()
        ..refreshedInfo = {
          'auth': 1,
          'status': 'Active',
          'exp_date': (expiry.millisecondsSinceEpoch ~/ 1000).toString(),
          'active_cons': '1',
          'max_connections': '2',
        };
      addTearDown(api.dispose);
      await _pumpApp(
        tester,
        store: store,
        api: api,
        screen: const SettingsScreen(),
      );
      await tester.ensureVisible(find.text('Refresh account information'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Refresh account information'));
      await tester.pumpAndSettle();
      expect(find.text('3 days'), findsOneWidget);
      expect(store.savedSession?.userInfo['max_connections'], '2');
      expect(store.preferences.controlsSeconds, 8);
      expect(find.text('Account information refreshed.'), findsOneWidget);
    },
  );

  _uiTest('unlimited subscription shows no expiry after account refresh', (
    tester,
  ) async {
    final store = _MemoryStore();
    final api = _TestApi()
      ..refreshedInfo = {
        'auth': 1,
        'status': 'Active',
        'exp_date': 'unlimited',
      };
    addTearDown(api.dispose);
    await _pumpApp(
      tester,
      store: store,
      api: api,
      screen: const SettingsScreen(),
    );
    await tester.ensureVisible(find.text('Refresh account information'));
    await tester.tap(find.text('Refresh account information'));
    await tester.pumpAndSettle();
    expect(find.text('Doesn’t expire'), findsNWidgets(2));
    await tester.ensureVisible(find.text('Speed test'));
    await tester.tap(find.text('Speed test'));
    await tester.pumpAndSettle();
    expect(find.text('Start speed test'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  _uiTest(
    'category visibility removes hidden films from browsing and recommendations',
    (tester) async {
      final store = _MemoryStore();
      await _pumpApp(
        tester,
        store: store,
        screen: const CategorySettingsScreen(),
      );
      await tester.tap(find.text('Movies'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Hide category').first);
      await tester.pumpAndSettle();
      expect(store.preferences.hiddenCategories, contains('movie:drama'));
      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpApp(tester, store: store);
      await tester.tap(find.text('Movies'));
      await tester.pumpAndSettle();
      expect(find.text('Zephyr'), findsNothing);
      expect(find.text('Drama'), findsNothing);
      expect(find.text('Night Shift'), findsWidgets);
    },
  );

  _uiTest('a protected movie stays behind a PIN and cannot appear on Home', (
    tester,
  ) async {
    final store = _MemoryStore()
      ..parentalPin = '1234'
      ..preferences = const AppSettings(
        lastSection: 'home',
        lockedCategories: {'movie:drama'},
      );
    await _pumpApp(
      tester,
      store: store,
      screen: MovieDetailScreen(item: _film),
    );
    expect(find.text('This category is protected'), findsOneWidget);
    expect(find.text('Zephyr'), findsNothing);
    await tester.tap(find.text('Cancel')); // Cancel the entry-point PIN prompt.
    await tester.pumpAndSettle();
    expect(store.entries, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpApp(tester, store: store);
    expect(find.text('Zephyr'), findsNothing);
    expect(find.text('Because you watched Zephyr'), findsNothing);
  });

  _uiTest('My List saves a movie and filters movies without mixing in series', (
    tester,
  ) async {
    final store = _MemoryStore()..favoriteItems = [_series];
    await _pumpApp(
      tester,
      store: store,
      screen: MovieDetailScreen(item: _film),
    );
    await tester.ensureVisible(find.text('My List'));
    await tester.tap(find.text('My List'));
    await tester.pumpAndSettle();
    expect(store.favoriteItems, contains(_film));
    expect(find.text('In My List'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpApp(tester, store: store);
    await tester.tap(find.text('Movies').last);
    await tester.pumpAndSettle();
    final chip = find.text('My List').first;
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(_gridTitles(tester), ['Zephyr']);
    await _screenshot(tester, 'phone-my-list');
  });

  _uiTest(
    'series selects the saved season and shows resume and watched markers',
    (tester) async {
      const first = Episode(
        id: '21',
        title: 'First Light',
        season: '1',
        episodeNumber: 1,
      );
      const second = Episode(
        id: '22',
        title: 'New Horizons',
        season: '2',
        episodeNumber: 1,
      );
      final store = _MemoryStore()
        ..episodeEntries = [
          EpisodeWatchEntry(
            item: _series,
            episode: second,
            positionMs: 45000,
            durationMs: 100000,
            lastAccessed: DateTime.now(),
          ),
          EpisodeWatchEntry(
            item: _series,
            episode: first,
            nextEpisode: second,
            positionMs: 100000,
            durationMs: 100000,
            lastAccessed: DateTime.now().subtract(const Duration(minutes: 1)),
          ),
        ];
      await _pumpApp(
        tester,
        store: store,
        tv: true,
        screen: const SeriesDetailScreen(item: _series),
      );
      await _reveal(tester, find.text('Resume · S2 E1'));
      expect(find.text('New Horizons'), findsOneWidget);
      expect(find.text('Resume · 00:45'), findsOneWidget);
      await _screenshot(tester, 'tv-series-progress');
      await tester.tap(find.text('Season 1'));
      await tester.pumpAndSettle();
      expect(find.text('Watched'), findsOneWidget);
      await tester.tap(find.text('Season 2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Resume · S2 E1'));
      await tester.pumpAndSettle();
      expect(find.text('Continue this episode?'), findsOneWidget);
      expect(find.text('Resume from 00:45'), findsOneWidget);
    },
  );

  _uiTest('series home shows continue watching and My List shelves', (
    tester,
  ) async {
    const first = Episode(
      id: '21',
      title: 'First Light',
      season: '1',
      episodeNumber: 1,
    );
    final store = _MemoryStore()
      ..favoriteItems = [_series]
      ..episodeEntries = [
        EpisodeWatchEntry(
          item: _series,
          episode: first,
          positionMs: 45000,
          durationMs: 100000,
          lastAccessed: DateTime.now(),
        ),
      ];
    await _pumpApp(tester, store: store, tv: true);
    await tester.tap(find.text('Series').first);
    await tester.pumpAndSettle();
    await _reveal(tester, find.text('Continue watching'));
    expect(find.text('Resume · S1 · E1'), findsOneWidget);
    await _screenshot(tester, 'tv-series-continue');
    expect(tester.takeException(), isNull);
  });

  _uiTest('phone login validates fields then authenticates and saves session', (
    tester,
  ) async {
    final store = _MemoryStore();
    final api = _TestApi();
    addTearDown(api.dispose);
    await _pumpApp(tester, store: store, signedIn: false, api: api);
    await _screenshot(tester, 'phone-login');
    final submit = find.text('Connect & start watching');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.text('Server URL'), findsNothing);
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.text('Enter your username'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);
    expect(api.authenticationCount, 0);
    await tester.enterText(find.byType(TextFormField).at(0), 'viewer');
    await tester.enterText(find.byType(TextFormField).at(1), 'test-only');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(api.authenticationCount, 1);
    expect(store.savedSession?.credentials.username, 'viewer');
    expect(store.savedSession?.credentials.serverUrl, providerPortalUrl);
    expect(find.textContaining('liquidmetal.vip'), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  _uiTest('TV login fits a landscape screen and autofocuses username input', (
    tester,
  ) async {
    await _pumpApp(tester, store: _MemoryStore(), tv: true, signedIn: false);
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(FocusManager.instance.primaryFocus?.hasFocus, isTrue);
    expect(find.text('Connect your account'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _screenshot(tester, 'tv-login');
  });

  _uiTest('phone dashboard shows EPG, history, category and search filtering', (
    tester,
  ) async {
    final store = _MemoryStore()
      ..entries = [
        WatchEntry(
          item: _film,
          positionMs: 1200000,
          durationMs: 6000000,
          lastAccessed: DateTime.now(),
        ),
      ];
    await _pumpApp(tester, store: store);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('The World Today'), findsOneWidget);
    await _screenshot(tester, 'phone-live');
    await tester.tap(find.text('Movies'));
    await tester.pumpAndSettle();
    await _screenshot(tester, 'phone-movies');
    await _reveal(tester, find.text('Continue watching'));
    expect(find.text('Continue watching'), findsOneWidget);
    await _reveal(tester, find.text('Recently watched'));
    expect(find.text('Recently watched'), findsOneWidget);
    await _reveal(tester, find.text('Drama').first);
    await tester.tap(find.text('Drama').first);
    await tester.pumpAndSettle();
    expect(find.text('Zephyr'), findsOneWidget);
    expect(find.text('Night Shift'), findsNothing);
    await tester.enterText(find.byType(TextField), 'no such film');
    await tester.pumpAndSettle();
    expect(find.text('No matches found'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'zephyr');
    await tester.pumpAndSettle();
    expect(find.text('Zephyr'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  _uiTest('TV dashboard uses remote focus and select for section navigation', (
    tester,
  ) async {
    await _pumpApp(tester, store: _MemoryStore(), tv: true);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    await _screenshot(tester, 'tv-live');
    final moviesLabel = find.text('Movies');
    _cardFocus(tester, moviesLabel).requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.textContaining('All categories'), findsOneWidget);
    expect(find.text('Zephyr'), findsWidgets);
    expect(tester.takeException(), isNull);
    await _screenshot(tester, 'tv-movies');
  });

  for (final kind in MediaKind.values) {
    _uiTest(
      'TV ${kind.name} has stable vertical category, content and navigation zones',
      (tester) async {
        final store = _MemoryStore()
          ..preferences = AppSettings(lastSection: kind.name);
        final categories = List.generate(
          32,
          (i) => Category(id: 'c$i', name: 'Group $i'),
        );
        final items = List.generate(
          32,
          (i) => MediaItem(
            id: '$i',
            name: 'Item $i',
            kind: kind,
            categoryId: 'c$i',
          ),
        );
        await _pumpApp(
          tester,
          store: store,
          tv: true,
          viewport: const Size(1024, 600),
          suppliedCategories: {kind: categories},
          liveChannels: items,
          movies: items,
          seriesItems: items,
        );
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'Navigation: ${kind.name}',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(FocusManager.instance.primaryFocus?.debugLabel, 'Category: All');
        final extra = kind == MediaKind.live ? 3 : 1;
        for (var i = 0; i < 12 + extra; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pumpAndSettle();
        }
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'Category: Group 12',
        );
        final before = FocusManager.instance.primaryFocus;
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
        expect(store.preferences.lastCategories[kind.name], 'c12');
        expect(FocusManager.instance.primaryFocus, same(before));
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          '${kind == MediaKind.live ? 'Channel' : 'Title'}: Item 12',
        );
        expect(find.text('Item 12'), findsWidgets);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'Category: Group 12',
        );
        for (var i = 0; i < 13 + extra; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
          await tester.pumpAndSettle();
        }
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'Navigation: ${kind.name}',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'Category: Group 12',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  _uiTest('TV restores an offscreen vertical category without touch', (
    tester,
  ) async {
    final store = _MemoryStore()
      ..preferences = const AppSettings(
        lastSection: 'movie',
        lastCategories: {'movie': 'c27'},
      );
    await _pumpApp(
      tester,
      store: store,
      tv: true,
      suppliedCategories: {
        MediaKind.movie: List.generate(
          40,
          (i) => Category(id: 'c$i', name: 'Group $i'),
        ),
      },
      movies: [
        const MediaItem(
          id: '27',
          name: 'Restored film',
          kind: MediaKind.movie,
          categoryId: 'c27',
        ),
      ],
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'Category: Group 27',
    );
    expect(
      tester
          .getRect(find.text('Group 27'))
          .overlaps(const Rect.fromLTWH(0, 0, 1280, 720)),
      true,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
    await tester.pumpAndSettle();
    expect(find.text('Restored film'), findsWidgets);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'Category: Group 27',
    );
    expect(tester.takeException(), isNull);
  });

  _uiTest(
    'recently added movies use actual dates and Browse all shows newest first',
    (tester) async {
      await _pumpApp(tester, store: _MemoryStore());
      await tester.tap(find.text('Movies'));
      await tester.pumpAndSettle();
      await _screenshot(tester, 'phone-movies-home');
      await _reveal(tester, find.text('Recently added movies'));
      final cards = tester
          .widgetList<MediaCard>(
            find.descendant(
              of: _rail('Recently added movies'),
              matching: find.byType(MediaCard),
            ),
          )
          .toList();
      expect(cards.map((card) => card.item.name), ['Night Shift', 'Zephyr']);
      expect(cards.any((card) => card.item.name == 'Amber Road'), isFalse);
      final browse = find.text('Browse all');
      await _reveal(tester, browse);
      await tester.tap(browse);
      await tester.pumpAndSettle();
      expect(_gridTitles(tester), ['Night Shift', 'Zephyr', 'Amber Road']);
      expect(find.text('Recently added movies'), findsNothing);
      await _screenshot(tester, 'phone-movies-browse');
      expect(tester.takeException(), isNull);
    },
  );

  _uiTest(
    'TV remote opens sort menu and selects ascending and descending titles',
    (tester) async {
      await _pumpApp(tester, store: _MemoryStore(), tv: true);
      _cardFocus(tester, find.text('Movies')).requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      await _screenshot(tester, 'tv-movies-home');
      await _remoteSort(tester, 'Newest', 1);
      expect(_gridTitles(tester), ['Amber Road', 'Night Shift', 'Zephyr']);
      await _screenshot(tester, 'tv-movies-browse');
      await _remoteSort(tester, 'A–Z', 2);
      expect(_gridTitles(tester), ['Zephyr', 'Night Shift', 'Amber Road']);
      await _remoteSort(tester, 'Z–A', 0);
      expect(_gridTitles(tester), ['Night Shift', 'Zephyr', 'Amber Road']);
      expect(tester.takeException(), isNull);
    },
  );

  _uiTest('missing provider dates show an honest recently added fallback', (
    tester,
  ) async {
    await _pumpApp(tester, store: _MemoryStore(), movies: const [_undatedFilm]);
    await tester.tap(find.text('Movies'));
    await tester.pumpAndSettle();
    await _reveal(tester, find.text('Recently added movies'));
    expect(find.text('Recently added movies'), findsOneWidget);
    expect(
      find.text(
        'Your provider does not include added dates. Browse all titles or explore a category.',
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _rail('Recently added movies'),
        matching: find.byType(MediaCard),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  _uiTest(
    'live favorites persist across reload and the Favorites filter handles removal',
    (tester) async {
      final store = _MemoryStore();
      await _pumpApp(tester, store: store);
      var add = find.byTooltip('Add World News to favorites');
      await _reveal(tester, add);
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(store.favoriteItems.map((item) => item.id), ['1']);
      expect(store.favoriteWrites, 1);
      await _reveal(tester, find.text('Favorite channels'));
      expect(find.text('Favorite channels'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await _pumpApp(tester, store: store);
      await _reveal(tester, find.text('Favorite channels'));
      expect(find.text('Favorite channels'), findsOneWidget);
      await _reveal(tester, find.byTooltip('Remove World News from favorites'));
      expect(
        find.byTooltip('Remove World News from favorites'),
        findsOneWidget,
      );
      await _reveal(tester, find.text('Favorite channels'));
      await _screenshot(tester, 'phone-favorite-channels');
      await _reveal(tester, find.text('Favorites'));
      await tester.tap(find.text('Favorites'));
      await tester.pumpAndSettle();
      expect(find.text('World News'), findsWidgets);
      expect(find.text('Arena Sports'), findsNothing);
      final remove = find.byTooltip('Remove World News from favorites');
      await _reveal(tester, remove);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(store.favoriteItems, isEmpty);
      expect(store.favoriteWrites, 2);
      expect(find.text('No favorite channels yet'), findsOneWidget);
      await _reveal(tester, find.text('Favorites'));
      await tester.tap(find.text('Favorites'));
      await tester.pumpAndSettle();
      add = find.byTooltip('Add World News to favorites');
      await _reveal(tester, add);
      expect(add, findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  _uiTest('recent live channels retain viewing order in their horizontal row', (
    tester,
  ) async {
    final store = _MemoryStore()..recentItems = [_sportsChannel, _channel];
    await _pumpApp(tester, store: store);
    await _reveal(tester, find.text('Recently viewed channels'));
    final cards = tester.widgetList<TvFocusCard>(
      find.descendant(
        of: _rail('Recently viewed channels'),
        matching: find.byType(TvFocusCard),
      ),
    );
    expect(cards.map((card) => card.label), [
      'Play Arena Sports',
      'Play World News',
    ]);
    await _reveal(tester, find.text('Recently viewed channels'));
    await _screenshot(tester, 'phone-recent-channels');
    expect(tester.takeException(), isNull);
  });

  _uiTest('landscape phone scrolls live guide without overflowing', (
    tester,
  ) async {
    await _pumpApp(
      tester,
      store: _MemoryStore(),
      viewport: const Size(844, 390),
    );
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('The World Today'), findsOneWidget);
    final watch = find.text('Watch channel');
    await tester.ensureVisible(watch);
    await tester.pumpAndSettle();
    expect(
      tester.getRect(watch).overlaps(const Rect.fromLTWH(0, 0, 844, 310)),
      isTrue,
    );
    expect(tester.takeException(), isNull);
    await _screenshot(tester, 'phone-landscape-live');
  });

  _uiTest('movie resume dialog uses persisted time and can be dismissed', (
    tester,
  ) async {
    final store = _MemoryStore()
      ..entries = [
        WatchEntry(
          item: _film,
          positionMs: 1200000,
          durationMs: 6000000,
          lastAccessed: DateTime.now(),
        ),
      ];
    await _pumpApp(
      tester,
      store: store,
      screen: MovieDetailScreen(item: _film),
    );
    final play = find.text('Resume movie');
    await tester.ensureVisible(play);
    await _screenshot(tester, 'phone-movie-detail');
    await tester.tap(play);
    // The opening indicator continues animating behind the modal.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Pick up where you left off?'), findsOneWidget);
    expect(find.text('Resume from 20:00'), findsOneWidget);
    expect(find.text('Start from beginning'), findsOneWidget);
    await _screenshot(tester, 'phone-resume');
    Navigator.of(tester.element(find.byType(AlertDialog))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(store.entries.single.positionMs, 1200000);
    expect(tester.takeException(), isNull);
  });

  _uiTest('series season selector replaces its episode list', (tester) async {
    await _pumpApp(
      tester,
      store: _MemoryStore(),
      tv: true,
      screen: const SeriesDetailScreen(item: _series),
    );
    expect(find.text('First Light'), findsOneWidget);
    await tester.tap(find.text('Season 2'));
    await tester.pumpAndSettle();
    expect(find.text('New Horizons'), findsOneWidget);
    expect(find.text('First Light'), findsNothing);
    expect(tester.takeException(), isNull);
    await _screenshot(tester, 'tv-series');
  });

  _uiTest('remote traversal scrolls lazy focus targets down and back up', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 320,
            child: ListView.builder(
              cacheExtent: 320,
              itemCount: 40,
              itemBuilder: (context, index) => SizedBox(
                height: 80,
                child: TvFocusCard(
                  autofocus: index == 0,
                  onPressed: () {},
                  child: Text('Target $index'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (var i = 0; i < 12; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
    expect(_cardFocus(tester, find.text('Target 12')).hasFocus, isTrue);
    for (var i = 0; i < 10; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
    }
    expect(_cardFocus(tester, find.text('Target 2')).hasFocus, isTrue);
    final top = tester.getTopLeft(find.text('Target 2')).dy;
    expect(top, inInclusiveRange(0, 320));
    expect(tester.takeException(), isNull);
  });
}
