import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/design_system.dart';
import 'tv_focus_card.dart';

class TvCategoryChoice {
  const TvCategoryChoice({
    required this.id,
    required this.label,
    required this.onPressed,
    this.selected = false,
  });
  final String id, label;
  final VoidCallback onPressed;
  final bool selected;
}

/// Fixed-extent, virtualized TV row. Explicit adjacency makes unbuilt categories
/// reachable and prevents geometric traversal escaping into unrelated controls.
class TvCategoryStrip extends StatefulWidget {
  const TvCategoryStrip({
    super.key,
    required this.choices,
    required this.onUp,
    required this.onLeftBoundary,
    this.onRightBoundary,
  });
  final List<TvCategoryChoice> choices;
  final VoidCallback onUp, onLeftBoundary;
  final VoidCallback? onRightBoundary;
  @override
  State<TvCategoryStrip> createState() => TvCategoryStripState();
}

class TvCategoryStripState extends State<TvCategoryStrip> {
  static const itemExtent = 184.0;
  final _scroll = ScrollController();
  final _nodes = <String, FocusNode>{};
  String? _focusedId;
  int _generation = 0;
  FocusNode _node(TvCategoryChoice choice) => _nodes.putIfAbsent(
    choice.id,
    () => FocusNode(debugLabel: 'Category: ${choice.label}'),
  );

  void focusSelected() {
    final index = widget.choices.indexWhere((choice) => choice.selected);
    _focus(index < 0 ? 0 : index);
  }

  void focusLastFocused() {
    final index = widget.choices.indexWhere(
      (choice) => choice.id == _focusedId,
    );
    if (index < 0) {
      focusSelected();
    } else {
      _focus(index);
    }
  }

  void _reveal(int index) {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (!position.hasContentDimensions) return;
    final left = index * itemExtent;
    final right = left + itemExtent;
    final desired = left < position.pixels
        ? left
        : right > position.pixels + position.viewportDimension
        ? right - position.viewportDimension
        : position.pixels;
    final offset = desired.clamp(0.0, position.maxScrollExtent);
    if ((offset - position.pixels).abs() > .5) _scroll.jumpTo(offset);
  }

  void _focus(int index) {
    if (widget.choices.isEmpty) return;
    final choice = widget.choices[index.clamp(0, widget.choices.length - 1)];
    _focusedId = choice.id;
    final generation = ++_generation;
    final node = _node(choice);
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
    final index = widget.choices.indexWhere(
      (choice) => choice.id == _focusedId,
    );
    if (index < 0) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (index + 1 < widget.choices.length) {
        _focus(index + 1);
      } else {
        _generation++;
        widget.onRightBoundary?.call();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (index > 0) {
        _focus(index - 1);
      } else {
        _generation++;
        widget.onLeftBoundary();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _generation++;
      widget.onUp();
      return KeyEventResult.handled;
    }
    // Down keeps the normal spatial transition into the library below the row.
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _generation++;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _generation++;
    _scroll.dispose();
    for (final node in _nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 46,
    child: FocusTraversalGroup(
      child: ListView.builder(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        itemExtent: itemExtent,
        cacheExtent: itemExtent * 3,
        itemCount: widget.choices.length,
        findChildIndexCallback: (key) {
          if (key is! ValueKey<String>) return null;
          final index = widget.choices.indexWhere(
            (choice) => choice.id == key.value,
          );
          return index < 0 ? null : index;
        },
        itemBuilder: (context, index) {
          final choice = widget.choices[index];
          return Padding(
            key: ValueKey(choice.id),
            padding: const EdgeInsets.only(right: 8),
            child: TvFocusCard(
              key: ValueKey(choice.id),
              focusNode: _node(choice),
              label: 'Category: ${choice.label}',
              selected: choice.selected,
              transparent: true,
              borderRadius: 30,
              revealOnFocus: false,
              onKeyEvent: _key,
              onFocusChange: (focused) {
                if (focused) {
                  _focusedId = choice.id;
                  _reveal(index);
                }
              },
              onPressed: choice.onPressed,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    choice.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: choice.selected
                          ? AppColors.accent
                          : AppColors.muted,
                      fontSize: 12,
                      fontWeight: choice.selected
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}
