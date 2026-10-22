import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streamline_iptv/core/providers.dart';
import 'package:streamline_iptv/core/playback_handle.dart';
import 'package:streamline_iptv/core/player_tracks.dart';
import 'package:video_player/video_player.dart';
import 'package:streamline_iptv/data/local_store.dart';
import 'package:streamline_iptv/data/models.dart';
import 'package:streamline_iptv/data/app_settings.dart';
import 'package:streamline_iptv/features/player_screen.dart';
import 'package:streamline_iptv/features/connection_diagnosis_screen.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

const _session = Session(
  credentials: Credentials(
    serverUrl: 'https://provider.example',
    username: 'viewer',
    password: 'test-password',
  ),
  userInfo: {},
  serverInfo: {},
);
const _movie = MediaItem(id: '42', name: 'Test movie', kind: MediaKind.movie);
const _firstChannel = MediaItem(
  id: '101',
  name: 'First channel',
  kind: MediaKind.live,
  containerExtension: 'm3u8',
);
const _secondChannel = MediaItem(
  id: '102',
  name: 'Second channel',
  kind: MediaKind.live,
  containerExtension: 'm3u8',
);
const _thirdChannel = MediaItem(
  id: '103',
  name: 'Third channel',
  kind: MediaKind.live,
  containerExtension: 'm3u8',
);
const _duration = Duration(minutes: 10);

class _SavedPosition {
  const _SavedPosition(
    this.accountId,
    this.item,
    this.positionMs,
    this.durationMs,
  );

  final String accountId;
  final MediaItem item;
  final int positionMs;
  final int durationMs;
}

class _HistoryStore implements LocalStore {
  AppSettings preferences = const AppSettings();
  @override
  Future<AppSettings> readSettings(String accountId) async => preferences;
  @override
  Future<void> saveSettings(String accountId, AppSettings settings) async {
    preferences = settings;
  }

  @override
  Future<bool> hasPin(String accountId) async => pinExists;
  bool pinExists = false;
  final episodeSaves = <(String, String, int)>[];
  @override
  Future<List<EpisodeWatchEntry>> seriesHistory(String accountId) async => [];
  @override
  Future<void> saveEpisodeProgress(
    String accountId,
    MediaItem item,
    Episode episode, {
    required int positionMs,
    required int durationMs,
    Episode? nextEpisode,
  }) async {
    episodeSaves.add((item.id, episode.id, positionMs));
  }

  final opened = <MediaItem>[];
  final saved = <_SavedPosition>[];
  final channelPlays = <MediaItem>[];
  final channelWriteAttempts = <MediaItem>[];
  final channelAccounts = <String>[];
  bool failChannelWrites = false;
  Completer<void>? channelWriteGate;
  Completer<void>? saveGate;

  @override
  Future<void> recordOpened(String accountId, MediaItem item) async {
    opened.add(item);
  }

  @override
  Future<void> saveProgress(
    String accountId,
    MediaItem item, {
    required int positionMs,
    required int durationMs,
  }) async {
    saved.add(_SavedPosition(accountId, item, positionMs, durationMs));
    await saveGate?.future;
  }

  @override
  Future<List<WatchEntry>> history(String accountId) async => [];

  @override
  Future<void> recordChannelPlayed(String accountId, MediaItem item) async {
    if (failChannelWrites) throw StateError('Database unavailable');
    channelWriteAttempts.add(item);
    await channelWriteGate?.future;
    channelPlays.add(item);
    channelAccounts.add(accountId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _VideoPlatform extends VideoPlayerPlatform {
  final sources = <int, DataSource>{};
  final events = <int, StreamController<VideoEvent>>{};
  final positions = <int, Duration>{};
  final calls = <String>[];
  final disposed = <int>[];
  Completer<void>? creationGate;
  int _nextId = 0;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = ++_nextId;
    sources[id] = options.dataSource;
    // Supply a cancellation future in the widget test's zone. A broadcast
    // controller returns Dart's shared root-zone null future on cancellation,
    // whose continuation cannot be drained by the fake clock's microtasks.
    events[id] = StreamController<VideoEvent>(
      sync: true,
      onCancel: () async {},
    );
    // Allocate done before cancellation as well: close() would otherwise
    // return the shared root-zone null future once its subscriber is gone.
    unawaited(events[id]!.done);
    positions[id] = Duration.zero;
    await creationGate?.future;
    return id;
  }

  void initialize(int id) {
    final controller = events[id]!;
    if (!controller.isClosed) {
      controller.add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: _duration,
          size: const Size(1920, 1080),
        ),
      );
    }
  }

