import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../data/models.dart';
import 'tv_controls.dart';

class MyListButton extends ConsumerStatefulWidget {
  const MyListButton({super.key, required this.item});
  final MediaItem item;
  @override
  ConsumerState<MyListButton> createState() => _MyListButtonState();
}

class _MyListButtonState extends ConsumerState<MyListButton> {
  bool _saving = false;
  Future<void> _toggle(bool saved) async {
    final session = ref.read(sessionProvider);
    if (_saving || session == null) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(storeProvider)
          .setFavorite(session.accountId, widget.item, !saved);
      if (mounted) ref.invalidate(favoritesProvider);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not update My List. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final collection = ref.watch(favoritesProvider);
    final saved =
        collection.asData?.value.any((item) => item == widget.item) ?? false;
    if (ref.watch(isTvProvider)) {
      return TvControl(
        onPressed: _saving || collection.isLoading
            ? () {}
            : collection.hasError
            ? () => ref.invalidate(favoritesProvider)
            : () => _toggle(saved),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _saving
                  ? Icons.hourglass_empty
                  : saved
                  ? Icons.check
                  : Icons.add,
            ),
            const SizedBox(width: 8),
            Text(
              collection.hasError
                  ? 'Reload My List'
                  : saved
                  ? 'In My List'
                  : 'My List',
            ),
          ],
        ),
      );
    }
    return Tooltip(
      message:
          '${saved ? 'Remove' : 'Add'} ${widget.item.name} ${saved ? 'from' : 'to'} My List',
      child: OutlinedButton.icon(
        onPressed: _saving || collection.isLoading
            ? null
            : collection.hasError
            ? () => ref.invalidate(favoritesProvider)
            : () => _toggle(saved),
        icon: Icon(
          _saving
              ? Icons.hourglass_empty
              : saved
              ? Icons.check_rounded
              : Icons.add_rounded,
          size: 20,
        ),
        label: Text(
          collection.hasError
              ? 'Reload My List'
              : saved
              ? 'In My List'
              : 'My List',
        ),
      ),
    );
  }
}
