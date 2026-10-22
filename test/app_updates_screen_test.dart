import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streamline_iptv/core/update_controller.dart';
import 'package:streamline_iptv/data/app_update.dart';
import 'package:streamline_iptv/features/app_updates_screen.dart';

import 'app_update_test.dart' show FakePlatform, FakeTransport;

void main() {
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
