import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_brand.dart';
import '../core/playback_handle.dart';
import '../core/providers.dart';
import '../core/settings_controller.dart';
import 'tv_controls.dart';

final tvAppExitProvider = Provider((ref) => TvAppExit());
final tvPlatformExitProvider = Provider<Future<void> Function()>(
  (ref) =>
      () => SystemNavigator.pop(),
);

class TvAppExit {
  bool _open = false;

  Future<void> request(
    BuildContext context,
    WidgetRef ref, {
    Future<void> Function()? beforeExit,
  }) async {
    if (_open || !ref.read(isTvProvider)) return;
    _open = true;
    // Capture dependencies before an asynchronous shutdown can remove a view.
    final players = ref.read(playbackRegistryProvider);
    final settings = ref.read(settingsProvider.notifier);
    final management = ref.read(managedConfigurationProvider);
    final platformExit = ref.read(tvPlatformExitProvider);
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ExitDialog(
          close: () async {
            // Cancel pending preview opens before draining native players.
            await beforeExit?.call();
            management?.foreground(false);
            try {
              await players.closeAll();
              await settings.flush();
              await platformExit();
            } catch (_) {
              players.resume();
              management?.foreground(true, refreshNow: false);
              rethrow;
            }
          },
        ),
      );
    } finally {
      _open = false;
    }
  }
}

/// Used on the TV sign-in screen; nested routes retain normal Back behaviour.
class TvExitOnBack extends ConsumerWidget {
  const TvExitOnBack({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) => PopScope<Object?>(
    canPop: false,
    onPopInvokedWithResult: (popped, _) {
      if (!popped) ref.read(tvAppExitProvider).request(context, ref);
    },
    child: child,
  );
}

class _ExitDialog extends StatefulWidget {
  const _ExitDialog({required this.close});
  final Future<void> Function() close;

  @override
  State<_ExitDialog> createState() => _ExitDialogState();
}

class _ExitDialogState extends State<_ExitDialog> {
  bool _closing = false;
  bool _failed = false;

  Future<void> _exit() async {
    if (_closing) return;
    setState(() {
      _closing = true;
      _failed = false;
    });
    try {
      await widget.close();
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _closing = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    canPop: !_closing,
    child: AlertDialog(
      title: Text(_closing ? 'Closing $appBrandName…' : 'Exit $appBrandName?'),
      content: SizedBox(
        width: 420,
        child: _closing
            ? const Row(
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(),
                  ),
                  SizedBox(width: 18),
                  Expanded(
                    child: Text('Stopping playback and saving preferences…'),
                  ),
                ],
              )
            : Text(
                _failed
                    ? 'The app could not finish closing. Try again or stay in the app.'
                    : 'Playback will stop. Your sign-in, favourites and watch history will be kept.',
              ),
      ),
      actions: _closing
          ? []
          : [
              TvControl(
                label: 'Stay in app',
                autofocus: true,
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Stay in app'),
              ),
              TvControl(
                label: 'Exit app',
                onPressed: _exit,
                child: const Text('Exit app'),
              ),
            ],
    ),
  );
}
