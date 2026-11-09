import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/providers.dart';

class ManagedHomeNotice extends ConsumerStatefulWidget {
  const ManagedHomeNotice({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<ManagedHomeNotice> createState() => _ManagedHomeNoticeState();
}

class _ManagedHomeNoticeState extends ConsumerState<ManagedHomeNotice> {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final manager = ref.watch(managedConfigurationProvider);
    if (manager == null) return widget.child;
    return ListenableBuilder(
      listenable: manager,
      builder: (context, _) {
        final notice = manager.current.notice;
        if (notice == null ||
            !notice.activeAt(DateTime.now()) ||
            manager.dismissedNoticeId == notice.id) {
          return widget.child;
        }
        return Column(
          children: [
            Material(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          notice.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      TextButton(
                        onPressed: () => showDialog<void>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text(notice.title),
                            content: SingleChildScrollView(
                              child: Text(notice.body),
                            ),
                            actions: [
                              TextButton(
                                autofocus: true,
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Close'),
                              ),
                            ],
                          ),
                        ),
                        child: const Text('Read notice'),
                      ),
                      IconButton(
                        tooltip: 'Dismiss notice',
                        onPressed: () => manager.dismissNotice(notice.id),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(child: widget.child),
          ],
        );
      },
    );
  }
}