  void failInitialization(int id) {
    events[id]!.addError(
      PlatformException(
        code: 'VideoError',
        message: 'Test initialization failure',
      ),
    );
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => events[playerId]!.stream;

  @override
  Future<void> dispose(int playerId) async {
    disposed.add(playerId);
    await events[playerId]?.close();
  }

  @override
  Future<void> play(int playerId) async => calls.add('play:$playerId');

  @override
  Future<void> pause(int playerId) async => calls.add('pause:$playerId');

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    calls.add('seek:$playerId:${position.inMilliseconds}');
    positions[playerId] = position;
  }

  @override
  Future<Duration> getPosition(int playerId) async => positions[playerId]!;

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      SizedBox.expand(key: ValueKey('video-${options.playerId}'));

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Future<void> setAllowBackgroundPlayback(bool allowBackgroundPlayback) async {}

  Future<void> close() async {
    for (final controller in events.values) {
      if (!controller.isClosed) await controller.close();
    }
  }
}

class _FakeCompatibility extends PlaybackHandle {
  final calls = <String>[];
  @override
  Future<void> initialize() async {
    value = const VideoPlayerValue(
      duration: _duration,
      size: Size(1920, 1080),
      isInitialized: true,
    );
  }

  @override
  Future<void> play() async {
    calls.add('play');
    value = value.copyWith(isPlaying: true);
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    value = value.copyWith(isPlaying: false);
  }

  @override
  Future<void> seekTo(Duration position) async {
    calls.add('seek:${position.inMilliseconds}');
    value = value.copyWith(position: position);
  }

  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> attachTracks(
    PlayerTracks bridge,
    AppSettings preferences,
  ) async {}
  @override
  Widget buildView() => const ColoredBox(color: Colors.black);
}

