import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import '../core/design_system.dart';

/// A single focus target that works with touch, a mouse and an Android remote.
class TvFocusCard extends StatefulWidget {
  const TvFocusCard({
    super.key,
    required this.child,
    required this.onPressed,
    this.autofocus = false,
    this.selected = false,
    this.borderRadius = 16,
    this.label,
    this.transparent = false,
    this.focusNode,
    this.onKeyEvent,
    this.onFocusChange,
    this.revealOnFocus = true,
  });

  final Widget child;
  final VoidCallback onPressed;
  final bool autofocus;
  final bool selected;
  final double borderRadius;
  final String? label;
  final bool transparent;
  final FocusNode? focusNode;
  final FocusOnKeyEventCallback? onKeyEvent;
  final ValueChanged<bool>? onFocusChange;
  final bool revealOnFocus;

  @override
  State<TvFocusCard> createState() => _TvFocusCardState();
}

class _TvFocusCardState extends State<TvFocusCard> {
  bool _focused = false;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: widget.label ?? 'Streamline card');
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: widget.onKeyEvent,
      child: FocusableActionDetector(
        focusNode: widget.focusNode ?? _focusNode,
        autofocus: widget.autofocus,
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed();
              return null;
            },
          ),
        },
        onFocusChange: (focused) {
          setState(() => _focused = focused);
          widget.onFocusChange?.call(focused);
          if (focused && widget.revealOnFocus) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _focused && _needsReveal()) {
                Scrollable.ensureVisible(
                  context,
                  alignment: .5,
                  alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
                  duration: duration,
                );
              }
            });
          }
        },
        child: Semantics(
          button: true,
          label: widget.label,
          selected: widget.selected,
          child: AnimatedScale(
            scale: _focused ? 1.025 : 1,
            duration: duration,
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: duration,
              decoration: BoxDecoration(
                color: _focused || widget.selected
                    ? AppColors.accent.withValues(alpha: .075)
                    : widget.transparent
                    ? Colors.transparent
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(widget.borderRadius),
                border: Border.all(
                  color: _focused
                      ? AppColors.text
                      : widget.selected
                      ? AppColors.accent.withValues(alpha: .65)
                      : widget.transparent
                      ? Colors.transparent
                      : AppColors.border,
                  width: 1.5,
                ),
                boxShadow: _focused
                    ? [
                        BoxShadow(
                          color: AppColors.accent.withValues(alpha: .15),
                          blurRadius: 24,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              clipBehavior: Clip.antiAlias,
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  canRequestFocus: false,
                  onTap: widget.onPressed,
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool _needsReveal() {
    final target = context.findRenderObject();
    if (target is! RenderBox || !target.hasSize) return false;
    RenderObject? parent = target.parent;
    while (parent != null) {
      if (parent is RenderAbstractViewport && parent is RenderBox) {
        final bounds = MatrixUtils.transformRect(
          target.getTransformTo(parent),
          Offset.zero & target.size,
        );
        if (!parent.paintBounds.inflate(1).contains(bounds.topLeft) ||
            !parent.paintBounds.inflate(1).contains(bounds.bottomRight)) {
          return true;
        }
      }
      parent = parent.parent;
    }
    return false;
  }
}
