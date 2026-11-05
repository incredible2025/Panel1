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
import '../widgets/tv_controls.dart';
import '../widgets/tv_utility_scaffold.dart';
import '../widgets/tv_text_entry_dialog.dart';
import '../widgets/tv_reading_dialog.dart';
import '../widgets/tv_page_navigation.dart';
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
  bool _catchupOnly = false;
  double get _rowHeight => ref.read(isLargeScreenProvider) ? 56.0 : 90.0;
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
      final minutes = _dayOffset == 0 && !_catchupOnly
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

  void _toggleCatchup() {
    setState(() {
      _catchupOnly = !_catchupOnly;
      _dayOffset = 0;
    });
    if (_names.hasClients) _names.jumpTo(0);
    _jumpToTime();
  }

  void _refreshGuide() {
    ref.invalidate(itemsProvider(MediaKind.live));
    ref.read(guideRefreshProvider.notifier).state++;
  }

  Future<void> _chooseReplayDay(int days) async {
    final today = DateUtils.dateOnly(DateTime.now());
    if (ref.read(isLargeScreenProvider)) {
      final format = MaterialLocalizations.of(context);
      final selected = await showTvMenu(context, 'Choose replay date', {
        for (var offset = 0; offset >= -days; offset--)
          '$offset': format.formatFullDate(
            DateTime(today.year, today.month, today.day + offset),
          ),
      }, selected: '$_dayOffset');
      if (mounted && _catchupOnly && selected != null) {
        _selectDay(int.parse(selected));
      }
      return;
    }
    final selected = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(today.year, today.month, today.day - days),
      lastDate: today,
      helpText: 'Choose replay date',
    );
    if (mounted && _catchupOnly && selected != null) {
      _selectDay(
        DateTime.utc(
          selected.year,
          selected.month,
          selected.day,
        ).difference(DateTime.utc(today.year, today.month, today.day)).inDays,
      );
    }
  }

  Future<void> _showProgramme(
    MediaItem channel,
    EpgEntry entry,
    List<MediaItem> channels,
  ) async {
    final now = DateTime.now();
    final replay = entry.canReplayOn(channel, now);
    final action = replay ? 'Watch replay' : 'Watch channel';
    final detail = replay
        ? 'Watch this programme from the beginning.'
        : 'Watch channel opens its live broadcast.';
    final state = now.isBefore(entry.start)
        ? 'UPCOMING'
        : now.isBefore(entry.end)
        ? 'ON NOW'
        : replay
        ? 'CATCH-UP'
        : 'EARLIER';
    final play = await (ref.read(isLargeScreenProvider)
        ? showTvReadingDialog(
            context,
            entry.title,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(state),
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
                const SizedBox(height: 18),
                Text(detail),
              ],
            ),
            actionLabel: action,
          )
        : showDialog<bool>(
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
                        Text(
                          detail,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
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
                  label: Text(action),
                ),
              ],
            ),
          ));
    if (play != true || !mounted) return;
    final settings = ref.read(settingsProvider).asData?.value;
    if (settings == null ||
        settings.hidden(channel) ||
        (settings.locked(channel) && !ref.read(parentalSessionProvider))) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerScreen(
          item: channel,
          channels: replay ? const [] : channels,
          catchupProgramme: replay ? entry : null,
        ),
      ),
    );
    if (mounted && !replay) ref.invalidate(recentChannelsProvider);
  }

  Future<void> _editSearch() async {
    final route = DialogRoute<bool>(
      context: context,
      builder: (_) =>
          TvTextEntryDialog(controller: _search, label: 'Filter channels'),
    );
    await Navigator.of(context).push(route);
    await route.completed;
    if (!mounted) return;
    setState(() {});
    if (_names.hasClients) _names.jumpTo(0);
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
    final tv = ref.watch(isLargeScreenProvider);
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
    final replayDays = (channels.asData?.value ?? const <MediaItem>[])
        .where(
          (channel) =>
              channel.supportsCatchup &&
              !settings.hidden(channel) &&
              (unlocked || !settings.locked(channel)),
        )
        .fold<int>(
          0,
          (days, channel) =>
              math.max(days, channel.archiveDays > 0 ? channel.archiveDays : 7),
        );
    final day = _day;
    final end = DateTime(day.year, day.month, day.day + 1);
    _hourWidth = tv ? 190 : 150;
    final hours = end.difference(day).inHours;
    final width = hours * _hourWidth;
    final body = SafeArea(
      top: false,
      child: Column(
        children: [
          Padding(
            padding: tv
                ? const EdgeInsets.only(bottom: 8)
                : const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: tv
                ? Row(
                    children: [
                      Expanded(
                        child: TvControl(
                          label: 'Filter channels',
                          onPressed: _editSearch,
                          child: Row(
                            children: [
                              const Icon(Icons.search, size: 17),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _search.text.isEmpty
                                      ? 'Filter channels'
                                      : _search.text,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      TvControl(
                        onPressed: () => _selectDay(0),
                        child: const Text(
                          'Now',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 10),
                      TvControl(
                        selected: _catchupOnly,
                        onPressed: _toggleCatchup,
                        child: const Text('Catch-up'),
                      ),
                      const SizedBox(width: 10),
                      TvControl(
                        label: 'Refresh TV guide',
                        onPressed: _refreshGuide,
                        child: const Icon(Icons.refresh, size: 18),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
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
                      const SizedBox(width: 8),
                      FilterChip(
                        label: const Text('Catch-up'),
                        selected: _catchupOnly,
                        onSelected: (_) => _toggleCatchup(),
                      ),
                    ],
                  ),
          ),
          if (_catchupOnly)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: tv
                  ? TvControl(
                      onPressed: () =>
                          _chooseReplayDay(math.max(replayDays, -_dayOffset)),
                      child: Text(
                        'Replay date · ${MaterialLocalizations.of(context).formatMediumDate(day)}',
                      ),
                    )
                  : OutlinedButton.icon(
                      onPressed: () =>
                          _chooseReplayDay(math.max(replayDays, -_dayOffset)),
                      icon: const Icon(Icons.calendar_today, size: 16),
                      label: Text(
                        'Replay date · ${MaterialLocalizations.of(context).formatMediumDate(day)}',
                      ),
                    ),
            )
          else
            SizedBox(
              height: tv ? 36 : 50,
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
                  if (tv) {
                    return TvControl(
                      selected: _dayOffset == offset,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      onPressed: () => _selectDay(offset),
                      child: Text(label, style: const TextStyle(fontSize: 13)),
                    );
                  }
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
                          (!_catchupOnly || channel.supportsCatchup) &&
                          !settings.hidden(channel) &&
                          (unlocked || !settings.locked(channel)) &&
                          channel.name.toLowerCase().contains(
                            _search.text.trim().toLowerCase(),
                          ),
                    )
                    .toList();
                if (filtered.isEmpty) {
                  return StatusView(
                    title: _catchupOnly && _search.text.trim().isEmpty
                        ? 'No catch-up channels reported'
                        : 'No matching channels',
                  );
                }
                if (_jumpPending) _jumpToTime();
                return Row(
                  children: [
                    SizedBox(
                      width: tv ? 190 : 118,
                      child: Column(
                        children: [
                          SizedBox(
                            height: tv ? 28 : 44,
                            child: const Center(child: Eyebrow('CHANNEL')),
                          ),
                          Expanded(
                            child: ListView.builder(
                              controller: _names,
                              itemExtent: _rowHeight,
                              itemCount: filtered.length,
                              itemBuilder: (context, index) => Padding(
                                padding: const EdgeInsets.fromLTRB(8, 5, 5, 5),
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
                                      child: Row(
                                        children: [
                                          if (filtered[index]
                                              .supportsCatchup) ...[
                                            Icon(
                                              Icons.history,
                                              size: 15,
                                              color: AppPalette.of(
                                                context,
                                              ).accent,
                                              semanticLabel: 'Catch-up channel',
                                            ),
                                            const SizedBox(width: 5),
                                          ],
                                          Expanded(
                                            child: Text(
                                              filtered[index].name,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: tv ? 15 : 12,
                                              ),
                                            ),
                                          ),
                                        ],
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
                                  height: tv ? 28 : 44,
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
                                                day.add(Duration(hours: hour)),
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
    );
    if (tv) {
      return TvUtilityScaffold(title: 'TV guide', child: body);
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('TV guide'),
        actions: [
          TextButton(onPressed: () => _selectDay(0), child: const Text('Now')),
          IconButton(
            tooltip: 'Refresh TV guide',
            onPressed: _refreshGuide,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: body,
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
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppPalette.of(context).border),
        ),
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
          final now = DateTime.now();
          final entries = value.entries
              .where(
                (entry) =>
                    guideInterval(entry, day, end) != null &&
                    (!_catchupOnly || entry.canReplayOn(channel, now)),
              )
              .toList();
          if (entries.isEmpty) {
            return _guideStatus(
              Text(
                value.limited
                    ? 'Limited EPG · No programmes for this day'
                    : _catchupOnly
                    ? 'No replays supplied for this day'
                    : 'No programme data supplied for this day',
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            );
          }
          final nowX =
              now.difference(day).inMilliseconds / 3600000 * _hourWidth;
          return Stack(
            children: [
              for (final entry in entries)
                Builder(
                  builder: (context) {
                    final span = guideInterval(entry, day, end)!;
                    final replay = entry.canReplayOn(channel, now);
                    final onNow =
                        !now.isBefore(entry.start) && now.isBefore(entry.end);
                    return Positioned(
                      left: span.start * _hourWidth / 60,
                      width: math.max(2, span.duration * _hourWidth / 60 - 4),
                      top: 5,
                      bottom: 5,
                      child: TvFocusCard(
                        label:
                            '${channel.name}, ${entry.title}, ${guideClock(entry.start)}${replay ? ', replay available' : ''}',
                        selected: onNow,
                        onPressed: () =>
                            _showProgramme(channel, entry, channels),
                        child: ClipRect(
                          child: Padding(
                            padding: const EdgeInsets.all(4),
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
                                    height: 1.1,
                                    fontWeight: onNow
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${guideClock(entry.start)}–${guideClock(entry.end)}${replay ? ' · Replay' : ''}${value.cached ? ' · cached' : ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 10,
                                    height: 1.1,
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
