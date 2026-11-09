import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:streamline_iptv/core/provider_config.dart';
import 'package:streamline_iptv/data/app_settings.dart';
import 'package:streamline_iptv/data/local_store.dart';
import 'package:streamline_iptv/data/managed_configuration.dart';
import 'package:streamline_iptv/data/models.dart';
import 'package:streamline_iptv/data/provider_connections.dart';
import 'package:streamline_iptv/data/xtream_api.dart';
import 'package:streamline_iptv/data/connection_diagnostics.dart';
import 'connection_diagnostics_test.dart' show FakeDiagnosticTransport;

const serviceOne = '11111111-1111-4111-8111-111111111111';
const serviceTwo = '22222222-2222-4222-8222-222222222222';
String encoded(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');
late SimpleKeyPair key;
late String publicKey;
Map<String, dynamic> payload({
  int revision = 1,
  String serviceId = serviceOne,
}) => {
  'schemaVersion': 1,
  'appId': 'test-brand',
  'packageId': 'com.example.test',
  'serviceId': serviceId,
  'revision': revision,
  'endpoints': [
    'https://primary.example.test/root',
    'http://backup.example.test/other',
  ],
  'updateManifestUrl': 'https://updates.example.test/update.json',
  'issuedAt': '2026-11-09T00:00:00+00:00',
};
Future<Map<String, dynamic>> sign(Map<String, dynamic> value) async {
  final bytes = utf8.encode(jsonEncode(value));
  final signature = await Ed25519().sign(bytes, keyPair: key);
  return {'payload': encoded(bytes), 'signature': encoded(signature.bytes)};
}

Future<ManagedProfile> profile() async => ManagedProfile.parse(
  jsonEncode({
    'appId': 'test-brand',
    'packageId': 'com.example.test',
    'configUrl': 'https://manager.example.test/config',
    'verificationKey': publicKey,
    'bootstrap': await sign(payload()),
  }),
  packageId: 'com.example.test',
);

class TrackingClient extends MockClient {
  TrackingClient(super.handler);
  bool closed = false;
  @override
  void close() {
    closed = true;
    super.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  setUpAll(() async {
    key = await Ed25519().newKeyPairFromSeed(List.filled(32, 11));
    publicKey = encoded((await key.extractPublicKey()).bytes);
  });

  test(
    'the primary Android bootstrap has a valid portal signature and package identity',
    () async {
      final p = ManagedProfile.parse(managedProfileJson);
      final config = await p.verify(p.bootstrap);
      expect(p.packageId, androidApplicationId);
      expect(p.appId, 'ultravpn-player');
      expect(config.revision, greaterThan(0));
    },
  );

  test(
    'diagnostic stream testing uses the same signed service route without exposing it',
    () async {
      final p = await profile();
      final config = await p.verify(p.bootstrap);
      final transport = FakeDiagnosticTransport();
      final report =
          await ConnectionDiagnostics(
            transport,
            approvedRoots: config.endpoints,
            now: () => DateTime.utc(2026, 10, 22, 12),
          ).run(
            config.credentials('viewer', 'secret'),
            item: const MediaItem(id: '1', name: 'Live', kind: MediaKind.live),
            testStream: true,
            streamPermitted: true,
          );
      expect(
        report.checks.any((check) => check.finding.code == 'STREAM_ADDRESS'),
        false,
      );
      expect(
        transport.uris.any((uri) => uri.path.startsWith('/root/live/')),
        true,
      );
      expect(report.toText(), isNot(contains('primary.example.test')));
      expect(report.toText(), isNot(contains('secret')));
    },
  );

  test(
    'Dart verifies an exact payload signed by the actual PHP portal signer',
    () async {
      final p = ManagedProfile.parse(
        await File('test/fixtures/managed-profile.json').readAsString(),
        packageId: 'com.example.fixture',
      );
      final config = await p.verify(p.bootstrap);
      expect(config.serviceId, serviceOne);
      expect(config.revision, 1);
      expect(config.endpoints.first.path, '/service');
    },
  );

  test(
    'valid signatures cannot cross app, package or schema boundaries',
    () async {
      final p = await profile();
      for (final patch in [
        {'appId': 'other-brand'},
        {'packageId': 'com.example.other'},
        {'schemaVersion': 2},
        {'revision': 0},
        {'serviceId': 'invalid'},
        {
          'endpoints': ['https://user:password@example.test'],
        },
        {
          'endpoints': ['https://example.test/?password=secret'],
        },
        {'updateManifestUrl': 'http://updates.example.test/update.json'},
      ]) {
        await expectLater(
          p.verify(await sign({...payload(), ...patch})),
          throwsFormatException,
        );
      }
    },
  );

  test('modified payloads or signatures are rejected', () async {
    final p = await profile();
    await expectLater(
      p.verify({
        ...p.bootstrap,
        'payload': encoded(utf8.encode(jsonEncode(payload(revision: 99)))),
      }),
      throwsFormatException,
    );
    await expectLater(
      p.verify({...p.bootstrap, 'signature': encoded(List.filled(64, 0))}),
      throwsFormatException,
    );
    expect(
      () => ManagedProfile.parse(
        jsonEncode({'appId': 'test-brand', 'packageId': 'com.wrong.app'}),
      ),
      throwsFormatException,
    );
  });

  test('offline startup uses the newest verified cached settings', () async {
    final p = await profile();
    final manager = ManagedConfigurationManager(
      profile: p,
      readCache: () async => jsonEncode(await sign(payload(revision: 7))),
      writeCache: (_) async =>
          fail('Offline startup must not rewrite settings'),
      clientFactory: () => MockClient((_) async => http.Response('', 503)),
    );
    addTearDown(manager.dispose);
    await manager.initialize();
    expect(manager.current.revision, 7);
  });

  test('corrupt cache falls back to the verified build bootstrap', () async {
    final manager = ManagedConfigurationManager(
      profile: await profile(),
      readCache: () async => 'broken',
      writeCache: (_) async {},
      clientFactory: () => MockClient((_) async => http.Response('', 503)),
    );
    addTearDown(manager.dispose);
    await manager.initialize();
    expect(manager.current.revision, 1);
  });

  test(
    'replay and same-revision changes cannot replace accepted settings; rollback uses a higher revision',
    () async {
      final p = await profile();
      var incoming = await sign(payload(revision: 4));
      String? cache;
      var notifications = 0;
      final manager = ManagedConfigurationManager(
        profile: p,
        readCache: () async => cache,
        writeCache: (value) async => cache = value,
        clientFactory: () =>
            MockClient((_) async => http.Response(jsonEncode(incoming), 200)),
      );
      manager.addListener(() => notifications++);
      addTearDown(manager.dispose);
      await manager.initialize();
      expect(manager.current.revision, 4);
      incoming = await sign(payload(revision: 2));
      expect(await manager.refresh(), false);
      incoming = await sign(payload(revision: 4, serviceId: serviceTwo));
      expect(await manager.refresh(), false);
      expect(manager.current.serviceId, serviceOne);
      incoming = await sign(payload(revision: 5));
      expect(await manager.refresh(), true);
      expect(manager.current.revision, 5);
      expect(notifications, 2);
      expect(jsonDecode(cache!)['payload'], incoming['payload']);
    },
  );

  test(
    'network deadlines close the client; redirects and oversized bodies are rejected',
    () async {
      final p = await profile();
      for (final status in [302, 200]) {
        final client = TrackingClient(
          (_) async => http.Response('x' * 65537, status),
        );
        final manager = ManagedConfigurationManager(
          profile: p,
          readCache: () async => null,
          writeCache: (_) async => fail('Invalid response saved'),
          clientFactory: () => client,
        );
        await manager.initialize();
        expect(manager.current.revision, 1);
        expect(client.closed, true);
        manager.dispose();
      }
      final client = TrackingClient((_) => Completer<http.Response>().future);
      final manager = ManagedConfigurationManager(
        profile: p,
        readCache: () async => null,
        writeCache: (_) async {},
        deadline: const Duration(milliseconds: 20),
        clientFactory: () => client,
      );
      await manager.initialize();
      expect(client.closed, true);
      expect(manager.current.revision, 1);
      manager.dispose();
    },
  );

  test('a failed durable save does not apply a new service', () async {
    final next = await sign(payload(revision: 2, serviceId: serviceTwo));
    final manager = ManagedConfigurationManager(
      profile: await profile(),
      readCache: () async => null,
      writeCache: (_) async => throw StateError('Storage unavailable'),
      clientFactory: () =>
          MockClient((_) async => http.Response(jsonEncode(next), 200)),
    );
    addTearDown(manager.dispose);
    await manager.initialize();
    expect(manager.current.serviceId, serviceOne);
  });

  test(
    'all API kinds and live/movie/episode/catch-up roots follow the managed service',
    () async {
      final p = await profile();
      final config = await p.verify(p.bootstrap);
      final requests = <Uri>[];
      final probes = <Uri>[];
      final api = XtreamApi(
        connections: ProviderConnections(configuration: () => config),
        client: MockClient((request) async {
          requests.add(request.url);
          return http.Response('[]', 200);
        }),
        streamProbe: (uri) async => probes.add(uri),
      );
      addTearDown(api.dispose);
      final session = Session(
        credentials: config.credentials('viewer', 'secret'),
        userInfo: const {},
        serverInfo: const {},
      );
      for (final kind in MediaKind.values) {
        await api.categories(session, kind);
        await api.items(session, kind);
        await api.prepareStreamUri(
          session,
          MediaItem(id: '1', name: 'Item', kind: kind),
          episode: kind == MediaKind.series
              ? const Episode(
                  id: '2',
                  title: 'Episode',
                  season: '1',
                  episodeNumber: 1,
                )
              : null,
        );
      }
      final now = DateTime.now();
      await api.prepareCatchupUri(
        session,
        const MediaItem(
          id: '1',
          name: 'Archive',
          kind: MediaKind.live,
          archiveEnabled: true,
          archiveDays: 7,
        ),
        EpgEntry(
          title: 'Programme',
          description: '',
          start: now.subtract(const Duration(hours: 2)),
          end: now.subtract(const Duration(hours: 1)),
          hasArchive: true,
        ),
      );
      expect(requests.length, 6);
      expect(
        requests.every(
          (uri) =>
              uri.host == 'primary.example.test' &&
              uri.path == '/root/player_api.php',
        ),
        true,
      );
      expect(probes.map((uri) => uri.pathSegments[1]), [
        'live',
        'movie',
        'series',
        'timeshift',
      ]);
      expect(probes.every((uri) => uri.host == 'primary.example.test'), true);
    },
  );

  test(
    'fallback preserves each endpoint path prefix and never forwards old credentials after replacement',
    () async {
      final p = await profile();
      var config = await p.verify(p.bootstrap);
      final connections = ProviderConnections(configuration: () => config);
      final probes = <Uri>[];
      final api = XtreamApi(
        connections: connections,
        streamProbe: (uri) async {
          probes.add(uri);
          if (uri.scheme == 'https') {
            throw const SocketException('Connection refused');
          }
        },
      );
      addTearDown(api.dispose);
      final session = Session(
        credentials: config.credentials('viewer', 'secret'),
        userInfo: const {},
        serverInfo: const {},
      );
      final result = await api.prepareStreamUri(
        session,
        const MediaItem(id: '1', name: 'Live', kind: MediaKind.live),
      );
      expect(result.host, 'backup.example.test');
      expect(result.path, '/other/live/viewer/secret/1.m3u8');
      config = await p.verify(
        await sign(payload(revision: 2, serviceId: serviceTwo)),
      );
      await expectLater(
        api.prepareStreamUri(
          session,
          const MediaItem(id: '2', name: 'Live', kind: MediaKind.live),
        ),
        throwsA(isA<ProviderServiceChanged>()),
      );
      expect(probes.length, 2);
      expect(
        () => api.streamUri(
          session,
          const MediaItem(id: '1', name: 'Live', kind: MediaKind.live),
        ),
        throwsA(isA<ProviderServiceChanged>()),
      );
    },
  );

  test(
    'replacement during a failed attempt prevents a fallback request with the old credentials',
    () async {
      final p = await profile();
      var config = await p.verify(p.bootstrap);
      final next = await p.verify(
        await sign(payload(revision: 2, serviceId: serviceTwo)),
      );
      final connections = ProviderConnections(configuration: () => config);
      var attempts = 0;
      await expectLater(
        connections.run(config.endpoints.first, ProviderRoute.api, (uri) async {
          attempts++;
          config = next;
          throw const SocketException('Connection refused');
        }, serviceId: serviceOne),
        throwsA(isA<ProviderServiceChanged>()),
      );
      expect(attempts, 1);
    },
  );

  test(
    'account aliases retain history, favourites, PIN and preferences across address changes, logout and cache clearing',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final store = await LocalStore.open(
        databaseFactory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      addTearDown(store.close);
      final p = await profile();
      final config = await p.verify(p.bootstrap);
      final legacy = Session(
        credentials: portalCredentials('viewer', 'secret'),
        userInfo: const {},
        serverInfo: const {},
      );
      const movie = MediaItem(id: '1', name: 'Movie', kind: MediaKind.movie);
      await store.saveProgress(
        legacy.accountId,
        movie,
        positionMs: 60000,
        durationMs: 120000,
      );
      await store.setFavorite(legacy.accountId, movie, true);
      await store.setPin(legacy.accountId, '1234');
      await store.saveSettings(
        legacy.accountId,
        const AppSettings(theme: 'cyberpunk'),
      );
      final migrated = (await restoreManagedSession(
        store,
        legacy,
        config,
        migrateLegacy: true,
      ))!;
      expect(migrated.accountId, legacy.accountId);
      await store.saveSession(migrated);
      expect((await store.readSession())!.accountId, legacy.accountId);
      await store.clearSession();
      await store.clearCache(migrated.accountId);
      final next = await p.verify(
        await sign({
          ...payload(revision: 2),
          'endpoints': ['https://moved.example.test/new'],
        }),
      );
      final rebound = await store.bindManagedAccount(
        Session(
          credentials: next.credentials('viewer', 'secret'),
          userInfo: const {},
          serverInfo: const {},
        ),
      );
      expect(rebound.accountId, legacy.accountId);
      expect((await store.history(rebound.accountId)).single.positionMs, 60000);
      expect((await store.favorites(rebound.accountId)).single.id, '1');
      expect(await store.verifyPin(rebound.accountId, '1234'), 0);
      expect((await store.readSettings(rebound.accountId)).theme, 'cyberpunk');
      final replaced = await p.verify(
        await sign(payload(revision: 3, serviceId: serviceTwo)),
      );
      expect(
        await restoreManagedSession(
          store,
          migrated,
          replaced,
          migrateLegacy: false,
        ),
        isNull,
      );
      final other = await store.bindManagedAccount(
        Session(
          credentials: replaced.credentials('viewer', 'secret'),
          userInfo: const {},
          serverInfo: const {},
        ),
      );
      expect(other.accountId, isNot(rebound.accountId));
      expect(await store.favorites(other.accountId), isEmpty);
      expect(await store.hasPin(other.accountId), false);
      expect(
        await restoreManagedSession(
          store,
          legacy,
          config,
          migrateLegacy: false,
        ),
        isNull,
      );
    },
  );
}
