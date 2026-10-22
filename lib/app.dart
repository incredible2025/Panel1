import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers.dart';
import 'core/design_system.dart';
import 'core/settings_controller.dart';
import 'data/app_settings.dart';
import 'features/dashboard_screen.dart';
import 'features/login_screen.dart';

class StreamlineApp extends ConsumerStatefulWidget {
  const StreamlineApp({super.key});

  @override
  ConsumerState<StreamlineApp> createState() => _StreamlineAppState();
}

class _StreamlineAppState extends ConsumerState<StreamlineApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      ref.read(parentalSessionProvider.notifier).lock();
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final settings =
        ref.watch(settingsProvider).asData?.value ?? const AppSettings();
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: AppColors.canvas,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: MaterialApp(
        title: 'Streamline',
        debugShowCheckedModeBanner: false,
        theme: settings.theme == 'cinema'
            ? StreamlineTheme.cinema
            : StreamlineTheme.dark,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations:
                MediaQuery.disableAnimationsOf(context) ||
                settings.reducedMotion,
          ),
          child: child!,
        ),
        shortcuts: <ShortcutActivator, Intent>{
          ...WidgetsApp.defaultShortcuts,
          const SingleActivator(LogicalKeyboardKey.select):
              const ActivateIntent(),
          const SingleActivator(LogicalKeyboardKey.gameButtonA):
              const ActivateIntent(),
        },
        home: session == null
            ? const LoginScreen()
            : DashboardScreen(key: ValueKey(session.accountId)),
      ),
    );
  }
}
