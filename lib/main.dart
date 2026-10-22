import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/platform_mode.dart';
import 'core/providers.dart';
import 'data/local_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Streamline native compatibility player',
    ], await rootBundle.loadString('assets/licenses/native-player.txt'));
  });
  try {
    final store = await LocalStore.open();
    final session = await store.readSession();
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
    theme: ThemeData.dark(useMaterial3: true),
    home: Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.storage_rounded, size: 56),
              const SizedBox(height: 24),
              const Text('Streamline could not open its local storage.'),
              const SizedBox(height: 12),
              const Text('Check available device storage, then try again.'),
              const SizedBox(height: 24),
              FilledButton(onPressed: main, child: const Text('Try again')),
            ],
          ),
        ),
      ),
    ),
  );
}
