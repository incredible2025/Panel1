import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models.dart';
import 'media_card.dart';
import 'tv_controls.dart';
import 'tv_glass_theme.dart';

class TvPosterBrowser extends StatefulWidget {
  const TvPosterBrowser({
    super.key,
    required this.items,
    required this.onOpen,
    required this.onLeft,
    required this.onTop,
    this.horizontal = false,
    this.largePosters = false,
    this.progress = const {},
    this.onDown,
    this.explicitVertical = false,
    this.compact = false,
  });
  final List<MediaItem> items;
  final ValueChanged<MediaItem> onOpen;
  final VoidCallback onLeft, onTop;
  final bool horizontal;
  final bool largePosters;
  final Map<String, double> progress;
  final VoidCallback? onDown;
  final bool explicitVertical, compact;
  @override
  State<TvPosterBrowser> createState() => TvPosterBrowserState();
}

class TvPosterBrowserState extends State<TvPosterBrowser> {
  final _scroll = ScrollController();
  final _nodes = <String, FocusNode>{};
  String? _focused;
  int _columns = 1, _generation = 0;
  double _extent = 280;
  String _id(MediaItem item) => AppKey.item(item);
  FocusNode _node(MediaItem item) => _nodes.putIfAbsent(
    _id(item),
    () => FocusNode(debugLabel: 'Title: ${item.name}'),
  );
  void focusFirst() => _focus(0);
  int get focusedIndex => widget.items.isEmpty
      ? 0
      : widget.items
            .indexWhere((e) => _id(e) == _focused)
            .clamp(0, widget.items.length - 1);
  void focusAt(int index) {
    if (widget.items.isNotEmpty) {
      _focus(index.clamp(0, widget.items.length - 1));
    }
  }

  void resetPosition() {
    _generation++;
    _focused = null;
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _reveal(int index) {
    if (!_scroll.hasClients || !_scroll.position.hasContentDimensions) return;
    final p = _scroll.position,
        start = (index ~/ _columns) * _extent,
        end = start + _extent;
    final offset =
        (start < p.pixels
                ? start
                : end > p.pixels + p.viewportDimension
                ? end - p.viewportDimension
                : p.pixels)
            .clamp(0.0, p.maxScrollExtent);
    if ((offset - p.pixels).abs() > .5) _scroll.jumpTo(offset);
  }

  void _focus(int index) {
    if (widget.items.isEmpty) return;
    final item = widget.items[index];
    _focused = _id(item);
    final generation = ++_generation, node = _node(item);
    _reveal(index);
    if (node.context != null) node.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && generation == _generation) {
        _reveal(index);
        if (node.context != null) node.requestFocus();
      }
    });
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final i = widget.items.indexWhere((e) => _id(e) == _focused);
    if (i < 0) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (i > 0 && (widget.horizontal || i % _columns > 0)) {
        _focus(i - 1);
      } else {
        _generation++;
        widget.onLeft();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (i + 1 < widget.items.length &&
          (widget.horizontal || i % _columns < _columns - 1)) {
        _focus(i + 1);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      if (widget.horizontal) {
        if (!widget.explicitVertical) return KeyEventResult.ignored;
        widget.onTop();
        return KeyEventResult.handled;
      }
      if (!widget.horizontal && i >= _columns) {
        _focus(i - _columns);
      } else {
        _generation++;
        widget.onTop();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown &&
        widget.horizontal &&
        widget.explicitVertical) {
      widget.onDown?.call();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown && !widget.horizontal) {
      final lastRow = (widget.items.length - 1) ~/ _columns;
      if (i ~/ _columns < lastRow) {
        _focus((i + _columns).clamp(0, widget.items.length - 1));
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void didUpdateWidget(covariant TvPosterBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.horizontal != widget.horizontal) {
      _generation++;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
      });
    }
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
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) {
      final glass = TvGlassScope.of(context);
      _columns = widget.horizontal
          ? 1
          : glass
          ? (widget.largePosters ? 5 : 6)
          : (size.maxWidth / (widget.largePosters ? 220 : 175)).floor().clamp(
              2,
              6,
            );
      final gap = glass ? 10.0 : 16.0;
      final width = widget.horizontal && glass
          ? (size.maxWidth - (widget.largePosters ? 4 : 5) * gap) /
                (widget.largePosters ? 5 : 6)
          : widget.horizontal
          ? (widget.largePosters ? 220.0 : 186.0)
          : (size.maxWidth - (_columns - 1) * gap) / _columns;
      _extent = widget.horizontal
          ? width + gap
          : glass
          ? width * .56 + 44 + gap
          : width * 1.38 + 64;
      Widget tile(int index) {
        final item = widget.items[index],
            progress = widget.progress[_id(widget.items[index])];
        return TvControl(
          style: TvControlStyle.poster,
          focusNode: _node(item),
          label: item.name,
          reveal: widget.horizontal,
          padding: EdgeInsets.zero,
          onKeyEvent: _key,
          onFocused: () {
            _focused = _id(item);
            _reveal(index);
          },
          onPressed: () => widget.onOpen(item),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(glass ? 3 : 10),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Artwork(url: item.imageUrl, title: item.name),
                      if (item.rating.isNotEmpty && !glass)
                        Positioned(
                          top: 9,
                          right: 9,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xDF060E1B),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.star_rounded,
                                  size: 14,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  item.rating,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (progress != null)
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: LinearProgressIndicator(
                            value: progress.clamp(0, 1),
                            minHeight: glass ? 2 : 5,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: glass ? 1 : 11,
                  vertical: glass ? 5 : 10,
                ),
                child: Text(
                  item.name,
                  maxLines: glass ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: glass ? 11 : 16, height: 1.2),
                ),
              ),
              if (glass && !widget.compact)
                Padding(
                  padding: const EdgeInsets.only(left: 1, bottom: 5),
                  child: Text(
                    '${item.kind == MediaKind.series
                        ? 'Series'
                        : item.kind == MediaKind.live
                        ? 'Live TV'
                        : 'Movie'}${item.rating.isEmpty ? '' : ' · Rating ${item.rating}'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 9, color: TvGlass.muted),
                  ),
                ),
            ],
          ),
        );
      }

      if (widget.horizontal) {
        return ListView.builder(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          itemExtent: _extent,
          itemCount: widget.items.length,
          cacheExtent: _extent * 3,
          itemBuilder: (_, i) => Padding(
            key: ValueKey(_id(widget.items[i])),
            padding: EdgeInsets.only(right: gap),
            child: tile(i),
          ),
        );
      }
      return GridView.builder(
        controller: _scroll,
        itemCount: widget.items.length,
        cacheExtent: _extent * 2,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _columns,
          mainAxisExtent: _extent - gap,
          crossAxisSpacing: gap,
          mainAxisSpacing: gap,
        ),
        itemBuilder: (_, i) =>
            KeyedSubtree(key: ValueKey(_id(widget.items[i])), child: tile(i)),
      );
    },
  );
}

abstract final class AppKey {
  static String item(MediaItem item) => '${item.kind.name}:${item.id}';
}
