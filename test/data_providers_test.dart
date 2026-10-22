import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streamline_iptv/core/providers.dart';
import 'package:streamline_iptv/data/local_store.dart';
import 'package:streamline_iptv/data/models.dart';
import 'package:streamline_iptv/data/xtream_api.dart';

class _CollectionStore implements LocalStore {
  final favoritesByAccount = <String, List<MediaItem>>{};
  final recentByAccount = <String, List<MediaItem>>{};

  @override
  Future<List<MediaItem>> favorites(String accountId) async =>
      favoritesByAccount[accountId] ?? [];

  @override
  Future<List<MediaItem>> recentChannels(String accountId) async =>
      recentByAccount[accountId] ?? [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _GuideStore extends _CollectionStore {
  dynamic cache;
  bool broken = false;
  @override
  Future<dynamic> cachedJson(
    String accountId,
    String key, {
    Duration maxAge = const Duration(hours: 2),
  }) async {
    if (broken) throw StateError('Cache unavailable');
    return cache;
  }

  @override
  Future<void> cacheJson(String accountId, String key, dynamic value) async {
    if (broken) throw StateError('Cache unavailable');
    cache = value;
  }
}

class _GuideApi extends XtreamApi {
  int requests = 0;
  bool offline = false;
  @override
  Future<GuideSchedule> fullEpg(Session session, String streamId) async {
    requests++;
    if (offline) throw const XtreamApiException('Schedule unavailable');
    return GuideSchedule([
      EpgEntry(
        title: 'News',
        description: '',
        start: DateTime.utc(2026, 10, 22, 10),
        end: DateTime.utc(2026, 10, 22, 11),
      ),
    ]);
  }
}

void main() {
  test(
    'guide refresh reaches provider and network failure uses cached schedule',
    () async {
      final store = _GuideStore();
      final api = _GuideApi();
      final container = ProviderContainer(
        overrides: [
          storeProvider.overrideWithValue(store),
          apiProvider.overrideWithValue(api),
          sessionProvider.overrideWith(
            (ref) => const Session(
              credentials: Credentials(
                serverUrl: 'https://example.com',
                username: 'alice',
                password: 'secret',
              ),
              userInfo: {},
              serverInfo: {},
            ),
          ),
        ],
      );
      final subscription = container.listen(
        guideScheduleProvider('1'),
        (_, __) {},
      );
      addTearDown(() {
        subscription.close();
        container.dispose();
        api.dispose();
      });
      expect(
        (await container.read(guideScheduleProvider('1').future)).cached,
        false,
      );
      container.invalidate(guideScheduleProvider('1'));
      expect(
        (await container.read(guideScheduleProvider('1').future)).cached,
        true,
      );
      expect(api.requests, 1);
      api.offline = true;
      container.read(guideRefreshProvider.notifier).state++;
      expect(
        (await container.read(guideScheduleProvider('1').future)).cached,
        true,
      );
      expect(api.requests, 2);
    },
  );

  test('broken cache cannot hide valid provider schedule', () async {
    final store = _GuideStore()..broken = true;
    final api = _GuideApi();
    final container = ProviderContainer(
      overrides: [
        storeProvider.overrideWithValue(store),
        apiProvider.overrideWithValue(api),
        sessionProvider.overrideWith(
          (ref) => const Session(
            credentials: Credentials(
              serverUrl: 'https://example.com',
              username: 'alice',
              password: 'secret',
            ),
            userInfo: {},
            serverInfo: {},
          ),
        ),
      ],
    );
    final subscription = container.listen(
      guideScheduleProvider('1'),
      (_, __) {},
    );
    addTearDown(() {
      subscription.close();
      container.dispose();
      api.dispose();
    });
    expect(
      (await container.read(
        guideScheduleProvider('1').future,
      )).entries.single.title,
      'News',
    );
  });

  test(
    'collection providers are empty when signed out without opening storage',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(await container.read(favoritesProvider.future), isEmpty);
      expect(await container.read(recentChannelsProvider.future), isEmpty);
    },
  );

  test(
    'collection providers refresh for account changes and explicit invalidation',
    () async {
      const alice = Session(
        credentials: Credentials(
          serverUrl: 'https://example.com',
          username: 'alice',
          password: 'secret',
        ),
        userInfo: {},
        serverInfo: {},
      );
      const bob = Session(
        credentials: Credentials(
          serverUrl: 'https://example.com',
          username: 'bob',
          password: 'secret',
        ),
        userInfo: {},
        serverInfo: {},
      );
      const movie = MediaItem(
        id: '1',
        name: 'Alice movie',
        kind: MediaKind.movie,
      );
      const channel = MediaItem(
        id: '2',
        name: 'Bob channel',
        kind: MediaKind.live,
      );
      final store = _CollectionStore()
        ..favoritesByAccount[alice.accountId] = [movie]
        ..recentByAccount[bob.accountId] = [channel];
      final container = ProviderContainer(
        overrides: [
          storeProvider.overrideWithValue(store),
          sessionProvider.overrideWith((ref) => alice),
        ],
      );
      addTearDown(container.dispose);
      expect(await container.read(favoritesProvider.future), [movie]);
      expect(await container.read(recentChannelsProvider.future), isEmpty);
      container.read(sessionProvider.notifier).state = bob;
      expect(await container.read(favoritesProvider.future), isEmpty);
      expect(await container.read(recentChannelsProvider.future), [channel]);
      store.favoritesByAccount[bob.accountId] = [channel];
      container.invalidate(favoritesProvider);
      expect(await container.read(favoritesProvider.future), [channel]);
      container.read(sessionProvider.notifier).state = null;
      expect(await container.read(favoritesProvider.future), isEmpty);
      expect(await container.read(recentChannelsProvider.future), isEmpty);
    },
  );
}
