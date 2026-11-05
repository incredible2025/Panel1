import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:streamline_iptv/data/models.dart';
import 'package:streamline_iptv/data/xtream_api.dart';

void main() {
  const credentials = Credentials(
    serverUrl: 'https://provider.example:8443/portal/',
    username: 'a +&/user',
    password: 'p?&/word',
  );
  const session = Session(
    credentials: credentials,
    userInfo: {},
    serverInfo: {},
  );

  test(
    'catch-up honours archive flags and keeps the provider start in cache',
    () async {
      final channel = MediaItem.fromJson({
        'stream_id': 42,
        'tv_archive': '1',
        'tv_archive_duration': '7',
      }, kind: MediaKind.live);
      final now = DateTime.now();
      final start = now.subtract(const Duration(days: 2));
      final end = start.add(const Duration(minutes: 30));
      final programme = EpgEntry.fromJson({
        'title': 'Replay',
        'start': '2026-10-30 23:05:00',
        'start_timestamp': start.millisecondsSinceEpoch ~/ 1000,
        'stop_timestamp': end.millisecondsSinceEpoch ~/ 1000,
        'has_archive': '1',
      })!;
      final cached = EpgEntry.fromJson(programme.toJson())!;
      final saved = MediaItem.fromJson(channel.toJson());
      expect(saved.supportsCatchup, isTrue);
      expect(cached.canReplayOn(saved, now), isTrue);
      expect(cached.canReplayOn(saved, start), isFalse);
      expect(
        cached.canReplayOn(saved, now.add(const Duration(days: 7))),
        isFalse,
      );
      expect(
        EpgEntry.fromJson({
          ...programme.toJson(),
          'has_archive': false,
        })!.canReplayOn(saved, now),
        isFalse,
      );
      expect(
        MediaItem.fromJson({
          ...channel.toJson(),
          'tv_archive': false,
        }).supportsCatchup,
        isFalse,
      );
      final api = XtreamApi();
      addTearDown(api.dispose);
      final uri = await api.prepareCatchupUri(session, saved, cached);
      expect(uri.pathSegments, [
        'portal',
        'timeshift',
        credentials.username,
        credentials.password,
        startsWith('3'),
        '2026-10-30:23-05',
        '42.m3u8',
      ]);
    },
  );

  test(
    'full guide uses provider schedule, sorts and removes duplicate or invalid intervals',
    () async {
      final api = XtreamApi(
        client: MockClient((request) async {
          expect(
            request.url.queryParameters['action'],
            'get_simple_data_table',
          );
          expect(request.url.queryParameters['stream_id'], '9');
          return http.Response(
            jsonEncode({
              'epg_listings': [
                {
                  'title': 'Later',
                  'start_timestamp': 2000000000,
                  'stop_timestamp': 2000003600,
                },
                {
                  'title': 'Earlier',
                  'start_timestamp': 1999996400,
                  'stop_timestamp': 2000000000,
                },
                {
                  'title': 'Duplicate',
                  'start_timestamp': 1999996400,
                  'stop_timestamp': 2000000000,
                },
                {
                  'title': 'Invalid',
                  'start_timestamp': 2000000000,
                  'stop_timestamp': 1999996400,
                },
              ],
            }),
            200,
          );
        }),
      );
      addTearDown(api.dispose);
      final result = await api.fullEpg(session, '9');
      expect(result.entries.map((entry) => entry.title), ['Earlier', 'Later']);
      expect(result.limited, false);
    },
  );

  test(
    'unsupported full guide falls back to a clearly limited short EPG',
    () async {
      final actions = <String>[];
      final api = XtreamApi(
        client: MockClient((request) async {
          final action = request.url.queryParameters['action']!;
          actions.add(action);
          if (action == 'get_simple_data_table') {
            return http.Response('Unavailable', 404);
          }
          expect(request.url.queryParameters['limit'], '192');
          return http.Response('{"epg_listings":[]}', 200);
        }),
      );
      addTearDown(api.dispose);
      final result = await api.fullEpg(session, '9');
      expect(actions, ['get_simple_data_table', 'get_short_epg']);
      expect(result.limited, true);
    },
  );

  test(
    'an HTTP 200 unsupported full-guide response still falls back to short EPG',
    () async {
      final api = XtreamApi(
        client: MockClient((request) async {
          return http.Response(
            request.url.queryParameters['action'] == 'get_simple_data_table'
                ? '[]'
                : '{"epg_listings":[{"title":"News","start_timestamp":2000000000,"stop_timestamp":2000003600}]}',
            200,
          );
        }),
      );
      addTearDown(api.dispose);
      final result = await api.fullEpg(session, '9');
      expect(result.limited, true);
      expect(result.entries.single.title, 'News');
    },
  );

  test(
    'authenticates with encoded GET credentials and normalizes server URL',
    () async {
      final api = XtreamApi(
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/portal/player_api.php');
          expect(request.url.queryParameters['username'], credentials.username);
          expect(request.url.queryParameters['password'], credentials.password);
          return http.Response(
            jsonEncode({
              'user_info': {'auth': '1', 'status': 'Active'},
              'server_info': {'timezone': 'Europe/London'},
            }),
            200,
          );
        }),
      );
      addTearDown(api.dispose);
      final result = await api.authenticate(credentials);
      expect(
        result.credentials.serverUrl,
        'https://provider.example:8443/portal',
      );
      expect(result.serverInfo['timezone'], 'Europe/London');
    },
  );

  test(
    'implements each category and item action with optional filters',
    () async {
      final requested = <String>[];
      final api = XtreamApi(
        client: MockClient((request) async {
          final query = request.url.queryParameters;
          final action = query['action']!;
          requested.add(action);
          if (action.endsWith('_categories')) {
            return http.Response(
              '[{"category_id":1,"category_name":"Popular"}]',
              200,
            );
          }
          expect(query['category_id'], '1');
          return http.Response(
            '[{"stream_id":2,"series_id":2,"name":"Sample"}]',
            200,
          );
        }),
      );
      addTearDown(api.dispose);
      for (final kind in MediaKind.values) {
        expect((await api.categories(session, kind)).single.id, '1');
        expect(
          (await api.items(session, kind, categoryId: '1')).single.kind,
          kind,
        );
      }
      expect(requested, [
        'get_live_categories',
        'get_live_streams',
        'get_vod_categories',
        'get_vod_streams',
        'get_series_categories',
        'get_series',
      ]);
    },
  );

  test('fetches details and short EPG using the correct identifiers', () async {
    final api = XtreamApi(
      client: MockClient((request) async {
        final query = request.url.queryParameters;
        switch (query['action']) {
          case 'get_vod_info':
            expect(query['vod_id'], 'movie-id');
            return http.Response(
              '{"info":{"plot":"Plot","cast":"Cast","rating":8},'
              '"movie_data":{"container_extension":"mkv"}}',
              200,
            );
          case 'get_series_info':
            expect(query['series_id'], 'series-id');
            return http.Response(
              '{"info":{},"episodes":{"1":[{"id":3,"episode_num":1}]}}',
              200,
            );
          case 'get_short_epg':
            expect(query['stream_id'], 'live-id');
            return http.Response(
              jsonEncode({
                'epg_listings': [
                  {
                    'title': base64Encode(utf8.encode('News')),
                    'start_timestamp': '1800000000',
                    'stop_timestamp': '1800003600',
                  },
                ],
              }),
              200,
            );
        }
        return http.Response('{}', 404);
      }),
    );
    addTearDown(api.dispose);
    final movie = await api.movieInfo(
      session,
      const MediaItem(id: 'movie-id', name: 'Movie', kind: MediaKind.movie),
    );
    expect(movie.plot, 'Plot');
    expect(movie.rating, '8');
    expect(movie.item.containerExtension, 'mkv');
    final series = await api.seriesInfo(
      session,
      const MediaItem(id: 'series-id', name: 'Series', kind: MediaKind.series),
    );
    expect(series.seasons['1']!.single.id, '3');
    expect((await api.shortEpg(session, 'live-id')).single.title, 'News');
  });

  test(
    'builds safe HLS, TS, VOD and episode paths with escaped credentials',
    () {
      final api = XtreamApi();
      addTearDown(api.dispose);
      for (final extension in ['m3u8', 'ts']) {
        final live = api.streamUri(
          session,
          MediaItem(
            id: '42',
            name: 'Channel',
            kind: MediaKind.live,
            containerExtension: extension,
          ),
        );
        expect(live.pathSegments, [
          'portal',
          'live',
          credentials.username,
          credentials.password,
          '42.$extension',
        ]);
      }
      final movie = api.streamUri(
        session,
        const MediaItem(
          id: '2',
          name: 'Movie',
          kind: MediaKind.movie,
          containerExtension: 'mkv',
        ),
      );
      expect(movie.pathSegments.last, '2.mkv');
      final series = api.streamUri(
        session,
        const MediaItem(id: '3', name: 'Series', kind: MediaKind.series),
        episode: const Episode(
          id: '4',
          title: 'Ep',
          season: '1',
          episodeNumber: 1,
        ),
      );
      expect(series.pathSegments[1], 'series');
      expect(series.pathSegments.last, '4.mp4');
    },
  );

  test('uses TS for HLS-default channels on TS-only accounts', () {
    final api = XtreamApi();
    addTearDown(api.dispose);
    const tsSession = Session(
      credentials: credentials,
      userInfo: {
        'allowed_output_formats': ['ts'],
      },
      serverInfo: {},
    );
    final channel = MediaItem.fromJson({
      'stream_id': 42,
      'name': 'Channel',
    }, kind: MediaKind.live);
    expect(channel.containerExtension, 'm3u8');
    expect(api.streamUri(tsSession, channel).pathSegments.last, '42.ts');
    expect(api.streamUri(session, channel).pathSegments.last, '42.m3u8');
    const explicitTs = MediaItem(
      id: '43',
      name: 'TS channel',
      kind: MediaKind.live,
      containerExtension: 'ts',
    );
    expect(api.streamUri(session, explicitTs).pathSegments.last, '43.ts');
  });

  test('authentication errors reject expired and inactive accounts', () async {
    for (final user in [
      {'auth': 0},
      {'auth': 1, 'status': 'Banned'},
      {'auth': 1, 'status': 'Active', 'exp_date': 1},
    ]) {
      final api = XtreamApi(
        client: MockClient(
          (_) async => http.Response(jsonEncode({'user_info': user}), 200),
        ),
      );
      await expectLater(
        api.authenticate(credentials),
        throwsA(isA<XtreamApiException>()),
      );
      api.dispose();
    }
  });

  test(
    'network and malformed response errors never reveal request credentials',
    () async {
      for (final mode in ['network', 'html', 'unauthorized', 'server']) {
        final api = XtreamApi(
          client: MockClient((request) async {
            if (mode == 'network') {
              throw http.ClientException('Failed ${request.url}', request.url);
            }
            if (mode == 'html') {
              return http.Response(
                '<html>password=${credentials.password}</html>',
                200,
              );
            }
            return http.Response(
              'secret ${credentials.password}',
              mode == 'unauthorized' ? 401 : 503,
            );
          }),
        );
        try {
          await api.categories(session, MediaKind.live);
          fail('A failed provider request should throw.');
        } catch (error) {
          expect(error, isA<XtreamApiException>());
          expect(error.toString(), isNot(contains(credentials.password)));
          expect(error.toString(), isNot(contains('provider.example')));
        } finally {
          api.dispose();
        }
      }
    },
  );
}
