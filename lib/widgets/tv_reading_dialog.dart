import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/design_system.dart';
import 'tv_controls.dart';
import 'tv_glass_theme.dart';
import 'tv_page_navigation.dart';

Future<bool?> showTvReadingDialog(
  BuildContext context,
  String title,
  Widget content, {
  String? actionLabel,
}) => showDialog<bool>(
  context: context,
  builder: (_) =>
      TvReadingDialog(title: title, content: content, actionLabel: actionLabel),
);

class TvReadingDialog extends StatefulWidget {
  const TvReadingDialog({
    super.key,
    required this.title,
    required this.content,
    this.actionLabel,
  });
  final String title;
  final Widget content;
  final String? actionLabel;
  @override
  State<TvReadingDialog> createState() => _TvReadingDialogState();
}

class _TvReadingDialogState extends State<TvReadingDialog> {
  final _reading = FocusNode(debugLabel: 'Dialog information');
  final _close = FocusNode(debugLabel: 'Close information');
  final _action = FocusNode(debugLabel: 'Information action');
  @override
  void dispose() {
    _reading.dispose();
    _close.dispose();
    _action.dispose();
    super.dispose();
  }

  KeyEventResult _key(KeyEvent event, FocusNode horizontal) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _reading.requestFocus();
      return KeyEventResult.handled;
    }
    if ([
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
    ].contains(event.logicalKey)) {
      horizontal.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    if (media.size.width < 600) {
      return AlertDialog(
        title: Text(widget.title),
        content: SizedBox(
          width: double.maxFinite,
          height: math.min(380, media.size.height * .5),
          child: TvScrollPane(
            label: widget.title,
            focusNode: _reading,
            onRight: _close.requestFocus,
            child: widget.content,
          ),
        ),
        actions: [
          TextButton(
            focusNode: _close,
            autofocus: widget.actionLabel == null,
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Close'),
          ),
          if (widget.actionLabel != null)
            FilledButton(
              focusNode: _action,
              autofocus: true,
              onPressed: () => Navigator.pop(context, true),
              child: Text(widget.actionLabel!),
            ),
        ],
      );
    }
    final scale = math
        .min(media.size.width / 960, (media.size.height - 40) / 450)
        .clamp(.5, 2.0);
    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 850 * scale,
        height: 450 * scale,
        child: FittedBox(
          child: SizedBox(
            width: 850,
            height: 450,
            child: TvGlassScope(
              child: Theme(
                data: TvGlass.theme(Theme.of(context)),
                child: AppBackdrop(
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          widget.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 23, height: 1.15),
                        ),
                        const SizedBox(height: 14),
                        Expanded(
                          child: TvScrollPane(
                            label: widget.title,
                            focusNode: _reading,
                            onRight: () =>
                                (widget.actionLabel == null ? _close : _action)
                                    .requestFocus(),
                            child: DefaultTextStyle.merge(
                              style: const TextStyle(fontSize: 15, height: 1.5),
                              child: widget.content,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TvControl(
                              focusNode: _close,
                              autofocus: widget.actionLabel == null,
                              onKeyEvent: (_, event) => _key(
                                event,
                                widget.actionLabel == null ? _reading : _action,
                              ),
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text(
                                'Close',
                                style: TextStyle(fontSize: 14),
                              ),
                            ),
                            if (widget.actionLabel != null) ...[
                              const SizedBox(width: 12),
                              TvControl(
                                focusNode: _action,
                                autofocus: true,
                                style: TvControlStyle.primary,
                                onKeyEvent: (_, event) => _key(event, _close),
                                onPressed: () => Navigator.pop(context, true),
                                child: Text(
                                  widget.actionLabel!,
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                            ],
                          ],
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
    );
  }
}
