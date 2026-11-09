import 'dart:async';
import 'models.dart';
import 'recommendations.dart';

/// A small, account-scoped index. Discovery is bounded and never blocks browsing.
class MovieGenreIndex {
  MovieGenreIndex({
    required this.read,
    required this.write,
    required this.fetch,
    DateTime Function()? clock,
    this.maximumFetches = 32,
    this.scanInterval = const Duration(minutes: 30),
    this.budget = const Duration(seconds: 30),
  }) : clock = clock ?? DateTime.now;
  final Future<dynamic> Function() read;
  final Future<void> Function(Map<String, dynamic>) write;
  final Future<MovieDetail> Function(MediaItem) fetch;
  final DateTime Function() clock;
  final int maximumFetches;
  final Duration scanInterval, budget;
  final _entries = <String, Map<String, dynamic>>{};
  final _knownGenres = <String, bool>{};
  bool _known(String value) =>
      _knownGenres.putIfAbsent(value, () => movieGenres(value).isNotEmpty);
  Future<void>? _loading;
  Future<void> _writes = Future.value();
  final _fetchSlots = [Future<void>.value(), Future<void>.value()];
  int _nextSlot = 0;

  Future<void> _lookup(MediaItem item, bool Function() active) {
    final slot = _nextSlot;
    _nextSlot = 1 - slot;
    final work = _fetchSlots[slot].then((_) async {
      if (!active() || _fresh(item)) return;
      final detail = await fetch(item);
      _record(item, detail.genre.isNotEmpty ? detail.genre : detail.item.genre);
    });
    _fetchSlots[slot] = work.then<void>((_) {}, onError: (Object _) {});
    return work;
  }

  int _cursor = 0;
  DateTime? _lastScan;

  Future<void> _load() => _loading ??= (() async {
    try {
      final data = objectValue(await read());
      _cursor = intValue(data['cursor']);
      final stamp = intValue(data['lastScan']);
      if (stamp > 0) _lastScan = DateTime.fromMillisecondsSinceEpoch(stamp);
      for (final entry in objectValue(data['entries']).entries.take(8000)) {
        _entries[entry.key] = objectValue(entry.value);
      }
    } catch (_) {
      /* A missing cache never prevents recommendations. */
    }
  })();

  bool _fresh(MediaItem item) {
    if (_known(item.genre)) return true;
    final cached = _entries[item.id];
    if (cached == null || cached['title'] != movieIdentity(item)) return false;
    final checked = intValue(cached['checked']);
    final age = clock().millisecondsSinceEpoch - checked;
    final known = _known(textValue(cached['genre']));
    return age >= 0 && age < Duration(days: known ? 30 : 1).inMilliseconds;
  }

  List<MediaItem> apply(List<MediaItem> catalog) => catalog.map((item) {
    if (_known(item.genre) || !_fresh(item)) return item;
    final genre = textValue(_entries[item.id]?['genre']);
    return genre.isEmpty ? item : item.withGenre(genre);
  }).toList();

  void _record(MediaItem item, String genre) {
    _entries.remove(item.id);
    _entries[item.id] = {
      'title': movieIdentity(item),
      'genre': genre,
      'checked': clock().millisecondsSinceEpoch,
    };
    while (_entries.length > 8000) {
      _entries.remove(_entries.keys.first);
    }
  }

  Future<void> _save() {
    _writes = _writes.then((_) async {
      try {
        await write({
          'cursor': _cursor,
          'lastScan': _lastScan?.millisecondsSinceEpoch,
          'entries': {
            for (final e in _entries.entries)
              e.key: Map<String, dynamic>.of(e.value),
          },
        });
      } catch (_) {
        /* Keep useful in-memory metadata if storage is unavailable. */
      }
    });
    return _writes;
  }

  Future<void> remember(MovieDetail detail) async {
    await _load();
    _record(
      detail.item,
      detail.genre.isNotEmpty ? detail.genre : detail.item.genre,
    );
    await _save();
  }

  Stream<List<MediaItem>> enrich(
    List<MediaItem> catalog,
    List<WatchEntry> history, {
    required bool Function() active,
  }) async* {
    await _load();
    if (!active()) return;
    final watched = meaningfulMovieHistory(history);
    for (final entry in watched.take(40)) {
      if (_known(entry.item.genre) && !_fresh(entry.item.withGenre(''))) {
        _record(entry.item, entry.item.genre);
      }
    }
    yield apply(catalog);
    if (watched.isEmpty || maximumFetches <= 0) return;
    final byId = {for (final item in catalog) item.id: item};
    final jobs = <(MediaItem, int?)>[];
    final queued = <String>{};
    for (final entry in watched.take(8)) {
      if (jobs.length >= maximumFetches) break;
      final item = byId[entry.item.id];
      if (item != null && !_fresh(item) && queued.add(item.id)) {
        jobs.add((item, null));
      }
    }
    final age = _lastScan == null ? null : clock().difference(_lastScan!);
    final scanEligible = age == null || age.isNegative || age >= scanInterval;
    if (scanEligible) {
      // Folder IDs only prioritise a small metadata lookup shortlist. They never
      // count as genre matches, and the rotating scan still explores all folders.
      final folders =
          watched
              .take(8)
              .map((entry) => (byId[entry.item.id] ?? entry.item).categoryId)
              .toSet()
            ..remove('');
      var priority = 0;
      for (final item in catalog) {
        if (jobs.length >= maximumFetches || priority >= maximumFetches ~/ 4) {
          break;
        }
        if (folders.contains(item.categoryId) &&
            !_fresh(item) &&
            queued.add(item.id)) {
          jobs.add((item, null));
          priority++;
        }
      }
      for (var i = 0; i < catalog.length && jobs.length < maximumFetches; i++) {
        final index = (_cursor + i) % catalog.length;
        final item = catalog[index];
        if (item.kind == MediaKind.movie &&
            !_fresh(item) &&
            queued.add(item.id)) {
          jobs.add((item, (index + 1) % catalog.length));
        }
      }
    }
    await _save();
    final watch = Stopwatch()..start();
    var failures = 0;
    for (
      var offset = 0;
      offset < jobs.length && offset < maximumFetches;
      offset += 2
    ) {
      if (!active() || watch.elapsed >= budget || failures >= 2) break;
      final batch = jobs.skip(offset).take(2).toList();
      await Future.wait(
        batch.map((job) async {
          if (!active() || _fresh(job.$1)) return;
          try {
            await _lookup(job.$1, active);
          } catch (_) {
            failures++;
          }
        }),
      );
      for (final job in batch) {
        if (job.$2 != null) _cursor = job.$2!;
      }
      if (offset < 4 || offset % 8 == 6 || offset + 2 >= jobs.length) {
        await _save();
        if (!active()) return;
        yield apply(catalog);
      }
    }
    if (active() && scanEligible) _lastScan = clock();
    await _save();
  }
}
