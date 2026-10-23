import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streamline_iptv/core/design_system.dart';
import 'package:streamline_iptv/core/providers.dart';
import 'package:streamline_iptv/core/update_controller.dart';
import 'package:streamline_iptv/data/app_update.dart';
import 'package:streamline_iptv/features/startup_update_gate.dart';
import 'app_update_test.dart' show FakePlatform, FakeTransport, candidate;

class PendingTransport extends FakeTransport {
  final result = Completer<AppUpdate>();
  @override
  Future<AppUpdate> check(String url) {
    checks++;
    return result.future;
  }
}

class PendingPlatform extends FakePlatform {
  final result = Completer<UpdateDevice>();
  @override
  Future<UpdateDevice> load() => result.future;
}

void main() {
  Future<void> mount(
    WidgetTester tester,
    UpdateController controller, {
    bool tv = true,
    Key? gateKey,
    VoidCallback? finished,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isTvProvider.overrideWithValue(tv),
          updateControllerProvider.overrideWith((ref) => controller),
        ],
        child: MaterialApp(
          theme: StreamlineTheme.dark,
          builder: (_, child) => AppBackdrop(child: child!),
          home: StartupUpdateGate(
            key: gateKey,
            onFinished: finished ?? () {},
            builder: (_) => const Scaffold(body: Text('Home visible')),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'cold launch waits for the check despite a recent check, then opens Home',
    (tester) async {
      final platform = FakePlatform()..checked = DateTime.now();
      final transport = PendingTransport();
      final controller = UpdateController(platform, transport);
      var completed = 0;
      await mount(tester, controller, finished: () => completed++);
      expect(transport.checks, 1);
      expect(find.text('Checking for updates'), findsOneWidget);
      expect(find.text('Home visible'), findsNothing);
      transport.result.complete(candidate(code: 8));
      await tester.pumpAndSettle();
      expect(find.text('Home visible'), findsOneWidget);
      expect(completed, 1);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [
    const Size(960, 540),
    const Size(1280, 720),
    const Size(1920, 1080),
    const Size(390, 844),
    const Size(844, 390),
  ]) {
    testWidgets(
      'launch update actions fit and Continue works by remote at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final transport = FakeTransport();
        await mount(
          tester,
          UpdateController(FakePlatform(), transport),
          tv: size.width >= 960,
        );
        await tester.pumpAndSettle();
        expect(find.text('An update is ready'), findsOneWidget);
        expect(find.text('Home visible'), findsNothing);
        expect(find.text('Update now').hitTestable(), findsOneWidget);
        if (size.width >= 960) {
          expect(find.text('Continue to app').hitTestable(), findsOneWidget);
        }
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'Startup update action',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'Continue to app',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
        expect(find.text('Home visible'), findsOneWidget);
        expect(transport.checks, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'failed launch check offers Retry, and every recreated launch checks again',
    (tester) async {
      final transport = FakeTransport()
        ..failure = const UpdateFailure('Update server unavailable.');
      final controller = UpdateController(FakePlatform(), transport);
      await mount(tester, controller);
      await tester.pumpAndSettle();
      expect(find.text('Couldn’t check for updates'), findsOneWidget);
      expect(find.text('Update server unavailable.'), findsOneWidget);
      expect(find.text('Home visible'), findsNothing);
      transport.failure = null;
      transport.next = candidate(code: 8);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.text('Home visible'), findsOneWidget);
      expect(transport.checks, 2);
      await mount(
        tester,
        controller,
        gateKey: const ValueKey('next cold launch'),
      );
      await tester.pumpAndSettle();
      expect(transport.checks, 3);
      expect(find.text('Home visible'), findsOneWidget);
    },
  );

  testWidgets('failed check permits continuing without claiming up to date', (
    tester,
  ) async {
    await mount(
      tester,
      UpdateController(
        FakePlatform(),
        FakeTransport()..failure = const UpdateFailure('No connection'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Home visible'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.text('Home visible'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test(
    'network deadline cancels the request and ignores a late response',
    () async {
      final transport = PendingTransport();
      final controller = UpdateController(FakePlatform(), transport);
      await controller.check(
        quiet: true,
        timeout: const Duration(milliseconds: 10),
      );
      expect(transport.cancelled, isTrue);
      expect(controller.stage, UpdateStage.failed);
      expect(controller.error, contains('too long to respond'));
      transport.result.complete(candidate());
      await Future<void>.delayed(Duration.zero);
      expect(controller.stage, UpdateStage.failed);
      expect(controller.update, isNull);
      controller.dispose();
    },
  );

  test(
    'native initialization deadline prevents a late network request',
    () async {
      final platform = PendingPlatform();
      final transport = FakeTransport();
      final controller = UpdateController(platform, transport);
      await controller.check(timeout: const Duration(milliseconds: 10));
      expect(controller.stage, UpdateStage.failed);
      platform.result.complete(await FakePlatform().load());
      await Future<void>.delayed(Duration.zero);
      expect(transport.checks, 0);
      expect(controller.stage, UpdateStage.failed);
      controller.dispose();
    },
  );
}
