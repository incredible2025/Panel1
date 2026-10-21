import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers.dart';
import 'features/dashboard_screen.dart';
import 'features/login_screen.dart';

class StreamlineApp extends ConsumerWidget {
  const StreamlineApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const accent = Color(0xFF54E1C1);
    final session = ref.watch(sessionProvider);
    return MaterialApp(
      title: 'Streamline',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF080E1B),
        colorScheme: ColorScheme.fromSeed(
          seedColor: accent,
          primary: accent,
          brightness: Brightness.dark,
          surface: const Color(0xFF111B2C),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF080E1B),
          elevation: 0,
          centerTitle: false,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF111B2C),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          contentPadding: const EdgeInsets.all(18),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(48, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        focusColor: accent.withValues(alpha: 0.3),
      ),
      shortcuts: <ShortcutActivator, Intent>{
        ...WidgetsApp.defaultShortcuts,
        const SingleActivator(LogicalKeyboardKey.select):
            const ActivateIntent(),
        const SingleActivator(LogicalKeyboardKey.gameButtonA):
            const ActivateIntent(),
      },
      home: session == null ? const LoginScreen() : const DashboardScreen(),
    );
  }
}
