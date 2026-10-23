import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models.dart';
import 'tv_controls.dart';
import 'tv_glass_theme.dart';
import 'tv_poster_browser.dart';

class TvHomeShelf {
  const TvHomeShelf(this.title, this.items, {this.progress = const {}});
  final String title;
  final List<MediaItem> items;
  final Map<String, double> progress;
}

/// A fixed home canvas: two complete horizontal shelves, with additional
/// collections selected by a compact row. There is no vertical page scroller.
class TvHomeShelves extends StatefulWidget {
  const TvHomeShelves({
    super.key,
    required this.shelves,
    required this.hero,
    required this.heroFocus,
    required this.onTop,
    required this.onOpen,
    this.largePosters = false,
    this.emptyMessage =
        'No titles are available. Browse Live TV from the navigation above.',
  });
  final List<TvHomeShelf> shelves;
  final Widget Function(double height) hero;
  final FocusNode heroFocus;
  final VoidCallback onTop;
  final ValueChanged<MediaItem> onOpen;
  final bool largePosters;
  final String emptyMessage;
  @override
  State<TvHomeShelves> createState() => _TvHomeShelvesState();
}

class _TvHomeShelvesState extends State<TvHomeShelves> {
  final _rows = [
    GlobalKey<TvPosterBrowserState>(),
    GlobalKey<TvPosterBrowserState>(),
  ];
  final _tabs = <String, FocusNode>{};
  int _page = 0;

  FocusNode _tab(int page, List<TvHomeShelf> shelves) => _tabs.putIfAbsent(
    shelves[page * 2].title,
    () => FocusNode(
      debugLabel:
          'Home collection: ${page == 0 ? 'For you' : shelves[page * 2].title}',
    ),
  );

  void _select(int page) {
    if (_page == page) return;
    setState(() => _page = page);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        for (final row in _rows) {
          row.currentState?.resetPosition();
        }
      }
    });
  }

  @override
  void dispose() {
    for (final node in _tabs.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shelves = widget.shelves.where((e) => e.items.isNotEmpty).toList();
    final pages = (shelves.length / 2).ceil();
    if (pages > 0) {
      _page = _page.clamp(0, pages - 1);
    }
    final visible = shelves.skip(_page * 2).take(2).toList();
    void focusTab() {
      if (pages > 0) {
        _tab(_page, shelves).requestFocus();
      } else {
        widget.onTop();
      }
    }

    return Column(
      key: const ValueKey('tv-fixed-home'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: (_, event) {
            if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
              return KeyEventResult.ignored;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
                event.logicalKey == LogicalKeyboardKey.arrowRight) {
              focusTab();
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
                event.logicalKey == LogicalKeyboardKey.arrowLeft) {
              widget.onTop();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: widget.hero(140),
        ),
        if (pages > 0)
          SizedBox(
            height: 34,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 26),
              child: Row(
                children: [
                  for (var page = 0; page < pages; page++)
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: TvControl(
                          style: TvControlStyle.navigation,
                          focusNode: _tab(page, shelves),
                          selected: _page == page,
                          label: page == 0
                              ? 'For you'
                              : shelves[page * 2].title,
                          onFocused: () => _select(page),
                          onPressed: () {
                            final changed = _page != page;
                            _select(page);
                            if (changed) {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted) {
                                  _rows[0].currentState?.focusFirst();
                                }
                              });
                            } else {
                              _rows[0].currentState?.focusFirst();
                            }
                          },
                          onKeyEvent: (_, event) {
                            if (event is! KeyDownEvent &&
                                event is! KeyRepeatEvent) {
                              return KeyEventResult.ignored;
                            }
                            switch (event.logicalKey) {
                              case LogicalKeyboardKey.arrowLeft:
                                if (page > 0) {
                                  _tab(page - 1, shelves).requestFocus();
                                }
                              case LogicalKeyboardKey.arrowRight:
                                if (page + 1 < pages) {
                                  _tab(page + 1, shelves).requestFocus();
                                }
                              case LogicalKeyboardKey.arrowUp:
                                widget.heroFocus.requestFocus();
                              case LogicalKeyboardKey.arrowDown:
                                _rows[0].currentState?.focusFirst();
                              default:
                                return KeyEventResult.ignored;
                            }
                            return KeyEventResult.handled;
                          },
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 6,
                          ),
                          child: Text(
                            page == 0 ? 'For you' : shelves[page * 2].title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        for (var index = 0; index < visible.length; index++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(26, 8, 26, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    visible[index].title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.2,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: TvPosterBrowser(
                      key: _rows[index],
                      horizontal: true,
                      compact: true,
                      explicitVertical: true,
                      items: visible[index].items.take(48).toList(),
                      progress: visible[index].progress,
                      largePosters: widget.largePosters,
                      onOpen: widget.onOpen,
                      onLeft: focusTab,
                      onTop: index == 0
                          ? focusTab
                          : () => _rows[0].currentState?.focusAt(
                              _rows[1].currentState?.focusedIndex ?? 0,
                            ),
                      onDown: index + 1 < visible.length
                          ? () => _rows[1].currentState?.focusAt(
                              _rows[0].currentState?.focusedIndex ?? 0,
                            )
                          : () {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (visible.length == 1) const Spacer(),
        if (visible.isEmpty)
          Expanded(
            child: Center(
              child: Text(
                widget.emptyMessage,
                style: TextStyle(fontSize: 13, color: TvGlass.muted),
              ),
            ),
          ),
      ],
    );
  }
}
