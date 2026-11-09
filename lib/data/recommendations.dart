import 'dart:math' as math;
import 'models.dart';

class RecommendationShelf {
  const RecommendationShelf(
    this.title,
    this.items, {
    this.sourceId,
    this.subtitle = 'Based on the genres you watch · On this device',
  });
  final String title;
  final List<MediaItem> items;
  final String? sourceId;
  final String subtitle;
}

final _qualityTokens = RegExp(
  r'\b(2160p|1080p|720p|4k|uhd|fhd|hd|hevc|hdr10|hdr|h265|h264|x265|x264|bluray|blu ray|10bit)\b',
);
final _titlePunctuation = RegExp(r'[^a-z0-9\u00c0-\uffff]+');

String movieIdentity(MediaItem item) => item.name
    .toLowerCase()
    .replaceAll(_qualityTokens, '')
    .replaceAll(_titlePunctuation, ' ')
    .trim();

/// Explicit metadata only: a catalogue folder, title or synopsis is not a genre.
Set<String> movieGenres(String raw) {
  final value = raw.toLowerCase().replaceAll('&amp;', '&');
  const patterns = {
    'Action': r'action',
    'Adventure': r'adventure',
    'Animation': r'animation|animated',
    'Comedy': r'comedy|comedies',
    'Crime': r'crime',
    'Documentary': r'documentary|documentaries',
    'Drama': r'drama',
    'Family': r'family',
    'Fantasy': r'fantasy',
    'History': r'history|historical',
    'Horror': r'horror',
    'Music': r'music|musical',
    'Mystery': r'mystery',
    'Romance': r'romance|romantic',
    'Science Fiction': r'science[ -]fiction|sci[ -]?fi',
    'Thriller': r'thriller|thrillers',
    'War': r'war',
    'Western': r'western',
  };
  return {
    for (final entry in patterns.entries)
      if (RegExp('\\b(?:${entry.value})\\b').hasMatch(value)) entry.key,
  };
}

List<WatchEntry> meaningfulMovieHistory(List<WatchEntry> history) =>
    history
        .where(
          (entry) =>
              entry.item.kind == MediaKind.movie &&
              entry.durationMs > 0 &&
              entry.positionMs >= 60000 &&
              entry.progress >= .05,
        )
        .toList()
      ..sort((a, b) => b.lastAccessed.compareTo(a.lastAccessed));

double _weight(String genre) =>
    {'Action', 'Adventure', 'Drama', 'Comedy'}.contains(genre) ? 1 : 2;
double _similarity(Set<String> source, Set<String> candidate) {
  if (source.isEmpty ||
      candidate.isEmpty ||
      source.contains('Documentary') != candidate.contains('Documentary')) {
    return 0;
  }
  final shared = source.intersection(candidate);
  if (shared.isEmpty) return 0;
  final specific = source.where((genre) => _weight(genre) > 1).toSet();
  if (specific.isNotEmpty && shared.intersection(specific).isEmpty) return 0;
  final numerator = shared.fold<double>(
    0,
    (sum, genre) => sum + _weight(genre),
  );
  final denominator = source
      .union(candidate)
      .fold<double>(0, (sum, genre) => sum + _weight(genre));
  final score = numerator / denominator;
  return score >= .25 ? score : 0;
}

/// Genre overlap drives matching; ratings only break otherwise similar results.
List<RecommendationShelf> recommendMovies(
  List<MediaItem> catalog,
  List<WatchEntry> history, {
  DateTime? now,
}) {
  final time = now ?? DateTime.now();
  final watched = meaningfulMovieHistory(history);
  if (watched.isEmpty) return [];
  final genreCache = <String, Set<String>>{};
  Set<String> genres(MediaItem item) =>
      genreCache.putIfAbsent(item.genre, () => movieGenres(item.genre));
  final similarities = <Set<String>, Map<Set<String>, double>>{};
  double similarity(Set<String> source, Set<String> candidate) => similarities
      .putIfAbsent(source, () => {})
      .putIfAbsent(candidate, () => _similarity(source, candidate));
  final byId = {for (final item in catalog) item.id: item};
  MediaItem current(WatchEntry entry) {
    final available = byId[entry.item.id];
    return available == null || genres(available).isEmpty
        ? entry.item
        : available;
  }

  final seenIds = watched.map((e) => e.item.id).toSet();
  final seenTitles = watched.map((e) => movieIdentity(e.item)).toSet();
  final ids = <String>{}, titles = <String>{};
  final candidates = catalog
      .where(
        (item) =>
            item.kind == MediaKind.movie &&
            !seenIds.contains(item.id) &&
            !seenTitles.contains(movieIdentity(item)) &&
            genres(item).isNotEmpty &&
            ids.add(item.id) &&
            titles.add(movieIdentity(item)),
      )
      .toList();
  if (candidates.isEmpty) return [];
  final sources = watched
      .take(40)
      .where((e) => genres(current(e)).isNotEmpty)
      .toList();
  if (sources.isEmpty) return [];
  List<MediaItem> ranked(double Function(MediaItem) score) {
    final scores = {for (final item in candidates) item.id: score(item)};
    final result = candidates.where((item) => scores[item.id]! > 0).toList();
    result.sort((a, b) {
      final match = scores[b.id]!.compareTo(scores[a.id]!);
      if (match != 0) return match;
      final rating = (double.tryParse(b.rating) ?? 0).compareTo(
        double.tryParse(a.rating) ?? 0,
      );
      if (rating != 0) return rating;
      return a.id.compareTo(b.id);
    });
    return result;
  }

  WatchEntry? source;
  var similar = <MediaItem>[];
  for (final entry in sources) {
    final sourceGenres = genres(current(entry));
    final matches = ranked((item) => similarity(sourceGenres, genres(item)));
    if (matches.isNotEmpty) {
      source = entry;
      similar = matches.take(16).toList();
      break;
    }
  }
  if (source == null) return [];
  final selected = similar.map((e) => e.id).toSet();
  final profiles = <String, (Set<String>, double)>{};
  for (final entry in sources) {
    final profile = genres(current(entry));
    final key = profile.join('|');
    final days = math.max(0, time.difference(entry.lastAccessed).inDays);
    final weight = (.5 + entry.progress.clamp(0, 1)) / (1 + days / 14);
    profiles[key] = (profile, (profiles[key]?.$2 ?? 0) + weight);
  }
  double personalScore(MediaItem item) => profiles.values.fold<double>(
    0,
    (sum, profile) => sum + similarity(profile.$1, genres(item)) * profile.$2,
  );
  final others = ranked(
    personalScore,
  ).where((item) => !selected.contains(item.id)).take(16).toList();
  final labels = genres(current(source)).take(4).join(' · ');
  return [
    RecommendationShelf(
      'Because you watched ${source.item.name}',
      similar,
      sourceId: source.item.id,
      subtitle: '$labels · Similar genres · On this device',
    ),
    if (others.isNotEmpty) RecommendationShelf('Picked for you', others),
  ];
}
