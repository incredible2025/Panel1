import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/local_store.dart';
import '../data/models.dart';
import '../data/app_update.dart';
import '../data/windows_update_platform.dart';
import 'app_version.dart';
import 'playback_handle.dart';

/// Explicit CI-only command-line entry point; never contacts the TV service.
Future<void> runWindowsSmoke(List<String> args) async {
  final report = File(args[args.indexOf('--smoke-test') + 1]);
  final fixtures = args[args.indexOf('--media-fixtures') + 1];
  final checks = <String, bool>{};
  var stage = 'startup';
  Directory? temporary;
  HttpServer? server;
  LocalStore? store;
  CompatibilityPlayback? playback;
  final secure = const FlutterSecureStorage();
  final surface = ValueNotifier<PlaybackHandle?>(null);
  final secureKey = 'ultravpn.smoke.${DateTime.now().microsecondsSinceEpoch}';
  try {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<PlaybackHandle?>(
            valueListenable: surface,
            builder: (_, player, _) =>
                player?.buildView() ??
                const Center(
                  child: Text('Ultravpn-player Windows verification'),
                ),
          ),
        ),
      ),
    );
    await WidgetsBinding.instance.endOfFrame;
    stage = 'application_directory';
    checks[stage] = (await getApplicationSupportDirectory()).path.isNotEmpty;
    temporary = await Directory.systemTemp.createTemp(
      'ultravpn-windows-smoke-',
    );
    stage = 'database';
    store = await LocalStore.open(
      databasePath: p.join(temporary.path, 'smoke.db'),
    );
    const item = MediaItem(
      id: 'smoke',
      name: 'Desktop test film',
      kind: MediaKind.movie,
    );
    await store.setFavorite('smoke-account', item, true);
    checks[stage] =
        (await store.favorites('smoke-account')).single.id == item.id;
    stage = 'secure_storage';
    await secure.write(key: secureKey, value: 'smoke-only');
    checks[stage] = await secure.read(key: secureKey) == 'smoke-only';
    stage = 'installer_validation';
    final updates = WindowsUpdatePlatform(
      directoryProvider: () async =>
          Directory(p.join(temporary!.path, 'updater')),
    );
    final device = await updates.load();
    final update = AppUpdate.parse(
      await File(args[args.indexOf('--manifest') + 1]).readAsString(),
      target: UpdateTarget.windows,
      sourceUri: Uri.parse('https://updates.example/windows-update.json'),
    );
    await Directory(device.directory).create(recursive: true);
    final installer = await File(
      args[args.indexOf('--installer') + 1],
    ).copy(p.join(device.directory, 'update.exe'));
    await updates.validate(installer.path, update);
    checks[stage] =
        device.code == appBuildNumber && device.sdk >= update.minSdk;
    stage = 'window_controls';
    const channel = MethodChannel('streamline/platform');
    checks[stage] = await channel.invokeMethod<bool>('isTelevision') == false;
    await channel.invokeMethod<void>('toggleFullscreen');
    await channel.invokeMethod<void>('toggleFullscreen');
    await channel.invokeMethod<void>('setKeepScreenOn', true);
    await channel.invokeMethod<void>('setKeepScreenOn', false);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final name = p.basename(request.uri.path);
      final file = File(p.join(fixtures, name));
      if (!await file.exists()) {
        request.response.statusCode = 404;
        await request.response.close();
        return;
      }
      request.response.headers.contentType = ContentType.parse(
        name.endsWith('.m3u8')
            ? 'application/vnd.apple.mpegurl'
            : name.endsWith('.ts')
            ? 'video/mp2t'
            : 'video/mp4',
      );
      request.response.contentLength = await file.length();
      await request.response.addStream(file.openRead());
      await request.response.close();
    });
    for (final name in ['fixture.mp4', 'fixture.ts', 'fixture.m3u8']) {
      stage = 'playback_${p.extension(name).substring(1)}';
      // Hosted runners have no speakers; decode audio into a null output sink.
      playback = CompatibilityPlayback(
        Uri(
          scheme: 'http',
          host: server.address.address,
          port: server.port,
          path: '/$name',
        ),
        audioOutput: 'null',
      );
      await playback.initialize().timeout(const Duration(seconds: 25));
      surface.value = playback;
      await WidgetsBinding.instance.endOfFrame;
      await playback.play();
      for (
        var attempt = 0;
        attempt < 80 && playback.value.position.inMilliseconds < 250;
        attempt++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      checks[stage] =
          playback.value.isInitialized &&
          playback.value.size.width > 0 &&
          playback.value.position.inMilliseconds >= 250;
      await playback.pause();
      await playback.seekTo(const Duration(seconds: 1));
      surface.value = null;
      await WidgetsBinding.instance.endOfFrame;
      await playback.dispose();
      playback = null;
      if (!checks[stage]!) throw StateError('Media verification failed');
    }
    if (checks.values.any((value) => !value)) {
      throw StateError('Desktop verification failed');
    }
    await report.writeAsString(
      jsonEncode({
        'passed': true,
        'version': appVersionName,
        'build': appBuildNumber,
        'checks': checks,
      }),
    );
  } catch (error) {
    await report.writeAsString(
      jsonEncode({
        'passed': false,
        'stage': stage,
        'errorType': error.runtimeType.toString(),
        'checks': checks,
      }),
    );
  } finally {
    surface.value = null;
    await WidgetsBinding.instance.endOfFrame;
    await playback?.dispose();
    await server?.close(force: true);
    await store?.close();
    await secure.delete(key: secureKey);
    if (temporary != null) await temporary.delete(recursive: true);
  }
  exit(jsonDecode(await report.readAsString())['passed'] == true ? 0 : 1);
}
