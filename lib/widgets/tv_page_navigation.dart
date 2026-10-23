import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'tv_controls.dart';

/// Utility pages use a predictable vertical order, including offscreen controls.
/// Their short forms must build all controls (Column, not a lazy ListView).
class TvPageNavigation extends StatefulWidget {
  const TvPageNavigation({
    super.key,
    required this.enabled,
    required this.child,
    this.autofocus = true,
    this.onLeft,
    this.onTop,
    this.onBottom,
  });
  final bool enabled, autofocus;
  final Widget child;
  final VoidCallback? onLeft, onTop, onBottom;
  @override
  State<TvPageNavigation> createState() => _TvPageNavigationState();
}

class _TvPageNavigationState extends State<TvPageNavigation> {
  final _scope = FocusScopeNode(
    debugLabel: 'TV page',
    traversalEdgeBehavior: TraversalEdgeBehavior.stop,
  );
  bool _scheduled = false;
  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_reveal);
  }

  void _reveal() {
    if (!widget.enabled || !_scope.hasFocus || _scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted || !_scope.hasFocus) return;
      final target = FocusManager.instance.primaryFocus?.context;
      if (target != null) Scrollable.ensureVisible(target, alignment: .4);
    });
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_reveal);
    _scope.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || ModalRoute.of(context)?.isCurrent == false) return;
        FocusManager.instance.applyFocusChangesIfNeeded();
        if (_scope.focusedChild == null) _scope.nextFocus();
      });
    }
    return FocusScope(
      node: _scope,
      autofocus: widget.autofocus,
      onKeyEvent: (_, event) {
        if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
            event.logicalKey == LogicalKeyboardKey.arrowLeft &&
            widget.onLeft != null) {
          widget.onLeft!();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: FocusTraversalGroup(
        policy: WidgetOrderTraversalPolicy(),
        child: Shortcuts(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.arrowDown): NextFocusIntent(),
            SingleActivator(LogicalKeyboardKey.arrowUp): PreviousFocusIntent(),
          },
          child: Actions(
            actions: {
              NextFocusIntent: CallbackAction<NextFocusIntent>(
                onInvoke: (_) {
                  if (!_scope.nextFocus()) widget.onBottom?.call();
                  return null;
                },
              ),
              PreviousFocusIntent: CallbackAction<PreviousFocusIntent>(
                onInvoke: (_) {
                  if (!_scope.previousFocus()) widget.onTop?.call();
                  return null;
                },
              ),
            },
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Makes long, read-only content scrollable with a remote as well as touch.
class TvScrollPane extends StatefulWidget {
  const TvScrollPane({
    super.key,
    required this.label,
    required this.child,
    this.onRight,
    this.onLeft,
    this.focusNode,
  });
  final String label;
  final Widget child;
  final VoidCallback? onRight, onLeft;
  final FocusNode? focusNode;
  @override
  State<TvScrollPane> createState() => _TvScrollPaneState();
}

class _TvScrollPaneState extends State<TvScrollPane> {
  final _scroll = ScrollController();
  final _own = FocusNode();
  bool _focused = false;
  FocusNode get _node => widget.focusNode ?? _own;
  @override
  void dispose() {
    _scroll.dispose();
    _own.dispose();
    super.dispose();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (!_node.hasPrimaryFocus ||
        (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight &&
        widget.onRight != null) {
      widget.onRight!();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
        widget.onLeft != null) {
      widget.onLeft!();
      return KeyEventResult.handled;
    }
    final down = event.logicalKey == LogicalKeyboardKey.arrowDown;
    final up = event.logicalKey == LogicalKeyboardKey.arrowUp;
    if ((!up && !down) || !_scroll.hasClients) return KeyEventResult.ignored;
    final p = _scroll.position;
    final next = (p.pixels + (down ? 1 : -1) * p.viewportDimension * .65).clamp(
      p.minScrollExtent,
      p.maxScrollExtent,
    );
    if ((next - p.pixels).abs() < .5) return KeyEventResult.handled;
    _scroll.jumpTo(next);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _node,
    onKeyEvent: _key,
    onFocusChange: (v) => setState(() => _focused = v),
    child: Semantics(
      label: widget.label,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _focused
                ? Colors.white.withValues(alpha: .65)
                : Colors.transparent,
            width: 2,
          ),
        ),
        child: Scrollbar(
          controller: _scroll,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.all(16),
            child: widget.child,
          ),
        ),
      ),
    ),
  );
}

Future<String?> showTvMenu(
  BuildContext context,
  String title,
  Map<String, String> choices,
) => showDialog<String>(
  context: context,
  builder: (context) => SimpleDialog(
    title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
    children: [
      SizedBox(
        width: 600,
        height: (choices.length * 46.0).clamp(
          46,
          MediaQuery.sizeOf(context).height * .58,
        ),
        child: TvRemoteList(
          autofocus: true,
          label: 'Menu option',
          fullRows: true,
          titleSize: 17,
          extent: 46,
          dense: true,
          onTop: () {},
          onLeft: () {},
          onRight: () {},
          entries: [
            for (final option in choices.entries)
              TvListEntry(
                id: option.key,
                title: option.value,
                onPressed: () => Navigator.pop(context, option.key),
              ),
          ],
        ),
      ),
    ],
  ),
);
