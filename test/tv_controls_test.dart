import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streamline_iptv/data/models.dart';
import 'package:streamline_iptv/widgets/tv_controls.dart';
import 'package:streamline_iptv/widgets/tv_poster_browser.dart';

Future<void> held(
  WidgetTester tester,
  LogicalKeyboardKey key,
  int count,
) async {
  await tester.sendKeyDownEvent(key);
  await tester.pumpAndSettle();
  for (var i = 1; i < count; i++) {
    await tester.sendKeyRepeatEvent(key);
    await tester.pumpAndSettle();
  }
  await tester.sendKeyUpEvent(key);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'TV list reveals and activates distant entries with held arrows',
    (tester) async {
      final key = GlobalKey<TvRemoteListState>();
      var opened = -1, top = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 320,
              child: TvRemoteList(
                key: key,
                entries: List.generate(
                  300,
                  (i) => TvListEntry(
                    id: '$i',
                    title: 'Category $i',
                    onPressed: () => opened = i,
                  ),
                ),
                onLeft: () {},
                onRight: () {},
                onTop: () => top++,
              ),
            ),
          ),
        ),
      );
      key.currentState!.focusIndex(0);
      await tester.pumpAndSettle();
      await held(tester, LogicalKeyboardKey.arrowDown, 55);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'List: Category 55',
      );
      expect(find.byType(TvControl).evaluate().length, lessThan(30));
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      expect(opened, 55);
      await held(tester, LogicalKeyboardKey.arrowUp, 56);
      expect(top, 1);
      expect(tester.takeException(), isNull);
    },
  );

  for (final horizontal in [false, true]) {
    testWidgets(
      'TV poster ${horizontal ? 'rail' : 'grid'} reveals distant focused titles',
      (tester) async {
        final key = GlobalKey<TvPosterBrowserState>();
        MediaItem? opened;
        final items = List.generate(
          300,
          (i) => MediaItem(id: '$i', name: 'Film $i', kind: MediaKind.movie),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 420,
                height: 320,
                child: TvPosterBrowser(
                  key: key,
                  items: items,
                  horizontal: horizontal,
                  onOpen: (item) => opened = item,
                  onLeft: () {},
                  onTop: () {},
                ),
              ),
            ),
          ),
        );
        key.currentState!.focusFirst();
        await tester.pumpAndSettle();
        await held(
          tester,
          horizontal
              ? LogicalKeyboardKey.arrowRight
              : LogicalKeyboardKey.arrowDown,
          30,
        );
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'Title: Film ${horizontal ? 30 : 60}',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        expect(opened?.id, horizontal ? '30' : '60');
        expect(find.byType(TvControl).evaluate().length, lessThan(30));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
