import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:streamline_iptv/core/design_system.dart';
import 'package:streamline_iptv/core/providers.dart';
import 'package:streamline_iptv/data/app_settings.dart';
import 'package:streamline_iptv/data/content_declaration.dart';
import 'package:streamline_iptv/data/local_store.dart';
import 'package:streamline_iptv/data/models.dart';
import 'package:streamline_iptv/features/content_declaration_screen.dart';

class _Store implements LocalStore {
  bool acknowledged = false, failRead = false, failWrite = false;
  int writes = 0;
  Completer<void>? saving;
  @override
  Future<bool> hasAcknowledgedContentDeclaration(int version) async {
    if (failRead) throw StateError('Private storage detail');
    return acknowledged;
  }

  @override
  Future<void> acknowledgeContentDeclaration(int version) async {
    writes++;
    await saving?.future;
    if (failWrite) throw StateError('Private storage detail');
    acknowledged = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  setUpAll(() async {
    await (FontLoader(
      'Glass Sans',
    )..addFont(rootBundle.load('assets/fonts/Inter-Variable.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  Future<void> key(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  Future<void> mount(
    WidgetTester tester,
    _Store store, {
    bool tv = true,
    Size size = const Size(960, 540),
    bool readOnly = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storeProvider.overrideWithValue(store),
          isTvProvider.overrideWithValue(tv),
          isDesktopProvider.overrideWithValue(false),
        ],
        child: MaterialApp(
          theme: StreamlineTheme.dark,
          builder: (_, child) => AppBackdrop(child: child!),
          home: RepaintBoundary(
            key: const ValueKey('declaration-capture'),
            child: readOnly
                ? const ContentDeclarationScreen()
                : ContentDeclarationGate(
                    builder: (_) => const Scaffold(body: Text('Protected app')),
                  ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> acknowledgeByRemote(WidgetTester tester) async {
    await key(tester, LogicalKeyboardKey.arrowRight);
    await key(tester, LogicalKeyboardKey.select);
    await key(tester, LogicalKeyboardKey.arrowDown);
    await key(tester, LogicalKeyboardKey.select);
  }

  for (final size in [
    const Size(960, 540),
    const Size(1280, 720),
    const Size(1920, 1080),
  ]) {
    testWidgets('TV declaration scrolls and acknowledgement works at $size', (
      tester,
    ) async {
      final store = _Store();
      await mount(tester, store, size: size);
      expect(find.text('Protected app'), findsNothing);
      for (var i = 0; i < 6; i++) {
        await key(tester, LogicalKeyboardKey.arrowDown);
      }
      expect(
        find.text('Content and subscription enquiries').hitTestable(),
        findsOneWidget,
      );
      if (const bool.fromEnvironment('CAPTURE_UI')) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('declaration-capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('build/qa').create(recursive: true);
          await File(
            'build/qa/declaration-tv-${size.width.toInt()}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await acknowledgeByRemote(tester);
      expect(store.writes, 1);
      expect(store.acknowledged, isTrue);
      expect(find.text('Protected app'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'continuing without acknowledgement never saves or opens the app',
    (tester) async {
      final store = _Store();
      await mount(tester, store);
      await key(tester, LogicalKeyboardKey.arrowRight);
      await key(tester, LogicalKeyboardKey.arrowDown);
      await key(tester, LogicalKeyboardKey.select);
      expect(store.writes, 0);
      expect(find.text('Protected app'), findsNothing);
      expect(find.textContaining('Please acknowledge'), findsOneWidget);
    },
  );

  testWidgets(
    'write must finish successfully before gate opens; retry is possible',
    (tester) async {
      final store = _Store()..failWrite = true;
      await mount(tester, store);
      await acknowledgeByRemote(tester);
      expect(find.textContaining('could not be saved'), findsOneWidget);
      expect(find.textContaining('Private storage'), findsNothing);
      expect(find.text('Protected app'), findsNothing);
      store.failWrite = false;
      store.saving = Completer<void>();
      await key(tester, LogicalKeyboardKey.select);
      expect(find.text('Saving…'), findsOneWidget);
      expect(find.text('Protected app'), findsNothing);
      await key(tester, LogicalKeyboardKey.select);
      expect(store.writes, 2); // First failed save plus one pending retry.
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('Protected app'), findsNothing);
      store.saving!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Protected app'), findsOneWidget);
    },
  );

  testWidgets(
    'saved acknowledgement skips gate; read failure cannot bypass it',
    (tester) async {
      final store = _Store()..failRead = true;
      await mount(tester, store);
      expect(find.textContaining('could not be read'), findsOneWidget);
      expect(find.text('Protected app'), findsNothing);
      store
        ..failRead = false
        ..acknowledged = true;
      await key(tester, LogicalKeyboardKey.select);
      expect(find.text('Protected app'), findsOneWidget);
      expect(store.writes, 0);
    },
  );

  for (final size in [const Size(390, 844), const Size(844, 390)]) {
    testWidgets('mobile declaration needs an explicit checkbox at $size', (
      tester,
    ) async {
      final store = _Store();
      await mount(tester, store, tv: false, size: size);
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse,
      );
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Acknowledge and continue'));
      await tester.tap(find.text('Acknowledge and continue'));
      await tester.pumpAndSettle();
      expect(find.text('Protected app'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'Settings declaration is read-only and does not request acceptance again',
    (tester) async {
      final store = _Store();
      await mount(tester, store, readOnly: true);
      expect(find.text('Player software only'), findsOneWidget);
      expect(find.text('Acknowledge and continue'), findsNothing);
      expect(store.writes, 0);
    },
  );

  testWidgets(
    'TV Back offers exit and cannot bypass an unacknowledged declaration',
    (tester) async {
      final store = _Store();
      await mount(tester, store);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await key(tester, LogicalKeyboardKey.select); // Stay in app.
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Protected app'), findsNothing);
      expect(store.writes, 0);
    },
  );

  test(
    'acknowledgement is installation scoped, versioned and retained across sign-out/cache reset',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final dir = await Directory.systemTemp.createTemp('declaration-store-');
      final file = '${dir.path}/test.db';
      var store = await LocalStore.open(
        databaseFactory: databaseFactoryFfi,
        databasePath: file,
      );
      try {
        expect(await store.hasAcknowledgedContentDeclaration(1), isFalse);
        await store.acknowledgeContentDeclaration(1);
        await store.acknowledgeContentDeclaration(1);
        await store.clearSession();
        await store.clearCache('account');
        await store.saveSettings('account', const AppSettings());
        await store.close();
        store = await LocalStore.open(
          databaseFactory: databaseFactoryFfi,
          databasePath: file,
        );
        expect(await store.hasAcknowledgedContentDeclaration(1), isTrue);
        expect(await store.hasAcknowledgedContentDeclaration(2), isFalse);
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'v5 migration requires acknowledgement and preserves existing watch history',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final dir = await Directory.systemTemp.createTemp(
        'declaration-migration-',
      );
      final file = '${dir.path}/test.db';
      var store = await LocalStore.open(
        databaseFactory: databaseFactoryFfi,
        databasePath: file,
      );
      await store.recordOpened(
        'account',
        const MediaItem(id: '1', name: 'Demo', kind: MediaKind.movie),
      );
      await store.close();
      final old = await databaseFactoryFfi.openDatabase(file);
      await old.execute('DROP TABLE installation_declarations');
      await old.execute('PRAGMA user_version = 5');
      await old.close();
      store = await LocalStore.open(
        databaseFactory: databaseFactoryFfi,
        databasePath: file,
      );
      try {
        expect(
          await store.hasAcknowledgedContentDeclaration(
            contentDeclarationVersion,
          ),
          isFalse,
        );
        expect((await store.history('account')).single.item.name, 'Demo');
        await store.acknowledgeContentDeclaration(contentDeclarationVersion);
        expect(
          await store.hasAcknowledgedContentDeclaration(
            contentDeclarationVersion,
          ),
          isTrue,
        );
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
