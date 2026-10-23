import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/design_system.dart';
import 'tv_glass_theme.dart';

enum TvControlStyle { button, navigation, row, poster, primary, programme }

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
    this.style = TvControlStyle.button,
    this.spaceActivates = true,
  });
  final Widget child;
  final VoidCallback onPressed;
  final String? label;
  final FocusNode? focusNode;
  final bool autofocus, selected, reveal;
  final VoidCallback? onFocused;
  final FocusOnKeyEventCallback? onKeyEvent;
  final EdgeInsets padding;
  final TvControlStyle style;
  final bool spaceActivates;
  @override
  State<TvControl> createState() => _TvControlState();
}

class _TvControlState extends State<TvControl> {
  final _own = FocusNode();
  bool _focused = false;
  bool get _poster => widget.style == TvControlStyle.poster;
  bool get _navigation => widget.style == TvControlStyle.navigation;
  bool get _row => widget.style == TvControlStyle.row;
  bool get _light =>
      _focused && !_poster || widget.style == TvControlStyle.primary;
  @override
  void dispose() {
    _own.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final glass = TvGlassScope.of(context);
    final programme = widget.style == TvControlStyle.programme;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: widget.onKeyEvent,
      child: FocusableActionDetector(
        focusNode: widget.focusNode ?? _own,
        autofocus: widget.autofocus,
        shortcuts: {
          const SingleActivator(LogicalKeyboardKey.select):
              const ActivateIntent(),
          const SingleActivator(LogicalKeyboardKey.enter):
              const ActivateIntent(),
          const SingleActivator(LogicalKeyboardKey.numpadEnter):
              const ActivateIntent(),
          const SingleActivator(LogicalKeyboardKey.gameButtonA):
              const ActivateIntent(),
          if (widget.spaceActivates)
            const SingleActivator(LogicalKeyboardKey.space):
                const ActivateIntent(),
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
              color: _light && !(glass && _navigation)
                  ? AppColors.text
                  : widget.selected && !(glass && _navigation)
                  ? glass
                        ? const Color(0x1FFFFFFF)
                        : const Color(0xFF1A2735)
                  : programme
                  ? const Color(0x0BFFFFFF)
                  : _row || _navigation || _poster
                  ? Colors.transparent
                  : glass
                  ? const Color(0x14FFFFFF)
                  : const Color(0xFF18212D),
              borderRadius: BorderRadius.circular(
                glass
                    ? 3
                    : _poster
                    ? 8
                    : 7,
              ),
              border: Border.all(
                width: glass ? 1 : 2,
                color: _focused
                    ? widget.style == TvControlStyle.primary
                          ? AppColors.accent
                          : Colors.white
                    : Colors.transparent,
              ),
              boxShadow: _focused && _poster
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: .45),
                        blurRadius: 18,
                        offset: const Offset(0, 7),
                      ),
                    ]
                  : null,
            ),
            child: Stack(
              fit: StackFit.passthrough,
              children: [
                if (widget.selected &&
                    (!_focused || glass && _navigation) &&
                    (_row || _navigation))
                  Positioned(
                    left: _row
                        ? 0
                        : glass
                        ? 0
                        : 18,
                    right: _row
                        ? null
                        : glass
                        ? 0
                        : 18,
                    top: _row
                        ? glass
                              ? 3
                              : 12
                        : null,
                    bottom: _row
                        ? glass
                              ? 3
                              : 12
                        : 0,
                    width: _row ? 3 : null,
                    height: _row ? null : 2,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                Material(
                  type: MaterialType.transparency,
                  child: DefaultTextStyle.merge(
                    style: TextStyle(
                      color: _light && !(glass && _navigation)
                          ? AppColors.canvas
                          : AppColors.text,
                      fontSize: glass ? 12 : 18,
                      height: 1.2,
                      fontWeight: _focused
                          ? FontWeight.w700
                          : widget.selected ||
                                widget.style == TvControlStyle.primary
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                    child: IconTheme.merge(
                      data: IconThemeData(
                        color: _light
                            ? AppColors.canvas
                            : const Color(0xFFB5C3D3),
                        size: glass ? 15 : 23,
                      ),
                      child: InkWell(
                        canRequestFocus: false,
                        onTap: widget.onPressed,
                        borderRadius: BorderRadius.circular(7),
                        child: Padding(
                          padding: widget.padding,
                          child: widget.child,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
    this.trailing = '',
  });
  final String id, title, subtitle, trailing;
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
    this.dense = false,
  });
  final List<TvListEntry> entries;
  final VoidCallback onLeft, onRight, onTop;
  final double extent;
  final bool autofocus;
  final bool dense;
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
        padding: EdgeInsets.only(bottom: widget.dense ? 3 : 7),
        child: TvControl(
          style: TvControlStyle.row,
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
          padding: EdgeInsets.symmetric(
            horizontal: widget.dense ? 8 : 14,
            vertical: widget.dense
                ? 1
                : widget.extent <= 60
                ? 3
                : 5,
          ),
          child: Row(
            children: [
              if (e.leading != null) ...[e.leading!, const SizedBox(width: 10)],
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.title,
                      maxLines: e.subtitle.isEmpty ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: widget.dense
                            ? 12
                            : widget.extent <= 60
                            ? 17
                            : 18,
                        height: widget.dense ? 1 : 1.1,
                      ),
                    ),
                    if (e.subtitle.isNotEmpty)
                      Text(
                        e.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: widget.dense ? 10 : 14,
                          height: 1.2,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                  ],
                ),
              ),
              if (e.trailing.isNotEmpty) ...[
                SizedBox(width: widget.dense ? 6 : 12),
                Text(
                  e.trailing,
                  style: TextStyle(
                    fontSize: widget.dense ? 9 : 13,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}
