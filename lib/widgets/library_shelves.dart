import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/design_system.dart';
import '../core/providers.dart';
import '../core/settings_controller.dart';
import '../data/app_settings.dart';
import '../data/models.dart';
import '../data/recommendations.dart';
import 'media_card.dart';

class MovieShelf extends ConsumerWidget {
  const MovieShelf({
    super.key,
    required this.title,
    required this.items,
    required this.onOpen,
    this.subtitle,
    this.onViewAll,
  });
  final String title;
  final String? subtitle;
  final List<MediaItem> items;
  final ValueChanged<MediaItem> onOpen;
  final VoidCallback? onViewAll;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tv = ref.watch(isTvProvider);
    final s = ref.watch(settingsProvider).asData?.value ?? const AppSettings();
    final width = (tv ? 174.0 : 140.0) * (s.largePosters ? 1.22 : 1);
    return Padding(
      padding: EdgeInsets.only(bottom: s.compact ? 24 : 38),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontSize: tv ? 26 : 23),
                ),
              ),
              if (onViewAll != null)
                TextButton(onPressed: onViewAll, child: const Text('View all')),
            ],
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                subtitle!,
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ),
          const SizedBox(height: 17),
          SizedBox(
            height: width * 1.5 + 56,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: items.length,
              separatorBuilder: (_, __) => SizedBox(width: s.compact ? 12 : 20),
              itemBuilder: (context, index) => SizedBox(
                width: width,
                child: MediaCard(
                  item: items[index],
                  onPressed: () => onOpen(items[index]),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MovieRecommendations extends ConsumerWidget {
  const MovieRecommendations({
    super.key,
    required this.catalog,
    required this.onOpen,
  });
  final List<MediaItem> catalog;
  final ValueChanged<MediaItem> onOpen;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings =
        ref.watch(settingsProvider).asData?.value ?? const AppSettings();
    if (!settings.recommendations) return const SizedBox.shrink();
    final unlocked = ref.watch(parentalSessionProvider);
    final visible = catalog
        .where(
          (item) =>
              !settings.hidden(item) && (unlocked || !settings.locked(item)),
        )
        .toList();
    return ref
        .watch(historyProvider)
        .when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => ref.invalidate(historyProvider),
              child: const Text('Reload recommendations'),
            ),
          ),
          data: (history) {
            final recommendations = recommendMovies(
              visible,
              history
                  .where(
                    (entry) =>
                        !settings.hidden(entry.item) &&
                        (unlocked || !settings.locked(entry.item)),
                  )
                  .toList(),
            );
            if (recommendations.isEmpty) {
              return Container(
                margin: const EdgeInsets.only(bottom: 30),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.auto_awesome_outlined, color: AppColors.accent),
                    SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Made for your movie nights',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Watch a film to start finding similar titles from your library. Recommendations stay on this device.',
                            style: TextStyle(
                              color: AppColors.muted,
                              height: 1.5,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }
            return Column(
              children: [
                for (final shelf in recommendations)
                  MovieShelf(
                    title: shelf.title,
                    subtitle: 'From categories you watch · On this device',
                    items: shelf.items,
                    onOpen: onOpen,
                  ),
              ],
            );
          },
        );
  }
}

class AccountExpiryNotice extends ConsumerWidget {
  const AccountExpiryNotice({super.key, required this.onAccount});
  final VoidCallback onAccount;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    if (session == null) return const SizedBox.shrink();
    final info = AccountInfo(session);
    if (!info.expiring) return const SizedBox.shrink();
    final expired = info.expiry!.isBefore(DateTime.now());
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: .1),
        border: Border.all(color: AppColors.danger.withValues(alpha: .3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: const Icon(Icons.schedule, color: AppColors.danger),
        title: Text(
          expired
              ? 'Your provider reports this account has expired'
              : 'Your account expires ${info.remainingDays == 0 ? 'today' : 'in ${info.remainingDays} days'}',
          style: const TextStyle(fontSize: 13),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onAccount,
      ),
    );
  }
}
