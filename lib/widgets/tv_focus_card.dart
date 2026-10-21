import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  });

  final Widget child;
  final VoidCallback onPressed;
  final bool autofocus;
  final bool selected;
  final double borderRadius;
  final String? label;

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
    final highlighted = _focused || widget.selected;
    return FocusableActionDetector(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
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
        if (focused) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              Scrollable.ensureVisible(
                context,
                alignment: .5,
                alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
                duration: const Duration(milliseconds: 160),
              );
            }
          });
        }
      },
      child: Semantics(
        button: true,
        label: widget.label,
        selected: widget.selected,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          decoration: BoxDecoration(
            color: highlighted
                ? const Color(0xFF193C3D)
                : const Color(0xFF121D2E),
            borderRadius: BorderRadius.circular(widget.borderRadius),
            border: Border.all(
              color: _focused
                  ? const Color(0xFF54E1C1)
                  : widget.selected
                  ? const Color(0xFF318B7D)
                  : const Color(0xFF223047),
              width: _focused ? 3 : 1,
            ),
            boxShadow: _focused
                ? const [BoxShadow(color: Color(0x4054E1C1), blurRadius: 15)]
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
    );
  }
}
