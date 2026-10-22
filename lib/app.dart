import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers.dart';
import 'core/design_system.dart';
import 'features/dashboard_screen.dart';
import 'features/login_screen.dart';

class StreamlineApp extends ConsumerWidget {
  const StreamlineApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: AppColors.canvas,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: MaterialApp(
        title: 'Streamline',
        debugShowCheckedModeBanner: false,
        theme: StreamlineTheme.dark,
        shortcuts: <ShortcutActivator, Intent>{
          ...WidgetsApp.defaultShortcuts,
          const SingleActivator(LogicalKeyboardKey.select):
              const ActivateIntent(),
          const SingleActivator(LogicalKeyboardKey.gameButtonA):
              const ActivateIntent(),
        },
        home: session == null ? const LoginScreen() : const DashboardScreen(),
      ),
    );
  }
}
