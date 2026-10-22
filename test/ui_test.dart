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
import 'package:streamline_iptv/data/local_store.dart';
import 'package:streamline_iptv/data/models.dart';
import 'package:streamline_iptv/data/xtream_api.dart';
import 'package:streamline_iptv/features/movie_detail_screen.dart';
import 'package:streamline_iptv/features/series_detail_screen.dart';
import 'package:streamline_iptv/widgets/media_card.dart';
import 'package:streamline_iptv/widgets/tv_focus_card.dart';

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
  @override
  Future<Session> authenticate(Credentials credentials) async {
    authenticationCount++;
    return Session(
      credentials: credentials,
      userInfo: _account.userInfo,
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
          (ref, kind) async => kind == MediaKind.movie
              ? const [
                  Category(id: 'drama', name: 'Drama'),
                  Category(id: 'action', name: 'Action'),
                ]
              : const [],
        ),
        itemsProvider.overrideWith(
          (ref, kind) async => switch (kind) {
            MediaKind.live => const [_channel, _sportsChannel],
            MediaKind.movie => movies ?? [_film, _otherFilm, _undatedFilm],
            MediaKind.series => const [_series],
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
  final card = find
      .ancestor(of: label, matching: find.byType(TvFocusCard))
      .first;
  final detector = find
      .descendant(of: card, matching: find.byType(FocusableActionDetector))
      .first;
  return tester.widget<FocusableActionDetector>(detector).focusNode!;
}

Finder _rail(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(Column)).first;

Future<void> _reveal(WidgetTester tester, Finder target) async {
  final pageScroll = find
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

List<String> _gridTitles(WidgetTester tester) => tester
    .widgetList<MediaCard>(
      find.descendant(
        of: find.byType(SliverGrid),
        matching: find.byType(MediaCard),
      ),
    )
    .map((card) => card.item.name)
    .toList();

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
    expect(
      find.text('Enter an http:// or https:// server URL'),
      findsOneWidget,
    );
    expect(find.text('Enter your username'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);
    expect(api.authenticationCount, 0);
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'https://provider.example',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'viewer');
    await tester.enterText(find.byType(TextFormField).at(2), 'test-only');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(api.authenticationCount, 1);
    expect(store.savedSession?.credentials.username, 'viewer');
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  _uiTest('TV login fits a landscape screen and autofocuses server input', (
    tester,
  ) async {
    await _pumpApp(tester, store: _MemoryStore(), tv: true, signedIn: false);
    expect(find.byType(TextFormField), findsNWidgets(3));
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
    expect(find.text('ANDROID TV'), findsOneWidget);
    await _screenshot(tester, 'tv-live');
    final moviesLabel = find.text('Movies');
    _cardFocus(tester, moviesLabel).requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.text('Browse movies'), findsOneWidget);
    expect(find.text('Zephyr'), findsWidgets);
    expect(tester.takeException(), isNull);
    await _screenshot(tester, 'tv-movies');
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
      await _reveal(tester, find.text('Browse all'));
      await tester.tap(find.text('Browse all'));
      await tester.pumpAndSettle();
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
