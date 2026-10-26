import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_version.dart';
import '../core/design_system.dart';
import '../core/providers.dart';
import '../core/update_controller.dart';
import '../widgets/tv_page_navigation.dart';
import '../widgets/tv_utility_scaffold.dart';
import '../widgets/tv_glass_theme.dart';

class AppUpdatesScreen extends ConsumerStatefulWidget {
  const AppUpdatesScreen({super.key});
  @override
  ConsumerState<AppUpdatesScreen> createState() => _AppUpdatesScreenState();
}

class _AppUpdatesScreenState extends ConsumerState<AppUpdatesScreen> {
  bool _loaded = false;
  final _primary = FocusNode(debugLabel: 'Update action');
  final _notes = FocusNode(debugLabel: 'Update details');
  final _check = FocusNode(debugLabel: 'Check update again');
  @override
  void dispose() {
    _primary.dispose();
    _notes.dispose();
    _check.dispose();
    super.dispose();
  }

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
    if (ref.watch(isLargeScreenProvider)) return _television(c, status);
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
                Text(update.publicNotes),
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
                onPressed: c.busy || !_loaded ? null : () => c.check(),
                child: const Text('Check for updates'),
              ),
              const SizedBox(height: 24),
              Text(
                ref.watch(isDesktopProvider)
                    ? 'Updates download only when you choose. Follow the Windows installer and close the player when asked.'
                    : 'Updates download only when you choose. Android asks you to approve installation.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _television(UpdateController c, String status) {
    final update = c.update;
    final install =
        update != null &&
        [
          UpdateStage.ready,
          UpdateStage.permission,
          UpdateStage.installer,
        ].contains(c.stage);
    final label = c.stage == UpdateStage.downloading
        ? 'Cancel download'
        : c.busy
        ? 'Checking…'
        : install
        ? 'Install update'
        : update != null
        ? 'Download update'
        : 'Check for updates';
    void activate() {
      if (c.stage == UpdateStage.downloading) {
        c.cancel();
        return;
      }
      if (c.busy || !_loaded) return;
      if (install) {
        c.install();
      } else if (update != null) {
        c.download();
      } else {
        c.check();
      }
    }

    return TvUtilityScaffold(
      title: 'App updates',
      subtitle: status,
      onEnter: _primary.requestFocus,
      hint:
          'Left  Release notes    Right  Update action    Up / Down  Browse / read    OK  Select    Back  Return',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Installed: ${c.device?.version ?? appVersion}${c.device == null ? '' : ' (${c.device!.code})'}',
                  style: const TextStyle(fontSize: 18),
                ),
                if (update != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Version ${update.version} · ${(update.bytes / 1048576).toStringAsFixed(1)} MB',
                      style: const TextStyle(
                        fontSize: 16,
                        color: TvGlass.accent,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Expanded(
                  child: TvScrollPane(
                    label: 'Update details and release notes',
                    focusNode: _notes,
                    onRight: _primary.requestFocus,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (c.error != null) ...[
                          Text(
                            c.error!,
                            style: const TextStyle(
                              color: AppColors.danger,
                              fontSize: 15,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (c.lastCheck != null) ...[
                          Text(
                            'Last attempt: ${c.lastCheck!.toLocal().toString().split('.').first}',
                            style: const TextStyle(
                              color: TvGlass.muted,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        Text(
                          update?.publicNotes ??
                              'Check for the latest improvements and fixes for Ultravpn-player.',
                          style: const TextStyle(fontSize: 15, height: 1.5),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          ref.watch(isDesktopProvider)
                              ? 'Updates download only when you choose. Follow the Windows installer and close the player when asked.'
                              : 'Updates download only when you choose. Android asks you to approve installation.',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.5,
                            color: TvGlass.muted,
                          ),
                        ),
                        if (install) ...[
                          const SizedBox(height: 16),
                          const Text(
                            'If you cancel the installer, return here and choose Install update again.',
                            style: TextStyle(fontSize: 13, height: 1.5),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          SizedBox(
            width: 250,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TvUtilityAction(
                  label: label,
                  focusNode: _primary,
                  autofocus: true,
                  onPressed: activate,
                  onLeft: _notes.requestFocus,
                  onDown: update != null && !c.busy
                      ? _check.requestFocus
                      : _notes.requestFocus,
                ),
                if (update != null && !c.busy) ...[
                  const SizedBox(height: 12),
                  TvUtilityAction(
                    label: 'Check for updates',
                    focusNode: _check,
                    onPressed: () => c.check(),
                    onLeft: _notes.requestFocus,
                    onUp: _primary.requestFocus,
                  ),
                ],
                const SizedBox(height: 20),
                if (c.stage == UpdateStage.downloading && update != null) ...[
                  LinearProgressIndicator(value: c.received / update.bytes),
                  const SizedBox(height: 10),
                  Text(
                    '${(100 * c.received / update.bytes).toStringAsFixed(0)}% downloaded',
                    style: const TextStyle(fontSize: 15),
                  ),
                ],
                const Spacer(),
                const Text(
                  'Left: release notes\nRight: update action\nBack: return',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: TvGlass.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
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
