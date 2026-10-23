import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/design_system.dart';

/// Large, high-contrast remote target. Focus and selection have distinct styles.
class TvControl extends StatefulWidget {
  const TvControl({
    super.key,
    required this.child,
    required this.onPressed,
    this.label,
    this.focusNode,
    this.autofocus = false,
    this.selected = false,
    this.onFocused,
    this.onKeyEvent,
    this.reveal = true,
    this.padding = const EdgeInsets.all(14),
  });
  final Widget child;
  final VoidCallback onPressed;
  final String? label;
  final FocusNode? focusNode;
  final bool autofocus, selected, reveal;
  final VoidCallback? onFocused;
  final FocusOnKeyEventCallback? onKeyEvent;
  final EdgeInsets padding;
  @override
  State<TvControl> createState() => _TvControlState();
}

class _TvControlState extends State<TvControl> {
  final _own = FocusNode();
  bool _focused = false;
  @override
  void dispose() {
    _own.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: widget.onKeyEvent,
    child: FocusableActionDetector(
      focusNode: widget.focusNode ?? _own,
      autofocus: widget.autofocus,
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onPressed();
            return null;
          },
        ),
      },
      onFocusChange: (value) {
        setState(() => _focused = value);
        if (value) {
          widget.onFocused?.call();
          if (widget.reveal) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _focused) {
                Scrollable.ensureVisible(
                  context,
                  duration: Duration.zero,
                  alignmentPolicy:
                      ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
                );
              }
            });
          }
        }
      },
      child: Semantics(
        button: true,
        label: widget.label,
        selected: widget.selected,
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 100),
          decoration: BoxDecoration(
            color: _focused
                ? AppColors.text
                : widget.selected
                ? const Color(0xFF153F54)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              width: 2,
              color: _focused
                  ? AppColors.accent
                  : widget.selected
                  ? AppColors.accent.withValues(alpha: .55)
                  : const Color(0xFF203148),
            ),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: DefaultTextStyle.merge(
              style: TextStyle(
                color: _focused ? AppColors.canvas : AppColors.text,
                fontSize: 18,
                height: 1.2,
                fontWeight: _focused ? FontWeight.w700 : FontWeight.w500,
              ),
              child: IconTheme.merge(
                data: IconThemeData(
                  color: _focused ? AppColors.canvas : AppColors.accent,
                  size: 23,
                ),
                child: InkWell(
                  canRequestFocus: false,
                  onTap: widget.onPressed,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(padding: widget.padding, child: widget.child),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class TvListEntry {
  const TvListEntry({
    required this.id,
    required this.title,
    required this.onPressed,
    this.subtitle = '',
    this.selected = false,
    this.leading,
    this.onFocused,
  });
  final String id, title, subtitle;
  final bool selected;
  final Widget? leading;
  final VoidCallback onPressed;
  final VoidCallback? onFocused;
}

class TvRemoteList extends StatefulWidget {
  const TvRemoteList({
    super.key,
    required this.entries,
    required this.onLeft,
    required this.onRight,
    required this.onTop,
    this.extent = 66,
    this.autofocus = false,
    this.label = 'List',
  });
  final List<TvListEntry> entries;
  final VoidCallback onLeft, onRight, onTop;
  final double extent;
  final bool autofocus;
  final String label;
  @override
  State<TvRemoteList> createState() => TvRemoteListState();
}

class TvRemoteListState extends State<TvRemoteList> {
  final _scroll = ScrollController();
  final _nodes = <String, FocusNode>{};
  String? _focused;
  int _generation = 0;
  FocusNode _node(TvListEntry e) => _nodes.putIfAbsent(
    e.id,
    () => FocusNode(debugLabel: '${widget.label}: ${e.title}'),
  );
  void focusSelected({bool remember = false}) {
    var index = remember
        ? widget.entries.indexWhere((e) => e.id == _focused)
        : -1;
    if (index < 0) index = widget.entries.indexWhere((e) => e.selected);
    focusIndex(index < 0 ? 0 : index);
  }

  void _reveal(int index) {
    if (!_scroll.hasClients || !_scroll.position.hasContentDimensions) return;
    final p = _scroll.position,
        start = index * widget.extent,
        end = (index + 1) * widget.extent;
    final offset =
        (start < p.pixels
                ? start
                : end > p.pixels + p.viewportDimension
                ? end - p.viewportDimension
                : p.pixels)
            .clamp(0.0, p.maxScrollExtent);
    if ((offset - p.pixels).abs() > .5) _scroll.jumpTo(offset);
  }

  void focusIndex(int index) {
    if (widget.entries.isEmpty) {
      widget.onTop();
      return;
    }
    index = index.clamp(0, widget.entries.length - 1);
    final e = widget.entries[index], node = _node(widget.entries[index]);
    _focused = e.id;
    final generation = ++_generation;
    _reveal(index);
    if (node.context != null) node.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _generation) return;
      _reveal(index);
      if (node.context != null) node.requestFocus();
    });
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final index = widget.entries.indexWhere((e) => e.id == _focused);
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (index + 1 < widget.entries.length) focusIndex(index + 1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (index > 0) {
        focusIndex(index - 1);
      } else {
        _generation++;
        widget.onTop();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
        event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _generation++;
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        widget.onLeft();
      } else {
        widget.onRight();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _scroll.dispose();
    for (final n in _nodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView.builder(
    controller: _scroll,
    itemExtent: widget.extent,
    cacheExtent: widget.extent * 6,
    itemCount: widget.entries.length,
    findChildIndexCallback: (key) {
      final i = widget.entries.indexWhere((e) => ValueKey(e.id) == key);
      return i < 0 ? null : i;
    },
    itemBuilder: (context, index) {
      final e = widget.entries[index];
      return Padding(
        key: ValueKey(e.id),
        padding: const EdgeInsets.only(bottom: 7),
        child: TvControl(
          autofocus:
              widget.autofocus &&
              (e.selected ||
                  !widget.entries.any((item) => item.selected) && index == 0),
          focusNode: _node(e),
          selected: e.selected,
          label: '${widget.label}: ${e.title}',
          reveal: false,
          onKeyEvent: _key,
          onFocused: () {
            _focused = e.id;
            _reveal(index);
            e.onFocused?.call();
          },
          onPressed: e.onPressed,
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
          child: Row(
            children: [
              if (e.leading != null) ...[e.leading!, const SizedBox(width: 10)],
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (e.subtitle.isNotEmpty)
                      Text(
                        e.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.2,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                  ],
                ),
              ),
              if (e.selected) ...[
                const SizedBox(width: 7),
                const Icon(Icons.check_rounded, size: 18),
              ],
            ],
          ),
        ),
      );
    },
  );
}
