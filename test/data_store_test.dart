import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:streamline_iptv/data/local_store.dart';
import 'package:streamline_iptv/data/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late LocalStore store;
  const movie = MediaItem(id: '1', name: 'First film', kind: MediaKind.movie);
  const secondMovie = MediaItem(
    id: '2',
    name: 'Second film',
    kind: MediaKind.movie,
  );

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    store = await LocalStore.open(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
  });
  tearDown(() => store.close());

  test(
    'favorites isolate accounts and media kinds even when IDs match',
    () async {
      const channel = MediaItem(id: '1', name: 'Channel', kind: MediaKind.live);
      const series = MediaItem(id: '1', name: 'Series', kind: MediaKind.series);
      await store.setFavorite('alice', movie, true);
      await store.setFavorite('alice', channel, true);
      await store.setFavorite('alice', series, true);
      await store.setFavorite('bob', channel, true);
      expect(
        (await store.favorites('alice')).map((item) => item.kind).toSet(),
        MediaKind.values.toSet(),
      );
      expect((await store.favorites('bob')).single.kind, MediaKind.live);
      await store.setFavorite('alice', channel, false);
      expect(
        (await store.favorites('alice')).map((item) => item.kind).toSet(),
        {MediaKind.movie, MediaKind.series},
      );
      expect((await store.favorites('bob')).single, channel);
      await store.clearSession();
      expect((await store.favorites('alice')).length, 2);
    },
  );

  test('saving a favorite twice updates metadata without duplicates', () async {
    await store.setFavorite('alice', movie, true);
    final updated = MediaItem(
      id: movie.id,
      name: 'Updated title',
      kind: movie.kind,
      imageUrl: 'https://art.example/new.jpg',
      addedAt: DateTime.utc(2026, 10, 22),
    );
    await store.setFavorite('alice', updated, true);
    final favorites = await store.favorites('alice');
    expect(favorites.length, 1);
    expect(favorites.single.name, 'Updated title');
    expect(favorites.single.addedAt, updated.addedAt);
    await store.setFavorite('alice', updated, false);
    await store.setFavorite('alice', updated, false);
    expect(await store.favorites('alice'), isEmpty);
  });

  test(
    'recent channels record real live playback only and stay isolated',
    () async {
      const channel = MediaItem(id: '1', name: 'News', kind: MediaKind.live);
      const otherChannel = MediaItem(
        id: '2',
        name: 'Sport',
        kind: MediaKind.live,
      );
      await store.recordChannelPlayed('alice', movie);
      await store.recordChannelPlayed(
        'alice',
        const MediaItem(id: 'series', name: 'Show', kind: MediaKind.series),
      );
      expect(await store.recentChannels('alice'), isEmpty);
      await store.recordChannelPlayed('alice', channel);
      await store.recordChannelPlayed('alice', otherChannel);
      await store.recordChannelPlayed('bob', otherChannel);
      await store.recordChannelPlayed('alice', channel);
      expect((await store.recentChannels('alice')).map((item) => item.id), [
        '1',
        '2',
      ]);
      expect((await store.recentChannels('bob')).single, otherChannel);
      expect(await store.history('alice'), isEmpty);
      expect(await store.favorites('alice'), isEmpty);
    },
  );

  test(
    'recent channels retain only the last twenty distinct channels per account',
    () async {
      for (var index = 0; index < 25; index++) {
        await store.recordChannelPlayed(
          'alice',
          MediaItem(id: '$index', name: 'Channel $index', kind: MediaKind.live),
        );
      }
      const bobChannel = MediaItem(
        id: '0',
        name: 'Bob channel',
        kind: MediaKind.live,
      );
      await store.recordChannelPlayed('bob', bobChannel);
      final recent = await store.recentChannels('alice');
      expect(
        recent.map((item) => item.id),
        List.generate(20, (index) => '${24 - index}'),
      );
      await store.recordChannelPlayed(
        'alice',
        const MediaItem(
          id: '20',
          name: 'Renamed channel',
          kind: MediaKind.live,
        ),
      );
      final replayed = await store.recentChannels('alice');
      expect(replayed.length, 20);
      expect(replayed.first.id, '20');
      expect(replayed.first.name, 'Renamed channel');
      expect(replayed.where((item) => item.id == '20').length, 1);
      expect((await store.recentChannels('bob')).single.name, 'Bob channel');
    },
  );

  test(
    'v1 migration preserves history/cache and new collections survive reopening',
    () async {
      final databasePath = path.join(
        Directory.systemTemp.path,
        'streamline-migration-${DateTime.now().microsecondsSinceEpoch}.db',
      );
      Database? legacy;
      LocalStore? migrated;
      try {
        legacy = await databaseFactoryFfi.openDatabase(
          databasePath,
          options: OpenDatabaseOptions(
            version: 1,
            onCreate: (db, _) async {
              await db.execute(
                'CREATE TABLE watch_history (account_id TEXT NOT NULL, media_id TEXT NOT NULL, item_json TEXT NOT NULL, position_ms INTEGER NOT NULL DEFAULT 0, duration_ms INTEGER NOT NULL DEFAULT 0, last_accessed INTEGER NOT NULL, PRIMARY KEY (account_id, media_id))',
              );
              await db.execute(
                'CREATE INDEX history_recent ON watch_history (account_id, last_accessed DESC)',
              );
              await db.execute(
                'CREATE TABLE provider_cache (account_id TEXT NOT NULL, cache_key TEXT NOT NULL, data_json TEXT NOT NULL, updated_at INTEGER NOT NULL, PRIMARY KEY (account_id, cache_key))',
              );
            },
          ),
        );
        final legacyMovie = movie.toJson()..remove('addedAt');
        final now = DateTime.now().millisecondsSinceEpoch;
        await legacy.insert('watch_history', {
          'account_id': 'alice',
          'media_id': movie.id,
          'item_json': jsonEncode(legacyMovie),
          'position_ms': 45000,
          'duration_ms': 100000,
          'last_accessed': now,
        });
        await legacy.insert('provider_cache', {
          'account_id': 'alice',
          'cache_key': 'epg:1',
          'data_json': '[{"title":"News"}]',
          'updated_at': now,
        });
        await legacy.close();
        legacy = null;
        migrated = await LocalStore.open(
          databaseFactory: databaseFactoryFfi,
          databasePath: databasePath,
        );
        final history = await migrated.history('alice');
        expect(history.single.positionMs, 45000);
        expect(history.single.canResume, true);
        expect(history.single.item.addedAt, isNull);
        expect(await migrated.cachedJson('alice', 'epg:1'), [
          {'title': 'News'},
        ]);
        await migrated.setFavorite('alice', movie, true);
        const channel = MediaItem(
          id: 'ch',
          name: 'News channel',
          kind: MediaKind.live,
        );
        await migrated.recordChannelPlayed('alice', channel);
        await migrated.close();
        migrated = await LocalStore.open(
          databaseFactory: databaseFactoryFfi,
          databasePath: databasePath,
        );
        expect((await migrated.favorites('alice')).single, movie);
        expect((await migrated.recentChannels('alice')).single, channel);
        expect((await migrated.history('alice')).single.positionMs, 45000);
        expect(await migrated.cachedJson('alice', 'epg:1'), [
          {'title': 'News'},
        ]);
      } finally {
        await legacy?.close();
        await migrated?.close();
        await databaseFactoryFfi.deleteDatabase(databasePath);
      }
    },
  );

  test(
    'episode progress isolates account and series, survives restart, and retains the next episode',
    () async {
      const series = MediaItem(id: 's1', name: 'Coast', kind: MediaKind.series);
      const other = MediaItem(
        id: 's2',
        name: 'Mountains',
        kind: MediaKind.series,
      );
      const episode = Episode(
        id: '1',
        title: 'Pilot',
        season: '1',
        episodeNumber: 1,
      );
      const next = Episode(
        id: '2',
        title: 'Next season',
        season: '2',
        episodeNumber: 1,
      );
      await store.saveEpisodeProgress(
        'alice',
        series,
        episode,
        positionMs: 30000,
        durationMs: 100000,
        nextEpisode: next,
      );
      await store.saveEpisodeProgress(
        'alice',
        other,
        episode,
        positionMs: 60000,
        durationMs: 100000,
      );
      await store.saveEpisodeProgress(
        'bob',
        series,
        episode,
        positionMs: 80000,
        durationMs: 100000,
      );
      var entries = await store.seriesHistory('alice');
      expect(entries.map((entry) => entry.item.id), ['s2', 's1']);
      expect(entries.last.canResume, true);
      expect(entries.last.nextEpisode?.season, '2');
      expect(entries.last.episode.title, 'Pilot');
      await store.saveEpisodeProgress(
        'alice',
        series,
        episode,
        positionMs: 0,
        durationMs: 0,
        nextEpisode: next,
      );
      entries = await store.seriesHistory('alice');
      expect(entries.first.positionMs, 30000);
      await store.saveEpisodeProgress(
        'alice',
        series,
        episode,
        positionMs: 999999,
        durationMs: 100000,
        nextEpisode: next,
      );
      final completed = (await store.seriesHistory('alice')).first;
      expect(completed.positionMs, 100000);
      expect(completed.watched, true);
      expect(completed.canResume, false);
      expect(completed.continueEpisode?.id, next.id);
      expect((await store.seriesHistory('bob')).single.positionMs, 80000);
      await store.clearSession();
      expect((await store.seriesHistory('alice')).length, 2);
      expect(await store.history('alice'), isEmpty);
    },
  );

  test(
    'v2 migration preserves movies and My List while adding persistent series progress',
    () async {
      final location = path.join(
        Directory.systemTemp.path,
        'streamline-v2-${DateTime.now().microsecondsSinceEpoch}.db',
      );
      LocalStore? current;
      Database? legacy;
      try {
        current = await LocalStore.open(
          databaseFactory: databaseFactoryFfi,
          databasePath: location,
        );
        await current.saveProgress(
          'alice',
          movie,
          positionMs: 40000,
          durationMs: 100000,
        );
        await current.setFavorite('alice', movie, true);
        await current.close();
        current = null;
        legacy = await databaseFactoryFfi.openDatabase(location);
        await legacy.execute('DROP TABLE episode_history');
        await legacy.setVersion(2);
        await legacy.close();
        legacy = null;
        current = await LocalStore.open(
          databaseFactory: databaseFactoryFfi,
          databasePath: location,
        );
        expect((await current.history('alice')).single.positionMs, 40000);
        expect((await current.favorites('alice')).single, movie);
        const series = MediaItem(
          id: 's',
          name: 'Series',
          kind: MediaKind.series,
        );
        const episode = Episode(
          id: 'e',
          title: 'Episode',
          season: '1',
          episodeNumber: 1,
        );
        await current.saveEpisodeProgress(
          'alice',
          series,
          episode,
          positionMs: 50000,
          durationMs: 100000,
        );
        await current.close();
        current = await LocalStore.open(
          databaseFactory: databaseFactoryFfi,
          databasePath: location,
        );
        expect((await current.seriesHistory('alice')).single.positionMs, 50000);
      } finally {
        await legacy?.close();
        await current?.close();
        await databaseFactoryFfi.deleteDatabase(location);
      }
    },
  );

  test('securely saves, restores and clears the session', () async {
    const session = Session(
      credentials: Credentials(
        serverUrl: 'https://example.com',
        username: 'alice',
        password: 'secret',
      ),
      userInfo: {'auth': 1, 'status': 'Active'},
      serverInfo: {'timezone': 'UTC'},
    );
    expect(await store.readSession(), isNull);
    await store.saveSession(session);
    final restored = (await store.readSession())!;
    expect(restored.accountId, session.accountId);
    expect(restored.credentials.password, 'secret');
    expect(restored.userInfo['status'], 'Active');
    await store.clearSession();
    expect(await store.readSession(), isNull);
  });

  test(
    'opening a film preserves progress and updates recent ordering',
    () async {
      await store.saveProgress(
        'alice',
        movie,
        positionMs: 45000,
        durationMs: 100000,
      );
      await store.recordOpened('alice', secondMovie);
      await store.recordOpened('alice', movie);
      final history = await store.history('alice');
      final entry = history.firstWhere((entry) => entry.item.id == movie.id);
      expect(entry.positionMs, 45000);
      expect(entry.durationMs, 100000);
      expect(entry.canResume, true);
      expect(history.length, 2);
      expect(
        history.first.lastAccessed.isBefore(history.last.lastAccessed),
        false,
      );
    },
  );

  test(
    'isolates history and cache between accounts and preserves history on logout',
    () async {
      await store.saveProgress(
        'alice',
        movie,
        positionMs: 20000,
        durationMs: 100000,
      );
      await store.saveProgress(
        'bob',
        movie,
        positionMs: 60000,
        durationMs: 100000,
      );
      expect((await store.history('alice')).single.positionMs, 20000);
      expect((await store.history('bob')).single.positionMs, 60000);
      await store.cacheJson('alice', 'epg:1', [
        {'title': 'News'},
      ]);
      expect(await store.cachedJson('bob', 'epg:1'), isNull);
      expect(await store.cachedJson('alice', 'epg:1'), [
        {'title': 'News'},
      ]);
      expect(
        await store.cachedJson(
          'alice',
          'epg:1',
          maxAge: const Duration(seconds: -1),
        ),
        isNull,
      );
      await store.clearSession();
      expect((await store.history('alice')).single.positionMs, 20000);
    },
  );

  test(
    'records completed movies, clamps positions and ignores failed initialization',
    () async {
      await store.saveProgress(
        'alice',
        movie,
        positionMs: 40000,
        durationMs: 100000,
      );
      await store.saveProgress('alice', movie, positionMs: 0, durationMs: 0);
      expect((await store.history('alice')).single.positionMs, 40000);
      await store.saveProgress(
        'alice',
        movie,
        positionMs: 120000,
        durationMs: 100000,
      );
      final entry = (await store.history('alice')).single;
      expect(entry.positionMs, 100000);
      expect(entry.canResume, false);
    },
  );
}
