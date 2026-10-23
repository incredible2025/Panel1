import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'tv_controls.dart';
import 'tv_glass_theme.dart';
import 'tv_system_text_entry_dialog.dart';

/// Remote typing works without a device IME; system input is optional.
class TvTextEntryDialog extends StatefulWidget {
  const TvTextEntryDialog({
    super.key,
    required this.controller,
    required this.label,
    this.password = false,
    this.numericOnly = false,
  });
  final TextEditingController controller;
  final String label;
  final bool password;
  final bool numericOnly;
  @override
  State<TvTextEntryDialog> createState() => _TvTextEntryDialogState();
}

class _TvTextEntryDialogState extends State<TvTextEntryDialog> {
  final _nodes = <String, FocusNode>{};
  bool _upper = false, _symbols = false, _obscured = true;
  bool _systemOpen = false, _closing = false;
  late bool _activationHeld;
  bool _activation(LogicalKeyboardKey key) => [
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.gameButtonA,
  ].contains(key);
  @override
  void initState() {
    super.initState();
    _activationHeld = HardwareKeyboard.instance.logicalKeysPressed.any(
      _activation,
    );
    widget.controller.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    for (final node in _nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  FocusNode _node(int row, int col) => _nodes.putIfAbsent(
    '$row:$col',
    () => FocusNode(debugLabel: 'Remote keyboard $row:$col'),
  );
  List<String> get _letters => widget.numericOnly
      ? ['123', '456', '789', '0']
      : _symbols
      ? ['!@#\$%^&*()', '-_+=[]{}\\|', ';:\'",.<>/?', '`~01234567']
      : [
          '1234567890',
          _upper ? 'QWERTYUIOP' : 'qwertyuiop',
          _upper ? 'ASDFGHJKL@' : 'asdfghjkl@',
          _upper ? 'ZXCVBNM._-' : 'zxcvbnm._-',
        ];
  void _insert(String text) {
    if (widget.numericOnly) {
      text = text.replaceAll(RegExp('[^0-9]'), '');
      if (text.isEmpty) return;
    }
    final c = widget.controller, s = cSelection;
    var next = TextEditingValue(
      text: c.text.replaceRange(s.start, s.end, text),
      selection: TextSelection.collapsed(offset: s.start + text.length),
    );
    if (widget.numericOnly) {
      next = LengthLimitingTextInputFormatter(
        8,
      ).formatEditUpdate(c.value, next);
    }
    c.value = next;
  }

  TextSelection get cSelection => widget.controller.selection.isValid
      ? widget.controller.selection
      : TextSelection.collapsed(offset: widget.controller.text.length);
  void _delete() {
    final c = widget.controller, s = cSelection;
    var start = s.start;
    if (start == s.end && start > 0) {
      start -= c.text.substring(0, start).characters.last.length;
    }
    c.value = TextEditingValue(
      text: c.text.replaceRange(start, s.end, ''),
      selection: TextSelection.collapsed(offset: start),
    );
  }

  void _press(VoidCallback action) {
    // Block a held opening OK and repeated activation; touch stays independent.
    final pressed = HardwareKeyboard.instance.logicalKeysPressed.any(
      _activation,
    );
    if (pressed && _activationHeld) return;
    _activationHeld = pressed;
    action();
  }

  void _finish() {
    if (_closing || _systemOpen) return;
    _closing = true;
    Navigator.pop(context, true);
  }

  Future<void> _systemKeyboard() async {
    if (_systemOpen || _closing) return;
    _systemOpen = true;
    final route = DialogRoute<bool>(
      context: context,
      builder: (_) => TvSystemTextEntryDialog(
        controller: widget.controller,
        label: widget.label,
        password: widget.password,
      ),
    );
    final done = await Navigator.of(context).push(route);
    await route.completed;
    _systemOpen = false;
    if (!mounted) return;
    _activationHeld = HardwareKeyboard.instance.logicalKeysPressed.any(
      _activation,
    );
    if (done == true) {
      _finish();
    } else {
      _node(5, widget.password ? 1 : 0).requestFocus();
    }
  }

  KeyEventResult _physicalKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent && _activation(event.logicalKey)) {
      _activationHeld = false;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      _delete();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.pop(context, false);
      return KeyEventResult.handled;
    }
    final character = event.character;
    if (!_activation(event.logicalKey) &&
        !HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isMetaPressed &&
        !HardwareKeyboard.instance.isAltPressed &&
        character != null &&
        character.isNotEmpty &&
        character.runes.every((rune) => rune >= 32 && rune != 127)) {
      _insert(character);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final footer = <(String, VoidCallback)>[
      if (widget.password)
        (
          _obscured ? 'Show password' : 'Hide password',
          () => setState(() => _obscured = !_obscured),
        ),
      if (!widget.numericOnly) ('Use system keyboard', _systemKeyboard),
      ('Back', () => Navigator.pop(context, false)),
    ];
    final actions = widget.numericOnly
        ? <(String, VoidCallback)>[
            ('Delete', _delete),
            ('Clear', widget.controller.clear),
            ('Done', _finish),
          ]
        : <(String, VoidCallback)>[
            (
              'Shift',
              () => setState(() {
                _symbols = false;
                _upper = !_upper;
              }),
            ),
            (
              _symbols ? 'ABC' : '#+=',
              () => setState(() => _symbols = !_symbols),
            ),
            ('Space', () => _insert(' ')),
            ('Delete', _delete),
            ('Clear', widget.controller.clear),
            ('Done', _finish),
          ];
    final rows = <List<(String, VoidCallback)>>[
      for (final row in _letters)
        [for (final letter in row.split('')) (letter, () => _insert(letter))],
      actions,
      footer,
    ];
    Widget key(int row, int col) {
      final (label, action) = rows[row][col];
      return Expanded(
        child: Padding(
          padding: EdgeInsets.only(right: col + 1 < rows[row].length ? 6 : 0),
          child: TvControl(
            focusNode: _node(row, col),
            autofocus: row == 0 && col == 0,
            reveal: false,
            spaceActivates: false,
            label: row < 4 ? 'Type $label' : label,
            selected: row == 4 && (col == 0 && _upper || col == 1 && _symbols),
            style: row == 4 && col == actions.length - 1
                ? TvControlStyle.primary
                : TvControlStyle.button,
            onPressed: () => _press(action),
            onKeyEvent: (_, event) {
              if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
                return KeyEventResult.ignored;
              }
              final (nextRow, nextCol) = switch (event.logicalKey) {
                LogicalKeyboardKey.arrowUp => (math.max(0, row - 1), col),
                LogicalKeyboardKey.arrowDown => (math.min(5, row + 1), col),
                LogicalKeyboardKey.arrowLeft => (row, math.max(0, col - 1)),
                LogicalKeyboardKey.arrowRight => (
                  row,
                  math.min(rows[row].length - 1, col + 1),
                ),
                _ => (-1, -1),
              };
              if (nextRow < 0) return KeyEventResult.ignored;
              _node(
                nextRow,
                math.min(nextCol, rows[nextRow].length - 1),
              ).requestFocus();
              return KeyEventResult.handled;
            },
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 7),
            child: Center(
              child: Text(
                label,
                maxLines: 1,
                style: TextStyle(fontSize: row < 4 ? 19 : 13),
              ),
            ),
          ),
        ),
      );
    }

