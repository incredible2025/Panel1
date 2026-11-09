import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:streamline_iptv/data/models.dart';
import 'package:streamline_iptv/data/recommendations.dart';
import 'package:streamline_iptv/data/movie_genre_index.dart';

const crime = MediaItem(
  id: '1',
  name: 'Crime source 4K',
  kind: MediaKind.movie,
  categoryId: '4k',
  genre: 'Action, Crime, Thriller',
);
WatchEntry watched(MediaItem item) => WatchEntry(
  item: item,
  positionMs: 600000,
  durationMs: 3600000,
  lastAccessed: DateTime.now(),
);
MediaItem film(String id, String genre, {String category = '4k'}) => MediaItem(
  id: id,
  name: 'Film $id',
  kind: MediaKind.movie,
  categoryId: category,
  genre: genre,
);

void main() {
  test(
    'lookup caps and cooldowns bound discovery while rotating through unknown films',
    () async {
      var now = DateTime.utc(2026, 11, 9);
      final calls = <String>[];
      final index = MovieGenreIndex(
        maximumFetches: 4,
        clock: () => now,
        read: () async => null,
        write: (_) async {},
        fetch: (item) async {
          calls.add(item.id);
          return MovieDetail(item: item, genre: 'Crime');
        },
      );
      final catalog = [crime, for (var i = 2; i < 20; i++) film('$i', '')];
      await index.enrich(catalog, [
        watched(crime),
      ], active: () => true).toList();
      expect(calls.length, 4);
      await index.enrich(catalog, [
        watched(crime),
      ], active: () => true).toList();
      expect(calls.length, 4);
      now = now.add(const Duration(minutes: 31));
      await index.enrich(catalog, [
        watched(crime),
      ], active: () => true).toList();
      expect(calls.length, 8);
      expect(calls.toSet().length, 8);
    },
  );
  test('a one-request cap includes watched-film metadata lookups', () async {
    var calls = 0;
    final one = film('1', ''), two = film('2', '');
    final index = MovieGenreIndex(
      maximumFetches: 1,
      read: () async => null,
      write: (_) async {},
      fetch: (item) async {
        calls++;
        return MovieDetail(item: item, genre: 'Crime');
      },
    );
    await index
        .enrich([one, two], [watched(one), watched(two)], active: () => true)
        .toList();
    expect(calls, 1);
  });
  test(
    'overlapping refreshes share two request slots and cancellation does not block discovery',
    () async {
      var firstActive = true, running = 0, peak = 0;
      final calls = <String>[];
      final gate = Completer<void>();
      final source = crime.withGenre('');
      final index = MovieGenreIndex(
        read: () async => null,
        write: (_) async {},
        fetch: (item) async {
          calls.add(item.id);
          running++;
          if (running > peak) peak = running;
          await gate.future;
          running--;
          return MovieDetail(item: item, genre: 'Crime');
        },
      );
      final catalog = [source, film('2', ''), film('3', '')];
      final first = index.enrich(catalog, [
        watched(source),
      ], active: () => firstActive).toList();
      await Future<void>.delayed(Duration.zero);
      firstActive = false;
      final second = index.enrich(catalog, [
        watched(source),
      ], active: () => true).toList();
      await Future<void>.delayed(Duration.zero);
      gate.complete();
      await first;
      final result = await second;
      expect(peak, 2);
      expect(calls.toSet().length, calls.length);
      expect(result.last.every((item) => item.genre == 'Crime'), true);
    },
  );
  test(
    'same folder is not similarity; strong genre matches can cross folders',
    () {
      final match = film('2', 'Crime / Thriller', category: 'hd');
      final comedy = film('3', 'Action, Comedy, Family');
      final unknown = film('4', '');
      final result = recommendMovies(
        [crime, match, comedy, unknown],
        [watched(crime)],
      );
      expect(result.single.items, [match]);
      expect(result.single.subtitle, contains('Crime'));
      expect(result.single.subtitle, isNot(contains('categories')));
    },
  );
  test(
    'documentaries match documentaries rather than fictional crime films',
    () {
      final source = film('1', 'Documentary, Crime');
      final match = film('2', 'Documentaries / Crime', category: 'hd');
      final fiction = film('3', 'Crime, Thriller');
      expect(
        recommendMovies(
          [source, match, fiction],
          [watched(source)],
        ).single.items,
        [match],
      );
    },
  );
  test(
    'metadata missing on either side never falls back to category matching',
    () {
      final unknown = film('2', '');
      expect(recommendMovies([crime, unknown], [watched(crime)]), isEmpty);
      expect(recommendMovies([unknown, crime], [watched(unknown)]), isEmpty);
    },
  );
  test('equivalent quality and codec editions are excluded', () {
    final duplicate = MediaItem(
      id: '9',
      name: 'Crime source HD HEVC',
      kind: MediaKind.movie,
      genre: crime.genre,
    );
    expect(recommendMovies([crime, duplicate], [watched(crime)]), isEmpty);
    expect(movieGenres('Sci-fi | documentaries'), {
      'Science Fiction',
      'Documentary',
    });
  });
  test('catalogue and detail genres survive storage round trips', () {
    final item = MediaItem.fromJson({
      'stream_id': 1,
      'name': 'Test',
      'genres': [
        {'id': 80, 'name': 'Crime'},
        {'name': 'Thriller'},
      ],
    });
    expect(movieGenres(item.genre), {'Crime', 'Thriller'});
    expect(MediaItem.fromJson(item.toJson()).genre, item.genre);
    final detail = MovieDetail.fromJson(item.withGenre(''), {
      'info': {'genre': 'Documentary'},
    });
    expect(detail.item.genre, 'Documentary');
    expect(MediaItem.fromJson(detail.item.toJson()).genre, 'Documentary');
  });
  test(
    'metadata discovery fills missing genres, persists them and reuses cache',
    () async {
      Map<String, dynamic>? cache;
      final calls = <String>[];
      final catalog = [crime.withGenre(''), film('2', '')];
      MovieGenreIndex index() => MovieGenreIndex(
        read: () async => cache,
        write: (value) async => cache = value,
        fetch: (item) async {
          calls.add(item.id);
          return MovieDetail(item: item, genre: 'Crime, Thriller');
        },
      );
      final updates = await index().enrich(catalog, [
        watched(catalog.first),
      ], active: () => true).toList();
      expect(calls.toSet(), {'1', '2'});
      expect(
        recommendMovies(updates.last, [
          watched(catalog.first),
        ]).single.items.single.id,
        '2',
      );
      calls.clear();
      final cached = await index().enrich(catalog, [
        watched(catalog.first),
      ], active: () => true).toList();
      expect(calls, isEmpty);
      expect(cached.first.last.genre, 'Crime, Thriller');
    },
  );
  test(
    'at most two lookups run concurrently and disposal stops further batches',
    () async {
      var active = true, running = 0, peak = 0, calls = 0;
      final gate = Completer<void>();
      final index = MovieGenreIndex(
        read: () async => null,
        write: (_) async {},
        fetch: (item) async {
          calls++;
          running++;
          if (running > peak) peak = running;
          await gate.future;
          running--;
          return MovieDetail(item: item, genre: 'Crime');
        },
      );
      final completion = index
          .enrich(
            [crime, for (var i = 2; i < 12; i++) film('$i', '')],
            [watched(crime)],
            active: () => active,
          )
          .toList();
      await Future<void>.delayed(Duration.zero);
      expect(peak, 2);
      active = false;
      gate.complete();
      await completion;
      expect(calls, 2);
    },
  );
  test(
    'cache failure is harmless; missing metadata is negatively cached',
    () async {
      var calls = 0;
      final unknown = film('2', '');
      final index = MovieGenreIndex(
        scanInterval: Duration.zero,
        read: () async => throw StateError('cache'),
        write: (_) async => throw StateError('cache'),
        fetch: (item) async {
          calls++;
          return MovieDetail(item: item);
        },
      );
      await index
          .enrich([crime, unknown], [watched(crime)], active: () => true)
          .toList();
      await index
          .enrich([crime, unknown], [watched(crime)], active: () => true)
          .toList();
      expect(calls, 1);
    },
  );
  test('recycled catalogue IDs never inherit another film genre', () async {
    Map<String, dynamic>? cache;
    final original = film('2', 'Crime');
    final first = MovieGenreIndex(
      read: () async => null,
      write: (data) async => cache = data,
      fetch: (item) async => MovieDetail(item: item),
    );
    await first.remember(MovieDetail(item: original, genre: 'Crime'));
    final replacement = MediaItem(
      id: '2',
      name: 'Different film',
      kind: MediaKind.movie,
    );
    final index = MovieGenreIndex(
      maximumFetches: 0,
      read: () async => cache,
      write: (_) async {},
      fetch: (item) async => MovieDetail(item: item),
    );
    final updates = await index
        .enrich([replacement], [], active: () => true)
        .toList();
    expect(updates.single.single.genre, isEmpty);
  });
}
