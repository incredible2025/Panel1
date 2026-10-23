import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streamline_iptv/widgets/tv_category_strip.dart';

void main() {
  testWidgets(
    'held remote direction traverses virtualized categories and respects both boundaries',
    (tester) async {
      final key = GlobalKey<TvCategoryStripState>();
      final activated = <int>[];
      var left = 0, right = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                child: TvCategoryStrip(
                  key: key,
                  onUp: () {},
                  onLeftBoundary: () => left++,
                  onRightBoundary: () => right++,
                  choices: List.generate(
                    35,
                    (i) => TvCategoryChoice(
                      id: '$i',
                      label: 'Group $i',
                      selected: i == 0,
                      onPressed: () => activated.add(i),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      key.currentState!.focusSelected();
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      for (var i = 0; i < 33; i++) {
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Category: Group 34',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
      await tester.pumpAndSettle();
      expect(activated, [34]);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(right, 1);
      for (var i = 0; i < 35; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
      }
      expect(left, 1);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Category: Group 0',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
