import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:streamline_iptv/core/playback_handle.dart';
import 'package:streamline_iptv/core/player_tracks.dart';
import 'package:streamline_iptv/core/providers.dart';
import 'package:streamline_iptv/data/app_settings.dart';
import 'package:streamline_iptv/data/local_store.dart';
import 'package:streamline_iptv/data/models.dart';
import 'package:streamline_iptv/data/xtream_api.dart';
import 'package:streamline_iptv/widgets/live_channel_preview.dart';

class _Store implements LocalStore {
  @override
  Future<AppSettings> readSettings(String accountId) async =>
      const AppSettings();
  @override
  Future<bool> hasPin(String accountId) async => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PreviewHandle extends PlaybackHandle {
  final events = <String>[];
  Completer<void>? opening, closing;
  bool failOpening = false;
  bool dead = false;
  @override
  Future<void> initialize() async {
    await opening?.future;
    if (failOpening) throw StateError('Preview unavailable');
    if (!dead) {
      value = const VideoPlayerValue(
        duration: Duration.zero,
        isInitialized: true,
        size: Size(1920, 1080),
      );
    }
  }

  @override
  Future<void> play() async {
    events.add('play');
    value = value.copyWith(isPlaying: true);
  }

  @override
  Future<void> pause() async {}
  @override
  Future<void> seekTo(Duration position) async {}
  @override
  Future<void> setVolume(double volume) async {
    events.add('volume:$volume');
  }

  @override
  Future<void> attachTracks(
    PlayerTracks bridge,
    AppSettings preferences,
  ) async {}
  @override
  Widget buildView() => const ColoredBox(color: Colors.black);
  @override
  Future<void> dispose() async {
    if (dead) return;
    dead = true;
    events.add('closing');
    await closing?.future;
    events.add('closed');
    await super.dispose();
  }
}

class _PreparedPreviewApi extends XtreamApi {
  int preparations = 0;
  @override
  Future<Uri> prepareStreamUri(
    Session session,
    MediaItem item, {
    Episode? episode,
  }) async {
    preparations++;
    return Uri.parse('https://playback.example/prepared.ts');
  }
}

void main() {
  const session = Session(
    credentials: Credentials(
      serverUrl: 'https://example.com',
      username: 'viewer',
      password: 'secret',
    ),
    userInfo: {},
    serverInfo: {},
  );
  const channel = MediaItem(id: '1', name: 'News', kind: MediaKind.live);
  Future<void> mount(
    WidgetTester tester,
    _PreviewHandle handle,
    GlobalKey<LiveChannelPreviewState> key,
    VoidCallback watch, {
    XtreamApi? api,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storeProvider.overrideWithValue(_Store()),
          if (api != null) apiProvider.overrideWithValue(api),
          sessionProvider.overrideWith((ref) => session),
          playbackFactoryProvider.overrideWithValue((uri, engine) => handle),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 430,
              child: LiveChannelPreview(
                key: key,
                item: channel,
                programme: null,
                onWatch: watch,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }

  testWidgets(
    'preview is muted and releases its stream before full-screen playback starts',
    (tester) async {
      final handle = _PreviewHandle();
      final key = GlobalKey<LiveChannelPreviewState>();
      var fullscreen = false;
      await mount(tester, handle, key, () async {
        await key.currentState!.stop();
        fullscreen = true;
      });
      await tester.tap(find.text('Preview'));
      await tester.pumpAndSettle();
      expect(handle.events, ['volume:0.0', 'play']);
      handle.closing = Completer<void>();
      await tester.tap(find.text('Watch channel'));
      await tester.pump();
      expect(fullscreen, false);
      handle.closing!.complete();
      await tester.pumpAndSettle();
      expect(handle.events.last, 'closed');
      expect(fullscreen, true);
    },
  );
  testWidgets(
    'cancelling a pending preview cannot start playback behind a new route',
    (tester) async {
      final handle = _PreviewHandle()..opening = Completer<void>();
      final key = GlobalKey<LiveChannelPreviewState>();
      await mount(tester, handle, key, () => key.currentState!.stop());
      await tester.tap(find.text('Preview'));
      await tester.pump();
      await tester.tap(find.text('Watch channel'));
      await tester.pump();
      handle.opening!.complete();
      await tester.pumpAndSettle();
      expect(handle.events, isNot(contains('play')));
      expect(handle.dead, true);
    },
  );
  testWidgets(
    'failed preview starts disposal without waiting for its closing future',
    (tester) async {
      final handle = _PreviewHandle()
        ..failOpening = true
        ..closing = Completer<void>();
      final key = GlobalKey<LiveChannelPreviewState>();
      await mount(tester, handle, key, () {});
      await tester.tap(find.text('Preview'));
      await tester.pump();
      expect(handle.events, ['closing']);
      expect(handle.dead, isTrue);
      expect(
        find.text('Preview unavailable. You can still open the channel.'),
        findsOneWidget,
      );
      handle.closing!.complete();
      await tester.pumpAndSettle();
      expect(handle.events.last, 'closed');
    },
  );
  testWidgets('preview uses shared connection preparation', (tester) async {
    final api = _PreparedPreviewApi();
    addTearDown(api.dispose);
    final handle = _PreviewHandle();
    await mount(
      tester,
      handle,
      GlobalKey<LiveChannelPreviewState>(),
      () {},
      api: api,
    );
    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();
    expect(api.preparations, 1);
    expect(handle.events, contains('play'));
  });

  testWidgets(
    'stuck preview times out, releases and cannot play after late initialization',
    (tester) async {
      final handle = _PreviewHandle()..opening = Completer<void>();
      await mount(tester, handle, GlobalKey<LiveChannelPreviewState>(), () {});
      await tester.tap(find.text('Preview'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 26));
      await tester.pumpAndSettle();
      expect(handle.dead, isTrue);
      expect(
        find.text('Preview unavailable. You can still open the channel.'),
        findsOneWidget,
      );
      handle.opening!.complete();
      await tester.pumpAndSettle();
      expect(handle.events, isNot(contains('play')));
    },
  );
}
