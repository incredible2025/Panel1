import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streamline_iptv/core/providers.dart';
import 'package:streamline_iptv/data/models.dart';
import 'package:streamline_iptv/widgets/tv_glass_guide.dart';
import 'package:streamline_iptv/widgets/tv_glass_theme.dart';

void main() {
  test(
    'Glass guide orders real current and upcoming programmes without inventing gaps',
    () {
      final now = DateTime.utc(2026, 10, 23, 19, 42);
      EpgEntry entry(String title, int start, int end) => EpgEntry(
        title: title,
        description: '',
        start: now.add(Duration(minutes: start)),
        end: now.add(Duration(minutes: end)),
      );
      final current = entry('Current', -10, 15);
      final next = entry('Next', 15, 45);
      final later = entry('Later', 45, 90);
      expect(
        glassGuideSlots([
          later,
          entry('Expired', -60, -20),
          next,
          current,
          entry('Invalid', 20, 10),
        ], now),
        [current, next, later],
      );
      expect(glassGuideSlots([next, later], now), [null, next, later]);
      expect(glassGuideSlots([], now), [null, null, null]);
    },
  );

  testWidgets(
    'Glass guide fits eight rows, bounds EPG requests and keeps held-key focus across a large catalogue',
    (tester) async {
      tester.view.physicalSize = const Size(1024, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final requested = <String>{};
      final key = GlobalKey<TvGlassGuideState>();
      var left = false, top = false, right = false;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            epgProvider.overrideWith((ref, id) async {
              requested.add(id);
              return <EpgEntry>[];
            }),
          ],
          child: MaterialApp(
            theme: ThemeData.dark(),
            home: Scaffold(
              body: TvGlassScope(
                child: TvGlassGuide(
                  key: key,
                  channels: List.generate(
                    1500,
                    (i) => MediaItem(
                      id: '$i',
                      name: 'Channel $i',
                      kind: MediaKind.live,
                    ),
                  ),
                  selectedId: '0',
                  onFocused: (_, column) {},
                  onOpen: (_) {},
                  onProgramme: (_, entry) {},
                  onLeft: () => left = true,
                  onRight: () => right = true,
                  onTop: () => top = true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(requested.length, lessThan(25));
      expect(find.text('Channel 7').hitTestable(), findsOneWidget);
      key.currentState!.focusSelected();
      await tester.pumpAndSettle();
      for (var i = 0; i < 45; i++) {
        if (i == 0) {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
        } else {
          await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
        }
        await tester.pumpAndSettle();
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Channel: Channel 45',
      );
      expect(find.text('Channel 45').hitTestable(), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Programme 2: Channel 45',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(right, isTrue);
      for (var i = 0; i < 3; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
      }
      expect(left, isTrue);
      key.currentState!.focusSelected();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      expect(top, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
