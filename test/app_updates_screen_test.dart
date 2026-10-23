import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streamline_iptv/core/update_controller.dart';
import 'package:streamline_iptv/data/app_update.dart';
import 'package:streamline_iptv/features/app_updates_screen.dart';
import 'package:streamline_iptv/core/providers.dart';
import 'package:streamline_iptv/core/design_system.dart';
import 'package:streamline_iptv/widgets/tv_page_navigation.dart';

import 'app_update_test.dart' show FakePlatform, FakeTransport, manifest;

void main() {
  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  Future<UpdateController> mountTv(
    WidgetTester tester,
    FakePlatform platform,
    FakeTransport transport,
    Size size,
    double scale,
  ) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final c = UpdateController(platform, transport);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          updateControllerProvider.overrideWith((ref) => c),
          isTvProvider.overrideWithValue(true),
        ],
        child: MaterialApp(
          theme: StreamlineTheme.dark,
          home: const AppUpdatesScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return c;
  }

  for (final size in [const Size(960, 540), const Size(1280, 720)]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets(
        'TV audit updates remain accessible with long notes at $size scale $scale',
        (tester) async {
          final platform = FakePlatform();
          final transport = FakeTransport()
            ..next = AppUpdate.parse(
              jsonEncode({
                ...manifest(),
                'releaseNotes': List.filled(
                  100,
                  'A long release description with improvements and fixes.',
                ).join('\n\n'),
              }),
            );
          await mountTv(tester, platform, transport, size, scale);
          expect(
            FocusManager.instance.primaryFocus?.debugLabel,
            'Update action',
          );
          await press(tester, LogicalKeyboardKey.select);
          expect(find.text('Download update').hitTestable(), findsOneWidget);
          expect(
            FocusManager.instance.primaryFocus?.debugLabel,
            'Update action',
          );
          await press(tester, LogicalKeyboardKey.arrowLeft);
          expect(
            FocusManager.instance.primaryFocus?.debugLabel,
            'Update details',
          );
          await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
          await tester.pumpAndSettle();
          for (var i = 0; i < 3; i++) {
            await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
            await tester.pumpAndSettle();
          }
          await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
          await tester.pumpAndSettle();
          final scroll = tester.state<ScrollableState>(
            find.descendant(
              of: find.byType(TvScrollPane),
              matching: find.byType(Scrollable),
            ),
          );
          expect(scroll.position.pixels, greaterThan(0));
          expect(find.text('Download update').hitTestable(), findsOneWidget);
          await press(tester, LogicalKeyboardKey.arrowRight);
          await press(tester, LogicalKeyboardKey.select);
          expect(find.text('Install update').hitTestable(), findsOneWidget);
          expect(
            FocusManager.instance.primaryFocus?.debugLabel,
            'Update action',
          );
          await press(tester, LogicalKeyboardKey.select);
          expect(platform.requested, isTrue);
          expect(find.text('Install update').hitTestable(), findsOneWidget);
          platform.allowed = true;
          await press(tester, LogicalKeyboardKey.select);
          expect(platform.installs, 1);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets(
    'TV audit download can be cancelled and retried without losing focus',
    (tester) async {
      final transport = FakeTransport()..pending = Completer<String>();
      final c = await mountTv(
        tester,
        FakePlatform(),
        transport,
        const Size(960, 540),
        1,
      );
      await press(tester, LogicalKeyboardKey.select);
      await press(tester, LogicalKeyboardKey.select);
      expect(c.stage, UpdateStage.downloading);
      expect(find.text('Cancel download').hitTestable(), findsOneWidget);
      await press(tester, LogicalKeyboardKey.select);
      expect(transport.cancelled, isTrue);
      expect(c.busy, isFalse);
      expect(find.text('Download update').hitTestable(), findsOneWidget);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Update action');
      transport.pending = null;
      await press(tester, LogicalKeyboardKey.select);
      expect(c.stage, UpdateStage.ready);
      expect(tester.takeException(), isNull);
    },
  );
  for (final previous in ['', 'https://old.example/update.json']) {
    testWidgets('updates show actions without source controls: $previous', (
      tester,
    ) async {
      final transport = FakeTransport();
      final c = UpdateController(FakePlatform()..url = previous, transport);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [updateControllerProvider.overrideWith((ref) => c)],
          child: const MaterialApp(home: AppUpdatesScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ready to check'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(SwitchListTile), findsNothing);
      expect(find.text('Save address'), findsNothing);
      expect(find.text('Use official updates'), findsNothing);
      expect(find.textContaining('ultra-vpn.store'), findsNothing);
      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();
      expect(transport.checkedUrl, appUpdateManifestUrl);
      expect(find.text('A new version is available'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final size in [const Size(390, 844), const Size(1280, 720)]) {
    testWidgets('check, download and installer permission flow at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final platform = FakePlatform();
      final c = UpdateController(platform, FakeTransport());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [updateControllerProvider.overrideWith((ref) => c)],
          child: MaterialApp(
            shortcuts: {
              ...WidgetsApp.defaultShortcuts,
              const SingleActivator(LogicalKeyboardKey.select):
                  const ActivateIntent(),
            },
            home: const AppUpdatesScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Installed: 0.6.0 (8)'), findsOneWidget);
      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();
      expect(find.text('A new version is available'), findsOneWidget);
      await tester.tap(find.text('Download update'));
      await tester.pumpAndSettle();
      expect(find.text('Verified and ready to install'), findsOneWidget);
      await tester.tap(find.text('Install update'));
      await tester.pumpAndSettle();
      expect(find.text('Allow installation, then return here'), findsOneWidget);
      platform.allowed = true;
      await tester.tap(find.text('Install update'));
      await tester.pumpAndSettle();
      expect(find.text('Installer opened'), findsOneWidget);
      expect(platform.installs, 1);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('TV select key can activate a focused update action', (
    tester,
  ) async {
    final transport = FakeTransport();
    final c = UpdateController(FakePlatform(), transport);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [updateControllerProvider.overrideWith((ref) => c)],
        child: MaterialApp(
          shortcuts: {
            ...WidgetsApp.defaultShortcuts,
            const SingleActivator(LogicalKeyboardKey.select):
                const ActivateIntent(),
          },
          home: const AppUpdatesScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final context = tester.element(find.text('Check for updates'));
    Focus.of(context).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(transport.checks, 1);
    expect(find.text('A new version is available'), findsOneWidget);
  });
}
