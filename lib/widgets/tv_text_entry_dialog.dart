import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tv_glass_theme.dart';

/// A remote-selectable field must reopen the IME even if it already has focus.
/// Merely requesting focus again does not replenish EditableText's keyboard token.
class TvTextEntryDialog extends StatefulWidget {
  const TvTextEntryDialog({
    super.key,
    required this.controller,
    required this.label,
    this.password = false,
  });
  final TextEditingController controller;
  final String label;
  final bool password;
  @override
  State<TvTextEntryDialog> createState() => _TvTextEntryDialogState();
}

class _TvTextEntryDialogState extends State<TvTextEntryDialog> {
  final _fieldKey = GlobalKey();
  late final _fieldFocus = FocusNode(
    debugLabel: 'TV ${widget.label.toLowerCase()} editor',
  );
  final _done = FocusNode(debugLabel: 'TV text entry done');
  final _visibility = FocusNode(debugLabel: 'TV password visibility');
  bool _obscured = true;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _fieldFocus.addListener(_inputFocusChanged);
  }

  void _inputFocusChanged() {
    if (_fieldFocus.hasFocus) return;
    scheduleMicrotask(() {
      // Android can close the IME connection and unfocus EditableText. When it
      // leaves the dialog scope as the focus target, return to the credential
      // control. Intentional moves to Show password or Done remain in the dialog.
      if (!mounted ||
          _closing ||
          ModalRoute.of(context)?.isCurrent != true ||
          _fieldFocus.hasFocus ||
          _done.hasFocus ||
          _visibility.hasFocus) {
        return;
      }
      if (FocusManager.instance.primaryFocus is FocusScopeNode) {
        _closing = true;
        Navigator.pop(context, false);
      }
    });
  }

  void _finish() {
    if (_closing) return;
    _closing = true;
    Navigator.pop(context, true);
  }

  void _keyboard() {
    // TextField owns the EditableText key. Use its public state API rather than
    // sending a bare TextInput.show without an attached input connection.
    EditableTextState? editable;
    void visit(Element element) {
      if (element is StatefulElement && element.state is EditableTextState) {
        editable = element.state as EditableTextState;
      } else {
        element.visitChildElements(visit);
      }
    }

    _fieldKey.currentContext?.visitChildElements(visit);
    editable?.requestKeyboard();
  }

  bool _activation(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.select ||
      key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter ||
      key == LogicalKeyboardKey.gameButtonA;

  KeyEventResult _fieldKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyRepeatEvent && _activation(event.logicalKey)) {
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_activation(event.logicalKey)) {
      _keyboard();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      (widget.password ? _visibility : _done).requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _fieldFocus.removeListener(_inputFocusChanged);
    _fieldFocus.dispose();
    _done.dispose();
    _visibility.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: TvGlass.theme(Theme.of(context)),
    child: AlertDialog(
      backgroundColor: TvGlass.canvas,
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 36, vertical: 12),
      title: Text(
        'Enter ${widget.label.toLowerCase()}',
        style: const TextStyle(fontSize: 20),
      ),
      content: SizedBox(
        width: 540,
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: _fieldKeyEvent,
          child: TextField(
            key: _fieldKey,
            controller: widget.controller,
            focusNode: _fieldFocus,
            autofocus: true,
            obscureText: widget.password && _obscured,
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: !widget.password,
            keyboardType: widget.password
                ? TextInputType.visiblePassword
                : TextInputType.text,
            autofillHints: [
              widget.password ? AutofillHints.password : AutofillHints.username,
            ],
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _finish(),
            style: const TextStyle(fontSize: 20),
            decoration: InputDecoration(
              labelText: widget.label,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 15,
              ),
            ),
          ),
        ),
      ),
      actions: [
        if (widget.password)
          TextButton(
            focusNode: _visibility,
            onPressed: () => setState(() => _obscured = !_obscured),
            child: Text(_obscured ? 'Show password' : 'Hide password'),
          ),
        FilledButton(
          focusNode: _done,
          onPressed: _finish,
          child: const Text('Done'),
        ),
      ],
    ),
  );
}
