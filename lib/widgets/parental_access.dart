import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/providers.dart';
import '../core/settings_controller.dart';
import '../data/models.dart';
import 'status_view.dart';
import 'tv_controls.dart';
import 'tv_pin_entry.dart';

Widget? protectedLibraryView(
  BuildContext context,
  WidgetRef ref,
  MediaItem item,
) {
  final preferences = ref.watch(settingsProvider);
  final unlocked = ref.watch(parentalSessionProvider);
  if (preferences.isLoading) {
    return const Scaffold(
      body: StatusView(title: 'Loading preferences', loading: true),
    );
  }
  if (preferences.hasError) {
    return Scaffold(
      appBar: AppBar(),
      body: StatusView(
        title: 'Preferences unavailable',
        onRetry: () => ref.read(settingsProvider.notifier).reload(),
      ),
    );
  }
  final settings = preferences.asData!.value;
  if (settings.hidden(item)) {
    return Scaffold(
      appBar: AppBar(),
      body: const StatusView(
        title: 'This category is hidden',
        message: 'Change category visibility in Settings to view this title.',
      ),
    );
  }
  if (settings.locked(item) && !unlocked) {
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 40),
            const SizedBox(height: 20),
            const Text('This category is protected'),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => requestParentalAccess(
                context,
                ref,
                reason: 'Unlock this category',
              ),
              child: const Text('Enter PIN'),
            ),
          ],
        ),
      ),
    );
  }
  return null;
}

Future<bool> requestParentalAccess(
  BuildContext context,
  WidgetRef ref, {
  String reason = 'Unlock protected settings',
}) async {
  if (ref.read(parentalSessionProvider)) return true;
  final account = ref.read(sessionProvider)?.accountId;
  if (account == null) return false;
  try {
    if (!await ref.read(storeProvider).hasPin(account)) return true;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Parental protection is unavailable. Try again.'),
        ),
      );
    }
    return false;
  }
  if (!context.mounted) return false;
  final success = await showDialog<bool>(
    context: context,
    builder: (_) => _PinDialog(account: account, reason: reason),
  );
  if (success == true &&
      context.mounted &&
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
    ref.read(parentalSessionProvider.notifier).unlock();
  }
  return success == true &&
      context.mounted &&
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
}

Future<bool> allowMedia(
  BuildContext context,
  WidgetRef ref,
  MediaItem item,
) async {
  await ref.read(settingsProvider.notifier).ready;
  final state = ref.read(settingsProvider);
  if (state.hasError) return false;
  final settings = state.asData!.value;
  if (settings.hidden(item)) return false;
  return !settings.locked(item) ||
      (context.mounted &&
          await requestParentalAccess(
            context,
            ref,
            reason: 'Unlock this category',
          ));
}

class _PinDialog extends ConsumerStatefulWidget {
  const _PinDialog({required this.account, required this.reason});
  final String account, reason;
  @override
  ConsumerState<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends ConsumerState<_PinDialog> {
  final _pin = TextEditingController();
  String? _error;
  bool _busy = false;
  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    if (_busy || _pin.text.length < 4) return;
    setState(() => _busy = true);
    try {
      final wait = await ref
          .read(storeProvider)
          .verifyPin(widget.account, _pin.text);
      if (!mounted) return;
      if (wait == 0) {
        Navigator.pop(context, true);
        return;
      }
      setState(() {
        _error = wait > 0
            ? 'Too many attempts. Try again in $wait seconds.'
            : 'Incorrect PIN.';
        _pin.clear();
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not verify PIN. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ref.watch(isLargeScreenProvider)
      ? AlertDialog(
          title: Text(widget.reason),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Enter your four to eight digit parental PIN. Access relocks after five minutes or when the app enters the background.',
                ),
                const SizedBox(height: 18),
                TvControl(
                  autofocus: true,
                  onPressed: () async {
                    if (_busy) return;
                    final value = await showTvPinEntry(
                      context,
                      'PIN',
                      initial: _pin.text,
                    );
                    if (value == null || !mounted) return;
                    _pin.text = value;
                    await _unlock();
                  },
                  child: Text(_busy ? 'Checking…' : 'Press OK to enter PIN'),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Text(_error!),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
          ],
        )
      : AlertDialog(
          title: Text(widget.reason),
          content: SizedBox(
            width: 350,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Enter your parental PIN. Access stays unlocked for five minutes, or until the app goes into the background.',
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _pin,
                  autofocus: true,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(8),
                  ],
                  onSubmitted: (_) => _unlock(),
                  decoration: InputDecoration(
                    labelText: 'PIN',
                    errorText: _error,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: _busy ? null : _unlock,
              child: Text(_busy ? 'Checking…' : 'Unlock'),
            ),
          ],
        );
}
