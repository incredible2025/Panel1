import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local_store.dart';
import '../data/models.dart';
import '../data/xtream_api.dart';

final storeProvider = Provider<LocalStore>((ref) {
  throw StateError('LocalStore must be initialized before launching the app.');
});

final apiProvider = Provider<XtreamApi>((ref) {
  final api = XtreamApi();
  ref.onDispose(api.dispose);
  return api;
});

final sessionProvider = StateProvider<Session?>((ref) => null);
final isTvProvider = Provider<bool>((ref) => false);

final historyProvider = FutureProvider<List<WatchEntry>>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return [];
  return ref.watch(storeProvider).history(session.accountId);
});

final seriesHistoryProvider = FutureProvider<List<EpisodeWatchEntry>>((
  ref,
) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return [];
  return ref.watch(storeProvider).seriesHistory(session.accountId);
});

final guideRefreshProvider = StateProvider<int>((ref) => 0);

final guideScheduleProvider = FutureProvider.autoDispose
    .family<GuideSchedule, String>((ref, id) async {
      final session = ref.watch(sessionProvider);
      if (session == null) return const GuideSchedule([]);
      final refresh = ref.watch(guideRefreshProvider);
      final store = ref.watch(storeProvider);
      final key = 'guide:$id';
      GuideSchedule? decode(dynamic data) {
        if (data is! Map) return null;
        return GuideSchedule(
          objectList(
            data['entries'],
          ).map(EpgEntry.fromJson).whereType<EpgEntry>().toList(),
          limited: data['limited'] == true,
          cached: true,
        );
      }

      try {
        if (refresh == 0) {
          try {
            final recent = decode(
              await store.cachedJson(
                session.accountId,
                key,
                maxAge: const Duration(minutes: 15),
              ),
            );
            if (recent != null) return recent;
          } catch (_) {
            /* Read failures do not prevent a live provider request. */
          }
        }
        final schedule = await ref.watch(apiProvider).fullEpg(session, id);
        try {
          await store.cacheJson(session.accountId, key, {
            'limited': schedule.limited,
            'entries': [for (final entry in schedule.entries) entry.toJson()],
          });
        } catch (_) {
          /* Cache failure must not hide a valid live schedule. */
        }
        return schedule;
      } catch (_) {
        try {
          final cached = decode(
            await store.cachedJson(
              session.accountId,
              key,
              maxAge: const Duration(hours: 24),
            ),
          );
          if (cached != null) return cached;
        } catch (_) {
          /* Keep the provider's neutral error. */
        }
        rethrow;
      }
    });

final favoritesProvider = FutureProvider<List<MediaItem>>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return [];
  return ref.watch(storeProvider).favorites(session.accountId);
});

final recentChannelsProvider = FutureProvider<List<MediaItem>>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return [];
  return ref.watch(storeProvider).recentChannels(session.accountId);
});

final categoriesProvider = FutureProvider.family<List<Category>, MediaKind>((
  ref,
  kind,
) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return [];
  return ref.watch(apiProvider).categories(session, kind);
});

final itemsProvider = FutureProvider.family<List<MediaItem>, MediaKind>((
  ref,
  kind,
) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return [];
  return ref.watch(apiProvider).items(session, kind);
});

final movieDetailProvider = FutureProvider.autoDispose
    .family<MovieDetail, MediaItem>((ref, item) {
      final session = ref.watch(sessionProvider);
      if (session == null) throw StateError('Please sign in again.');
      return ref.watch(apiProvider).movieInfo(session, item);
    });

final seriesDetailProvider = FutureProvider.autoDispose
    .family<SeriesDetail, MediaItem>((ref, item) {
      final session = ref.watch(sessionProvider);
      if (session == null) throw StateError('Please sign in again.');
      return ref.watch(apiProvider).seriesInfo(session, item);
    });

final epgProvider = FutureProvider.autoDispose.family<List<EpgEntry>, String>((
  ref,
  id,
) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return [];
  final store = ref.watch(storeProvider);
  final key = 'epg:$id';
  try {
    final entries = await ref.watch(apiProvider).shortEpg(session, id);
    await store.cacheJson(session.accountId, key, [
      for (final entry in entries)
        {
          'title': entry.title,
          'description': entry.description,
          'start': entry.start.toIso8601String(),
          'end': entry.end.toIso8601String(),
        },
    ]);
    return entries;
  } catch (_) {
    final cached = await store.cachedJson(
      session.accountId,
      key,
      maxAge: const Duration(hours: 2),
    );
    if (cached is List) {
      return cached.map((entry) {
        final value = Map<String, dynamic>.from(entry as Map);
        return EpgEntry(
          title: value['title'] as String,
          description: value['description'] as String,
          start: DateTime.parse(value['start'] as String),
          end: DateTime.parse(value['end'] as String),
        );
      }).toList();
    }
    rethrow;
  }
});
