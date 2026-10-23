import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'tv_controls.dart';
import 'tv_glass_theme.dart';

/// TV utility pages share the fixed Glass canvas; only bounded panes may scroll.
class TvUtilityScaffold extends StatefulWidget {
  const TvUtilityScaffold({
    super.key,
    required this.title,
    required this.child,
    this.subtitle = '',
    this.onEnter,
    this.hint = 'D-pad  Move    OK  Select    Back  Return',
  });
  final String title, subtitle, hint;
  final Widget child;
  final VoidCallback? onEnter;
  @override
  State<TvUtilityScaffold> createState() => _TvUtilityScaffoldState();
}

class _TvUtilityScaffoldState extends State<TvUtilityScaffold> {
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, box) {
          final scale = math.min(box.maxWidth / 1024, box.maxHeight / 576);
          return Center(
            child: SizedBox(
              width: 1024 * scale,
              height: 576 * scale,
              child: FittedBox(
                child: SizedBox(
                  key: const ValueKey('tv-utility-canvas'),
                  width: 1024,
                  height: 576,
                  child: MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.noScaling),
                    child: TvGlassScope(
                      child: Theme(
                        data: TvGlass.theme(Theme.of(context)).copyWith(
                          textTheme: TvGlass.theme(
                            Theme.of(context),
                          ).textTheme.apply(fontSizeFactor: .9),
                        ),
                        child: TvGlassBackdrop(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 14, 24, 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    TvControl(
                                      label: 'Back',
                                      reveal: false,
                                      onPressed: () =>
                                          Navigator.maybePop(context),
                                      onKeyEvent: (_, event) {
                                        if ((event is KeyDownEvent ||
                                                event is KeyRepeatEvent) &&
                                            event.logicalKey ==
                                                LogicalKeyboardKey.arrowDown &&
                                            widget.onEnter != null) {
                                          widget.onEnter!();
                                          return KeyEventResult.handled;
                                        }
                                        return KeyEventResult.ignored;
                                      },
                                      padding: const EdgeInsets.all(8),
                                      child: const Icon(
                                        Icons.arrow_back,
                                        size: 19,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            widget.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 23,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          if (widget.subtitle.isNotEmpty)
                                            Text(
                                              widget.subtitle,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: TvGlass.muted,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Expanded(child: widget.child),
                                const SizedBox(height: 10),
                                Text(
                                  widget.hint,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: TvGlass.muted,
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
              ),
            ),
          );
        },
      ),
    ),
  );
}

/// Small fixed action column. Primary actions keep their focus across run states.
class TvUtilityAction extends StatelessWidget {
  const TvUtilityAction({
    super.key,
    required this.label,
    required this.onPressed,
    required this.focusNode,
    this.autofocus = false,
    this.onLeft,
    this.onRight,
    this.onUp,
    this.onDown,
  });
  final String label;
  final VoidCallback? onPressed, onLeft, onRight, onUp, onDown;
  final FocusNode focusNode;
  final bool autofocus;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 56,
    child: TvControl(
      focusNode: focusNode,
      autofocus: autofocus,
      reveal: false,
      onPressed: () => onPressed?.call(),
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        final move = switch (event.logicalKey) {
          LogicalKeyboardKey.arrowLeft => onLeft,
          LogicalKeyboardKey.arrowRight => onRight,
          LogicalKeyboardKey.arrowUp => onUp,
          LogicalKeyboardKey.arrowDown => onDown,
          _ => null,
        };
        if (move == null) {
          return event.logicalKey == LogicalKeyboardKey.arrowDown
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        }
        move();
        return KeyEventResult.handled;
      },
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Text(
        label,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 14,
          height: 1.1,
          color: onPressed == null ? TvGlass.muted : null,
        ),
      ),
    ),
  );
}
