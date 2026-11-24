import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streamline_iptv/data/connection_diagnostics.dart';
import 'package:streamline_iptv/features/tv_diagnosis_view.dart';

void main() {
  for (final size in [
    const Size(960, 540),
    const Size(1280, 720),
    const Size(1920, 1080),
  ]) {
    testWidgets(
      'TV diagnosis support action is visible and reachable at $size',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var sent = false;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: TvDiagnosisView(
              report: DiagnosticReport(DateTime.now(), const [
                DiagnosticCheck(
                  'dns',
                  DiagnosticFinding(
                    'DNS_TIMEOUT',
                    'DNS lookup timed out',
                    'The device resolver did not finish.',
                  ),
                  8000,
                ),
              ]),
              busy: false,
              canRun: true,
              onRun: () {},
              onStop: () {},
              onCopy: () {},
              progressLabel: '',
              includeStream: false,
              onStreamChanged: (_) {},
              showSend: true,
              onSend: () {
                sent = true;
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Send to support').hitTestable(), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'Send diagnosis',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
        expect(sent, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
