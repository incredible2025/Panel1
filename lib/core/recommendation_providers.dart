import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models.dart';
import '../data/recommendations.dart';
import 'providers.dart';
import 'settings_controller.dart';

final movieRecommendationsProvider =
    StreamProvider.autoDispose<List<RecommendationShelf>>((ref) async* {
      final settings = ref.watch(settingsProvider).asData?.value;
      final unlocked = ref.watch(parentalSessionProvider);
      final index = ref.watch(movieGenreIndexProvider);
      if (settings == null || !settings.recommendations || index == null) {
        yield [];
        return;
      }
      var active = true;
      ref.onDispose(() => active = false);
      final catalogFuture = ref.watch(itemsProvider(MediaKind.movie).future);
      final historyFuture = ref.watch(historyProvider.future);
      final (catalog, history) = await (catalogFuture, historyFuture).wait;
      if (!active) return;
      bool visible(MediaItem item) =>
          !settings.hidden(item) && (unlocked || !settings.locked(item));
      final available = {for (final item in catalog) item.id: item};
      final historyVisible = history
          .where((entry) => visible(available[entry.item.id] ?? entry.item))
          .toList();
      await for (final enriched in index.enrich(
        catalog.where(visible).toList(),
        historyVisible,
        active: () => active,
      )) {
        if (!active) return;
        yield recommendMovies(enriched, historyVisible);
      }
    });
