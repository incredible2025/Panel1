import 'package:flutter/material.dart';
import 'tv_text_entry_dialog.dart';

Future<String?> showTvPinEntry(
  BuildContext context,
  String label, {
  String initial = '',
}) async {
  final controller = TextEditingController(text: initial);
  try {
    final route = DialogRoute<bool>(
      context: context,
      builder: (_) => TvTextEntryDialog(
        controller: controller,
        label: label,
        password: true,
        numericOnly: true,
      ),
    );
    final done = await Navigator.of(context).push(route);
    await route.completed;
    if (done != true || !context.mounted) return null;
    if (controller.text.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Use four to eight digits for your parental PIN.'),
        ),
      );
      return null;
    }
    return controller.text;
  } finally {
    controller.dispose();
  }
}
