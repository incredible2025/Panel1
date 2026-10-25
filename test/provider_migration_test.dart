import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:streamline_iptv/core/provider_config.dart';
import 'package:streamline_iptv/data/app_settings.dart';
import 'package:streamline_iptv/data/local_store.dart';
import 'package:streamline_iptv/data/models.dart';
import 'package:streamline_iptv/data/xtream_api.dart';

const _oldAccountId =
    '2436c8ac7ec1ffb840a8b3cbd606b2394717311b81ebc1b6a43f9741c36f0b0e';
Session _saved({
  String address = 'http://liquidmetal.vip',
  String username = 'viewer',
}) => Session(
  credentials: Credentials(
    serverUrl: address,
    username: username,
    password: ' secret ',
  ),
  userInfo: const {'auth': 1, 'status': 'Active'},
  serverInfo: const {'url': 'liquidmetal.vip'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test(
    'approved old sessions move to the IP without losing credentials or the historical account key',
    () {
      for (final address in [
        'http://liquidmetal.vip',
        'http://LIQUIDMETAL.VIP/player_api.php',
      ]) {
        final saved = _saved(address: address);
        final migrated = restoreConfiguredSession(saved)!;
        expect(migrated.credentials.serverUrl, 'http://167.235.169.168');
        expect(migrated.credentials.username, saved.credentials.username);
        expect(migrated.credentials.password, saved.credentials.password);
        expect(migrated.userInfo, saved.userInfo);
        expect(migrated.serverInfo, saved.serverInfo);
        expect(saved.accountId, _oldAccountId);
        expect(migrated.accountId, _oldAccountId);
        expect(usesConfiguredPortal(saved), false);
        expect(usesConfiguredPortal(migrated), true);
        expect(restoreConfiguredSession(migrated), same(migrated));
        expect(
          Session.fromJson(jsonDecode(jsonEncode(migrated.toJson()))).accountId,
          _oldAccountId,
        );
      }
    },
  );

  test(
    'unrelated, lookalike and malformed portals cannot forward saved credentials',
    () {
      expect(restoreConfiguredSession(null), isNull);
      for (final address in [
        'https://other.example',
        'http://liquidmetal.vip.other.example',
        'http://liquidmetal.vip:8080',
        'http://liquidmetal.vip/other',
        'http://user:pass@liquidmetal.vip',
        '://',
      ]) {
        expect(restoreConfiguredSession(_saved(address: address)), isNull);
      }
      expect(
        _saved(address: providerPortalUrl, username: 'other').accountId,
        isNot(_oldAccountId),
      );
      expect(
        _saved(address: 'https://other.example').accountId,
        isNot(_oldAccountId),
      );
    },
  );

  test(
    'migrated and fresh authentication, catalogue and all stream kinds use only the configured IP',
    () async {
      final requests = <Uri>[];
      final api = XtreamApi(
        client: MockClient((request) async {
          requests.add(request.url);
          if (request.url.queryParameters.containsKey('action')) {
            return http.Response('[]', 200);
          }
          return http.Response(
            jsonEncode({
              'user_info': {'auth': 1, 'status': 'Active'},
              'server_info': {'url': 'liquidmetal.vip'},
            }),
            200,
          );
        }),
      );
      addTearDown(api.dispose);
      final migrated = restoreConfiguredSession(_saved())!;
      final fresh = await api.authenticate(migrated.credentials);
      final signedIn = await api.authenticate(
        portalCredentials('viewer', ' secret '),
      );
      for (final session in [migrated, fresh, signedIn]) {
        expect(session.accountId, _oldAccountId);
        for (final kind in MediaKind.values) {
          await api.categories(session, kind);
          await api.items(session, kind);
          final item = MediaItem(id: '101', name: 'Title', kind: kind);
          final stream = api.streamUri(
            session,
            item,
            episode: kind == MediaKind.series
                ? const Episode(
                    id: '201',
                    title: 'Episode',
                    season: '1',
                    episodeNumber: 1,
                  )
                : null,
          );
          expect(stream.host, '167.235.169.168');
          expect(stream.scheme, 'http');
          expect(
            stream.pathSegments.first,
            kind == MediaKind.live
                ? 'live'
                : kind == MediaKind.movie
                ? 'movie'
                : 'series',
          );
        }
      }
      expect(requests, isNotEmpty);
      expect(
        requests.every(
          (request) =>
              request.host == '167.235.169.168' && request.scheme == 'http',
        ),
        true,
      );
      expect(requests.first.queryParameters['password'], ' secret ');
    },
  );

  test(
    'saved history, settings, favourites, PIN and cache survive session migration and re-login',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final store = await LocalStore.open(
        databaseFactory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      addTearDown(store.close);
      const movie = MediaItem(id: '1', name: 'Movie', kind: MediaKind.movie);
      const channel = MediaItem(id: '2', name: 'Channel', kind: MediaKind.live);
      const series = MediaItem(id: '3', name: 'Series', kind: MediaKind.series);
      const episode = Episode(
        id: '4',
        title: 'Episode',
        season: '1',
        episodeNumber: 1,
      );
      await store.saveSession(_saved());
      await store.saveProgress(
        _oldAccountId,
        movie,
        positionMs: 600000,
        durationMs: 6000000,
      );
      await store.saveEpisodeProgress(
        _oldAccountId,
        series,
        episode,
        positionMs: 300000,
        durationMs: 3000000,
      );
      await store.setFavorite(_oldAccountId, movie, true);
      await store.recordChannelPlayed(_oldAccountId, channel);
      await store.saveSettings(
        _oldAccountId,
        const AppSettings(lastSection: 'series', controlsSeconds: 8),
      );
      await store.setPin(_oldAccountId, '1234');
      await store.cacheJson(_oldAccountId, 'epg', {
        'programme': 'Saved programme',
      });
      final migrated = restoreConfiguredSession(await store.readSession())!;
      await store.saveSession(migrated);
      for (final session in [
        (await store.readSession())!,
        _saved(address: providerPortalUrl),
      ]) {
        expect(session.credentials.serverUrl, providerPortalUrl);
        expect(
          (await store.history(session.accountId)).single.positionMs,
          600000,
        );
        expect(
          (await store.seriesHistory(session.accountId)).single.positionMs,
          300000,
        );
        expect((await store.favorites(session.accountId)).single, movie);
        expect((await store.recentChannels(session.accountId)).single, channel);
        expect(
          (await store.readSettings(session.accountId)).lastSection,
          'series',
        );
        expect(
          (await store.readSettings(session.accountId)).controlsSeconds,
          8,
        );
        expect(await store.verifyPin(session.accountId, '1234'), 0);
        expect(await store.cachedJson(session.accountId, 'epg'), {
          'programme': 'Saved programme',
        });
      }
    },
  );
}
