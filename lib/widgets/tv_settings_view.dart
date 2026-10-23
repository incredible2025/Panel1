import 'package:flutter/material.dart';
import 'tv_controls.dart';
import 'tv_glass_theme.dart';
import 'tv_page_navigation.dart';
import 'tv_utility_scaffold.dart';

class TvSetting extends StatelessWidget {
  const TvSetting({
    super.key,
    required this.title,
    this.value = '',
    this.description = '',
    this.onPressed,
  });
  final String title, value, description;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class TvSettingsGroup extends StatelessWidget {
  const TvSettingsGroup({
    super.key,
    required this.title,
    required this.entries,
  });
  final String title;
  final List<TvSetting> entries;
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class TvSettingsView extends StatefulWidget {
  const TvSettingsView({
    super.key,
    required this.groups,
    this.initialGroup = 0,
    this.notice,
  });
  final List<TvSettingsGroup> groups;
  final int initialGroup;
  final String? notice;
  @override
  State<TvSettingsView> createState() => _TvSettingsViewState();
}

class _TvSettingsViewState extends State<TvSettingsView> {
  final _groups = GlobalKey<TvRemoteListState>();
  final _items = GlobalKey<TvRemoteListState>();
  final _reading = FocusNode(debugLabel: 'Setting explanation');
  late int _group = widget.initialGroup;
  int _selected = 0;
  bool _initialFocus = true;
  @override
  void dispose() {
    _reading.dispose();
    super.dispose();
  }

  void _select(int index) {
    if (_group == index) return;
    setState(() {
      _group = index;
      _selected = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _items.currentState?.resetPosition();
    });
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.groups[_group];
    final autofocus = _initialFocus;
    _initialFocus = false;
    final selected =
        group.entries[_selected.clamp(0, group.entries.length - 1)];
    return TvUtilityScaffold(
      title: 'Settings',
      subtitle: widget.notice ?? 'Your picture. Your sound. Your space.',
      onEnter: () => _items.currentState?.focusSelected(remember: true),
      hint:
          'Left  Sections    Right  Options / explanation    Up / Down  Browse    OK  Change    Back  Return',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 190,
            child: TvRemoteList(
              key: _groups,
              label: 'Settings section',
              titleSize: 14,
              fullRows: true,
              extent: 52,
              dense: true,
              onRight: () => _items.currentState?.focusSelected(remember: true),
              onLeft: () {},
              onTop: () {},
              entries: [
                for (var i = 0; i < widget.groups.length; i++)
                  TvListEntry(
                    id: '$i',
                    title: widget.groups[i].title,
                    selected: i == _group,
                    onFocused: () => _select(i),
                    onPressed: () {
                      _select(i);
                      _items.currentState?.focusSelected();
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 430,
            child: TvRemoteList(
              key: _items,
              autofocus: autofocus,
              label: 'Setting',
              fullRows: true,
              titleSize: 14,
              extent: 54,
              dense: true,
              onLeft: () => _groups.currentState?.focusSelected(remember: true),
              onTop: () {},
              onRight: _reading.requestFocus,
              entries: [
                for (final entry in group.entries)
                  TvListEntry(
                    id: '$_group:${group.entries.indexOf(entry)}',
                    title: entry.title,
                    subtitle: entry.value.isEmpty
                        ? (entry.onPressed == null
                              ? 'Information'
                              : 'OK to open')
                        : entry.value,
                    selected: identical(entry, selected),
                    onFocused: () => setState(
                      () => _selected = group.entries.indexOf(entry),
                    ),
                    onPressed: entry.onPressed ?? _reading.requestFocus,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: TvScrollPane(
              key: ValueKey('${group.title}/${selected.title}'),
              label: 'Setting details',
              focusNode: _reading,
              onLeft: () => _items.currentState?.focusSelected(remember: true),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    selected.title,
                    style: const TextStyle(fontSize: 21, height: 1.2),
                  ),
                  const SizedBox(height: 16),
                  if (selected.value.isNotEmpty)
                    Text(
                      selected.value,
                      style: const TextStyle(
                        fontSize: 17,
                        color: TvGlass.accent,
                      ),
                    ),
                  const SizedBox(height: 12),
                  Text(
                    selected.description.isEmpty
                        ? 'This value was supplied by your account or device.'
                        : selected.description,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: TvGlass.muted,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    selected.onPressed == null
                        ? 'Back returns to Settings.'
                        : 'Select the option and press OK to change it.',
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: TvGlass.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
