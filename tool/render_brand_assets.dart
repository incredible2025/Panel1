// Run: flutter test tool/render_brand_assets.dart
// Renders the actual Flutter brand widget into the native TV banner resource.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streamline_iptv/core/app_brand.dart';
import 'package:streamline_iptv/core/design_system.dart';

void main() {
  testWidgets('export native TV banner and review branding', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1024, 640);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await (FontLoader('Streamline Sans')
          ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf')))
        .load();
    await tester.pumpWidget(
      MaterialApp(
        theme: StreamlineTheme.dark,
        home: RepaintBoundary(
          key: const ValueKey('preview'),
          child: Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(appBrandName, style: TextStyle(fontSize: 24)),
                  const SizedBox(height: 28),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset(appBrandArtwork, width: 240, height: 240),
                      const SizedBox(width: 48),
                      Column(
                        children: [
                          const Text('Android launcher · circle mask'),
                          const SizedBox(height: 16),
                          ClipOval(
                            child: Container(
                              width: 120,
                              height: 120,
                              color: AppColors.canvas,
                              alignment: Alignment.center,
                              child: const StreamlineMark(size: 76),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  const Text('Android TV banner · 320 × 180'),
                  const SizedBox(height: 12),
                  const RepaintBoundary(
                    key: ValueKey('banner'),
                    child: SizedBox(
                      width: 320,
                      height: 180,
                      child: UltraVpnBanner(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      final context = tester.element(find.byType(UltraVpnBanner));
      await precacheImage(const AssetImage(appBrandMark), context);
      await precacheImage(const AssetImage(appBrandArtwork), context);
    });
    await tester.pumpAndSettle();
    for (final entry in {
      'banner':
          'android/app/src/main/res/drawable-xhdpi/ultravpn_tv_banner.png',
      'preview': 'build/qa/ultravpn-brand-preview.png',
    }.entries) {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(ValueKey(entry.key)),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File(entry.value);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  });
}
