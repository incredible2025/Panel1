import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:streamline_iptv/core/providers.dart';
import 'package:streamline_iptv/data/managed_activity.dart';
import 'package:streamline_iptv/data/managed_configuration.dart';
import 'package:streamline_iptv/features/management_support_screen.dart';
import 'package:streamline_iptv/widgets/managed_home_notice.dart';

Future<ManagedConfigurationManager> manager() async {
  final profile = ManagedProfile.parse(managedProfileJson);
  final result = ManagedConfigurationManager(
    profile: profile,
    readCache: () async => null,
    writeCache: (_) async {},
    clientFactory: () => MockClient(
      (_) async => http.Response(jsonEncode(profile.bootstrap), 200),
    ),
  );
  await result.initialize();
  final current = result.current;
  result.current = ManagedConfiguration(
    serviceId: current.serviceId,
    revision: current.revision,
    endpoints: current.endpoints,
    updateManifestUrl: current.updateManifestUrl,
    envelope: current.envelope,
    notice: ManagedNotice(
      'notice-1',
      'Maintenance notice',
      'We will return shortly.',
      DateTime.now().add(const Duration(hours: 1)),
    ),
    support: const ManagedSupport(
      email: 'help@example.test',
      website: 'https://help.example.test',
      message: 'Contact our team.',
    ),
  );
  result.activity = ManagedActivity(
    configUrl: Uri.parse('https://manager.example.test/config'),
    secret: 'a' * 64,
    revision: () => result.current.revision,
    clientFactory: () => MockClient(
      (request) async => request.url.path == '/pair'
          ? http.Response('{"code":"123456"}', 200)
          : http.Response('', 204),
    ),
  );
  result.activity!.foreground(true);
  return result;
}

void main() {
  testWidgets('home notice can be read and dismissed without removing home', (
    tester,
  ) async {
    final management = await manager();
    addTearDown(management.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [managedConfigurationProvider.overrideWithValue(management)],
        child: const MaterialApp(
          home: ManagedHomeNotice(child: Scaffold(body: Text('Home content'))),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Maintenance notice'), findsOneWidget);
    await tester.tap(find.text('Read notice'));
    await tester.pumpAndSettle();
    expect(find.text('We will return shortly.'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Dismiss notice'));
    await tester.pumpAndSettle();
    expect(find.text('Maintenance notice'), findsNothing);
    expect(find.text('Home content'), findsOneWidget);
    expect(management.dismissedNoticeId, 'notice-1');
    management.activity!.foreground(false);
    await tester.pumpWidget(const SizedBox());
  });

  for (final size in [
    const Size(960, 540),
    const Size(1280, 720),
    const Size(1920, 1080),
  ]) {
    testWidgets(
      'TV remote opens pairing at ${size.width.toInt()} width without overflow',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final management = await manager();
        addTearDown(management.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              managedConfigurationProvider.overrideWithValue(management),
              isTvProvider.overrideWithValue(true),
            ],
            child: MaterialApp(
              shortcuts: {
                ...WidgetsApp.defaultShortcuts,
                const SingleActivator(LogicalKeyboardKey.select):
                    const ActivateIntent(),
              },
              home: const ManagementSupportScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'Setting: Installed version',
        );
        for (var i = 0; i < 3; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pumpAndSettle();
        }
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'Setting: Link test device',
        );
        await tester.runAsync(() async {
          await tester.sendKeyEvent(LogicalKeyboardKey.select);
          await Future<void>.delayed(const Duration(milliseconds: 30));
        });
        await tester.pumpAndSettle();
        expect(
          find.text('123456'),
          findsWidgets,
          reason: tester
              .widgetList<Text>(find.byType(Text))
              .map((e) => e.data)
              .join(' | '),
        );
        expect(tester.takeException(), isNull);
        management.activity!.foreground(false);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
