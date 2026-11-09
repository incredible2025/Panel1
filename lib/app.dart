import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers.dart';
import 'core/update_controller.dart';
import 'core/app_brand.dart';
import 'core/desktop_controls.dart';
import 'core/design_system.dart';
import 'core/settings_controller.dart';
import 'data/app_settings.dart';
import 'data/managed_configuration.dart';
import 'features/dashboard_screen.dart';
import 'features/login_screen.dart';
import 'features/tv_dashboard_screen.dart';
import 'features/startup_update_gate.dart';
import 'widgets/managed_home_notice.dart';

class StreamlineApp extends ConsumerStatefulWidget {
  const StreamlineApp({super.key});

  @override
  ConsumerState<StreamlineApp> createState() => _StreamlineAppState();
}

class _StreamlineAppState extends ConsumerState<StreamlineApp>
    with WidgetsBindingObserver {
  bool _startupFinished = false;
  final _navigator = GlobalKey<NavigatorState>();
  String? _managedFeed;
  ManagedConfigurationManager? _management;
  static const _platform = MethodChannel('streamline/platform');
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final management = ref.read(managedConfigurationProvider);
    _management = management;
    _managedFeed = management?.current.updateManifestUrl;
    management?.addListener(_configurationChanged);
    management?.foreground(true, refreshNow: false);
    _platform.setMethodCallHandler((call) async {
      if (call.method == 'networkChanged' && mounted) {
        ref.read(apiProvider).resetConnectionPreferences();
      }
    });
  }

  void _configurationChanged() {
    if (!mounted) return;
    final management = ref.read(managedConfigurationProvider)!;
    ref.read(apiProvider).resetConnectionPreferences();
    if (_managedFeed != management.current.updateManifestUrl) {
      _managedFeed = management.current.updateManifestUrl;
      final controller = ref.read(updateControllerProvider);
      controller.sourceChanged();
      if (_startupFinished) unawaited(controller.autoCheck());
    }
    final session = ref.read(sessionProvider);
    if (session != null &&
        session.credentials.managedServiceId != management.current.serviceId) {
      ref.read(sessionProvider.notifier).state = null;
      unawaited(ref.read(storeProvider).clearSession().catchError((_) {}));
      _navigator.currentState?.popUntil((route) => route.isFirst);
    }
  }

  @override
  void dispose() {
    _platform.setMethodCallHandler(null);
    WidgetsBinding.instance.removeObserver(this);
    final management = _management;
    management?.removeListener(_configurationChanged);
    management?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ref
        .read(managedConfigurationProvider)
        ?.foreground(state == AppLifecycleState.resumed);
    if (state == AppLifecycleState.resumed) {
      ref.read(apiProvider).resetConnectionPreferences();
    }
    if (state == AppLifecycleState.resumed && _startupFinished) {
      ref.read(updateControllerProvider).autoCheck();
    }
    if (state != AppLifecycleState.resumed) {
      ref.read(parentalSessionProvider.notifier).lock();
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final tv = ref.watch(isLargeScreenProvider);
    final settings =
        ref.watch(settingsProvider).asData?.value ?? const AppSettings();
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: AppPalette.forAppearance(
          AppAppearance.parse(settings.theme),
        ).canvas,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: MaterialApp(
        navigatorKey: _navigator,
        title: appBrandName,
        debugShowCheckedModeBanner: false,
        theme: StreamlineTheme.forAppearance(
          AppAppearance.parse(settings.theme),
        ),
        themeAnimationDuration: settings.reducedMotion
            ? Duration.zero
            : const Duration(milliseconds: 200),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations:
                MediaQuery.disableAnimationsOf(context) ||
                settings.reducedMotion,
          ),
          child: ref.watch(isDesktopProvider)
              ? DesktopControls(child: AppBackdrop(child: child!))
              : AppBackdrop(child: child!),
        ),
        shortcuts: <ShortcutActivator, Intent>{
          ...WidgetsApp.defaultShortcuts,
          const SingleActivator(LogicalKeyboardKey.select):
              const ActivateIntent(),
          const SingleActivator(LogicalKeyboardKey.gameButtonA):
              const ActivateIntent(),
        },
        home: StartupUpdateGate(
          onFinished: () => _startupFinished = true,
          builder: (_) => ManagedHomeNotice(
            child: session == null
                ? const LoginScreen()
                : tv
                ? TvDashboardScreen(key: ValueKey(session.accountId))
                : DashboardScreen(key: ValueKey(session.accountId)),
          ),
        ),
      ),
    );
  }
}