    final media = MediaQuery.of(context);
    final scale = math
        .min(
          media.size.width / 900,
          (media.size.height - media.viewInsets.bottom - 40) / 430,
        )
        .clamp(.4, 2.0);
    final value = widget.controller.text;
    final display = widget.password && _obscured
        ? List.filled(value.characters.length, '•').join()
        : value;
    return TvGlassScope(
      child: Theme(
        data: TvGlass.theme(Theme.of(context)),
        child: Dialog(
          backgroundColor: TvGlass.canvas,
          insetPadding: const EdgeInsets.all(20),
          child: SizedBox(
            width: 760 * scale,
            height: 430 * scale,
            child: FittedBox(
              child: SizedBox(
                width: 760,
                height: 430,
                child: Focus(
                  canRequestFocus: false,
                  skipTraversal: true,
                  onKeyEvent: _physicalKey,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Enter ${widget.label.toLowerCase()}',
                          style: const TextStyle(fontSize: 22),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          height: 48,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          alignment: Alignment.centerLeft,
                          decoration: BoxDecoration(
                            color: TvGlass.panel,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Semantics(
                            label:
                                '${widget.label}, ${value.characters.length} characters',
                            excludeSemantics: widget.password && _obscured,
                            child: Text(
                              display.isEmpty ? widget.label : display,
                              key: const ValueKey('tv-keyboard-value'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 20,
                                color: display.isEmpty
                                    ? TvGlass.muted
                                    : TvGlass.ink,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'D-pad to choose a key · OK to type · Done to continue',
                          style: TextStyle(fontSize: 12, color: TvGlass.muted),
                        ),
                        const SizedBox(height: 12),
                        for (var row = 0; row < rows.length; row++) ...[
                          SizedBox(
                            height: row == 5 ? 34 : 38,
                            child: Row(
                              children: [
                                for (var col = 0; col < rows[row].length; col++)
                                  key(row, col),
                              ],
                            ),
                          ),
                          if (row + 1 < rows.length)
                            SizedBox(height: row == 3 ? 12 : 6),
                        ],
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
