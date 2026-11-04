import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streamline_iptv/widgets/live_programme_summary.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:streamline_iptv/core/providers.dart';
import 'package:streamline_iptv/core/update_controller.dart';
import 'package:streamline_iptv/data/local_store.dart';
import 'package:streamline_iptv/data/models.dart';
import 'package:streamline_iptv/data/xtream_api.dart';
import 'app_update_test.dart' show FakePlatform, FakeTransport;

class BrokenCache implements LocalStore {
  @override
  Future<void> cacheJson(String a, String k, dynamic v) async =>
      throw StateError('Disk unavailable');
  @override
  Future<dynamic> cachedJson(
    String a,
    String k, {
    Duration maxAge = const Duration(hours: 2),
  }) async => null;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class ValidEpg extends XtreamApi {
  int requests = 0;
  @override
  Future<List<EpgEntry>> shortEpg(Session s, String id, {int limit = 6}) async {
    requests++;
    return [
      EpgEntry(
        title: 'Valid programme',
        description: '',
        start: DateTime.now(),
        end: DateTime.now().add(const Duration(hours: 1)),
      ),
    ];
  }
}

class BrokenPreferences extends FakePlatform {
  @override
  Future<void> preferences(String u, bool a, DateTime? d) async =>
      throw StateError('Preferences unavailable');
}

void main() {
  testWidgets('mounted EPG refreshes and stops after disposal', (tester) async {
    final api = ValidEpg();
    final c = ProviderContainer(
      overrides: [
        storeProvider.overrideWithValue(BrokenCache()),
        apiProvider.overrideWithValue(api),
        sessionProvider.overrideWith(
          (ref) => const Session(
            credentials: Credentials(
              serverUrl: 'https://example.com',
              username: 'test',
              password: 'test',
            ),
            userInfo: {},
            serverInfo: {},
          ),
        ),
      ],
    );
    final keep = c.listen(epgProvider('1'), (_, __) {});
    try {
      await c.read(epgProvider('1').future);
      expect(api.requests, 1);
      await tester.pump(const Duration(minutes: 5));
      await tester.pump();
      await c.read(epgProvider('1').future);
      expect(api.requests, 2);
    } finally {
      keep.close();
      c.dispose();
      api.dispose();
    }
    await tester.pump(const Duration(minutes: 6));
    expect(api.requests, 2);
  });
  testWidgets('programme labels advance when the shared clock ticks', (
    tester,
  ) async {
    final clock = StreamController<DateTime>();
    final start = DateTime(2026, 11, 4, 12);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          programmeClockProvider.overrideWith((ref) => clock.stream),
          epgProvider.overrideWith(
            (ref, id) async => [
              EpgEntry(
                title: 'First',
                description: '',
                start: start,
                end: start.add(const Duration(minutes: 30)),
              ),
              EpgEntry(
                title: 'Second',
                description: '',
                start: start.add(const Duration(minutes: 30)),
                end: start.add(const Duration(hours: 1)),
              ),
            ],
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: LiveProgrammeSummary(channelId: '1')),
        ),
      ),
    );
    clock.add(start.add(const Duration(minutes: 1)));
    await tester.pumpAndSettle();
    expect(find.text('Now · First'), findsOneWidget);
    clock.add(start.add(const Duration(minutes: 31)));
    await tester.pumpAndSettle();
    expect(find.text('Now · Second'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    unawaited(clock.close());
    await tester.pump();
  });
  test('valid live EPG survives cache write failure', () async {
    final api = ValidEpg();
    final c = ProviderContainer(
      overrides: [
        storeProvider.overrideWithValue(BrokenCache()),
        apiProvider.overrideWithValue(api),
        sessionProvider.overrideWith(
          (ref) => const Session(
            credentials: Credentials(
              serverUrl: 'https://example.com',
              username: 'test',
              password: 'test',
            ),
            userInfo: {},
            serverInfo: {},
          ),
        ),
      ],
    );
    final keep = c.listen(epgProvider('1'), (_, __) {});
    try {
      final entries = await c.read(epgProvider('1').future);
      expect(entries.single.title, 'Valid programme');
    } finally {
      keep.close();
      c.dispose();
      api.dispose();
    }
  });
  test(
    'valid updates remain available when preferences cannot be saved',
    () async {
      final t = FakeTransport();
      final c = UpdateController(BrokenPreferences(), t);
      try {
        await c.load();
        await c.check();
        expect(t.checks, 1);
        expect(c.stage, UpdateStage.available);
        expect(c.update, isNotNull);
      } finally {
        c.dispose();
      }
    },
  );
}
