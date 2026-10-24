import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show LicenseRegistry, LicenseEntryWithLineBreaks;
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
import 'package:streamline_iptv/widgets/tv_glass_guide.dart';
import 'package:streamline_iptv/widgets/tv_glass_theme.dart';
import 'package:streamline_iptv/widgets/tv_text_entry_dialog.dart';
import 'package:streamline_iptv/widgets/tv_system_text_entry_dialog.dart';
import 'package:streamline_iptv/widgets/tv_home_shelves.dart';
import 'package:streamline_iptv/widgets/tv_poster_browser.dart';
import 'package:streamline_iptv/widgets/tv_page_navigation.dart';
import 'package:streamline_iptv/core/update_controller.dart';
import 'package:streamline_iptv/features/app_updates_screen.dart';
import 'package:streamline_iptv/features/speed_test_screen.dart';
import 'package:streamline_iptv/features/connection_diagnosis_screen.dart';
import 'package:streamline_iptv/features/startup_update_gate.dart';
import 'package:streamline_iptv/features/tv_licences_screen.dart';
import 'package:streamline_iptv/data/speed_test.dart';
import 'package:streamline_iptv/data/connection_diagnostics.dart';
import 'package:streamline_iptv/widgets/tv_utility_scaffold.dart';
import 'speed_test_test.dart' show FakeSpeedTransport;
import 'connection_diagnostics_test.dart' show FakeDiagnosticTransport;
import 'app_update_test.dart' show FakePlatform, FakeTransport, manifest;
import 'package:streamline_iptv/data/app_update.dart';

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

class _RejectedDownloadTransport extends FakeSpeedTransport {
  @override
  Future<SpeedMeasurement> measure({
    required int bytes,
    bool upload = false,
  }) async {
    if (bytes > 0 && !upload) {
      throw const SpeedTestFailure('http', httpStatus: 403);
    }
    return super.measure(bytes: bytes, upload: upload);
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
  UpdateController? updater,
  SpeedTestRunner Function()? speed,
  ConnectionDiagnostics Function()? diagnosis,
  String? moviePlot,
  bool withEpg = true,
  bool startupUpdates = false,
  Map<String, List<EpgEntry>>? schedules,
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
        startupUpdatesEnabledProvider.overrideWithValue(startupUpdates),
        if (speed != null) speedTestFactoryProvider.overrideWithValue(speed),
        if (diagnosis != null)
          connectionDiagnosticsFactoryProvider.overrideWithValue(diagnosis),
        if (updater != null)
          updateControllerProvider.overrideWith((ref) => updater),
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
          (ref, id) async =>
              schedules?[id] ??
              (withEpg
                  ? [
                      EpgEntry(
                        title: 'The World Today',
                        description:
                            'Headlines and stories from around the world.',
                        start: now.subtract(const Duration(minutes: 15)),
                        end: now.add(const Duration(minutes: 15)),
                      ),
                    ]
                  : <EpgEntry>[]),
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
                moviePlot ??
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
      .where(
        (provider) =>
            provider is AssetImage ||
            provider is ResizeImage ||
            const bool.fromEnvironment('CAPTURE_UI_ART') &&
                provider is NetworkImage,
      )
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
  if (find
      .ancestor(of: trigger, matching: find.byType(TvControl))
      .evaluate()
      .isNotEmpty) {
    _cardFocus(tester, trigger).requestFocus();
  } else {
    Focus.of(tester.element(trigger)).requestFocus();
  }
  await tester.pumpAndSettle();
  await tester.sendKeyEvent(LogicalKeyboardKey.select);
  await tester.pumpAndSettle();
  final newestOption = find.descendant(
    of: find.byType(SimpleDialog),
    matching: find.text('Recently added'),
  );
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
  Future<void> remote(
    WidgetTester tester,
    LogicalKeyboardKey key, [
    int count = 1,
  ]) async {
    for (var i = 0; i < count; i++) {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }
  }

  Future<void> useSystemKeyboard(
    WidgetTester tester, {
    bool password = false,
  }) async {
    await remote(tester, LogicalKeyboardKey.arrowDown, 5);
    if (password) await remote(tester, LogicalKeyboardKey.arrowRight);
    await remote(tester, LogicalKeyboardKey.select);
    expect(find.byType(TvSystemTextEntryDialog), findsOneWidget);
  }

  Future<void> keyboardKey(
    WidgetTester tester,
    int row,
    int col, {
    LogicalKeyboardKey activation = LogicalKeyboardKey.select,
  }) async {
    List<int> position() => FocusManager.instance.primaryFocus!.debugLabel!
        .split(' ')
        .last
        .split(':')
        .map(int.parse)
        .toList();
    var at = position();
    await remote(
      tester,
      row < at[0] ? LogicalKeyboardKey.arrowUp : LogicalKeyboardKey.arrowDown,
      (row - at[0]).abs(),
    );
    at = position();
    await remote(
      tester,
      col < at[1]
          ? LogicalKeyboardKey.arrowLeft
          : LogicalKeyboardKey.arrowRight,
      (col - at[1]).abs(),
    );
    expect(position(), [row, col]);
    await remote(tester, activation);
  }

  bool focused(Finder label) {
    final target = FocusManager.instance.primaryFocus?.context;
    return label.evaluate().any((element) {
      var found = identical(element, target);
      element.visitAncestorElements((parent) {
        if (identical(parent, target)) {
          found = true;
          return false;
        }
        return true;
      });
      return found;
    });
  }

  for (final size in [
    const Size(960, 540),
    const Size(1280, 720),
    const Size(1920, 1080),
  ]) {
    _uiTest('TV redesign visual approved Glass guide at $size', (tester) async {
      const names = [
        'Sports Main',
        'BBC One',
        'BBC Two',
        'ITV 1',
        'Channel 4',
        'Sports Football',
        'Cinema Premiere',
        'Nature HD',
      ];
      const programmes = [
        ['Friday Night Football', 'The Football Show', 'Match Highlights'],
        ['The Evening News', 'The One Show', 'A Question of Sport'],
        ['Coast & Country', 'The Repair Workshop', 'Inside the Museum'],
        ['Evening Headlines', 'The Chase', 'Friday Night Drama'],
        ['A Place by the Sea', 'Food Unwrapped', 'The Great Escape'],
        ['Matchday Live', 'Premier League Preview', 'Football Classics'],
        ['Beyond the Summit', 'The Last Crossing', 'After Midnight'],
        ['The Hidden Forest', 'Wild Britain', 'Life on Earth'],
      ];
      final now = DateTime.now();
      final channels = List.generate(
        80,
        (i) => MediaItem(
          id: '$i',
          name: i < names.length ? names[i] : 'Channel $i',
          kind: MediaKind.live,
          imageUrl: const bool.fromEnvironment('CAPTURE_UI_ART')
              ? 'https://artwork.example/glass/football.jpg'
              : '',
        ),
      );
      await _pumpApp(
        tester,
        store: _MemoryStore(),
        tv: true,
        viewport: size,
        liveChannels: channels,
        suppliedCategories: {
          MediaKind.live: const [
            Category(id: 'ent', name: 'Entertainment'),
            Category(id: 'sport', name: 'Sports'),
            Category(id: 'film', name: 'Movies'),
            Category(id: 'doc', name: 'Documentaries'),
            Category(id: 'kids', name: 'Kids'),
          ],
        },
        schedules: {
          for (var i = 0; i < 80; i++)
            '$i': List.generate(
              3,
              (column) => EpgEntry(
                title: programmes[i % 8][column],
                description: 'Live coverage, analysis and all the key moments.',
                start: now.add(Duration(minutes: column * 60 - 15)),
                end: now.add(Duration(minutes: column * 60 + 45)),
              ),
            ),
        },
      );
      await remote(tester, LogicalKeyboardKey.arrowDown);
      await remote(tester, LogicalKeyboardKey.arrowRight);
      expect(find.byType(TvGlassGuide), findsOneWidget);
      expect(
        tester.getRect(find.byType(TvGlassBackdrop)),
        Rect.fromLTWH(0, 0, size.width, size.height),
      );
      expect(find.text('Nature HD').hitTestable(), findsOneWidget);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Channel: Sports Main',
      );
      expect(tester.takeException(), isNull);
      await _screenshot(
        tester,
        'tv-redesign-glass-guide-${size.width.toInt()}',
      );
      await remote(tester, LogicalKeyboardKey.arrowRight);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Programme 1: Sports Main',
      );
      await remote(tester, LogicalKeyboardKey.select);
      expect(find.text('Watch live channel'), findsOneWidget);
      await remote(tester, LogicalKeyboardKey.escape);
      expect(tester.takeException(), isNull);
    });
    for (final section in ['home', 'movie']) {
      _uiTest('TV redesign visual approved Glass $section at $size', (
        tester,
      ) async {
        const names = [
          'Beyond the Summit',
          'The Hidden Forest',
          'Friday Night Live',
          'Northern Lights',
          'Wild Britain',
          'The Last Match',
        ];
        final movies = List.generate(
          12,
          (i) => MediaItem(
            id: 'glass-$i',
            name: i < 6 ? names[i] : 'Film $i',
            kind: MediaKind.movie,
            addedAt: DateTime.now().subtract(Duration(days: i)),
            imageUrl: const bool.fromEnvironment('CAPTURE_UI_ART')
                ? 'https://artwork.example/glass/${['mountains', 'forest', 'football'][i % 3]}.jpg'
                : '',
          ),
        );
        final store = _MemoryStore()
          ..preferences = AppSettings(lastSection: section);
        await _pumpApp(
          tester,
          store: store,
          tv: true,
          viewport: size,
          movies: movies,
        );
        expect(find.text('The Last Match').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _screenshot(
          tester,
          'tv-redesign-glass-$section-${size.width.toInt()}',
        );
      });
    }
  }

