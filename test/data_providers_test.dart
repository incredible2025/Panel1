import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streamline_iptv/core/providers.dart';
import 'package:streamline_iptv/data/local_store.dart';
import 'package:streamline_iptv/data/models.dart';

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

void main() {
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
