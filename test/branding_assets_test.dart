import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streamline_iptv/core/app_brand.dart';
import 'package:streamline_iptv/core/design_system.dart';

void main() {
  testWidgets('selected brand renders its own wordmark and asset exports', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final fonts = FontLoader('Glass Sans')
        ..addFont(rootBundle.load('assets/fonts/Inter-Variable.ttf'));
      await fonts.load();
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(640, 360);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final boundary = GlobalKey();
    Future<void> render(Widget child) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(
              child: RepaintBoundary(key: boundary, child: child),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final context = boundary.currentContext!;
      final providers = tester
          .widgetList<Image>(find.byType(Image))
          .map((image) => image.image)
          .toList();
      await tester.runAsync(() async {
        for (final provider in providers) {
          await precacheImage(provider, context);
        }
      });
      await tester.pumpAndSettle();
    }

    Future<void> save(String name) async {
      final image =
          await (boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      await File(name).writeAsBytes(bytes!.buffer.asUint8List());
    }

    await render(const UltraVpnBanner());
    expect(find.text(appBrandTitle), findsOneWidget);
    expect(find.text(appBrandSubtitle), findsOneWidget);
    if (const bool.fromEnvironment('EXPORT_BRAND_ASSETS')) {
      final output = const String.fromEnvironment('BRAND_ASSET_OUTPUT');
      if (output.isEmpty) {
        throw StateError('Asset output directory is required.');
      }
      await tester.runAsync(() => Directory(output).create(recursive: true));
      await tester.runAsync(() => save('$output/tv-banner.png'));
      tester.view.physicalSize = const Size(512, 512);
      await render(
        Center(
          child: Image.asset(
            appBrandMark,
            width: 512,
            height: 512,
            fit: BoxFit.contain,
          ),
        ),
      );
      await tester.runAsync(() => save('$output/icon.png'));
      await render(
        DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF20103F), Color(0xFF071B38)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(appBrandMark, width: 260, height: 260),
                const SizedBox(height: 16),
                Text(
                  appBrandTitle,
                  style: const TextStyle(
                    fontFamily: 'Glass Sans',
                    fontSize: 44,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  appBrandSubtitle,
                  style: const TextStyle(
                    fontFamily: 'Glass Sans',
                    fontSize: 20,
                    letterSpacing: 4,
                    color: Color(0xFF9AEFF5),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.runAsync(() => save('$output/artwork.png'));
    }
  });
}
