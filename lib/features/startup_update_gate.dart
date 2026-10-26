import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/design_system.dart';
import '../core/providers.dart';
import '../core/update_controller.dart';
import '../widgets/tv_controls.dart';
import '../widgets/tv_utility_scaffold.dart';
import 'app_updates_screen.dart';

// UI harnesses can replace startup I/O; production always uses the true default.
final startupUpdatesEnabledProvider = Provider<bool>((ref) => true);

class StartupUpdateGate extends ConsumerStatefulWidget {
  const StartupUpdateGate({
    super.key,
    required this.builder,
    required this.onFinished,
  });
  final WidgetBuilder builder;
  final VoidCallback onFinished;
  @override
  ConsumerState<StartupUpdateGate> createState() => _StartupUpdateGateState();
}

class _StartupUpdateGateState extends ConsumerState<StartupUpdateGate> {
  bool _finished = false, _checking = true;
  final _primary = FocusNode(debugLabel: 'Startup update action');
  final _continue = FocusNode(debugLabel: 'Continue to app');
  @override
  void initState() {
    super.initState();
    scheduleMicrotask(() {
      if (!mounted) return;
      if (!ref.read(startupUpdatesEnabledProvider)) {
        _finish();
        return;
      }
      _check();
    });
  }

  @override
  void dispose() {
    _primary.dispose();
    _continue.dispose();
    super.dispose();
  }

  void _finish() {
    if (!mounted || _finished) return;
    widget.onFinished();
    setState(() => _finished = true);
  }

  Future<void> _check() async {
    if (!mounted) return;
    setState(() => _checking = true);
    // Deliberately bypass autoCheck's twelve-hour resume throttle on cold launch.
    final controller = ref.read(updateControllerProvider);
    await controller.check(quiet: true, timeout: const Duration(seconds: 8));
    if (!mounted) return;
    if (controller.stage == UpdateStage.current) {
      _finish();
      return;
    }
    setState(() => _checking = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _primary.requestFocus();
    });
  }

  KeyEventResult _move(KeyEvent event, FocusNode target) {
    if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
        [
          LogicalKeyboardKey.arrowUp,
          LogicalKeyboardKey.arrowDown,
          LogicalKeyboardKey.arrowLeft,
          LogicalKeyboardKey.arrowRight,
        ].contains(event.logicalKey)) {
      target.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    if (_finished) return widget.builder(context);
    final controller = ref.watch(updateControllerProvider);
    final available =
        controller.update != null && controller.stage != UpdateStage.failed;
    final tv = ref.watch(isLargeScreenProvider);
    final content = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const StreamlineMark(size: 60, wordmark: true),
          const SizedBox(height: 26),
          Text(
            _checking
                ? 'Checking for updates'
                : available
                ? 'An update is ready'
                : 'Couldn’t check for updates',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 28,
              height: 1.15,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            _checking
                ? 'Getting everything ready before you start watching.'
                : available
                ? 'Version ${controller.update!.version} is available. Install the latest improvements before you start watching.'
                : controller.error ??
                      'The update server could not be reached. You can retry or continue with the installed app.',
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              height: 1.5,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: 24),
          if (_checking)
            MediaQuery.disableAnimationsOf(context)
                ? const Icon(
                    Icons.system_update,
                    color: AppColors.accent,
                    size: 28,
                  )
                : const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
          else ...[
            SizedBox(
              width: 320,
              child: TvControl(
                focusNode: _primary,
                autofocus: true,
                reveal: false,
                style: TvControlStyle.primary,
                onKeyEvent: (_, event) => _move(event, _continue),
                onPressed: available
                    ? () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const AppUpdatesScreen(),
                        ),
                      )
                    : _check,
                child: Center(
                  child: Text(
                    available ? 'Update now' : 'Try again',
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: 320,
              child: TvControl(
                focusNode: _continue,
                reveal: false,
                onKeyEvent: (_, event) => _move(event, _primary),
                onPressed: _finish,
                child: const Center(
                  child: Text(
                    'Continue to app',
                    style: TextStyle(fontSize: 15),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
    return tv
        ? TvUtilityScaffold(
            title: 'Ultravpn-player',
            showBack: false,
            hint: _checking
                ? 'Checking the installed version…'
                : 'D-pad  Move    OK  Choose',
            child: Center(child: content),
          )
        : Scaffold(
            body: SafeArea(
              child: LayoutBuilder(
                builder: (context, box) => SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: (box.maxHeight - 48).clamp(0, double.infinity),
                    ),
                    child: Center(child: content),
                  ),
                ),
              ),
            ),
          );
  }
}
