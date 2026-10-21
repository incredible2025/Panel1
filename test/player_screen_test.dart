import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streamline_iptv/core/providers.dart';
import 'package:streamline_iptv/data/local_store.dart';
import 'package:streamline_iptv/data/models.dart';
import 'package:streamline_iptv/features/player_screen.dart';
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
  final opened = <MediaItem>[];
  final saved = <_SavedPosition>[];
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

Future<void> _mountPlayer(
  WidgetTester tester,
  _HistoryStore store, {
  Duration startPosition = Duration.zero,
}) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  addTearDown(() async {
    // Cancel player timers before the fake platform is restored.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    if (store.saveGate != null && !store.saveGate!.isCompleted) {
      store.saveGate!.complete();
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storeProvider.overrideWithValue(store),
        sessionProvider.overrideWith((ref) => _session),
        isTvProvider.overrideWithValue(false),
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
                        item: _movie,
                        startPosition: startPosition,
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
  platform.initialize(platform.sources.keys.single);
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
          const MethodChannel('streamline/platform'),
          null,
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
}
