import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streamline_iptv/core/design_system.dart';
import 'package:streamline_iptv/data/speed_test.dart';
import 'package:streamline_iptv/features/speed_test_screen.dart';

import 'speed_test_test.dart' show FakeSpeedTransport;

Future<void> mount(WidgetTester tester, FakeSpeedTransport transport) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        speedTestFactoryProvider.overrideWithValue(
          () => SpeedTestRunner(transport),
        ),
      ],
      child: MaterialApp(
        theme: StreamlineTheme.dark,
        home: const SpeedTestScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final size in [
    const Size(390, 844),
    const Size(1280, 720),
    const Size(800, 400),
  ]) {
    testWidgets(
      'speed test fits $size, starts only by remote Select and displays measured results',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final t = FakeSpeedTransport();
        await mount(tester, t);
        expect(t.calls, isEmpty);
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
        expect(t.closed, true);
        expect(find.text('Your results'), findsOneWidget);
        expect(find.text('16.8'), findsOneWidget);
        expect(find.text('4.2'), findsOneWidget);
        expect(find.text('Copy results'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'Stop cancels traffic and a stale completion cannot replace the stopped result',
    (tester) async {
      final t = FakeSpeedTransport()..gate = Completer<SpeedMeasurement>();
      await mount(tester, t);
      await tester.ensureVisible(find.text('Start speed test'));
      await tester.tap(find.text('Start speed test'));
      await tester.pump();
      expect(find.text('Stop test'), findsOneWidget);
      await tester.tap(find.text('Stop test'));
      await tester.pumpAndSettle();
      expect(t.closed, true);
      expect(t.calls.length, 1);
      expect(find.text('Test stopped'), findsOneWidget);
      expect(find.text('Your results'), findsNothing);
    },
  );
  testWidgets('backgrounding cancels an active test', (tester) async {
    final t = FakeSpeedTransport()..gate = Completer<SpeedMeasurement>();
    await mount(tester, t);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    expect(t.closed, true);
    expect(find.text('Test stopped'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
}
