import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../data/models.dart';
import 'tv_controls.dart';
import 'tv_glass_theme.dart';

/// Real provider entries, ordered by time. Missing current programmes stay empty.
List<EpgEntry?> glassGuideSlots(List<EpgEntry> entries, DateTime now) {
  final sorted = entries.where((e) => e.end.isAfter(e.start)).toList()
    ..sort((a, b) => a.start.compareTo(b.start));
  final current = sorted
      .where((e) => !e.start.isAfter(now) && e.end.isAfter(now))
      .firstOrNull;
  final future = sorted
      .where(
        (e) => current == null
            ? e.start.isAfter(now)
            : !e.start.isBefore(current.end),
      )
      .take(2)
      .toList();
  return [current, future.firstOrNull, future.length > 1 ? future[1] : null];
}

/// Eight rows fit in the approved 16:9 layout. Only mounted rows subscribe to EPG.
class TvGlassGuide extends StatefulWidget {
  const TvGlassGuide({
    super.key,
    required this.channels,
    required this.selectedId,
    required this.onFocused,
    required this.onOpen,
    required this.onProgramme,
    required this.onLeft,
    required this.onRight,
    required this.onTop,
  });
  final List<MediaItem> channels;
  final String selectedId;
  final void Function(MediaItem, int) onFocused;
  final ValueChanged<MediaItem> onOpen;
  final void Function(MediaItem, EpgEntry) onProgramme;
  final VoidCallback onLeft, onRight, onTop;
  @override
  State<TvGlassGuide> createState() => TvGlassGuideState();
}

class TvGlassGuideState extends State<TvGlassGuide> {
  final _scroll = ScrollController();
  final _nodes = <String, FocusNode>{};
  String? _focusedId;
  int _column = 0, _generation = 0;

  FocusNode _node(MediaItem item, int column) => _nodes.putIfAbsent(
    '${item.id}:$column',
    () => FocusNode(
      debugLabel: column == 0
          ? 'Channel: ${item.name}'
          : 'Programme $column: ${item.name}',
    ),
  );

  void _reveal(int index) {
    if (!_scroll.hasClients || !_scroll.position.hasContentDimensions) return;
    final p = _scroll.position;
    final start = index * TvGlass.rowHeight;
    final end = start + TvGlass.rowHeight;
    final target =
        (start < p.pixels
                ? start
                : end > p.pixels + p.viewportDimension
                ? end - p.viewportDimension
                : p.pixels)
            .clamp(0.0, p.maxScrollExtent);
    if ((target - p.pixels).abs() > .5) _scroll.jumpTo(target);
  }

  void focusSelected({bool remember = false}) {
    var index = widget.channels.indexWhere(
      (e) => e.id == (remember ? _focusedId : widget.selectedId),
    );
    if (index < 0) index = 0;
    _focus(index, remember ? _column : 0);
  }

  void _focus(int index, int column) {
    if (widget.channels.isEmpty) {
      widget.onTop();
      return;
    }
    index = index.clamp(0, widget.channels.length - 1);
    final item = widget.channels[index];
    final node = _node(item, column);
    final generation = ++_generation;
    _focusedId = item.id;
    _column = column;
    _reveal(index);
    if (node.context != null) node.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _generation) return;
      _reveal(index);
      if (node.context != null) node.requestFocus();
    });
  }

  KeyEventResult _key(MediaItem item, int column, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final index = widget.channels.indexWhere((e) => e.id == item.id);
    if (index < 0) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        if (index + 1 < widget.channels.length) _focus(index + 1, column);
      case LogicalKeyboardKey.arrowUp:
        if (index > 0) {
          _focus(index - 1, column);
        } else {
          _generation++;
          widget.onTop();
        }
      case LogicalKeyboardKey.arrowLeft:
        if (column > 0) {
          _focus(index, column - 1);
        } else {
          _generation++;
          widget.onLeft();
        }
      case LogicalKeyboardKey.arrowRight:
        if (column < 2) {
          _focus(index, column + 1);
        } else {
          _generation++;
          widget.onRight();
        }
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _scroll.dispose();
    for (final node in _nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SizedBox(
        height: 28,
        child: Row(
          children: [
            const SizedBox(
              width: 122,
              child: Text(
                'CHANNEL',
                style: TextStyle(
                  fontSize: 10,
                  color: TvGlass.muted,
                  letterSpacing: 1,
                ),
              ),
            ),
            for (final label in ['On now', 'Up next', 'Later'])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      color: label == 'On now' ? TvGlass.accent : TvGlass.muted,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      Expanded(
        child: ListView.builder(
          controller: _scroll,
          itemExtent: TvGlass.rowHeight,
          itemCount: widget.channels.length,
          cacheExtent: TvGlass.rowHeight * 2,
          itemBuilder: (context, index) {
            final item = widget.channels[index];
            return _GlassGuideRow(
              key: ValueKey(item.id),
              item: item,
              number: index + 1,
              selected: widget.selectedId == item.id,
              node: (column) => _node(item, column),
              onKey: (column, event) => _key(item, column, event),
              onFocus: (column) {
                _focusedId = item.id;
                _column = column;
                _reveal(index);
                widget.onFocused(item, column);
              },
              onOpen: () => widget.onOpen(item),
              onProgramme: (entry) => widget.onProgramme(item, entry),
            );
          },
        ),
      ),
    ],
  );
}

class _GlassGuideRow extends ConsumerWidget {
  const _GlassGuideRow({
    super.key,
    required this.item,
    required this.number,
    required this.selected,
    required this.node,
    required this.onKey,
    required this.onFocus,
    required this.onOpen,
    required this.onProgramme,
  });
  final MediaItem item;
  final int number;
  final bool selected;
  final FocusNode Function(int) node;
  final KeyEventResult Function(int, KeyEvent) onKey;
  final ValueChanged<int> onFocus;
  final VoidCallback onOpen;
  final ValueChanged<EpgEntry> onProgramme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(epgProvider(item.id));
    final slots = glassGuideSlots(state.asData?.value ?? [], DateTime.now());
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          SizedBox(
            width: 122,
            child: Row(
              children: [
                Text(
                  number.toString().padLeft(3, '0'),
                  style: const TextStyle(fontSize: 9, color: Color(0xFF91ABCF)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
            ),
          ),
          for (var column = 0; column < 3; column++)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: column < 2 ? 3 : 0),
                child: TvControl(
                  style: TvControlStyle.programme,
                  focusNode: node(column),
                  label:
                      '${item.name}: ${slots[column]?.title ?? (column == 0 ? 'Watch channel' : 'Programme guide unavailable')}',
                  selected: selected && column == 0,
                  reveal: false,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  onKeyEvent: (_, event) => onKey(column, event),
                  onFocused: () => onFocus(column),
                  onPressed: () {
                    if (column == 0 || slots[column] == null) {
                      onOpen();
                    } else {
                      onProgramme(slots[column]!);
                    }
                  },
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      slots[column]?.title ??
                          (state.isLoading
                              ? 'Loading guide…'
                              : column == 0
                              ? 'No programme guide'
                              : '—'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, height: 1.2),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
