import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:streamline_iptv/core/design_system.dart';
import 'package:streamline_iptv/core/providers.dart';
import 'package:streamline_iptv/core/settings_controller.dart';
import 'package:streamline_iptv/data/app_settings.dart';
import 'package:streamline_iptv/data/local_store.dart';
import 'package:streamline_iptv/features/appearance_screen.dart';
import 'package:streamline_iptv/widgets/tv_glass_theme.dart';
import 'package:streamline_iptv/widgets/tv_controls.dart';

class _TestSettings extends SettingsController {
  _TestSettings({this.fail = false}) : super(null, null);
  final bool fail;
  @override
  Future<void> reload() async => state = const AsyncData(AppSettings());
  @override
  Future<bool> patch(Map<String, dynamic> values) async {
    if (fail) return false;
    state = AsyncData(current.patch(values));
    return true;
  }
}

class _AppearanceApp extends ConsumerWidget {
  const _AppearanceApp();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(settingsProvider).asData?.value.theme;
    return MaterialApp(
      theme: StreamlineTheme.forAppearance(AppAppearance.parse(theme)),
      builder: (_, child) => AppBackdrop(child: child!),
      home: const AppearanceScreen(),
    );
  }
}

Future<_TestSettings> _mount(
  WidgetTester tester, {
  bool tv = false,
  bool desktop = false,
  bool fail = false,
}) async {
  final settings = _TestSettings(fail: fail);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        isTvProvider.overrideWithValue(tv),
        isDesktopProvider.overrideWithValue(desktop),
        settingsProvider.overrideWith((ref) => settings),
      ],
      child: const _AppearanceApp(),
    ),
  );
  await tester.pumpAndSettle();
  return settings;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test(
    'all theme keys survive SQLite reload and stay account scoped',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final store = await LocalStore.open(
        databaseFactory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      addTearDown(store.close);
      for (final appearance in AppAppearance.values) {
        final controller = SettingsController(store, 'alice');
        await controller.ready;
        expect(
          await controller.patch({'theme': appearance.name, 'compact': true}),
          true,
        );
        controller.dispose();
        final reloaded = SettingsController(store, 'alice');
        await reloaded.ready;
        expect(reloaded.current.theme, appearance.name);
        expect(reloaded.current.compact, true);
        reloaded.dispose();
        expect((await store.readSettings('bob')).theme, 'midnight');
      }
      expect(AppSettings.fromJson({'theme': 'cinema'}).theme, 'cinema');
      expect(
        AppSettings.fromJson({'theme': 'unknown-future-theme'}).theme,
        'midnight',
      );
    },
  );

  double contrast(Color a, Color b) {
    final x = a.computeLuminance(), y = b.computeLuminance();
    return x > y ? (x + .05) / (y + .05) : (y + .05) / (x + .05);
  }

  for (final appearance in AppAppearance.values) {
    test(
      '${appearance.label} has readable labels and TV preserves the palette',
      () {
        final theme = StreamlineTheme.forAppearance(appearance);
        final palette = AppPalette.fromTheme(theme);
        final tv = TvGlass.theme(theme);
        expect(tv.colorScheme.primary, palette.accent);
        expect(tv.scaffoldBackgroundColor, palette.canvas);
        expect(AppPalette.fromTheme(tv), same(palette));
        for (final surface in [
          palette.canvas,
          palette.surface,
          palette.surfaceRaised,
          palette.gradientStart,
          palette.gradientMiddle,
          palette.glow,
        ]) {
          expect(contrast(AppColors.text, surface), greaterThanOrEqualTo(4.5));
          expect(contrast(AppColors.muted, surface), greaterThanOrEqualTo(4.5));
        }
        expect(
          contrast(palette.canvas, palette.accent),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrast(palette.accent, palette.surface),
          greaterThanOrEqualTo(4.5),
        );
      },
    );
  }

  for (final desktop in [false, true]) {
    testWidgets(
      '${desktop ? "Windows" : "TV"} remote previews every theme without saving, OK applies and focus remains usable',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final settings = await _mount(tester, tv: !desktop, desktop: desktop);
        expect(FocusManager.instance.primaryFocus?.debugLabel, 'Theme: Glass');
        for (final appearance in AppAppearance.values.skip(1)) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pumpAndSettle();
          expect(
            FocusManager.instance.primaryFocus?.debugLabel,
            'Theme: ${appearance.label}',
          );
          expect(
            tester.widget<ThemePreview>(find.byType(ThemePreview)).appearance,
            appearance,
          );
          expect(settings.current.theme, 'midnight');
          expect(tester.takeException(), isNull);
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
        expect(settings.current.theme, 'sunset');
        final controlContext = tester.element(find.byType(TvControl).last);
        expect(
          AppPalette.of(controlContext).accent,
          AppPalette.forAppearance(AppAppearance.sunset).accent,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(settings.current.theme, 'emerald');
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final size in [const Size(390, 844), const Size(800, 400)]) {
    testWidgets('touch theme selection and scrolling fit $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final settings = await _mount(tester);
      await tester.scrollUntilVisible(
        find.text('Cyberpunk'),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cyberpunk'));
      await tester.pumpAndSettle();
      expect(settings.current.theme, 'cyberpunk');
      await tester.scrollUntilVisible(
        find.text('Sunset'),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sunset'));
      await tester.pumpAndSettle();
      expect(settings.current.theme, 'sunset');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'failed save leaves applied theme unchanged and explains failure',
    (tester) async {
      final settings = await _mount(tester, fail: true);
      await tester.scrollUntilVisible(find.text('Cyberpunk'), 200);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cyberpunk'));
      await tester.pumpAndSettle();
      expect(settings.current.theme, 'midnight');
      expect(
        find.text('Theme could not be saved. Please try again.'),
        findsOneWidget,
      );
    },
  );
}
