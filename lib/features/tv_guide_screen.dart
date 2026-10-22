import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/design_system.dart';
import '../core/providers.dart';
import '../core/settings_controller.dart';
import '../data/app_settings.dart';
import '../data/models.dart';
import '../widgets/status_view.dart';
import '../widgets/tv_focus_card.dart';
import 'player_screen.dart';

String guideClock(DateTime value) {
  final local = value.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

/// Clips a programme to the actual local day, including 23/25-hour DST days.
({double start, double duration})? guideInterval(
  EpgEntry entry,
  DateTime start,
  DateTime end,
) {
  if (!entry.end.isAfter(start) || !entry.start.isBefore(end)) return null;
  final first = entry.start.isBefore(start) ? start : entry.start;
  final last = entry.end.isAfter(end) ? end : entry.end;
  if (!last.isAfter(first)) return null;
  return (
    start: first.difference(start).inMilliseconds / 60000,
    duration: last.difference(first).inMilliseconds / 60000,
  );
}

class TvGuideScreen extends ConsumerStatefulWidget {
  const TvGuideScreen({super.key});
  @override
  ConsumerState<TvGuideScreen> createState() => _TvGuideScreenState();
}

class _TvGuideScreenState extends ConsumerState<TvGuideScreen> {
  final _names = ScrollController();
  final _programmes = ScrollController();
  final _timeline = ScrollController();
  final _search = TextEditingController();
  Timer? _clock;
  bool _syncing = false;
  bool _jumpPending = true;
  int _dayOffset = 0;
  static const _rowHeight = 90.0;
  double _hourWidth = 170;

  DateTime get _day {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day + _dayOffset);
  }

  @override
  void initState() {
    super.initState();
    _names.addListener(() => _sync(_names, _programmes));
    _programmes.addListener(() => _sync(_programmes, _names));
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    _jumpToTime();
  }

  void _sync(ScrollController source, ScrollController target) {
    if (_syncing || !source.hasClients || !target.hasClients) return;
    _syncing = true;
    target.jumpTo(source.offset.clamp(0, target.position.maxScrollExtent));
    _syncing = false;
  }

  void _jumpToTime() {
    _jumpPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_timeline.hasClients) return;
      _jumpPending = false;
      final minutes = _dayOffset == 0
          ? DateTime.now().difference(_day).inMinutes - 30
          : 0;
      _timeline.jumpTo(
        (minutes * _hourWidth / 60).clamp(
          0,
          _timeline.position.maxScrollExtent,
        ),
      );
    });
  }

  void _selectDay(int value) {
    setState(() => _dayOffset = value);
    _jumpToTime();
  }

  Future<void> _showProgramme(
    MediaItem channel,
    EpgEntry entry,
    List<MediaItem> channels,
  ) async {
    final now = DateTime.now();
    final state = now.isBefore(entry.start)
        ? 'UPCOMING'
        : now.isBefore(entry.end)
        ? 'ON NOW'
        : 'EARLIER';
    final play = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(entry.title),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Eyebrow(state),
                const SizedBox(height: 12),
                Text(
                  '${channel.name} · ${guideClock(entry.start)}–${guideClock(entry.end)}',
                ),
                const SizedBox(height: 18),
                Text(
                  entry.description.isEmpty
                      ? 'No programme description supplied.'
                      : entry.description,
                ),
                if (state != 'ON NOW') ...[
                  const SizedBox(height: 18),
                  const Text(
                    'Watch channel opens its live broadcast.',
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Watch channel'),
          ),
        ],
      ),
    );
    if (play == true && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PlayerScreen(item: channel, channels: channels),
        ),
      );
      if (mounted) ref.invalidate(recentChannelsProvider);
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    _names.dispose();
    _programmes.dispose();
    _timeline.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tv = ref.watch(isTvProvider);
    final preferences = ref.watch(settingsProvider);
    final unlocked = ref.watch(parentalSessionProvider);
    if (preferences.isLoading) {
      return const Scaffold(
        body: StatusView(title: 'Loading preferences', loading: true),
      );
    }
    if (preferences.hasError) {
      return Scaffold(
        appBar: AppBar(title: const Text('TV guide')),
        body: StatusView(
          title: 'Preferences unavailable',
          onRetry: () => ref.read(settingsProvider.notifier).reload(),
        ),
      );
    }
    final settings = preferences.asData?.value ?? const AppSettings();
    final channels = ref.watch(itemsProvider(MediaKind.live));
    final day = _day;
    final end = DateTime(day.year, day.month, day.day + 1);
    _hourWidth = tv ? 190 : 150;
    final hours = end.difference(day).inHours;
    final width = hours * _hourWidth;
    return Scaffold(
      appBar: AppBar(
        title: const Text('TV guide'),
        actions: [
          TextButton(onPressed: () => _selectDay(0), child: const Text('Now')),
          IconButton(
            tooltip: 'Refresh TV guide',
            onPressed: () => ref.read(guideRefreshProvider.notifier).state++,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(tv ? 28 : 16, 8, tv ? 28 : 16, 12),
              child: TextField(
                controller: _search,
                onChanged: (_) {
                  setState(() {});
                  if (_names.hasClients) _names.jumpTo(0);
                },
                decoration: const InputDecoration(
                  hintText: 'Filter channels',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
              ),
            ),
            SizedBox(
              height: 50,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: 8,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final offset = index - 1;
                  final today = DateTime.now();
                  final date = DateTime(
                    today.year,
                    today.month,
                    today.day + offset,
                  );
                  final label = offset == 0
                      ? 'Today'
                      : offset == 1
                      ? 'Tomorrow'
                      : offset == -1
                      ? 'Yesterday'
                      : '${const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][date.weekday - 1]} ${date.day}/${date.month}';
                  return ChoiceChip(
                    label: Text(label),
                    selected: _dayOffset == offset,
                    onSelected: (_) => _selectDay(offset),
                  );
                },
              ),
            ),
            Expanded(
              child: channels.when(
                loading: () =>
                    const StatusView(title: 'Loading channels', loading: true),
                error: (_, __) => StatusView(
                  title: 'Channels unavailable',
                  onRetry: () => ref.invalidate(itemsProvider(MediaKind.live)),
                ),
                data: (all) {
                  final filtered = all
                      .where(
                        (channel) =>
                            !settings.hidden(channel) &&
                            (unlocked || !settings.locked(channel)) &&
                            channel.name.toLowerCase().contains(
                              _search.text.trim().toLowerCase(),
                            ),
                      )
                      .toList();
                  if (filtered.isEmpty) {
                    return const StatusView(title: 'No matching channels');
                  }
                  if (_jumpPending) _jumpToTime();
                  return Row(
                    children: [
                      SizedBox(
                        width: tv ? 190 : 118,
                        child: Column(
                          children: [
                            const SizedBox(
                              height: 44,
                              child: Center(child: Eyebrow('CHANNEL')),
                            ),
                            Expanded(
                              child: ListView.builder(
                                controller: _names,
                                itemExtent: _rowHeight,
                                itemCount: filtered.length,
                                itemBuilder: (context, index) => Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    8,
                                    5,
                                    5,
                                    5,
                                  ),
                                  child: TvFocusCard(
                                    autofocus: tv && index == 0,
                                    label: 'Watch ${filtered[index].name}',
                                    onPressed: () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => PlayerScreen(
                                          item: filtered[index],
                                          channels: filtered,
                                        ),
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          filtered[index].name,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: tv ? 15 : 12,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Scrollbar(
                          controller: _timeline,
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            controller: _timeline,
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(
                              width: width,
                              child: Column(
                                children: [
                                  SizedBox(
                                    height: 44,
                                    child: Row(
                                      children: [
                                        for (var hour = 0; hour < hours; hour++)
                                          SizedBox(
                                            width: _hourWidth,
                                            child: Padding(
                                              padding: const EdgeInsets.only(
                                                left: 8,
                                                top: 12,
                                              ),
                                              child: Text(
                                                guideClock(
                                                  day.add(
                                                    Duration(hours: hour),
                                                  ),
                                                ),
                                                style: const TextStyle(
                                                  color: AppColors.muted,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: ListView.builder(
                                      controller: _programmes,
                                      cacheExtent: _rowHeight,
                                      itemExtent: _rowHeight,
                                      itemCount: filtered.length,
                                      itemBuilder: (context, index) =>
                                          _scheduleRow(
                                            filtered[index],
                                            day,
                                            end,
                                            width,
                                            filtered,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(10),
              child: Text(
                'Provider schedule · Times shown in your device’s time zone',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.subdued, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _guideStatus(Widget child) => AnimatedBuilder(
    animation: _timeline,
    builder: (context, _) => Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(
          left: (_timeline.hasClients ? _timeline.offset : 0) + 12,
        ),
        child: child,
      ),
    ),
  );

  Widget _scheduleRow(
    MediaItem channel,
    DateTime day,
    DateTime end,
    double width,
    List<MediaItem> channels,
  ) {
    final schedule = ref.watch(guideScheduleProvider(channel.id));
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: schedule.when(
        loading: () => _guideStatus(
          const Text(
            'Loading schedule…',
            style: TextStyle(color: AppColors.muted),
          ),
        ),
        error: (_, __) => _guideStatus(
          TextButton.icon(
            onPressed: () => ref.invalidate(guideScheduleProvider(channel.id)),
            icon: const Icon(Icons.refresh),
            label: const Text('Guide unavailable · Retry'),
          ),
        ),
        data: (value) {
          final entries = value.entries
              .where((entry) => guideInterval(entry, day, end) != null)
              .toList();
          if (entries.isEmpty) {
            return _guideStatus(
              Text(
                value.limited
                    ? 'Limited EPG · No programmes for this day'
                    : 'No programme data supplied for this day',
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            );
          }
          final now = DateTime.now();
          final nowX =
              now.difference(day).inMilliseconds / 3600000 * _hourWidth;
          return Stack(
            children: [
              for (final entry in entries)
                Builder(
                  builder: (context) {
                    final span = guideInterval(entry, day, end)!;
                    final onNow =
                        !now.isBefore(entry.start) && now.isBefore(entry.end);
                    return Positioned(
                      left: span.start * _hourWidth / 60,
                      width: math.max(2, span.duration * _hourWidth / 60 - 4),
                      top: 5,
                      bottom: 5,
                      child: TvFocusCard(
                        label:
                            '${channel.name}, ${entry.title}, ${guideClock(entry.start)}',
                        selected: onNow,
                        onPressed: () =>
                            _showProgramme(channel, entry, channels),
                        child: ClipRect(
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  entry.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: onNow
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 7),
                                Text(
                                  '${guideClock(entry.start)}–${guideClock(entry.end)}${value.cached ? ' · cached' : ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              if (nowX >= 0 && nowX < width)
                Positioned(
                  left: nowX,
                  top: 0,
                  bottom: 0,
                  child: const IgnorePointer(
                    child: ColoredBox(
                      color: AppColors.live,
                      child: SizedBox(width: 2),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
