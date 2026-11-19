import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streamline_iptv/core/providers.dart';
import 'package:streamline_iptv/core/settings_controller.dart';
import 'package:streamline_iptv/data/app_settings.dart';
import 'package:streamline_iptv/data/local_store.dart';
import 'package:streamline_iptv/data/models.dart';
import 'package:streamline_iptv/features/catchup_screen.dart';
import 'package:streamline_iptv/features/player_screen.dart';

class _Store implements LocalStore {
  @override
  Future<AppSettings> readSettings(String account) async => const AppSettings(
    hiddenCategories: {'live:hidden'},
    lockedCategories: {'live:locked'},
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const channels = [
    MediaItem(
      id: '2',
      name: 'Sports archive',
      kind: MediaKind.live,
      archiveDays: 7,
    ),
    MediaItem(
      id: '1',
      name: 'News archive',
      kind: MediaKind.live,
      archiveDays: 2,
    ),
    MediaItem(id: '3', name: 'Live only', kind: MediaKind.live),
    MediaItem(
      id: '4',
      name: 'Hidden archive',
      kind: MediaKind.live,
      categoryId: 'hidden',
      archiveDays: 7,
    ),
    MediaItem(
      id: '5',
      name: 'Locked archive',
      kind: MediaKind.live,
      categoryId: 'locked',
      archiveDays: 7,
    ),
  ];

  Future<void> key(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  for (final tv in [false, true]) {
    testWidgets(
      'catch-up browses one guide at a time and opens a replay on ${tv ? 'TV' : 'mobile'}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = tv
            ? const Size(960, 540)
            : const Size(390, 844);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final requested = <String>[];
        final now = DateTime.now();
        EpgEntry programme(String title, int hours, {bool archived = true}) =>
            EpgEntry(
              title: title,
              description: '',
              start: now.add(Duration(hours: hours)),
              end: now.add(Duration(hours: hours + 1)),
              hasArchive: archived,
            );
        final replay = programme('Evening report', -3);
        final store = _Store();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              storeProvider.overrideWithValue(store),
              isTvProvider.overrideWithValue(tv),
              isDesktopProvider.overrideWithValue(false),
              settingsProvider.overrideWith(
                (_) => SettingsController(store, 'test'),
              ),
              itemsProvider.overrideWith((_, _) async => channels),
              guideScheduleProvider.overrideWith((_, id) async {
                requested.add(id);
                if (id == '2') throw StateError('Fixture guide failure');
                return GuideSchedule([
                  programme('Older report', -24),
                  programme('Upcoming news', 3),
                  programme('Expired replay', -72),
                  programme('No replay rights', -4, archived: false),
                  replay,
                  replay,
                ]);
              }),
            ],
            child: const MaterialApp(home: CatchupScreen()),
          ),
        );
        await tester.pumpAndSettle();
        expect(requested, isEmpty);
        expect(find.text('News archive'), findsOneWidget);
        expect(find.text('Sports archive'), findsOneWidget);
        for (final title in ['Live only', 'Hidden archive', 'Locked archive']) {
          expect(find.text(title), findsNothing);
        }
        if (tv) {
          await key(tester, LogicalKeyboardKey.arrowDown);
          expect(
            FocusManager.instance.primaryFocus?.debugLabel,
            'Catch-up channel: News archive',
          );
          await key(tester, LogicalKeyboardKey.arrowDown);
          await key(tester, LogicalKeyboardKey.select);
          expect(find.text('Programme guide unavailable'), findsOneWidget);
          await key(tester, LogicalKeyboardKey.arrowRight);
          expect(
            FocusManager.instance.primaryFocus?.debugLabel,
            'Retry programme guide',
          );
          await key(tester, LogicalKeyboardKey.select);
          expect(requested, ['2', '2']);
          requested.clear();
          await key(tester, LogicalKeyboardKey.arrowUp);
          await key(tester, LogicalKeyboardKey.select);
          await key(tester, LogicalKeyboardKey.arrowRight);
          expect(
            FocusManager.instance.primaryFocus?.debugLabel,
            'Replay: Evening report',
          );
          await key(tester, LogicalKeyboardKey.arrowLeft);
          expect(
            FocusManager.instance.primaryFocus?.debugLabel,
            'Catch-up channel: News archive',
          );
          await key(tester, LogicalKeyboardKey.arrowRight);
        } else {
          await tester.enterText(find.byType(TextField), 'news');
          await tester.pumpAndSettle();
          expect(find.text('Sports archive'), findsNothing);
          await tester.tap(find.text('News archive'));
          await tester.pumpAndSettle();
        }
        expect(requested, ['1']);
        for (final title in [
          'Upcoming news',
          'Expired replay',
          'No replay rights',
        ]) {
          expect(find.text(title), findsNothing);
        }
        expect(find.text('Evening report'), findsOneWidget);
        expect(
          tester.getTopLeft(find.text('Evening report')).dy,
          lessThan(tester.getTopLeft(find.text('Older report')).dy),
        );
        if (tv) {
          await key(tester, LogicalKeyboardKey.select);
          await key(tester, LogicalKeyboardKey.select);
        } else {
          await tester.tap(find.text('Evening report'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Watch replay'));
          await tester.pumpAndSettle();
        }
        final player = tester.widget<PlayerScreen>(find.byType(PlayerScreen));
        expect(player.catchupProgramme, same(replay));
        expect(player.item.id, '1');
        expect(player.channels, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
