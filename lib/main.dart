import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/platform_mode.dart';
import 'core/providers.dart';
import 'core/provider_config.dart';
import 'data/local_store.dart';
import 'core/design_system.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Inter typeface',
    ], await rootBundle.loadString('assets/fonts/Inter-OFL.txt'));
    yield LicenseEntryWithLineBreaks([
      'ULTRAVPN PLAYER native compatibility player',
    ], await rootBundle.loadString('assets/licenses/native-player.txt'));
  });
  try {
    final store = await LocalStore.open();
    final saved = await store.readSession();
    final session = saved != null && usesConfiguredPortal(saved) ? saved : null;
    if (saved != null && session == null) await store.clearSession();
    final television = await detectTelevision();
    runApp(
      ProviderScope(
        overrides: [
          storeProvider.overrideWithValue(store),
          sessionProvider.overrideWith((ref) => session),
          isTvProvider.overrideWithValue(television),
        ],
        child: const StreamlineApp(),
      ),
    );
  } catch (_) {
    runApp(const _StartupError());
  }
}

class _StartupError extends StatelessWidget {
  const _StartupError();
  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: StreamlineTheme.dark,
    shortcuts: {
      ...WidgetsApp.defaultShortcuts,
      const SingleActivator(LogicalKeyboardKey.select): const ActivateIntent(),
      const SingleActivator(LogicalKeyboardKey.gameButtonA):
          const ActivateIntent(),
    },
    builder: (_, child) => AppBackdrop(child: child!),
    home: Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const StreamlineMark(size: 64, wordmark: true),
              const SizedBox(height: 24),
              const Text('ULTRAVPN PLAYER could not open its local storage.'),
              const SizedBox(height: 12),
              const Text('Check available device storage, then try again.'),
              const SizedBox(height: 24),
              FilledButton(
                autofocus: true,
                onPressed: main,
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
