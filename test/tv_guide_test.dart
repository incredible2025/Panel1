import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streamline_iptv/core/design_system.dart';
import 'package:streamline_iptv/core/providers.dart';
import 'package:streamline_iptv/data/local_store.dart';
import 'package:streamline_iptv/data/app_settings.dart';
import 'package:streamline_iptv/data/models.dart';
import 'package:streamline_iptv/features/tv_guide_screen.dart';
import 'package:streamline_iptv/widgets/tv_focus_card.dart';

class _GuidePreferencesStore implements LocalStore {
  @override
  Future<AppSettings> readSettings(String accountId) async =>
      const AppSettings();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() async {
    if (!const bool.fromEnvironment('CAPTURE_UI')) return;
    await (FontLoader('Streamline Sans')
          ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Roboto-Medium.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf')))
        .load();
    await (FontLoader('Streamline Display')
          ..addFont(rootBundle.load('assets/fonts/RobotoCondensed-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/RobotoCondensed-Bold.ttf')))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  test(
    'guide clips overnight programmes and excludes invalid or outside intervals',
    () {
      final start = DateTime.utc(2026, 10, 22);
      final end = start.add(const Duration(days: 1));
      EpgEntry entry(DateTime a, DateTime b) =>
          EpgEntry(title: 'Programme', description: '', start: a, end: b);
      expect(
        guideInterval(
          entry(
            start.subtract(const Duration(hours: 1)),
            start.add(const Duration(minutes: 45)),
          ),
          start,
          end,
        ),
        (start: 0.0, duration: 45.0),
      );
      expect(
        guideInterval(
          entry(
            end.subtract(const Duration(minutes: 30)),
            end.add(const Duration(hours: 1)),
          ),
          start,
          end,
        ),
        (start: 1410.0, duration: 30.0),
      );
      expect(
        guideInterval(
          entry(end, end.add(const Duration(hours: 1))),
          start,
          end,
        ),
        isNull,
      );
      expect(
        guideInterval(
          entry(start.add(const Duration(hours: 1)), start),
          start,
          end,
        ),
        isNull,
      );
    },
  );

  for (final tv in [false, true]) {
    testWidgets(
      '${tv ? 'TV' : 'Phone'} guide displays provider programmes, navigates by remote and filters channels',
      (tester) async {
        tester.view.physicalSize = tv
            ? const Size(1280, 720)
            : const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
        });
        final now = DateTime.now();
        final key = GlobalKey();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              storeProvider.overrideWithValue(_GuidePreferencesStore()),
              isTvProvider.overrideWithValue(tv),
              itemsProvider.overrideWith(
                (ref, kind) async => [
                  const MediaItem(
                    id: '1',
                    name: 'World News',
                    kind: MediaKind.live,
                  ),
                  const MediaItem(
                    id: '2',
                    name: 'Cinema',
                    kind: MediaKind.live,
                  ),
                ],
              ),
              guideScheduleProvider.overrideWith(
                (ref, id) async => GuideSchedule([
                  EpgEntry(
                    title: id == '1' ? 'World Report' : 'Evening Film',
                    description: 'Provider programme description.',
                    start: now.subtract(const Duration(minutes: 30)),
                    end: now.add(const Duration(hours: 1)),
                  ),
                ]),
              ),
            ],
            child: MaterialApp(
              theme: StreamlineTheme.dark,
              home: RepaintBoundary(key: key, child: const TvGuideScreen()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('World Report'), findsOneWidget);
        final title = find.text('World Report');
        final card = find.ancestor(
          of: title,
          matching: find.byType(TvFocusCard),
        );
        final detector = find.descendant(
          of: card,
          matching: find.byType(FocusableActionDetector),
        );
        tester
            .widget<FocusableActionDetector>(detector)
            .focusNode!
            .requestFocus();
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
        expect(find.text('ON NOW'), findsOneWidget);
        expect(find.text('Provider programme description.'), findsOneWidget);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        if (const bool.fromEnvironment('CAPTURE_UI')) {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            await Directory('build/qa').create(recursive: true);
            await File(
              'build/qa/${tv ? 'tv' : 'phone'}-guide.png',
            ).writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.enterText(find.byType(TextField), 'Cinema');
        await tester.pumpAndSettle();
        expect(find.text('World News'), findsNothing);
        expect(find.text('Evening Film'), findsOneWidget);
        await tester.ensureVisible(find.text('Tomorrow'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Tomorrow'));
        await tester.pumpAndSettle();
        expect(find.textContaining('No programme data'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