  for (final size in [const Size(960, 540), const Size(1280, 720)]) {
    _uiTest(
      'TV redesign visual premium Live TV with missing artwork and guide at $size',
      (tester) async {
        final store = _MemoryStore()
          ..preferences = const AppSettings(lastSection: 'live');
        await _pumpApp(
          tester,
          store: store,
          tv: true,
          viewport: size,
          withEpg: false,
          liveChannels: List.generate(
            24,
            (i) => MediaItem(
              id: 'channel-$i',
              name: i == 0
                  ? 'FRIDAYS FOOTBALL'
                  : 'Ipswich 20:00 Notts Forest ${i + 1}',
              kind: MediaKind.live,
              categoryId: 'uk',
            ),
          ),
          suppliedCategories: {
            MediaKind.live: const [
              Category(id: 'uk', name: 'UK: ENTERTAINMENT'),
              Category(id: 'regional', name: 'UK: REGIONAL'),
              Category(id: 'sport', name: 'UK: SPORTS'),
              Category(id: 'football', name: 'LIVE FOOTBALL'),
            ],
          },
        );
        await remote(tester, LogicalKeyboardKey.arrowDown);
        await remote(tester, LogicalKeyboardKey.arrowRight);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'Channel: FRIDAYS FOOTBALL',
        );
        expect(find.text('No programme guide available'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _screenshot(
          tester,
          'tv-redesign-live-premium-${size.width.toInt()}',
        );
      },
    );
  }

  _uiTest(
    'TV audit long movie descriptions scroll and return to Play using the remote',
    (tester) async {
      await _pumpApp(
        tester,
        store: _MemoryStore(),
        tv: true,
        viewport: const Size(960, 540),
        screen: MovieDetailScreen(item: _film),
        moviePlot: List.filled(
          90,
          'A journey across a quiet landscape becomes an unforgettable adventure.',
        ).join('\n\n'),
      );
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Movie play');
      await remote(tester, LogicalKeyboardKey.arrowDown, 2);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Movie description',
      );
      await remote(tester, LogicalKeyboardKey.arrowDown, 3);
      final scroll = tester.state<ScrollableState>(
        find.descendant(
          of: find.byType(TvScrollPane),
          matching: find.byType(Scrollable),
        ),
      );
      expect(scroll.position.pixels, greaterThan(0));
      await remote(tester, LogicalKeyboardKey.arrowRight);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Movie play');
      expect(find.text('Play movie').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(960, 540), const Size(1280, 720)]) {
    _uiTest(
      'TV redesign visual fixed update actions with long notes at $size',
      (tester) async {
        final platform = FakePlatform();
        final t = FakeTransport()
          ..next = AppUpdate.parse(
            jsonEncode({
              ...manifest(),
              'releaseNotes': List.filled(
                80,
                'Playback, browsing and remote navigation improvements.',
              ).join('\n\n'),
            }),
          );
        final c = UpdateController(platform, t);
        await c.check();
        await _pumpApp(
          tester,
          store: _MemoryStore(),
          tv: true,
          viewport: size,
          updater: c,
          screen: const AppUpdatesScreen(),
        );
        expect(focused(find.text('Download update')), isTrue);
        expect(find.text('Download update').hitTestable(), findsOneWidget);
        await _screenshot(tester, 'tv-redesign-updates-${size.width.toInt()}');
        await remote(tester, LogicalKeyboardKey.select);
        expect(find.text('Install update').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  _uiTest('TV audit player preference dialog works from initial remote focus', (
    tester,
  ) async {
    final store = _MemoryStore();
    await _pumpApp(
      tester,
      store: store,
      tv: true,
      viewport: const Size(960, 540),
      screen: const SettingsScreen(groupIndex: 0),
    );
    expect(focused(find.text('Default player')), isTrue);
    await remote(tester, LogicalKeyboardKey.select);
    expect(focused(find.text('ExoPlayer · Standard')), isTrue);
    await remote(tester, LogicalKeyboardKey.arrowDown);
    await remote(tester, LogicalKeyboardKey.select);
    expect(store.preferences.engine, PlayerEngine.compatibility);
    expect(focused(find.text('Default player')), isTrue);
    expect(tester.takeException(), isNull);
  });
  _uiTest(
    'TV audit favourite ordering reaches distant channels and restores focus',
    (tester) async {
      final channels = List.generate(
        80,
        (i) => MediaItem(id: '$i', name: 'Channel $i', kind: MediaKind.live),
      );
      final store = _MemoryStore()
        ..favoriteItems = channels
        ..preferences = AppSettings(
          favoriteOrder: channels.map((e) => 'live:${e.id}').toList(),
        );
      await _pumpApp(
        tester,
        store: store,
        tv: true,
        viewport: const Size(960, 540),
        screen: const FavoriteOrderScreen(),
      );
      await remote(tester, LogicalKeyboardKey.arrowDown, 45);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Favourite channel: Channel 45',
      );
      await remote(tester, LogicalKeyboardKey.select);
      await remote(tester, LogicalKeyboardKey.select);
      expect(store.preferences.favoriteOrder[44], 'live:45');
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Favourite channel: Channel 45',
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(960, 540), const Size(1280, 720)]) {
    _uiTest(
      'TV audit remote-only Settings shortcut and maintenance update journey at $size',
      (tester) async {
        final platform = FakePlatform()..checked = DateTime.now();
        final updater = UpdateController(platform, FakeTransport());
        final store = _MemoryStore()
          ..preferences = const AppSettings(lastSection: 'settings');
        await _pumpApp(
          tester,
          store: store,
          tv: true,
          viewport: size,
          updater: updater,
        );
        await remote(tester, LogicalKeyboardKey.arrowDown);
        await remote(tester, LogicalKeyboardKey.arrowRight);
        expect(focused(find.text('Speed test')), isTrue);
        await remote(tester, LogicalKeyboardKey.arrowDown);
        expect(focused(find.text('App updates')), isTrue);
        expect(find.text('App updates').hitTestable(), findsOneWidget);
        await remote(tester, LogicalKeyboardKey.select);
        expect(find.byType(AppUpdatesScreen), findsOneWidget);
        expect(focused(find.text('Check for updates')), isTrue);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(focused(find.text('App updates')), isTrue);
        await remote(tester, LogicalKeyboardKey.arrowUp);
        await remote(tester, LogicalKeyboardKey.select);
        expect(find.byType(SpeedTestScreen), findsOneWidget);
        expect(find.text('Start speed test').hitTestable(), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        await remote(tester, LogicalKeyboardKey.arrowLeft);
        await remote(tester, LogicalKeyboardKey.arrowDown, 5);
        await remote(tester, LogicalKeyboardKey.select);
        expect(find.byType(SettingsScreen), findsOneWidget);
        expect(focused(find.text('Speed test')), isTrue);
        await remote(tester, LogicalKeyboardKey.arrowDown);
        expect(focused(find.text('Connection diagnosis')), isTrue);
        await remote(tester, LogicalKeyboardKey.select);
        expect(find.byType(ConnectionDiagnosisScreen), findsOneWidget);
        expect(find.text('Run diagnosis').hitTestable(), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        await remote(tester, LogicalKeyboardKey.arrowDown);
        expect(focused(find.text('App updates')), isTrue);
        await remote(tester, LogicalKeyboardKey.select);
        expect(focused(find.text('Check for updates')), isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (var group = 0; group < 6; group++) {
    _uiTest(
      'TV audit all Settings group $group controls remain reachable by remote',
      (tester) async {
        await _pumpApp(
          tester,
          store: _MemoryStore(),
          tv: true,
          screen: SettingsScreen(groupIndex: group),
          viewport: const Size(960, 540),
        );
        final visited = <FocusNode>{};
        for (var i = 0; i < 32; i++) {
          final node = FocusManager.instance.primaryFocus;
          if (node != null) visited.add(node);
          await remote(tester, LogicalKeyboardKey.arrowDown);
        }
        expect(visited.length, greaterThanOrEqualTo([4, 6, 5, 3, 1, 7][group]));
        expect(
          focused(
            find.text(
              [
                'Play the next episode',
                'Subtitle background',
                'Personal movie recommendations',
                'Set parental PIN',
                'Refresh account information',
                'Sign out',
              ][group],
            ),
          ),
          isTrue,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  _uiTest('TV audit distant categories can be managed using only the remote', (
    tester,
  ) async {
    final store = _MemoryStore();
    await _pumpApp(
      tester,
      store: store,
      tv: true,
      viewport: const Size(960, 540),
      screen: const CategorySettingsScreen(),
      suppliedCategories: {
        MediaKind.live: List.generate(
          80,
          (i) => Category(id: '$i', name: 'Group $i'),
        ),
      },
    );
    await remote(tester, LogicalKeyboardKey.arrowDown, 45);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'Manage category: Group 45',
    );
    await remote(tester, LogicalKeyboardKey.select);
    expect(focused(find.text('Move up')), isTrue);
    await remote(tester, LogicalKeyboardKey.arrowDown, 2);
    await remote(tester, LogicalKeyboardKey.select);
    expect(store.preferences.hiddenCategories, contains('live:45'));
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'Manage category: Group 45',
    );
    expect(tester.takeException(), isNull);
  });
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
                    'Northbound',
                    'After the Rain',
                    'Wild Frontier',
                    'Echoes',
                    'Breaking Dawn',
                    'Beyond the Atlas',
                    'Lost in Orbit',
                    'Under Neon Skies',
                    'A Winter Promise',
                    'Red Harbour',
                    'First Light',
                    'Night Voyage',
                    'The Glass River',
                    'Amber Road',
                    'Fading Starlight',
                    'Blue Latitude',
                  ][i % 20],
            kind: kind,
            categoryId: 'c${i % 12}',
            imageUrl: _qaArtwork,
            rating: kind == MediaKind.live ? '' : '8.2',
            addedAt: DateTime.utc(2026, 10, 20).subtract(Duration(hours: i)),
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

  _uiTest(
    'TV redesign visual movie details keep resume and My List reachable',
    (tester) async {
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
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.text('Pick up where you left off?'), findsOneWidget);
      expect(find.text('Resume from 10:00'), findsOneWidget);
    },
  );

  _uiTest(
    'TV search is deliberate and filters without displaying a server URL',
    (tester) async {
      await _pumpApp(tester, store: _MemoryStore(), tv: true);
      _cardFocus(tester, find.text('Movies')).requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      _cardFocus(tester, find.text('Search')).requestFocus();
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Search');
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      for (final letter in 'zephyr'.split('')) {
        await tester.tap(find.text(letter));
        await tester.pump();
      }
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(_gridTitles(tester), ['Zephyr']);
      expect(find.textContaining('provider.example'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [
    const Size(960, 540),
    const Size(1280, 720),
    const Size(1920, 1080),
  ]) {
    for (final kind in MediaKind.values) {
      _uiTest(
        'TV Search preserves ${kind.name} while crossing header tabs at $size',
        (tester) async {
          const movie = MediaItem(
            id: 'beacon-movie',
            name: 'Beacon Movie',
            kind: MediaKind.movie,
          );
          const series = MediaItem(
            id: 'beacon-series',
            name: 'Beacon Series',
            kind: MediaKind.series,
          );
          const channel = MediaItem(
            id: 'beacon-live',
            name: 'Beacon Live',
            kind: MediaKind.live,
          );
          final store = _MemoryStore()
            ..preferences = AppSettings(lastSection: kind.name)
            ..favoriteItems = [_otherFilm];
          await _pumpApp(
            tester,
            store: store,
            tv: true,
            viewport: size,
            movies: [movie, _otherFilm],
            seriesItems: [series, _series],
            liveChannels: [channel, _channel],
          );
          expect(
            FocusManager.instance.primaryFocus?.debugLabel,
            'Navigation: ${kind.name}',
          );
          final steps = kind == MediaKind.live
              ? 4
              : kind == MediaKind.movie
              ? 3
              : 2;
          for (var i = 0; i < steps; i++) {
            await remote(tester, LogicalKeyboardKey.arrowRight);
            expect(store.preferences.lastSection, kind.name);
          }
          expect(FocusManager.instance.primaryFocus?.debugLabel, 'Search');
          await remote(tester, LogicalKeyboardKey.select);
          expect(
            tester
                .widget<TvTextEntryDialog>(find.byType(TvTextEntryDialog))
                .label,
            'Search ${kind == MediaKind.live
                ? 'channels'
                : kind == MediaKind.series
                ? 'series'
                : 'movies'}',
          );
          for (final position in [
            (3, 4),
            (1, 2),
            (2, 0),
            (3, 2),
            (1, 8),
            (3, 5),
          ]) {
            await keyboardKey(tester, position.$1, position.$2);
          }
          await keyboardKey(tester, 4, 5);
          final results = kind == MediaKind.live
              ? tester.widget<TvGlassGuide>(find.byType(TvGlassGuide)).channels
              : tester
                    .widget<TvPosterBrowser>(find.byType(TvPosterBrowser))
                    .items;
          expect(results.map((item) => item.name), [
            kind == MediaKind.live
                ? 'Beacon Live'
                : kind == MediaKind.series
                ? 'Beacon Series'
                : 'Beacon Movie',
          ]);
          expect(store.preferences.lastSection, kind.name);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final activation in [
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.arrowDown,
  ]) {
    _uiTest(
      'TV header focus does not switch section; $activation opens the focused tab',
      (tester) async {
        final store = _MemoryStore()
          ..preferences = const AppSettings(lastSection: 'movie');
        await _pumpApp(tester, store: store, tv: true);
        await remote(tester, LogicalKeyboardKey.arrowRight);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'Navigation: series',
        );
        expect(store.preferences.lastSection, 'movie');
        await remote(tester, activation);
        expect(store.preferences.lastSection, 'series');
        expect(find.text('The Coast'), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );
  }

  _uiTest(
    'TV Search cancellation preserves series and explicit My List search opens the movie catalogue',
    (tester) async {
      final store = _MemoryStore()
        ..preferences = const AppSettings(lastSection: 'series')
        ..favoriteItems = [_otherFilm];
      await _pumpApp(tester, store: store, tv: true);
      await remote(tester, LogicalKeyboardKey.arrowRight, 2);
      await remote(tester, LogicalKeyboardKey.select);
      await remote(tester, LogicalKeyboardKey.escape);
      expect(store.preferences.lastSection, 'series');
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Search');
      await remote(tester, LogicalKeyboardKey.arrowLeft);
      await remote(tester, LogicalKeyboardKey.select);
      expect(store.preferences.lastSection, 'list');
      await remote(tester, LogicalKeyboardKey.arrowRight);
      await remote(tester, LogicalKeyboardKey.select);
      for (final letter in 'zephyr'.split('')) {
        await tester.tap(find.text(letter));
        await tester.pump();
      }
      await keyboardKey(tester, 4, 5);
      expect(_gridTitles(tester), ['Zephyr']);
      expect(store.preferences.lastSection, 'movie');
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
    await (FontLoader(
      'Glass Sans',
    )..addFont(rootBundle.load('assets/fonts/Inter-Variable.ttf'))).load();
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
        if (tv) {
          await remote(tester, LogicalKeyboardKey.arrowLeft);
          await remote(tester, LogicalKeyboardKey.arrowDown, 4);
          await remote(tester, LogicalKeyboardKey.arrowRight);
          await remote(tester, LogicalKeyboardKey.arrowDown, 2);
        } else {
          await tester.ensureVisible(find.text('Expiry date'));
        }
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
    'TV redesign visual series selects saved season with resume and watched markers',
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
      await tester.ensureVisible(find.text('Resume · S2 E1'));
      expect(find.text('New Horizons'), findsOneWidget);
      expect(find.text('Resume · 00:45'), findsOneWidget);
      await _screenshot(tester, 'tv-redesign-series-detail');
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
    await tester.tap(find.text('Home').first);
    await tester.pumpAndSettle();
    await _reveal(tester, find.text('Continue watching series'));
    expect(
      tester
          .widgetList<TvPosterBrowser>(find.byType(TvPosterBrowser))
          .any((w) => w.progress['series:20'] == .45),
      isTrue,
    );
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

  for (final size in [
    const Size(960, 540),
    const Size(1280, 720),
    const Size(1920, 1080),
  ]) {
    _uiTest(
      'TV redesign visual login keeps updates and validation visible at $size',
      (tester) async {
        await _pumpApp(
          tester,
          store: _MemoryStore(),
          tv: true,
          signedIn: false,
          viewport: size,
        );
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'Login username',
        );
        expect(find.text('App updates').hitTestable(), findsOneWidget);
        expect(
          find.text('Connect & start watching').hitTestable(),
          findsOneWidget,
        );
        expect(find.byType(Scrollable), findsNothing);
        expect(tester.testTextInput.isVisible, isFalse);
        await remote(tester, LogicalKeyboardKey.arrowDown, 2);
        await remote(tester, LogicalKeyboardKey.select);
        expect(find.text('Enter your username').hitTestable(), findsOneWidget);
        expect(find.text('App updates').hitTestable(), findsOneWidget);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'Login username',
        );
        expect(tester.takeException(), isNull);
        await _screenshot(tester, 'tv-redesign-login-${size.width.toInt()}');
      },
    );
  }

  for (final activation in [
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.gameButtonA,
  ]) {
    _uiTest(
      'TV login $activation opens and reopens the keyboard and authenticates without touch',
      (tester) async {
        final store = _MemoryStore();
        final api = _TestApi();
        addTearDown(api.dispose);
        await _pumpApp(
          tester,
          store: store,
          tv: true,
          signedIn: false,
          api: api,
          viewport: const Size(960, 540),
        );
        await remote(tester, activation);
        expect(find.byType(TvTextEntryDialog), findsOneWidget);
        expect(tester.testTextInput.isVisible, isFalse);
        await useSystemKeyboard(tester);
        expect(tester.testTextInput.isVisible, isTrue);
        tester.testTextInput.hide();
        tester.testTextInput.log.clear();
        await remote(tester, activation);
        expect(tester.testTextInput.isVisible, isTrue);
        expect(
          tester.testTextInput.log.any(
            (call) => call.method == 'TextInput.show',
          ),
          isTrue,
        );
        tester.testTextInput.enterText('viewer');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'Login password',
        );
        await remote(tester, activation);
        await useSystemKeyboard(tester, password: true);
        expect(tester.testTextInput.isVisible, isTrue);
        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.obscureText, isTrue);
        tester.testTextInput.enterText('test-only');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(FocusManager.instance.primaryFocus?.debugLabel, 'Login connect');
        await remote(tester, activation);
        expect(api.authenticationCount, 1);
        expect(store.savedSession?.credentials.username, 'viewer');
        expect(store.savedSession?.credentials.password, 'test-only');
        expect(store.savedSession?.credentials.serverUrl, providerPortalUrl);
        expect(find.textContaining('liquidmetal.vip'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  _uiTest(
    'TV native keyboard connection closure returns to the built-in keyboard',
    (tester) async {
      await _pumpApp(
        tester,
        store: _MemoryStore(),
        tv: true,
        signedIn: false,
        viewport: const Size(960, 540),
      );
      await remote(tester, LogicalKeyboardKey.select);
      await useSystemKeyboard(tester);
      tester.testTextInput.enterText('keep-this-name');
      tester.testTextInput.closeConnection();
      await tester.pumpAndSettle();
      expect(find.byType(TvTextEntryDialog), findsOneWidget);
      expect(find.byType(TvSystemTextEntryDialog), findsNothing);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Remote keyboard 5:0',
      );
      expect(find.text('keep-this-name').hitTestable(), findsOneWidget);
      await remote(tester, LogicalKeyboardKey.select);
      expect(tester.testTextInput.isVisible, isTrue);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'keep-this-name',
      );
      expect(tester.takeException(), isNull);
    },
  );

  _uiTest('TV held OK opens only one credential entry dialog', (tester) async {
    await _pumpApp(
      tester,
      store: _MemoryStore(),
      tv: true,
      signedIn: false,
      viewport: const Size(960, 540),
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    expect(find.byType(TvTextEntryDialog), findsOneWidget);
    expect(tester.testTextInput.isVisible, isFalse);
    expect(
      tester
          .widget<TvTextEntryDialog>(find.byType(TvTextEntryDialog))
          .controller
          .text,
      isEmpty,
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    expect(
      tester
          .widget<TvTextEntryDialog>(find.byType(TvTextEntryDialog))
          .controller
          .text,
      '1',
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(TvTextEntryDialog), findsNothing);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Login username');
    expect(tester.takeException(), isNull);
  });

  _uiTest('TV login opens updates using only the remote and restores focus', (
    tester,
  ) async {
    final updater = UpdateController(FakePlatform(), FakeTransport());
    await _pumpApp(
      tester,
      store: _MemoryStore(),
      tv: true,
      signedIn: false,
      updater: updater,
      viewport: const Size(960, 540),
    );
    await remote(tester, LogicalKeyboardKey.arrowUp);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Login updates');
    await remote(tester, LogicalKeyboardKey.select);
    expect(find.byType(AppUpdatesScreen), findsOneWidget);
    expect(find.text('Check for updates').hitTestable(), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Login updates');
    await remote(tester, LogicalKeyboardKey.arrowDown);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Login username');
    expect(tester.takeException(), isNull);
  });

  _uiTest(
    'TV text entry fits above the keyboard and retains text when returning',
    (tester) async {
      await _pumpApp(
        tester,
        store: _MemoryStore(),
        tv: true,
        signedIn: false,
        viewport: const Size(960, 540),
      );
      await remote(tester, LogicalKeyboardKey.select);
      await useSystemKeyboard(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 270);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      final rect = tester.getRect(find.byType(TextField));
      expect(rect.bottom, lessThanOrEqualTo(270));
      tester.testTextInput.enterText('remember-me');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(find.byType(TvTextEntryDialog), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('remember-me'), findsOneWidget);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Login username');
      expect(tester.takeException(), isNull);
    },
  );

  _uiTest(
    'TV Home stays fixed while the remote browses both complete horizontal rows',
    (tester) async {
      final movies = List.generate(
        80,
        (i) => MediaItem(
          id: '$i',
          name: 'Movie $i',
          kind: MediaKind.movie,
          addedAt: DateTime.utc(2026, 10, 23).subtract(Duration(minutes: i)),
        ),
      );
      final series = List.generate(
        30,
        (i) => MediaItem(id: 's$i', name: 'Series $i', kind: MediaKind.series),
      );
      final store = _MemoryStore()
        ..preferences = const AppSettings(lastSection: 'home');
      await _pumpApp(
        tester,
        store: store,
        tv: true,
        movies: movies,
        seriesItems: series,
        viewport: const Size(960, 540),
      );
      final surface = find.byKey(const ValueKey('tv-fixed-home'));
      final before = tester.getRect(surface);
      void fixed() {
        expect(tester.getRect(surface), before);
        expect(
          tester
              .widgetList<Scrollable>(
                find.descendant(of: surface, matching: find.byType(Scrollable)),
              )
              .every(
                (w) => axisDirectionToAxis(w.axisDirection) == Axis.horizontal,
              ),
          isTrue,
        );
        expect(find.text('Series to discover').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      }

      fixed();
      await remote(tester, LogicalKeyboardKey.arrowDown, 3);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Title: Movie 0');
      await remote(tester, LogicalKeyboardKey.arrowRight, 17);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Title: Movie 17');
      await remote(tester, LogicalKeyboardKey.arrowDown);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Title: Series 17',
      );
      await remote(tester, LogicalKeyboardKey.arrowDown, 20);
      fixed();
      await remote(tester, LogicalKeyboardKey.arrowUp);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Title: Movie 17');
      await remote(tester, LogicalKeyboardKey.arrowLeft, 18);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Home collection: For you',
      );
      await remote(tester, LogicalKeyboardKey.arrowUp, 2);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Navigation: home',
      );
      fixed();
    },
  );

  _uiTest(
    'TV fixed Home collection selector keeps history and discovery reachable',
    (tester) async {
      final store = _MemoryStore()
        ..preferences = const AppSettings(lastSection: 'home')
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
        viewport: const Size(960, 540),
      );
      final shelves = tester
          .widget<TvHomeShelves>(find.byType(TvHomeShelves))
          .shelves
          .where((e) => e.items.isNotEmpty)
          .toList();
      expect(
        shelves.map((e) => e.title),
        containsAll([
          'Continue watching',
          'Recently added movies',
          'Recently watched',
          'Series to discover',
        ]),
      );
      await remote(tester, LogicalKeyboardKey.arrowDown, 2);
      for (var page = 0; page < (shelves.length / 2).ceil(); page++) {
        expect(find.text(shelves[page * 2].title).hitTestable(), findsWidgets);
        if (page * 2 + 1 < shelves.length) {
          expect(
            find.text(shelves[page * 2 + 1].title).hitTestable(),
            findsWidgets,
          );
        }
        if (page + 1 < (shelves.length / 2).ceil()) {
          await remote(tester, LogicalKeyboardKey.arrowRight);
        }
      }
      await remote(tester, LogicalKeyboardKey.select);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        startsWith('Title:'),
      );
      expect(tester.takeException(), isNull);
    },
  );

  _uiTest(
    'TV login password visibility and connection diagnosis work using the remote',
    (tester) async {
      await _pumpApp(
        tester,
        store: _MemoryStore(),
        tv: true,
        signedIn: false,
        viewport: const Size(960, 540),
      );
      await remote(tester, LogicalKeyboardKey.arrowDown);
      await remote(tester, LogicalKeyboardKey.select);
      await useSystemKeyboard(tester, password: true);
      tester.testTextInput.enterText('private-example');
      await remote(tester, LogicalKeyboardKey.arrowDown);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'TV password visibility',
      );
      await remote(tester, LogicalKeyboardKey.select);
      expect(
        tester.widget<TextField>(find.byType(TextField)).obscureText,
        isFalse,
      );
      await remote(tester, LogicalKeyboardKey.select);
      expect(
        tester.widget<TextField>(find.byType(TextField)).obscureText,
        isTrue,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Login password');
      await remote(tester, LogicalKeyboardKey.arrowLeft);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Login diagnosis');
      await remote(tester, LogicalKeyboardKey.select);
      expect(find.byType(ConnectionDiagnosisScreen), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Login diagnosis');
      expect(tester.takeException(), isNull);
    },
  );

  for (final activation in [
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.gameButtonA,
  ]) {
    _uiTest(
      'TV built-in keyboard $activation types credentials and signs in without a platform keyboard',
      (tester) async {
        final store = _MemoryStore(), api = _TestApi();
        addTearDown(api.dispose);
        await _pumpApp(
          tester,
          store: store,
          tv: true,
          signedIn: false,
          api: api,
          viewport: const Size(960, 540),
        );
        tester.testTextInput.log.clear();
        await remote(tester, activation);
        expect(find.byType(TextField), findsNothing);
        await keyboardKey(tester, 1, 0, activation: activation);
        await keyboardKey(tester, 0, 0, activation: activation);
        expect(
          tester
              .widget<TvTextEntryDialog>(find.byType(TvTextEntryDialog))
              .controller
              .text,
          'q1',
        );
        await keyboardKey(tester, 4, 5, activation: activation);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'Login password',
        );
        await remote(tester, activation);
        await keyboardKey(tester, 4, 0, activation: activation);
        await keyboardKey(tester, 2, 0, activation: activation);
        await keyboardKey(tester, 4, 1, activation: activation);
        await keyboardKey(tester, 0, 0, activation: activation);
        await keyboardKey(tester, 4, 1, activation: activation);
        await keyboardKey(tester, 0, 8, activation: activation);
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('tv-keyboard-value')))
              .data,
          '•••',
        );
        await keyboardKey(tester, 4, 5, activation: activation);
        expect(FocusManager.instance.primaryFocus?.debugLabel, 'Login connect');
        await remote(tester, activation);
        expect(api.authenticationCount, 1);
        expect(store.savedSession?.credentials.username, 'q1');
        expect(store.savedSession?.credentials.password, 'A!9');
        expect(
          tester.testTextInput.log.any(
            (call) => call.method == 'TextInput.show',
          ),
          isFalse,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final size in [
    const Size(960, 540),
    const Size(1280, 720),
    const Size(1920, 1080),
  ]) {
    for (final failed in [false, true]) {
      _uiTest('TV redesign visual startup update gate failed=$failed at $size', (
        tester,
      ) async {
        final transport = FakeTransport();
        if (failed) {
          transport.failure = const UpdateFailure(
            'The update server could not be reached. Retry or continue with your installed app.',
          );
        }
        await _pumpApp(
          tester,
          store: _MemoryStore(),
          tv: true,
          viewport: size,
          startupUpdates: true,
          updater: UpdateController(FakePlatform(), transport),
        );
        expect(
          find.text(failed ? 'Try again' : 'Update now').hitTestable(),
          findsOneWidget,
        );
        expect(find.text('Continue to app').hitTestable(), findsOneWidget);
        expect(find.text('Home'), findsNothing);
        await _screenshot(
          tester,
          'tv-redesign-startup-$failed-${size.width.toInt()}',
        );
        if (!failed) {
          await remote(tester, LogicalKeyboardKey.select);
          expect(find.text('Check for updates').hitTestable(), findsOneWidget);
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(
            FocusManager.instance.primaryFocus?.debugLabel,
            'Startup update action',
          );
        }
        await remote(tester, LogicalKeyboardKey.arrowDown);
        await remote(tester, LogicalKeyboardKey.select);
        expect(find.text('Home'), findsOneWidget);
        expect(transport.checks, 1);
        expect(tester.takeException(), isNull);
      });
    }
    _uiTest('TV redesign visual movie detail keeps actions fixed at $size', (
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
        viewport: size,
        screen: MovieDetailScreen(item: _film),
        moviePlot: List.filled(
          60,
          'A long provider synopsis remains readable with the remote.',
        ).join(' '),
      );
      expect(find.text('Resume movie').hitTestable(), findsOneWidget);
      final button = tester.getRect(find.text('Resume movie'));
      await remote(tester, LogicalKeyboardKey.arrowUp);
      await remote(tester, LogicalKeyboardKey.arrowDown, 8);
      expect(tester.getRect(find.text('Resume movie')), button);
      await _screenshot(
        tester,
        'tv-redesign-movie-detail-${size.width.toInt()}',
      );
      expect(tester.takeException(), isNull);
    });
    _uiTest('TV redesign visual series detail and information at $size', (
      tester,
    ) async {
      await _pumpApp(
        tester,
        store: _MemoryStore(),
        tv: true,
        viewport: size,
        screen: const SeriesDetailScreen(item: _series),
      );
      expect(find.text('Season 1').hitTestable(), findsOneWidget);
      expect(find.text('First Light').hitTestable(), findsOneWidget);
      await _screenshot(
        tester,
        'tv-redesign-series-detail-${size.width.toInt()}',
      );
      await remote(tester, LogicalKeyboardKey.arrowUp);
      await remote(tester, LogicalKeyboardKey.select);
      expect(
        find.text('Life unfolds in a small coastal town.'),
        findsOneWidget,
      );
      expect(find.text('Close').hitTestable(), findsOneWidget);
      await _screenshot(
        tester,
        'tv-redesign-series-information-${size.width.toInt()}',
      );
      expect(tester.takeException(), isNull);
    });
    _uiTest('TV redesign visual built-in keyboard fits at $size', (
      tester,
    ) async {
      await _pumpApp(
        tester,
        store: _MemoryStore(),
        tv: true,
        signedIn: false,
        viewport: size,
      );
      await remote(tester, LogicalKeyboardKey.select);
      for (final label in ['Done', 'Clear', 'Use system keyboard', 'Back']) {
        expect(find.text(label).hitTestable(), findsOneWidget);
      }
      expect(find.byType(TextField), findsNothing);
      expect(tester.testTextInput.isVisible, isFalse);
      await _screenshot(tester, 'tv-redesign-keyboard-${size.width.toInt()}');
      expect(tester.takeException(), isNull);
    });
  }

  _uiTest(
    'TV built-in keyboard supports all printable credential characters and clear',
    (tester) async {
      await _pumpApp(
        tester,
        store: _MemoryStore(),
        tv: true,
        signedIn: false,
        viewport: const Size(960, 540),
      );
      await remote(tester, LogicalKeyboardKey.select);
      final controller = tester
          .widget<TvTextEntryDialog>(find.byType(TvTextEntryDialog))
          .controller;
      for (var mode = 0; mode < 3; mode++) {
        if (mode == 1) await keyboardKey(tester, 4, 0);
        if (mode == 2) await keyboardKey(tester, 4, 1);
        for (var row = 0; row < 4; row++) {
          for (var col = 0; col < 10; col++) {
            await keyboardKey(tester, row, col);
          }
        }
      }
      await keyboardKey(tester, 4, 2);
      expect(
        controller.text.runes.toSet().containsAll(
          List.generate(95, (i) => i + 32),
        ),
        isTrue,
      );
      await keyboardKey(tester, 4, 3);
      expect(controller.text.endsWith(' '), isFalse);
      await keyboardKey(tester, 4, 4);
      expect(controller.text, isEmpty);
      await keyboardKey(tester, 1, 0);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Login username');
      await remote(tester, LogicalKeyboardKey.select);
      expect(
        tester
            .widget<TvTextEntryDialog>(find.byType(TvTextEntryDialog))
            .controller
            .text,
        '-',
      );
      expect(tester.takeException(), isNull);
    },
  );

  _uiTest(
    'TV built-in keyboard masks passwords and accepts physical typing without IME',
    (tester) async {
      await _pumpApp(
        tester,
        store: _MemoryStore(),
        tv: true,
        signedIn: false,
        viewport: const Size(960, 540),
      );
      await remote(tester, LogicalKeyboardKey.arrowDown);
      await remote(tester, LogicalKeyboardKey.select);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA, character: 'a');
      await tester.sendKeyEvent(LogicalKeyboardKey.space, character: ' ');
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB, character: '😀');
      await tester.pumpAndSettle();
      final controller = tester
          .widget<TvTextEntryDialog>(find.byType(TvTextEntryDialog))
          .controller;
      expect(controller.text, 'a 😀');
      await remote(tester, LogicalKeyboardKey.backspace);
      expect(controller.text, 'a ');
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('tv-keyboard-value')))
            .data,
        '••',
      );
      await keyboardKey(tester, 5, 0);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('tv-keyboard-value')))
            .data,
        'a ',
      );
      await keyboardKey(tester, 5, 0);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('tv-keyboard-value')))
            .data,
        '••',
      );
      expect(tester.testTextInput.isVisible, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [
    const Size(960, 540),
    const Size(1280, 720),
    const Size(1920, 1080),
  ]) {
    for (var group = 0; group < 6; group++) {
      _uiTest('TV redesign visual fixed Settings group $group at $size', (
        tester,
      ) async {
        await _pumpApp(
          tester,
          store: _MemoryStore(),
          tv: true,
          screen: SettingsScreen(groupIndex: group),
          viewport: size,
        );
        final canvas = find.byKey(const ValueKey('tv-utility-canvas'));
        final before = tester.getRect(canvas);
        await _screenshot(
          tester,
          'tv-redesign-settings-$group-${size.width.toInt()}',
        );
        final visited = <String>{};
        for (var i = 0; i < 15; i++) {
          final label = FocusManager.instance.primaryFocus!.debugLabel!;
          expect(label, startsWith('Setting: '));
          visited.add(label);
          final text = find.text(label.substring('Setting: '.length)).first;
          expect(text.hitTestable(), findsOneWidget);
          final rect = tester.getRect(text);
          expect(rect.top, greaterThan(before.top + 30));
          expect(rect.bottom, lessThan(before.bottom - 15));
          await remote(tester, LogicalKeyboardKey.arrowDown);
          expect(tester.getRect(canvas), before);
        }
        expect(visited.length, [5, 6, 5, 3, 7, 9][group]);
        await _screenshot(
          tester,
          'tv-redesign-settings-$group-bottom-${size.width.toInt()}',
        );
        final selected = FocusManager.instance.primaryFocus!.debugLabel;
        await remote(tester, LogicalKeyboardKey.arrowRight);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'Setting explanation',
        );
        await remote(tester, LogicalKeyboardKey.arrowDown, 5);
        expect(tester.getRect(canvas), before);
        await remote(tester, LogicalKeyboardKey.arrowLeft);
        expect(FocusManager.instance.primaryFocus?.debugLabel, selected);
        expect(tester.takeException(), isNull);
      });
    }

    for (final partial in [false, true]) {
      _uiTest('TV redesign visual fixed speed test partial=$partial at $size', (
        tester,
      ) async {
        final transport = partial
            ? _RejectedDownloadTransport()
            : FakeSpeedTransport();
        await _pumpApp(
          tester,
          store: _MemoryStore(),
          tv: true,
          viewport: size,
          screen: const SpeedTestScreen(),
          speed: () => SpeedTestRunner(transport),
        );
        final bounds = {
          for (final metric in ['Download', 'Upload', 'HTTP latency', 'Jitter'])
            metric: tester.getRect(find.byKey(ValueKey('tv-speed-$metric'))),
        };
        final actionRect = tester.getRect(
          find.ancestor(
            of: find.text('Start speed test'),
            matching: find.byType(TvControl),
          ),
        );
        for (final metric in bounds.keys) {
          expect(find.text(metric).hitTestable(), findsOneWidget);
        }
        expect(transport.calls, isEmpty);
        await _screenshot(
          tester,
          'tv-redesign-speed-idle-${size.width.toInt()}',
        );
        await remote(tester, LogicalKeyboardKey.select);
        expect(find.text('Run again').hitTestable(), findsOneWidget);
        if (partial) {
          expect(find.textContaining('HTTP 403').hitTestable(), findsOneWidget);
          expect(find.text('Test finished with notices'), findsOneWidget);
        } else {
          expect(find.text('16.8').hitTestable(), findsOneWidget);
          expect(find.text('4.2').hitTestable(), findsOneWidget);
        }
        expect(
          tester.getRect(
            find.ancestor(
              of: find.text('Run again'),
              matching: find.byType(TvControl),
            ),
          ),
          actionRect,
        );
        await _screenshot(
          tester,
          'tv-redesign-speed-${partial ? 'error' : 'results'}-${size.width.toInt()}',
        );
        await remote(tester, LogicalKeyboardKey.arrowDown);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'Copy speed results',
        );
        await remote(tester, LogicalKeyboardKey.arrowLeft);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'Speed test explanation',
        );
        await remote(tester, LogicalKeyboardKey.arrowDown, 12);
        for (final metric in bounds.keys) {
          expect(
            tester.getRect(find.byKey(ValueKey('tv-speed-$metric'))),
            bounds[metric],
          );
          expect(find.text(metric).hitTestable(), findsOneWidget);
        }
        await remote(tester, LogicalKeyboardKey.arrowRight);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'Speed test action',
        );
        await _screenshot(
          tester,
          'tv-redesign-speed-reading-${partial ? 'error' : 'results'}-${size.width.toInt()}',
        );
        expect(tester.takeException(), isNull);
      });
    }

    _uiTest(
      'TV redesign visual fixed diagnosis explains DNS failures at $size',
      (tester) async {
        final transport = FakeDiagnosticTransport()
          ..failures['dns'] = 'dns_failed';
        await _pumpApp(
          tester,
          store: _MemoryStore(),
          tv: true,
          viewport: size,
          screen: const ConnectionDiagnosisScreen(),
          diagnosis: () => ConnectionDiagnostics(transport),
        );
        final before = tester.getRect(
          find.byKey(const ValueKey('tv-utility-canvas')),
        );
        await remote(tester, LogicalKeyboardKey.select);
        expect(find.text('Run again').hitTestable(), findsOneWidget);
        await remote(tester, LogicalKeyboardKey.arrowUp);
        await remote(tester, LogicalKeyboardKey.arrowDown, 2);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'Diagnosis check: Provider DNS lookup',
        );
        await remote(tester, LogicalKeyboardKey.arrowRight);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'Diagnosis explanation',
        );
        await remote(tester, LogicalKeyboardKey.arrowDown, 2);
        final scroll = tester.state<ScrollableState>(
          find.descendant(
            of: find.byType(TvScrollPane),
            matching: find.byType(Scrollable),
          ),
        );
        expect(scroll.position.pixels, greaterThan(0));
        expect(
          tester.getRect(find.byKey(const ValueKey('tv-utility-canvas'))),
          before,
        );
        expect(find.text('Run again').hitTestable(), findsOneWidget);
        await _screenshot(
          tester,
          'tv-redesign-diagnosis-${size.width.toInt()}',
        );
        await remote(tester, LogicalKeyboardKey.arrowLeft);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'Diagnosis check: Provider DNS lookup',
        );
        await remote(tester, LogicalKeyboardKey.arrowDown, 20);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'Diagnosis action',
        );
        expect(tester.takeException(), isNull);
      },
    );

    _uiTest('TV redesign visual fixed licences scroll their text at $size', (
      tester,
    ) async {
      LicenseRegistry.addLicense(() async* {
        yield LicenseEntryWithLineBreaks(
          ['Sample library'],
          List.filled(
            40,
            'Sample licence paragraph for remote reading and scrolling.',
          ).join('\n\n'),
        );
      });
      await _pumpApp(
        tester,
        store: _MemoryStore(),
        tv: true,
        viewport: size,
        screen: const TvLicencesScreen(),
      );
      expect(find.text('Open source licences').hitTestable(), findsOneWidget);
      final before = tester.getRect(
        find.byKey(const ValueKey('tv-utility-canvas')),
      );
      await remote(tester, LogicalKeyboardKey.arrowRight);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Licence text');
      await remote(tester, LogicalKeyboardKey.arrowDown, 5);
      expect(
        tester.getRect(find.byKey(const ValueKey('tv-utility-canvas'))),
        before,
      );
      await remote(tester, LogicalKeyboardKey.arrowLeft);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        startsWith('Licence: '),
      );
      await _screenshot(tester, 'tv-redesign-licences-${size.width.toInt()}');
      expect(tester.takeException(), isNull);
    });
  }

  _uiTest(
    'TV Settings sections switch without stealing focus and long language menus work',
    (tester) async {
      final store = _MemoryStore();
      await _pumpApp(
        tester,
        store: store,
        tv: true,
        screen: const SettingsScreen(groupIndex: 5),
        viewport: const Size(960, 540),
      );
      await remote(tester, LogicalKeyboardKey.arrowDown, 8);
      await remote(tester, LogicalKeyboardKey.arrowLeft);
      await remote(tester, LogicalKeyboardKey.arrowUp, 4);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Settings section: Audio & subtitles',
      );
      await remote(tester, LogicalKeyboardKey.arrowRight);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Setting: Preferred audio language',
      );
      await remote(tester, LogicalKeyboardKey.select);
      await remote(tester, LogicalKeyboardKey.arrowDown, 11);
      expect(find.text('Dutch').hitTestable(), findsOneWidget);
      await remote(tester, LogicalKeyboardKey.select);
      expect(store.preferences.audioLanguage, 'nl');
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Setting: Preferred audio language',
      );
      expect(tester.takeException(), isNull);
    },
  );

  _uiTest(
    'TV speed test keeps Stop visible while running and cancellation retains metric bounds',
    (tester) async {
      final transport = FakeSpeedTransport()
        ..gate = Completer<SpeedMeasurement>();
      await _pumpApp(
        tester,
        store: _MemoryStore(),
        tv: true,
        screen: const SpeedTestScreen(),
        viewport: const Size(960, 540),
        speed: () => SpeedTestRunner(transport),
      );
      final before = tester.getRect(
        find.byKey(const ValueKey('tv-speed-Download')),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(find.text('Stop test').hitTestable(), findsOneWidget);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Speed test action',
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('tv-speed-Download'))),
        before,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.text('Test stopped').hitTestable(), findsOneWidget);
      expect(transport.closed, true);
      expect(tester.takeException(), isNull);
    },
  );

  for (final signedIn in [false, true]) {
    _uiTest(
      'current launch opens ${signedIn ? 'Home' : 'login'} and resume keeps the check throttle',
      (tester) async {
        final transport = FakeTransport()
          ..next = AppUpdate.parse(jsonEncode(manifest(code: 8)));
        final controller = UpdateController(
          FakePlatform()..checked = DateTime.now(),
          transport,
        );
        await _pumpApp(
          tester,
          store: _MemoryStore(),
          tv: true,
          signedIn: signedIn,
          startupUpdates: true,
          updater: controller,
        );
        expect(transport.checks, 1);
        expect(controller.stage, UpdateStage.current);
        expect(find.text('Checking for updates'), findsNothing);
        expect(find.text(signedIn ? 'Home' : 'Username'), findsOneWidget);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(transport.checks, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  _uiTest('TV parental PIN creation uses the built-in numeric keypad', (
    tester,
  ) async {
    final store = _MemoryStore();
    await _pumpApp(
      tester,
      store: store,
      tv: true,
      screen: const SettingsScreen(groupIndex: 3),
      viewport: const Size(960, 540),
    );
    await remote(tester, LogicalKeyboardKey.arrowDown, 2);
    await remote(tester, LogicalKeyboardKey.select);
    for (var entry = 0; entry < 2; entry++) {
      expect(
        tester
            .widget<TvTextEntryDialog>(find.byType(TvTextEntryDialog))
            .numericOnly,
        isTrue,
      );
      for (final position in [(0, 0), (0, 1), (0, 2), (1, 0)]) {
        await keyboardKey(tester, position.$1, position.$2);
      }
      await keyboardKey(tester, 4, 2);
    }
    expect(store.parentalPin, '1234');
    expect(tester.testTextInput.isVisible, isFalse);
    expect(find.text('Change parental PIN').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  _uiTest(
    'TV protected Settings unlock through the numeric keypad without an IME',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final store = _MemoryStore()..parentalPin = '1234';
      await _pumpApp(
        tester,
        store: store,
        tv: true,
        screen: const SettingsScreen(groupIndex: 4),
        viewport: const Size(960, 540),
      );
      expect(find.text('Settings are protected'), findsOneWidget);
      expect(find.text('viewer'), findsNothing);
      await remote(tester, LogicalKeyboardKey.select);
      expect(find.text('Press OK to enter PIN'), findsOneWidget);
      await remote(tester, LogicalKeyboardKey.select);
      for (final position in [(0, 0), (0, 1), (0, 2), (1, 0)]) {
        await keyboardKey(tester, position.$1, position.$2);
      }
      await keyboardKey(tester, 4, 2);
      expect(find.byType(TvUtilityScaffold), findsOneWidget);
      expect(find.text('viewer'), findsWidgets);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

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
    expect(find.text('Recently added'), findsOneWidget);
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
        if (kind != MediaKind.live) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pumpAndSettle();
          expect(
            FocusManager.instance.primaryFocus?.debugLabel,
            'Featured title',
          );
          _cardFocus(tester, find.text('Browse all')).requestFocus();
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(LogicalKeyboardKey.select);
        } else {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        }
        await tester.pumpAndSettle();
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          kind == MediaKind.live ? 'Category: All channels' : 'Category: All',
        );
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
