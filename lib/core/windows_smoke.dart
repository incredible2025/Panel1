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
  final observations = <String, Object>{};
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
      final length = await file.length();
      var start = 0, end = length - 1;
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      final range = request.headers.value(HttpHeaders.rangeHeader);
      if (range != null) {
        final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(range);
        if (match == null || (match[1]!.isEmpty && match[2]!.isEmpty)) {
          request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          await request.response.close();
          return;
        }
        if (match[1]!.isEmpty) {
          start = (length - int.parse(match[2]!)).clamp(0, length);
        } else {
          start = int.parse(match[1]!);
          end = match[2]!.isEmpty ? end : int.parse(match[2]!).clamp(0, end);
        }
        if (start >= length || start > end) {
          request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          request.response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes */$length',
          );
          await request.response.close();
          return;
        }
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-$end/$length',
        );
      }
      request.response.contentLength = end - start + 1;
      if (request.method != 'HEAD') {
        await request.response.addStream(file.openRead(start, end + 1));
      }
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
        onDiagnostic: (message) {
          final logs =
              observations.putIfAbsent('decoderMessages', () => <String>[])
                  as List<String>;
          if (logs.length < 8) {
            logs.add(
              message.replaceAll(RegExp(r'https?://\S+'), '[local media]'),
            );
          }
        },
      );
      await playback.initialize().timeout(const Duration(seconds: 25));
      surface.value = playback;
      await WidgetsBinding.instance.endOfFrame;
      await playback.play();
      for (
        var attempt = 0;
        attempt < 80 &&
            (!playback.hasVideoOutput ||
                playback.value.position.inMilliseconds < 250);
        attempt++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      checks[stage] =
          playback.value.isInitialized &&
          playback.hasVideoOutput &&
          playback.value.position.inMilliseconds >= 250;
      observations[stage] = {
        'positionMs': playback.value.position.inMilliseconds,
        'durationMs': playback.value.duration.inMilliseconds,
        'videoOutput': playback.hasVideoOutput,
        'error': playback.value.hasError,
        'playing': playback.value.isPlaying,
      };
      await playback.pause();
      await playback.seekTo(const Duration(seconds: 1));
      for (
        var attempt = 0;
        attempt < 20 &&
            (playback.value.position - const Duration(seconds: 1)).abs() >
                const Duration(milliseconds: 500);
        attempt++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      checks['seek_${p.extension(name).substring(1)}'] =
          (playback.value.position - const Duration(seconds: 1)).abs() <=
          const Duration(milliseconds: 500);
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
        'observations': observations,
      }),
    );
  } catch (error) {
    if (playback != null) observations['failureState'] = playback.debugState;
    await report.writeAsString(
      jsonEncode({
        'passed': false,
        'stage': stage,
        'errorType': error.runtimeType.toString(),
        'checks': checks,
        'observations': observations,
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
