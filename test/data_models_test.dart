import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:streamline_iptv/data/models.dart';

void main() {
  group('provider data parsing', () {
    test('reads cinematic artwork and release metadata from provider info', () {
      const movie = MediaItem(id: 'm', name: 'Movie', kind: MediaKind.movie);
      final detail = MovieDetail.fromJson(movie, {
        'info': {
          'backdrop_path': [
            null,
            '/relative.jpg',
            'https://art.example/backdrop.jpg',
          ],
          'releasedate': '2024-09-02',
        },
      });
      expect(detail.backdropUrl, 'https://art.example/backdrop.jpg');
      expect(detail.year, '2024');
      const series = MediaItem(id: 's', name: 'Series', kind: MediaKind.series);
      final show = SeriesDetail.fromJson(series, {
        'info': {
          'backdrop_path': 'https://art.example/show.jpg',
          'releaseDate': '2023-01-01',
          'genre': 'Drama',
          'rating': 8.4,
        },
      });
      expect(show.backdropUrl, 'https://art.example/show.jpg');
      expect(show.year, '2023');
      expect(show.genre, 'Drama');
      expect(show.rating, '8.4');
      expect(artworkValue(['bad', null, {}]), '');
      expect(releaseYear(null), '');
    });

    test('tolerates numeric IDs, null artwork and missing metadata', () {
      final category = Category.fromJson({
        'category_id': 7,
        'category_name': null,
      });
      expect(category.id, '7');
      expect(category.name, 'Uncategorized');
      final item = MediaItem.fromJson({
        'stream_id': 42,
        'name': 'A film',
        'stream_icon': null,
        'rating': 7.4,
      }, kind: MediaKind.movie);
      expect(item.id, '42');
      expect(item.imageUrl, '');
      expect(item.rating, '7.4');
      expect(MediaItem.fromJson(item.toJson()).toJson(), item.toJson());
      expect(MovieDetail.fromJson(item, {'info': []}).plot, '');
    });

    test('sorts seasons and episode numbers from mixed provider types', () {
      const item = MediaItem(id: '3', name: 'Series', kind: MediaKind.series);
      final detail = SeriesDetail.fromJson(item, {
        'info': {'plot': 'A story', 'cast': 'One, Two'},
        'episodes': {
          '10': [
            {'id': 100, 'episode_num': '2', 'container_extension': 'mkv'},
            {'id': '99', 'episode_num': 1, 'title': 'First'},
          ],
          '2': [],
        },
      });
      expect(detail.seasons.keys, ['2', '10']);
      expect(detail.seasons['10']!.map((e) => e.id), ['99', '100']);
      expect(detail.seasons['10']!.last.containerExtension, 'mkv');
      expect(detail.seasons['10']!.first.season, '10');
    });

    test('decodes UTF-8 base64 EPG and roundtrips cached entries', () {
      final entry = EpgEntry.fromJson({
        'title': base64Encode(utf8.encode('Café Tonight')),
        'description': base64Encode(utf8.encode('News & films')),
        'start_timestamp': '1800000000',
        'stop_timestamp': 1800003600,
      })!;
      expect(entry.title, 'Café Tonight');
      expect(entry.end.difference(entry.start), const Duration(hours: 1));
      final cached = EpgEntry.fromJson(entry.toJson())!;
      expect(cached.title, entry.title);
      expect(cached.start, entry.start);
      expect(EpgEntry.fromJson({'start': 'broken', 'end': null}), isNull);
      expect(
        EpgEntry.fromJson({
          'title': 'News Tonight',
          'start_timestamp': 1800000000,
          'stop_timestamp': 1800003600,
        })!.title,
        'News Tonight',
      );
    });
  });

  group('account isolation', () {
    Session session(
      String server,
      String username, [
      String password = 'password',
    ]) => Session(
      credentials: Credentials(
        serverUrl: server,
        username: username,
        password: password,
      ),
      userInfo: const {},
      serverInfo: const {},
    );

    test('canonical provider identity persists through password changes', () {
      final first = session(
        'HTTPS://PROVIDER.EXAMPLE/portal/player_api.php?username=old',
        'alice',
      );
      final second = session(
        'https://provider.example/portal/',
        'alice',
        'new-password',
      );
      expect(first.accountId, second.accountId);
      expect(first.accountId.length, 64);
      expect(first.accountId, isNot(contains('alice')));
      expect(
        first.accountId,
        isNot(session('https://other.example', 'alice').accountId),
      );
      expect(
        first.accountId,
        isNot(session('https://provider.example/portal', 'bob').accountId),
      );
    });

    test('normalizes a server path and rejects unsupported schemes', () {
      expect(
        normalizeServerUri(
          ' example.com:8443/portal/get.php?password=secret ',
        ).toString(),
        'https://example.com:8443/portal',
      );
      expect(
        () => normalizeServerUri('ftp://example.com'),
        throwsFormatException,
      );
      expect(
        () => normalizeServerUri('https://user:pass@example.com'),
        throwsFormatException,
      );
    });
  });

  group('continue watching thresholds', () {
    const item = MediaItem(id: '1', name: 'Film', kind: MediaKind.movie);
    WatchEntry progress(int position, [int duration = 10000]) => WatchEntry(
      item: item,
      positionMs: position,
      durationMs: duration,
      lastAccessed: DateTime(2026),
    );

    test('only resumes strictly above 5% and below 95%', () {
      expect(progress(500).canResume, false);
      expect(progress(501).canResume, true);
      expect(progress(9499).canResume, true);
      expect(progress(9500).canResume, false);
      expect(progress(0, 0).canResume, false);
    });

    test('clamps invalid progress to the displayable range', () {
      expect(progress(-100).progress, 0);
      expect(progress(20000).progress, 1);
      expect(progress(100, 0).progress, 0);
    });
  });
}
