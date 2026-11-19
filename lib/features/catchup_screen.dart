import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../core/settings_controller.dart';
import '../data/app_settings.dart';
import '../data/models.dart';
import '../widgets/status_view.dart';
import '../widgets/tv_controls.dart';
import '../widgets/tv_reading_dialog.dart';
import '../widgets/tv_text_entry_dialog.dart';
import '../widgets/tv_utility_scaffold.dart';
import 'player_screen.dart';
import 'tv_guide_screen.dart' show guideClock;

/// Browse the archive independently of the live guide and its category filters.
class CatchupScreen extends ConsumerStatefulWidget {
  const CatchupScreen({super.key});

  @override
  ConsumerState<CatchupScreen> createState() => _CatchupScreenState();
}

class _CatchupScreenState extends ConsumerState<CatchupScreen> {
  final _filter = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'Find a catch-up channel');
  final _retryFocus = FocusNode(debugLabel: 'Retry programme guide');
  final _channels = GlobalKey<TvRemoteListState>();
  final _programmes = GlobalKey<TvRemoteListState>();
  String? _selectedId;

  @override
  void dispose() {
    _filter.dispose();
    _searchFocus.dispose();
    _retryFocus.dispose();
    super.dispose();
  }

  bool _allowed(MediaItem channel) {
    final settings = ref.read(settingsProvider).asData?.value;
    return channel.supportsCatchup &&
        settings != null &&
        !settings.hidden(channel) &&
        (!settings.locked(channel) || ref.read(parentalSessionProvider));
  }

  Future<void> _editFilter() async {
    final route = DialogRoute<bool>(
      context: context,
      builder: (_) => TvTextEntryDialog(
        controller: _filter,
        label: 'Find a catch-up channel',
      ),
    );
    await Navigator.of(context).push(route);
    await route.completed;
    if (!mounted) return;
    _channels.currentState?.resetPosition();
    setState(() {});
    _searchFocus.requestFocus();
  }

  String _programmeTime(EpgEntry entry) {
    final day = MaterialLocalizations.of(
      context,
    ).formatMediumDate(entry.start.toLocal());
    return '$day · ${guideClock(entry.start)}–${guideClock(entry.end)}';
  }

  Future<void> _openProgramme(MediaItem channel, EpgEntry entry) async {
    final session = ref.read(sessionProvider);
    if (!_allowed(channel) || !entry.canReplayOn(channel, DateTime.now())) {
      return;
    }
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(channel.name),
        Text(_programmeTime(entry)),
        if (entry.description.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(entry.description),
        ],
      ],
    );
    final confirmed = await (ref.read(isLargeScreenProvider)
        ? showTvReadingDialog(
            context,
            entry.title,
            details,
            actionLabel: 'Watch replay',
          )
        : showDialog<bool>(
            context: context,
            builder: (dialog) => AlertDialog(
              title: Text(entry.title),
              content: SingleChildScrollView(child: details),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialog),
                  child: const Text('Close'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialog, true),
                  child: const Text('Watch replay'),
                ),
              ],
            ),
          ));
    if (!mounted ||
        confirmed != true ||
        ref.read(sessionProvider)?.accountId != session?.accountId ||
        !_allowed(channel)) {
      return;
    }
    if (!entry.canReplayOn(channel, DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This replay is no longer available.')),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerScreen(item: channel, catchupProgramme: entry),
      ),
    );
  }

  Widget _schedule(MediaItem channel, bool tv) {
    final schedule = ref.watch(guideScheduleProvider(channel.id));
    final now =
        ref.watch(programmeClockProvider).asData?.value ?? DateTime.now();
    void retry() {
      if (tv) _channels.currentState?.focusSelected(remember: true);
      ref.invalidate(guideScheduleProvider(channel.id));
    }

    return schedule.when(
      loading: () =>
          const StatusView(title: 'Loading programme guide', loading: true),
      error: (_, _) =>
          _scheduleStatus('Programme guide unavailable', tv, retry),
      data: (guide) {
        final seen = <(DateTime, DateTime)>{};
        final entries =
            guide.entries
                .where(
                  (entry) =>
                      entry.canReplayOn(channel, now) &&
                      seen.add((entry.start, entry.end)),
                )
                .toList()
              ..sort((a, b) => b.start.compareTo(a.start));
        if (entries.isEmpty) {
          return _scheduleStatus(
            'No replays available',
            tv,
            retry,
            message: guide.limited
                ? 'The provider only supplied a limited programme guide for this channel.'
                : 'The provider did not supply any replayable programmes for this channel.',
          );
        }
        if (tv) {
          return TvRemoteList(
            key: _programmes,
            label: 'Replay',
            extent: 60,
            onLeft: () => _channels.currentState?.focusSelected(remember: true),
            onRight: () {},
            onTop: _searchFocus.requestFocus,
            entries: [
              for (final entry in entries)
                TvListEntry(
                  id: '${channel.id}:${entry.start.microsecondsSinceEpoch}:${entry.end.microsecondsSinceEpoch}',
                  title: entry.title,
                  subtitle: _programmeTime(entry),
                  leading: const Icon(Icons.play_circle_outline, size: 19),
                  onPressed: () => _openProgramme(channel, entry),
                ),
            ],
          );
        }
        return ListView.separated(
          key: ValueKey(channel.id),
          itemCount: entries.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final entry = entries[index];
            return ListTile(
              leading: const Icon(Icons.play_circle_outline),
              title: Text(entry.title),
              subtitle: Text(_programmeTime(entry)),
              onTap: () => _openProgramme(channel, entry),
            );
          },
        );
      },
    );
  }

  Widget _scheduleStatus(
    String title,
    bool tv,
    VoidCallback retry, {
    String? message,
  }) {
    if (!tv) return StatusView(title: title, message: message, onRetry: retry);
    return Column(
      children: [
        Expanded(
          child: StatusView(title: title, message: message),
        ),
        TvControl(
          focusNode: _retryFocus,
          onPressed: retry,
          onKeyEvent: (_, event) {
            if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
              return KeyEventResult.ignored;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
              _channels.currentState?.focusSelected(remember: true);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: const Text('Try again'),
        ),
      ],
    );
  }

  void _selectChannel(MediaItem channel) {
    setState(() => _selectedId = channel.id);
  }

  Widget _browser(
    AsyncValue<AppSettings> preferences,
    AsyncValue<List<MediaItem>> channels,
    List<MediaItem> available,
    List<MediaItem> visible,
    MediaItem? selected,
    bool tv,
  ) {
    if (preferences.isLoading || channels.isLoading) {
      return const StatusView(
        title: 'Loading catch-up channels',
        loading: true,
      );
    }
    if (preferences.hasError) {
      return StatusView(
        title: 'Preferences unavailable',
        onRetry: () => ref.read(settingsProvider.notifier).reload(),
      );
    }
    if (channels.hasError) {
      return StatusView(
        title: 'Channels unavailable',
        onRetry: () => ref.invalidate(itemsProvider(MediaKind.live)),
      );
    }
    if (!tv && selected != null) return _schedule(selected, false);
    if (visible.isEmpty) {
      return StatusView(
        title: available.isEmpty
            ? 'No catch-up channels reported'
            : 'No matching channels',
      );
    }
    if (tv) return _tvBrowser(visible, selected);
    return ListView.builder(
      key: const PageStorageKey('catch-up-channels'),
      itemCount: visible.length,
      itemBuilder: (context, index) {
        final channel = visible[index];
        return ListTile(
          leading: const Icon(Icons.history),
          title: Text(channel.name),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _selectChannel(channel),
        );
      },
    );
  }

  Widget _tvBrowser(List<MediaItem> visible, MediaItem? selected) => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SizedBox(
        width: 316,
        child: TvRemoteList(
          key: _channels,
          label: 'Catch-up channel',
          extent: 52,
          onTop: _searchFocus.requestFocus,
          onLeft: _searchFocus.requestFocus,
          onRight: () {
            if (_programmes.currentState case final programmes?) {
              programmes.focusSelected(remember: true);
            } else if (_retryFocus.context != null) {
              _retryFocus.requestFocus();
            }
          },
          entries: [
            for (final channel in visible)
              TvListEntry(
                id: channel.id,
                title: channel.name,
                selected: selected?.id == channel.id,
                leading: const Icon(Icons.history, size: 18),
                onPressed: () => _selectChannel(channel),
              ),
          ],
        ),
      ),
      const SizedBox(width: 20),
      Expanded(
        child: selected == null
            ? const StatusView(
                title: 'Choose a channel',
                message: 'Select a channel to see its available replays.',
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    selected.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: KeyedSubtree(
                      key: ValueKey(selected.id),
                      child: _schedule(selected, true),
                    ),
                  ),
                ],
              ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final tv = ref.watch(isLargeScreenProvider);
    final preferences = ref.watch(settingsProvider);
    ref.watch(parentalSessionProvider);
    final channels = ref.watch(itemsProvider(MediaKind.live));
    final available =
        (channels.asData?.value ?? const <MediaItem>[]).where(_allowed).toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
    final visible = available
        .where(
          (channel) => channel.name.toLowerCase().contains(
            _filter.text.trim().toLowerCase(),
          ),
        )
        .toList();
    final selected = (tv ? visible : available)
        .where((channel) => channel.id == _selectedId)
        .firstOrNull;
    final showingProgrammes = !tv && selected != null;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!showingProgrammes)
          if (tv)
            Align(
              alignment: Alignment.centerLeft,
              child: TvControl(
                label: 'Find a catch-up channel',
                autofocus: true,
                focusNode: _searchFocus,
                onPressed: _editFilter,
                onKeyEvent: (_, event) {
                  if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
                      event.logicalKey == LogicalKeyboardKey.arrowDown &&
                      _channels.currentState != null) {
                    _channels.currentState?.focusSelected(remember: true);
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: Text(
                  _filter.text.isEmpty
                      ? 'Find a channel'
                      : 'Filter: ${_filter.text}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _filter,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Find a channel',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
        const SizedBox(height: 8),
        Expanded(
          child: _browser(
            preferences,
            channels,
            available,
            visible,
            selected,
            tv,
          ),
        ),
      ],
    );
    if (tv) {
      return TvUtilityScaffold(
        title: 'Catch-up',
        subtitle: 'Choose a channel to browse past programmes',
        hint: 'OK  Select    Right  Replays    Left  Channels    Back  Return',
        onEnter: _searchFocus.requestFocus,
        child: content,
      );
    }
    return PopScope<Object?>(
      canPop: !showingProgrammes,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && showingProgrammes) setState(() => _selectedId = null);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(showingProgrammes ? selected.name : 'Catch-up'),
          leading: showingProgrammes
              ? BackButton(onPressed: () => setState(() => _selectedId = null))
              : null,
        ),
        body: SafeArea(top: false, child: content),
      ),
    );
  }
}
