import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streamline_iptv/core/playback_handle.dart';
import 'package:streamline_iptv/core/providers.dart';
import 'package:streamline_iptv/core/settings_controller.dart';
import 'package:streamline_iptv/data/app_settings.dart';
import 'package:streamline_iptv/data/local_store.dart';
import 'package:streamline_iptv/widgets/tv_app_exit.dart';

class _Player extends PlaybackHandle {
  _Player(this.gate);
  final Completer<void> gate;
  bool closing = false;
  Future<void>? _release;
  @override
  Future<void> dispose() => _release ??= () async {
    closing = true;
    await gate.future;
    await super.dispose();
  }();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Store implements LocalStore {
  final write = Completer<void>();
  @override
  Future<AppSettings> readSettings(String accountId) async =>
      const AppSettings();
  @override
  Future<void> saveSettings(String accountId, AppSettings settings) =>
      write.future;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Future<void> mount(
    WidgetTester tester, {
    required PlaybackRegistry players,
    required Future<void> Function() exit,
    SettingsController? settings,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isTvProvider.overrideWithValue(true),
          managedConfigurationProvider.overrideWithValue(null),
          playbackRegistryProvider.overrideWithValue(players),
          tvPlatformExitProvider.overrideWithValue(exit),
          settingsProvider.overrideWith(
            (ref) => settings ?? SettingsController(null, null),
          ),
        ],
        child: const MaterialApp(
          home: TvExitOnBack(child: Scaffold(body: Text('TV home'))),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Back opens one remote-friendly confirmation; cancelling keeps players',
    (tester) async {
      final players = PlaybackRegistry();
      final player = _Player(Completer<void>());
      players.track(player);
      var exits = 0;
      await mount(tester, players: players, exit: () async => exits++);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(FocusManager.instance.primaryFocus?.context?.widget, isNotNull);
      // The safe default is Stay; remote OK must cancel without closing streams.
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(player.closing, isFalse);
      expect(exits, 0);
      player.gate.complete();
      await player.dispose();
    },
  );

  testWidgets(
    'exit waits for native stream teardown and pending preference writes',
    (tester) async {
      final players = PlaybackRegistry();
      final gate = Completer<void>();
      final player = _Player(gate);
      players.track(player);
      final store = _Store();
      final settings = SettingsController(store, 'account');
      await settings.ready;
      final saving = settings.patch({'controlsSeconds': 8});
      var exits = 0;
      await mount(
        tester,
        players: players,
        settings: settings,
        exit: () async => exits++,
      );
      await tester.tap(find.text('Exit app'));
      await tester.pump();
      expect(player.closing, isTrue);
      expect(exits, 0);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(AlertDialog), findsOneWidget);
      gate.complete();
      await tester.pump();
      expect(exits, 0);
      store.write.complete();
      await saving;
      await tester.pumpAndSettle();
      expect(exits, 1);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );

  testWidgets('platform exit failure is recoverable and exposes no raw error', (
    tester,
  ) async {
    final players = PlaybackRegistry();
    var attempts = 0;
    await mount(
      tester,
      players: players,
      exit: () async {
        if (++attempts == 1) throw StateError('private native failure');
      },
    );
    await tester.tap(find.text('Exit app'));
    await tester.pumpAndSettle();
    expect(find.textContaining('could not finish closing'), findsOneWidget);
    expect(find.textContaining('private native failure'), findsNothing);
    final player = _Player(Completer<void>()..complete());
    players.track(
      player,
    ); // A failed exit must not permanently disable playback.
    await tester.tap(find.text('Exit app'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(player.closing, isTrue);
  });

  test(
    'shutdown waits for players already closing after their view disappeared',
    () async {
      final players = PlaybackRegistry();
      final gate = Completer<void>();
      final player = _Player(gate);
      players.track(player);
      final priorClose = player.dispose();
      var finished = false;
      final shutdown = players.closeAll().then((_) => finished = true);
      await Future<void>.delayed(Duration.zero);
      expect(finished, isFalse);
      gate.complete();
      await Future.wait([priorClose, shutdown]);
      expect(finished, isTrue);
    },
  );
}
