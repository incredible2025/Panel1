import 'dart:math' as math;
import 'models.dart';

class RecommendationShelf {
  const RecommendationShelf(this.title, this.items, {this.sourceId});
  final String title;
  final List<MediaItem> items;
  final String? sourceId;
}

/// Account-scoped content-based recommendations. Only meaningful playback is a
/// signal: opening a detail page never counts as watching a film.
List<RecommendationShelf> recommendMovies(
  List<MediaItem> catalog,
  List<WatchEntry> history, {
  DateTime? now,
}) {
  final time = now ?? DateTime.now();
  String title(MediaItem item) => item.name
      .toLowerCase()
      .replaceAll(RegExp(r'\b(2160p|1080p|720p|4k|uhd|fhd|hd)\b'), '')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();
  final watched =
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
  if (watched.isEmpty) return [];
  final seenIds = watched.map((entry) => entry.item.id).toSet();
  final seenTitles = watched.map((entry) => title(entry.item)).toSet();
  final byId = {for (final item in catalog) item.id: item};
  final weights = <String, double>{};
  for (final entry in watched.take(40)) {
    final category = (byId[entry.item.id] ?? entry.item).categoryId;
    if (category.isEmpty) continue;
    final days = math.max(0, time.difference(entry.lastAccessed).inDays);
    weights[category] =
        (weights[category] ?? 0) + (.5 + entry.progress) / (1 + days / 14);
  }
  final ids = <String>{};
  final titles = <String>{};
  final candidates = catalog
      .where(
        (item) =>
            item.kind == MediaKind.movie &&
            !seenIds.contains(item.id) &&
            !seenTitles.contains(title(item)) &&
            (weights[item.categoryId] ?? 0) > 0 &&
            ids.add(item.id) &&
            titles.add(title(item)),
      )
      .toList();
  double score(MediaItem item) =>
      (weights[item.categoryId] ?? 0) * 10 +
      (double.tryParse(item.rating) ?? 0).clamp(0, 10) / 10;
  candidates.sort((a, b) {
    final match = score(b).compareTo(score(a));
    if (match != 0) return match;
    final date = (b.addedAt ?? DateTime(1970)).compareTo(
      a.addedAt ?? DateTime(1970),
    );
    return date != 0 ? date : a.id.compareTo(b.id);
  });
  if (candidates.isEmpty) return [];
  final source = watched
      .where(
        (entry) => candidates.any(
          (item) =>
              item.categoryId == (byId[entry.item.id] ?? entry.item).categoryId,
        ),
      )
      .first;
  final sourceCategory = (byId[source.item.id] ?? source.item).categoryId;
  final similar = candidates
      .where((item) => item.categoryId == sourceCategory)
      .take(16)
      .toList();
  final similarIds = similar.map((item) => item.id).toSet();
  final others = candidates
      .where((item) => !similarIds.contains(item.id))
      .take(16)
      .toList();
  return [
    RecommendationShelf(
      'Because you watched ${source.item.name}',
      similar,
      sourceId: source.item.id,
    ),
    if (others.isNotEmpty) RecommendationShelf('Picked for you', others),
  ];
}
