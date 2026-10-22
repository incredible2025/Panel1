import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streamline_iptv/core/update_controller.dart';
import 'package:streamline_iptv/features/app_updates_screen.dart';

import 'app_update_test.dart' show FakePlatform, FakeTransport;

void main() {
  testWidgets('unconfigured screen has remote setup, no preset and no error', (tester) async {
    final transport = FakeTransport();
    final c = UpdateController(FakePlatform()..url = '', transport);
    await tester.pumpWidget(ProviderScope(
      overrides: [updateControllerProvider.overrideWith((ref) => c)],
      child: const MaterialApp(home: AppUpdatesScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Set up remote updates'), findsOneWidget);
    expect(find.text('Use official updates'), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '');
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Check for updates')).onPressed, null);
    await tester.enterText(find.byType(TextField), 'https://own.example/updates/update.json');
    await tester.ensureVisible(find.text('Save address'));
    await tester.tap(find.text('Save address'));
    await tester.pumpAndSettle();
    expect(c.configured, true);
    expect(c.url, 'https://own.example/updates/update.json');
    expect(transport.checks, 0);
    expect(tester.takeException(), isNull);
  });

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