Future<void> _mountPlayer(
  WidgetTester tester,
  _HistoryStore store, {
  Duration startPosition = Duration.zero,
  MediaItem item = _movie,
  List<MediaItem> channels = const [],
  Episode? episode,
  List<Episode> episodes = const [],
  PlaybackFactory? factory,
}) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  addTearDown(() async {
    // Cancel player timers before the fake platform is restored.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    if (store.saveGate != null && !store.saveGate!.isCompleted) {
      store.saveGate!.complete();
    }
    if (store.channelWriteGate != null &&
        !store.channelWriteGate!.isCompleted) {
      store.channelWriteGate!.complete();
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storeProvider.overrideWithValue(store),
        if (factory != null) playbackFactoryProvider.overrideWithValue(factory),
        sessionProvider.overrideWith((ref) => _session),
        isTvProvider.overrideWithValue(false),
        epgProvider.overrideWith((ref, id) async => []),
      ],
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => PlayerScreen(
                        item: item,
                        startPosition: startPosition,
                        channels: channels,
                        episode: episode,
                        episodes: episodes,
                      ),
                    ),
                  ),
                  child: const Text('Open player'),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open player'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> _finishInitialization(
  WidgetTester tester,
  _VideoPlatform platform,
) async {
  platform.initialize(platform.sources.keys.last);
  await tester.pump();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late VideoPlayerPlatform originalPlatform;
  late _VideoPlatform platform;
  late _HistoryStore store;
  late List<bool> screenAwake;

  setUp(() {
    originalPlatform = VideoPlayerPlatform.instance;
    platform = _VideoPlatform();
    store = _HistoryStore();
    screenAwake = [];
    VideoPlayerPlatform.instance = platform;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('streamline/player_tracks'),
          (_) async => throw MissingPluginException(),
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('streamline/platform'), (
          call,
        ) async {
          if (call.method == 'setKeepScreenOn') {
            screenAwake.add(call.arguments as bool);
          }
          return null;
        });
  });

  tearDown(() async {
    if (platform.creationGate != null && !platform.creationGate!.isCompleted) {
      platform.creationGate!.complete();
    }
    await platform.close();
    VideoPlayerPlatform.instance = originalPlatform;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('streamline/player_tracks'),
          null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('streamline/platform'),
          null,
        );
  });

  testWidgets(
    'series resumes and saves the correct episode before advancing across seasons',
    (tester) async {
      const series = MediaItem(id: 's', name: 'Series', kind: MediaKind.series);
      const first = Episode(
        id: 'e1',
        title: 'First',
        season: '1',
        episodeNumber: 1,
      );
      const second = Episode(
        id: 'e2',
        title: 'Second',
        season: '2',
        episodeNumber: 1,
      );
      await _mountPlayer(
        tester,
        store,
        item: series,
        episode: first,
        episodes: [first, second],
        startPosition: const Duration(seconds: 45),
      );
      await _finishInitialization(tester, platform);
      expect(
        platform.calls.indexOf('seek:1:45000'),
        lessThan(platform.calls.indexOf('play:1')),
      );
      platform.positions[1] = _duration;
      platform.events[1]!.add(VideoEvent(eventType: VideoEventType.completed));
      await tester.pump();
      expect(find.text('Next episode in 8'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pump(const Duration(seconds: 9));
      expect(platform.sources.length, 1);
      await tester.tap(find.text('Next episode'));
      await tester.pump();
      await tester.pump();
      expect(platform.sources.values.last.uri, contains('/e2.mp4'));
      expect(
        store.episodeSaves.any(
          (entry) => entry.$2 == 'e1' && entry.$3 == _duration.inMilliseconds,
        ),
        true,
      );
      await _finishInitialization(tester, platform);
      expect(find.text('Second'), findsOneWidget);
      expect(store.opened, isEmpty);
    },
  );

  testWidgets(
    'completed series automatically advances once after eight seconds',
    (tester) async {
      const series = MediaItem(id: 's', name: 'Series', kind: MediaKind.series);
      const first = Episode(
        id: 'e1',
        title: 'First',
        season: '1',
        episodeNumber: 1,
      );
      const second = Episode(
        id: 'e2',
        title: 'Second',
        season: '1',
        episodeNumber: 2,
      );
      await _mountPlayer(
        tester,
        store,
        item: series,
        episode: first,
        episodes: [first, second],
      );
      await _finishInitialization(tester, platform);
      platform.positions[1] = _duration;
      platform.events[1]!.add(VideoEvent(eventType: VideoEventType.completed));
      await tester.pump();
      await tester.pump(const Duration(seconds: 8));
      await tester.pump();
      expect(platform.sources.length, 2);
      expect(platform.sources.values.last.uri, contains('/e2.mp4'));
      await _finishInitialization(tester, platform);
      expect(find.text('Next episode'), findsNothing);
    },
  );

  testWidgets(
    'reconnection stops after three attempts and backgrounding cancels it',
    (tester) async {
      await _mountPlayer(tester, store);
      for (var attempt = 0; attempt < 4; attempt++) {
        platform.failInitialization(platform.sources.keys.last);
        await tester.pump();
        await tester.pump();
        await tester.pump(Duration(seconds: 2 << attempt));
        await tester.pump();
      }
      expect(platform.sources.length, 4);
      await tester.pump(const Duration(seconds: 40));
      expect(platform.sources.length, 4);
      await tester.tap(find.text('Try again'));
      await tester.pump();
      platform.failInitialization(platform.sources.keys.last);
      await tester.pump();
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 10));
      expect(platform.sources.length, 5);
    },
  );

  testWidgets(
    'picture modes and unavailable audio remain usable without a native track bridge',
    (tester) async {
      await _mountPlayer(tester, store);
      await _finishInitialization(tester, platform);
      await tester.tap(find.text('Picture: Fit'));
      await tester.pump();
      expect(find.text('Picture: Fill'), findsOneWidget);
      await tester.tap(find.text('Audio'));
      await tester.pumpAndSettle();
      expect(
        find.text('Track selection is unavailable for this player.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(platform.calls, contains('play:1'));
    },
  );

  testWidgets(
    'native audio and subtitle menus select supplied tracks and render captions',
    (tester) async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final selections = <String>[];
      Map<String, dynamic> snapshot({String caption = ''}) => {
        'tracks': [
          {
            'key': '0:0',
            'type': 'audio',
            'label': 'English',
            'selected': true,
            'supported': true,
          },
          {
            'key': '1:0',
            'type': 'text',
            'label': 'Spanish',
            'selected': false,
            'supported': true,
          },
        ],
        'caption': caption,
        'textOff': caption.isEmpty,
        'audioAuto': true,
      };
      messenger.setMockMethodCallHandler(
        const MethodChannel('streamline/player_tracks'),
        (call) async {
          if (call.method == 'select') {
            selections.add(
              '${call.arguments['type']}:${call.arguments['key']}',
            );
            return snapshot(caption: 'Provider caption');
          }
          return snapshot();
        },
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('streamline/player_tracks/events'),
        (call) async => null,
      );
      addTearDown(() {
        messenger.setMockMethodCallHandler(
          const MethodChannel('streamline/player_tracks'),
          null,
        );
        messenger.setMockMethodCallHandler(
          const MethodChannel('streamline/player_tracks/events'),
          null,
        );
      });
      await _mountPlayer(tester, store);
      await _finishInitialization(tester, platform);
      await tester.tap(find.text('Audio'));
      await tester.pumpAndSettle();
      expect(find.text('Automatic'), findsOneWidget);
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      expect(selections, ['audio:0:0']);
      expect(find.text('Provider caption'), findsOneWidget);
      await tester.tap(find.text('Subtitles'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Spanish'));
      await tester.pumpAndSettle();
      expect(selections.last, 'text:1:0');
    },
  );

  testWidgets(
    'reconnection restores the last playing movie position before play',
    (tester) async {
      await _mountPlayer(tester, store);
      await _finishInitialization(tester, platform);
      platform.positions[1] = const Duration(minutes: 3);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      platform.failInitialization(1);
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(platform.sources.length, 2);
      await _finishInitialization(tester, platform);
      expect(
        platform.calls.indexOf('seek:2:180000'),
        lessThan(platform.calls.indexOf('play:2')),
      );
      expect(platform.positions[2], const Duration(minutes: 3));
    },
  );

  testWidgets(
    'playing hides all chrome after five seconds and OK reveals without pausing',
    (tester) async {
      await _mountPlayer(tester, store);
      await _finishInitialization(tester, platform);
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 250));
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.byKey(const ValueKey('player-chrome')),
            )
            .opacity,
        0,
      );
      expect(
        tester
            .widget<AnimatedOpacity>(find.byKey(const ValueKey('player-scrim')))
            .opacity,
        0,
      );
      expect(find.text('Pause').hitTestable(), findsNothing);
      final pauses = platform.calls.where((call) => call == 'pause:1').length;
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.byKey(const ValueKey('player-chrome')),
            )
            .opacity,
        1,
      );
      expect(platform.calls.where((call) => call == 'pause:1').length, pauses);
    },
  );

  testWidgets(
    'controls stay visible for pause and menus then respect the saved timeout',
    (tester) async {
      store.preferences = const AppSettings(controlsSeconds: 3);
      await _mountPlayer(tester, store);
      await _finishInitialization(tester, platform);
      await tester.tap(find.text('Audio'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 10));
      expect(
        find.text('Track selection is unavailable for this player.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pause'));
      await tester.pump(const Duration(seconds: 10));
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.byKey(const ValueKey('player-chrome')),
            )
            .opacity,
        1,
      );
      await tester.tap(find.text('Play'));
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 250));
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.byKey(const ValueKey('player-chrome')),
            )
            .opacity,
        0,
      );
    },
  );

  testWidgets('never-hide preference and disabled reconnect are applied', (
    tester,
  ) async {
    store.preferences = const AppSettings(controlsSeconds: 0, reconnect: false);
    await _mountPlayer(tester, store);
    await _finishInitialization(tester, platform);
    await tester.pump(const Duration(seconds: 15));
    expect(
      tester
          .widget<AnimatedOpacity>(find.byKey(const ValueKey('player-chrome')))
          .opacity,
      1,
    );
    platform.failInitialization(1);
    await tester.pump();
    await tester.pump(const Duration(seconds: 20));
    expect(platform.sources.length, 1);
    expect(find.text('Cancel reconnect (1/3)'), findsNothing);
  });

  testWidgets('Back hides controls before leaving a playing stream', (
    tester,
  ) async {
    await _mountPlayer(tester, store);
    await _finishInitialization(tester, platform);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byType(PlayerScreen), findsOneWidget);
    expect(
      tester
          .widget<AnimatedOpacity>(find.byKey(const ValueKey('player-chrome')))
          .opacity,
      0,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(PlayerScreen), findsNothing);
  });

  testWidgets('disabled next-episode autoplay still permits manual next', (
    tester,
  ) async {
    store.preferences = const AppSettings(autoNext: false);
    const series = MediaItem(id: 's', name: 'Series', kind: MediaKind.series);
    const first = Episode(
      id: 'e1',
      title: 'First',
      season: '1',
      episodeNumber: 1,
    );
    const next = Episode(
      id: 'e2',
      title: 'Second',
      season: '1',
      episodeNumber: 2,
    );
    await _mountPlayer(
      tester,
      store,
      item: series,
      episode: first,
      episodes: [first, next],
    );
    await _finishInitialization(tester, platform);
    platform.positions[1] = _duration;
    platform.events[1]!.add(VideoEvent(eventType: VideoEventType.completed));
    await tester.pump(const Duration(seconds: 10));
    expect(platform.sources.length, 1);
    expect(find.textContaining('Next episode in'), findsNothing);
    await tester.tap(find.text('Next episode'));
    await tester.pump();
    await tester.pump();
    expect(platform.sources.length, 2);
    await _finishInitialization(tester, platform);
  });

  testWidgets(
    'compatibility preference uses shared resume, controls and history',
    (tester) async {
      store.preferences = const AppSettings(engine: PlayerEngine.compatibility);
      final handle = _FakeCompatibility();
      final engines = <PlayerEngine>[];
      await _mountPlayer(
        tester,
        store,
        startPosition: const Duration(minutes: 2),
        factory: (uri, engine) {
          engines.add(engine);
          return handle;
        },
      );
      await tester.pump();
      expect(engines, [PlayerEngine.compatibility]);
      expect(
        handle.calls.indexOf('seek:120000'),
        lessThan(handle.calls.indexOf('play')),
      );
      await tester.tap(find.text('Pause'));
      await tester.pump();
      expect(store.saved.last.positionMs, 120000);
      expect(find.text('Play'), findsOneWidget);
    },
  );

  testWidgets('direct protected playback cannot start without unlocking', (
    tester,
  ) async {
    store.pinExists = true;
    store.preferences = const AppSettings(lockedCategories: {'movie:'});
    await _mountPlayer(tester, store);
    expect(find.text('Unlock this category'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(platform.sources, isEmpty);
    expect(store.opened, isEmpty);
    expect(
      find.text(
        'This category is hidden or protected. Unlock it before playing.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('resumes before playing and saves progress when paused', (
    tester,
  ) async {
    await _mountPlayer(
      tester,
      store,
      startPosition: const Duration(seconds: 90),
    );
    await _finishInitialization(tester, platform);
    final id = platform.sources.keys.single;
    expect(platform.calls.indexOf('seek:$id:90000'), greaterThanOrEqualTo(0));
    expect(
      platform.calls.indexOf('seek:$id:90000'),
      lessThan(platform.calls.indexOf('play:$id')),
    );
    expect(store.opened, [_movie]);
    expect(screenAwake, [true]);

    platform.positions[id] = const Duration(minutes: 3);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();

    expect(store.saved.last.accountId, _session.accountId);
    expect(store.saved.last.item, _movie);
    expect(store.saved.last.positionMs, 180000);
    expect(store.saved.last.durationMs, _duration.inMilliseconds);
  });

  testWidgets('pauses and flushes progress when the application is paused', (
    tester,
  ) async {
    await _mountPlayer(tester, store);
    await _finishInitialization(tester, platform);
    final id = platform.sources.keys.single;
    platform.positions[id] = const Duration(minutes: 2);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    final previousPauses = platform.calls
        .where((call) => call == 'pause:$id')
        .length;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(
      platform.calls.where((call) => call == 'pause:$id').length,
      greaterThan(previousPauses),
    );
    expect(store.saved.last.positionMs, 120000);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
  });

  testWidgets(
    'Back waits for the final history write before removing the route',
    (tester) async {
      await _mountPlayer(tester, store);
      await _finishInitialization(tester, platform);
      final id = platform.sources.keys.single;
      platform.positions[id] = const Duration(minutes: 4);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump();
      store.saveGate = Completer<void>();

      await tester.tap(find.byTooltip('Back'));
      await tester.pump();

      expect(store.saved.last.positionMs, 240000);
      expect(find.byType(PlayerScreen), findsOneWidget);
      store.saveGate!.complete();
      await tester.pump();
      // An outgoing route can already be offstage while its State is still
      // awaiting removal at the end of the reverse transition.
      await tester.pumpAndSettle();
      await tester.pump();

      expect(find.byType(PlayerScreen), findsNothing);
      expect(find.text('Open player'), findsOneWidget);
      expect(platform.disposed, contains(id));
      expect(screenAwake, [true, false]);
    },
  );

  testWidgets(
    'Back during pending native creation exits without starting playback',
    (tester) async {
      platform.creationGate = Completer<void>();
      await _mountPlayer(tester, store);
      final id = platform.sources.keys.single;

      await tester.tap(find.byTooltip('Back'));
      await tester.pump();
      await tester.pumpAndSettle();
      await tester.pump();
      expect(find.byType(PlayerScreen), findsNothing);

      platform.creationGate!.complete();
      await tester.pump();
      await tester.pump();
      expect(platform.calls.where((call) => call.startsWith('play:')), isEmpty);
      expect(platform.disposed, contains(id));
      expect(store.saved, isEmpty);
    },
  );

  testWidgets('initialization completing in the background does not autoplay', (
    tester,
  ) async {
    await _mountPlayer(tester, store);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await _finishInitialization(tester, platform);

    expect(platform.calls.where((call) => call.startsWith('play:')), isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(platform.calls.where((call) => call.startsWith('play:')), isEmpty);
  });

  testWidgets('records only successfully played live channels when zapping', (
    tester,
  ) async {
    await _mountPlayer(
      tester,
      store,
      item: _firstChannel,
      channels: const [_firstChannel, _secondChannel],
    );
    expect(store.channelPlays, isEmpty);
    await _finishInitialization(tester, platform);
    expect(store.channelPlays, [_firstChannel]);
    expect(store.channelAccounts, [_session.accountId]);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.pump();
    expect(platform.sources, hasLength(2));
    expect(store.channelPlays, [_firstChannel]);
    await _finishInitialization(tester, platform);
    expect(store.channelPlays, [_firstChannel, _secondChannel]);
    expect(store.channelAccounts, [_session.accountId, _session.accountId]);

    // Pausing/resuming the same native player is not another channel visit.
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump();
    expect(store.channelPlays, [_firstChannel, _secondChannel]);
    expect(store.opened, isEmpty);
    expect(store.saved, isEmpty);
  });

  testWidgets(
    'connection diagnosis releases the failed player before opening and keeps stream opt-in off',
    (tester) async {
      await _mountPlayer(tester, store);
      platform.failInitialization(platform.sources.keys.single);
      await tester.pump();
      await tester.pump();
      await tester.ensureVisible(find.text('Connection diagnosis'));
      await tester.tap(find.text('Connection diagnosis'));
      await tester.pumpAndSettle();
      expect(platform.disposed, contains(1));
      expect(find.byType(PlayerScreen), findsNothing);
      expect(find.byType(ConnectionDiagnosisScreen), findsOneWidget);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        false,
      );
      await tester.pump(const Duration(seconds: 10));
      expect(platform.sources.length, 1);
    },
  );

  testWidgets('failed live initialization is not added to recent channels', (
    tester,
  ) async {
    await _mountPlayer(tester, store, item: _firstChannel);
    final failedId = platform.sources.keys.single;
    platform.failInitialization(failedId);
    await tester.pump();
    await tester.pump();

    expect(store.channelPlays, isEmpty);
    expect(platform.calls.where((call) => call.startsWith('play:')), isEmpty);
    expect(find.text('Try again'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump();
    await _finishInitialization(tester, platform);
    expect(store.channelPlays, [_firstChannel]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('live playback continues when recent-channel storage fails', (
    tester,
  ) async {
    store.failChannelWrites = true;
    await _mountPlayer(tester, store, item: _firstChannel);
    await _finishInitialization(tester, platform);

    expect(find.byIcon(Icons.pause), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
    expect(find.text('Playback progress could not be saved.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('background live initialization waits for first play to record', (
    tester,
  ) async {
    await _mountPlayer(tester, store, item: _firstChannel);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await _finishInitialization(tester, platform);
    expect(store.channelPlays, isEmpty);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump();
    expect(store.channelPlays, [_firstChannel]);
  });

  testWidgets('an obsolete account does not receive a new recent channel', (
    tester,
  ) async {
    await _mountPlayer(tester, store, item: _firstChannel);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PlayerScreen)),
    );
    container.read(sessionProvider.notifier).state = null;
    await _finishInitialization(tester, platform);

    expect(store.channelPlays, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('queued live visits survive later zapping and leaving playback', (
    tester,
  ) async {
    store.channelWriteGate = Completer<void>();
    await _mountPlayer(
      tester,
      store,
      item: _firstChannel,
      channels: const [_firstChannel, _secondChannel, _thirdChannel],
    );
    await _finishInitialization(tester, platform);
    expect(store.channelWriteAttempts, [_firstChannel]);
    expect(store.channelPlays, isEmpty);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.pump();
    await _finishInitialization(tester, platform);
    // Zapping uses DateTime.now rather than the test scheduler's fake clock.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 275)),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.pump();
    await _finishInitialization(tester, platform);
    expect(platform.sources, hasLength(3));
    expect(store.channelWriteAttempts, [_firstChannel]);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(PlayerScreen), findsNothing);
    store.channelWriteGate!.complete();
    await tester.pump();
    await tester.pump();

    expect(store.channelPlays, [_firstChannel, _secondChannel, _thirdChannel]);
    expect(store.channelAccounts, List.filled(3, _session.accountId));
    expect(tester.takeException(), isNull);
  });
}
