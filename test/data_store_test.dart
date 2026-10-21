import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
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
