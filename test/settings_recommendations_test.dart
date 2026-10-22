import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:streamline_iptv/core/settings_controller.dart';
import 'package:streamline_iptv/data/app_settings.dart';
import 'package:streamline_iptv/data/local_store.dart';
import 'package:streamline_iptv/data/models.dart';
import 'package:streamline_iptv/data/recommendations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  final now = DateTime.utc(2026, 10, 22);
  const source = MediaItem(
    id: '1',
    name: 'Coastal Road (2024)',
    kind: MediaKind.movie,
    categoryId: 'drama',
  );
  const secondSource = MediaItem(
    id: '2',
    name: 'Flight',
    kind: MediaKind.movie,
    categoryId: 'action',
  );
  WatchEntry watched(
    MediaItem item, {
    int position = 400000,
    int duration = 1000000,
    int days = 0,
  }) => WatchEntry(
    item: item,
    positionMs: position,
    durationMs: duration,
    lastAccessed: now.subtract(Duration(days: days)),
  );
  const candidate = MediaItem(
    id: '3',
    name: 'New drama',
    kind: MediaKind.movie,
    categoryId: 'drama',
    rating: '8',
  );
  const other = MediaItem(
    id: '4',
    name: 'New action',
    kind: MediaKind.movie,
    categoryId: 'action',
    rating: '9',
  );

  test(
    'recommendations use actual playback, exclude seen/duplicate editions and explain the source',
    () {
      const duplicate = MediaItem(
        id: '5',
        name: 'Coastal Road (2024) 4K',
        kind: MediaKind.movie,
        categoryId: 'drama',
      );
      const unrelated = MediaItem(
        id: '6',
        name: 'Cooking',
        kind: MediaKind.movie,
        categoryId: 'documentary',
      );
      final catalog = [
        source,
        secondSource,
        candidate,
        candidate,
        other,
        duplicate,
        unrelated,
      ];
      expect(
        recommendMovies(catalog, [watched(source, position: 0)], now: now),
        isEmpty,
      );
      expect(
        recommendMovies(catalog, [watched(source, position: 59000)], now: now),
        isEmpty,
      );
      final result = recommendMovies(catalog, [
        watched(source),
        watched(secondSource, days: 10),
      ], now: now);
      expect(result.first.title, 'Because you watched Coastal Road (2024)');
      expect(result.first.sourceId, source.id);
      expect(result.first.items.map((item) => item.id), ['3']);
      expect(result.last.title, 'Picked for you');
      expect(result.last.items, [other]);
      expect(
        result
            .expand((shelf) => shelf.items)
            .any((item) => item.id == '5' || item.id == '6'),
        false,
      );
    },
  );

  test(
    'recommendations stop when similar available titles run out and do not invent dates',
    () {
      expect(
        recommendMovies([source, other], [watched(source)], now: now),
        isEmpty,
      );
      final result = recommendMovies(
        [source, candidate],
        [watched(source)],
        now: now,
      );
      expect(result.single.items.single.addedAt, isNull);
      expect(recommendMovies([source, candidate], [], now: now), isEmpty);
    },
  );

  test(
    'settings reject invalid saved values and retain account/category/player state',
    () {
      final settings = AppSettings.fromJson({
        'engine': 'bad',
        'controlsSeconds': -5,
        'picture': 'zoom',
        'subtitleSize': 'NaN',
        'lastCategories': {'movie': 'drama'},
        'hiddenCategories': ['movie:drama'],
        'lockedCategories': ['series:adults'],
        'playerOverrides': {'movie:3': 'compatibility'},
      });
      expect(settings.engine, PlayerEngine.native);
      expect(settings.controlsSeconds, 5);
      expect(settings.picture, 'fit');
      expect(settings.subtitleSize, 22);
      expect(settings.hidden(source), true);
      expect(settings.engineFor(candidate), PlayerEngine.compatibility);
      expect(
        AppSettings.fromJson(
          jsonDecode(jsonEncode(settings.toJson())),
        ).lastCategories['movie'],
        'drama',
      );
    },
  );

  test(
    'account expiry handles missing fields, expired dates and future timestamps honestly',
    () {
      Session session(Map<String, dynamic> info) => Session(
        credentials: const Credentials(
          serverUrl: 'https://example.com',
          username: 'viewer',
          password: 'secret',
        ),
        userInfo: info,
        serverInfo: {},
      );
      final missing = AccountInfo(session({}), now: now);
      expect(missing.expiryLabel, 'Not supplied');
      expect(missing.count('active_cons'), 'Not supplied');
      expect(missing.remainingDays, isNull);
      final future = AccountInfo(
        session({
          'exp_date':
              now
                  .add(const Duration(days: 3, hours: 1))
                  .millisecondsSinceEpoch ~/
              1000,
        }),
        now: now,
      );
      expect(future.remainingDays, 4);
      expect(future.expiring, true);
      final expired = AccountInfo(
        session({
          'exp_date':
              now.subtract(const Duration(days: 2)).millisecondsSinceEpoch ~/
              1000,
        }),
        now: now,
      );
      expect(expired.remainingDays, -2);
      expect(expired.expiring, true);
    },
  );

  test(
    'preferences survive reopening, isolate accounts and do not clear history with cache',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final location =
          '${Directory.systemTemp.path}/streamline-v5-${DateTime.now().microsecondsSinceEpoch}.db';
      var store = await LocalStore.open(
        databaseFactory: databaseFactoryFfi,
        databasePath: location,
      );
      try {
        await store.saveSettings(
          'alice',
          const AppSettings(
            engine: PlayerEngine.compatibility,
            hiddenCategories: {'movie:drama'},
            lastSection: 'movie',
            lastChannel: '7',
          ),
        );
        await store.saveProgress(
          'alice',
          source,
          positionMs: 100000,
          durationMs: 1000000,
        );
        await store.cacheJson('alice', 'epg:7', []);
        await store.clearCache('alice');
        expect((await store.history('alice')).single.positionMs, 100000);
        expect((await store.readSettings('bob')).hiddenCategories, isEmpty);
        await store.close();
        store = await LocalStore.open(
          databaseFactory: databaseFactoryFfi,
          databasePath: location,
        );
        final preferences = await store.readSettings('alice');
        expect(preferences.engine, PlayerEngine.compatibility);
        expect(preferences.hiddenCategories, {'movie:drama'});
        expect(preferences.lastChannel, '7');
        expect(await store.cachedJson('alice', 'epg:7'), isNull);
      } finally {
        await store.close();
        await databaseFactoryFfi.deleteDatabase(location);
      }
    },
  );

  test(
    'v3 upgrade adds preferences without changing episode or movie positions',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final location =
          '${Directory.systemTemp.path}/streamline-v3-upgrade-${DateTime.now().microsecondsSinceEpoch}.db';
      var store = await LocalStore.open(
        databaseFactory: databaseFactoryFfi,
        databasePath: location,
      );
      try {
        await store.saveProgress(
          'alice',
          source,
          positionMs: 250000,
          durationMs: 1000000,
        );
        await store.close();
        final legacy = await databaseFactoryFfi.openDatabase(location);
        await legacy.execute('DROP TABLE app_preferences');
        await legacy.setVersion(3);
        await legacy.close();
        store = await LocalStore.open(
          databaseFactory: databaseFactoryFfi,
          databasePath: location,
        );
        expect((await store.history('alice')).single.positionMs, 250000);
        expect((await store.readSettings('alice')).engine, PlayerEngine.native);
        await store.saveSettings(
          'alice',
          const AppSettings(controlsSeconds: 8),
        );
        expect((await store.readSettings('alice')).controlsSeconds, 8);
      } finally {
        await store.close();
        await databaseFactoryFfi.deleteDatabase(location);
      }
    },
  );

  test(
    'parental PINs are account scoped, salted and throttle repeated wrong attempts',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final store = await LocalStore.open(
        databaseFactory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      addTearDown(store.close);
      expect(await store.hasPin('alice'), false);
      await store.setPin('alice', '1234');
      expect(await store.hasPin('alice'), true);
      expect(await store.hasPin('bob'), false);
      expect(await store.verifyPin('alice', '1234'), 0);
      for (var attempt = 0; attempt < 4; attempt++) {
        expect(await store.verifyPin('alice', '9999'), -1);
      }
      expect(await store.verifyPin('alice', '9999'), 30);
      expect(await store.verifyPin('alice', '1234'), greaterThan(0));
      final saved = await const FlutterSecureStorage().readAll();
      final secret = saved.values.single;
      expect(secret.contains('1234'), false);
      expect(jsonDecode(secret)['digest'], isNotEmpty);
      await store.removePin('alice');
      expect(await store.hasPin('alice'), false);
    },
  );

  test(
    'rapid preference writes are serialized without losing other changes',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final store = await LocalStore.open(
        databaseFactory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      final controller = SettingsController(store, 'alice');
      addTearDown(() async {
        controller.dispose();
        await store.close();
      });
      await controller.ready;
      final results = await Future.wait([
        controller.patch({'controlsSeconds': 8}),
        controller.patch({'subtitles': true}),
        controller.patch({'theme': 'cinema'}),
      ]);
      expect(results, everyElement(true));
      final saved = await store.readSettings('alice');
      expect(saved.controlsSeconds, 8);
      expect(saved.subtitles, true);
      expect(saved.theme, 'cinema');
      expect(controller.state, isA<AsyncData<AppSettings>>());
      expect(
        await controller.update((_) => throw StateError('Invalid change')),
        false,
      );
      expect(await controller.patch({'controlsSeconds': 3}), true);
      expect((await store.readSettings('alice')).controlsSeconds, 3);
    },
  );
}
