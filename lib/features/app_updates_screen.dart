import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_version.dart';
import '../core/update_controller.dart';

class AppUpdatesScreen extends ConsumerStatefulWidget {
  const AppUpdatesScreen({super.key});
  @override
  ConsumerState<AppUpdatesScreen> createState() => _AppUpdatesScreenState();
}

class _AppUpdatesScreenState extends ConsumerState<AppUpdatesScreen> {
  bool _loaded = false;
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final controller = ref.read(updateControllerProvider);
      try {
        await controller.load();
      } catch (_) {
        /* Manual check reports the error. */
      }
      if (mounted) {
        setState(() {
          _loaded = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(updateControllerProvider);
    final update = c.update;
    final status = switch (c.stage) {
      UpdateStage.idle => 'Ready to check',
      UpdateStage.checking => 'Checking for updates…',
      UpdateStage.current => 'You’re up to date',
      UpdateStage.available => 'A new version is available',
      UpdateStage.downloading => 'Downloading update…',
      UpdateStage.ready => 'Verified and ready to install',
      UpdateStage.permission => 'Allow installation, then return here',
      UpdateStage.installer => 'Installer opened',
      UpdateStage.failed => 'Update needs attention',
    };
    return Scaffold(
      appBar: AppBar(title: const Text('App updates')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(status, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              Text(
                'Installed: ${c.device?.version ?? appVersion}${c.device == null ? '' : ' (${c.device!.code})'}',
              ),
              if (c.lastCheck != null)
                Text(
                  'Last attempt: ${c.lastCheck!.toLocal().toString().split('.').first}',
                ),
              const SizedBox(height: 20),
              if (c.error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    c.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (update != null) ...[
                Text(
                  'Version ${update.version} • ${(update.bytes / 1048576).toStringAsFixed(1)} MB',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Text(
                  update.notes.isEmpty
                      ? 'Improvements and fixes for ULTRAVPN PLAYER.'
                      : update.notes,
                ),
                const SizedBox(height: 20),
              ],
              if (c.stage == UpdateStage.downloading) ...[
                LinearProgressIndicator(value: c.received / update!.bytes),
                const SizedBox(height: 8),
                Text(
                  '${(100 * c.received / update.bytes).toStringAsFixed(0)}% downloaded',
                ),
                TextButton(
                  onPressed: c.cancel,
                  child: const Text('Cancel download'),
                ),
              ] else if (update != null &&
                  [
                    UpdateStage.ready,
                    UpdateStage.permission,
                    UpdateStage.installer,
                  ].contains(c.stage)) ...[
                FilledButton.icon(
                  onPressed: c.busy ? null : c.install,
                  icon: const Icon(Icons.system_update),
                  label: const Text('Install update'),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Android asks you to approve installation. If you cancel the installer, return here and choose Install update again.',
                ),
              ] else if (update != null && !c.busy)
                FilledButton.icon(
                  onPressed: c.download,
                  icon: const Icon(Icons.download),
                  label: const Text('Download update'),
                ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: c.busy || !_loaded
                    ? null
                    : () => c.check(),
                child: const Text('Check for updates'),
              ),
              const SizedBox(height: 24),
              const Text(
                'Updates download only when you choose. Android asks you to approve installation.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class UpdateNotice extends ConsumerWidget {
  const UpdateNotice({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(updateControllerProvider);
    if (c.update == null) return const SizedBox.shrink();
    return TextButton.icon(
      onPressed: () => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const AppUpdatesScreen())),
      icon: const Icon(Icons.system_update),
      label: Text('Update ${c.update!.version} available'),
    );
  }
}
