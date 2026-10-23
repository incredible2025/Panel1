import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streamline_iptv/core/design_system.dart';
import 'package:streamline_iptv/data/connection_diagnostics.dart';
import 'package:streamline_iptv/data/dns_lookup.dart';
import 'package:streamline_iptv/features/connection_diagnosis_screen.dart';

import 'connection_diagnostics_test.dart'
    show FakeDiagnosticTransport, credentials, channel, now;

Future<void> mount(
  WidgetTester tester,
  FakeDiagnosticTransport transport, {
  bool selected = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        connectionDiagnosticsFactoryProvider.overrideWithValue(
          () => ConnectionDiagnostics(transport, now: () => now),
        ),
      ],
      child: MaterialApp(
        theme: StreamlineTheme.dark,
        home: RepaintBoundary(
          key: const ValueKey('diagnosis-preview'),
          child: ConnectionDiagnosisScreen(
            credentials: credentials,
            item: selected ? channel : null,
            canTestStream: selected,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('CAPTURE_UI')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('diagnosis-preview')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory('build/qa').create(recursive: true);
    await File('build/qa/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    if (!const bool.fromEnvironment('CAPTURE_UI')) return;
    await (FontLoader(
      'Streamline Sans',
    )..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
    await (FontLoader('Streamline Display')
          ..addFont(rootBundle.load('assets/fonts/RobotoCondensed-Bold.ttf')))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  for (final size in [
    const Size(390, 844),
    const Size(1280, 720),
    const Size(800, 400),
  ]) {
    testWidgets(
      'diagnosis is reachable by remote and fits ${size.width} x ${size.height}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final t = FakeDiagnosticTransport();
        await mount(tester, t);
        expect(t.calls, isEmpty);
        // Autofocus makes Select usable without a mouse or touch screen.
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
        expect(t.calls, contains('api'));
        await tester.scrollUntilVisible(
          find.text('All completed checks passed'),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('All completed checks passed'), findsOneWidget);
        expect(t.closed, true);
        expect(t.calls, isNot(contains('stream')));
        expect(tester.takeException(), isNull);
        await capture(tester, 'v5.1-diagnosis-${size.width.toInt()}');
      },
    );
  }

  testWidgets(
    'failed DNS expands explanations and actionable steps without raw errors',
    (tester) async {
      final t = FakeDiagnosticTransport()..failures['dns'] = 'dns_failed';
      await mount(tester, t);
      await tester.tap(find.text('Run diagnosis'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Provider DNS lookup'),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Possible causes'), findsOneWidget);
      expect(find.text('What to try'), findsOneWidget);
      expect(
        find.text('1. Ask support to verify the provider DNS configuration.'),
        findsOneWidget,
      );
      expect(find.textContaining('private-pass'), findsNothing);
      expect(tester.takeException(), isNull);
      await capture(tester, 'v5.1-diagnosis-dns-error');
    },
  );

  testWidgets(
    'DNS response evidence is visible separately from possible causes',
    (tester) async {
      final t = FakeDiagnosticTransport()
        ..dnsResult = const DnsLookupResult(
          [],
          androidResolver: true,
          cacheBypassed: true,
          observations: [
            DnsObservation(DnsFamily.ipv4, responseCode: 3, elapsedMs: 25),
            DnsObservation(DnsFamily.ipv6, responseCode: 3, elapsedMs: 27),
          ],
        );
      await mount(tester, t);
      await tester.tap(find.text('Run diagnosis'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Observed on this device'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Observed on this device'), findsOneWidget);
      expect(find.textContaining('A / IPv4: NXDOMAIN (3)'), findsOneWidget);
      expect(find.text('Possible causes'), findsOneWidget);
      expect(find.textContaining('private-provider'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Stop cancels the active run and does not send later credentials',
    (tester) async {
      final gate = Completer<void>();
      final t = FakeDiagnosticTransport()..dnsGate = gate;
      await mount(tester, t);
      await tester.tap(find.text('Run diagnosis'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Stop diagnosis'), findsOneWidget);
      await tester.tap(find.text('Stop diagnosis'));
      await tester.pumpAndSettle();
      expect(find.text('Diagnosis stopped'), findsOneWidget);
      expect(t.closed, true);
      gate.complete();
      await tester.pumpAndSettle();
      expect(t.uris, isEmpty);
      expect(find.text('Diagnosis stopped'), findsOneWidget);
    },
  );

  testWidgets(
    'optional stream is off by default and explicitly describes its connection use',
    (tester) async {
      final t = FakeDiagnosticTransport();
      await mount(tester, t, selected: true);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        false,
      );
      expect(
        find.textContaining('briefly count as a provider connection'),
        findsOneWidget,
      );
      await tester.tap(find.text('Run diagnosis'));
      await tester.pumpAndSettle();
      expect(t.calls, isNot(contains('stream')));
    },
  );

  testWidgets(
    'report copying contains explanations but no private credentials',
    (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final t = FakeDiagnosticTransport()..failures['tcp'] = 'timeout';
      await mount(tester, t);
      await tester.tap(find.text('Run diagnosis'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy private report'));
      await tester.pumpAndSettle();
      expect(copied, contains('CONNECTION_TIMEOUT'));
      expect(copied, contains('Try:'));
      expect(copied, isNot(contains(credentials.password)));
      expect(copied, isNot(contains('private-provider')));
    },
  );
}
