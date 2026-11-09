import 'core/app_brand.dart';
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
import 'core/windows_smoke.dart';
import 'data/managed_configuration.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (args.contains('--smoke-test')) {
    await runWindowsSmoke(args);
    return;
  }
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Inter typeface',
    ], await rootBundle.loadString('assets/fonts/Inter-OFL.txt'));
    yield LicenseEntryWithLineBreaks([
      '$appBrandName native compatibility player',
    ], await rootBundle.loadString('assets/licenses/native-player.txt'));
    yield LicenseEntryWithLineBreaks([
      'LibVLC for Android',
    ], await rootBundle.loadString('assets/licenses/libvlc-LGPL-2.1.txt'));
  });
  try {
    final store = await LocalStore.open();
    ManagedConfigurationManager? management;
    if (defaultTargetPlatform == TargetPlatform.android &&
        managedProfileJson.isNotEmpty) {
      final profile = ManagedProfile.parse(managedProfileJson);
      management = ManagedConfigurationManager(
        profile: profile,
        readCache: () => store.managedConfigurationCache(profile.appId),
        writeCache: (envelope) =>
            store.saveManagedConfigurationCache(profile.appId, envelope),
      );
      await management.initialize();
    }
    final saved = await store.readSession();
    final session = management == null
        ? restoreConfiguredSession(saved)
        : await restoreManagedSession(
            store,
            saved,
            management.current,
            migrateLegacy:
                management.current.serviceId == managedLegacyServiceId,
          );
    if (saved != null && session == null) await store.clearSession();
    if (session != null && !identical(session, saved)) {
      await store.saveSession(session);
    }
    final television = await detectTelevision();
    runApp(
      ProviderScope(
        overrides: [
          storeProvider.overrideWithValue(store),
          managedConfigurationProvider.overrideWithValue(management),
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
              const Text('$appBrandName could not open its local storage.'),
              const SizedBox(height: 12),
              const Text('Check available device storage, then try again.'),
              const SizedBox(height: 24),
              FilledButton(
                autofocus: true,
                onPressed: () => main(const []),
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
