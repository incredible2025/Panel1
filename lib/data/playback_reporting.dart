import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../core/app_version.dart';
import 'app_settings.dart';
import 'managed_activity.dart';

enum PlaybackIssue {
  connection,
  decoder,
  timeout,
  certificate,
  buffering,
  greenScreen,
  noPicture,
  pixelation,
  crash,
  unknown;

  String get code => switch (this) {
    greenScreen => 'green_screen',
    noPicture => 'no_picture',
    _ => name,
  };

  bool get manual => [greenScreen, noPicture, pixelation].contains(this);
}

/// Accepts fixed categories only. Stream exceptions and media names stay local.
class PlaybackReporting {
  PlaybackReporting(this.activity, {http.Client Function()? clientFactory})
    : _clientFactory = clientFactory ?? http.Client.new;

  static const platform = MethodChannel('streamline/platform');
  final ManagedActivity activity;
  final http.Client Function() _clientFactory;
  final _recent = <String, DateTime>{};
  final _clients = <http.Client>{};
  Map<String, String>? _device;
  bool _disposed = false;

  static String _model(Object? value) {
    final safe = (value is String ? value : 'Unknown Android')
        .replaceAll(RegExp(r'[^A-Za-z0-9 _()-]'), '')
        .trim();
    return safe.isEmpty
        ? 'Unknown Android'
        : safe.substring(0, min(80, safe.length));
  }

  Future<Map<String, String>> _metadata() async {
    if (_device != null) return _device!;
    final data = await platform
        .invokeMapMethod<String, dynamic>('playbackDevice')
        .timeout(const Duration(seconds: 3));
    final release = '${data?['release'] ?? '0'}';
    return _device = {
      'device_model': _model(data?['model']),
      'os_version':
          'Android ${RegExp(r'^[0-9.]{1,20}$').hasMatch(release) ? release : '0'}',
      'form_factor': data?['tv'] == true ? 'tv' : 'mobile',
    };
  }

  static String _uuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<bool> report(
    PlaybackIssue issue, {
    required PlayerEngine engine,
    required DecodingMode decoding,
    required String kind,
    String? eventId,
    String? previousVersion,
    int? previousBuild,
  }) async {
    if (_disposed ||
        _clients.length >= 2 ||
        !['live', 'movie', 'series', 'catchup'].contains(kind)) {
      return false;
    }
    final key = '${issue.code}/${engine.name}/${decoding.name}';
    final now = DateTime.now();
    _recent.removeWhere(
      (_, time) => now.difference(time) >= const Duration(minutes: 1),
    );
    if (_recent.containsKey(key) || _recent.length >= 8) return false;
    _recent[key] = now;
    final client = _clientFactory();
    _clients.add(client);
    try {
      await activity.report();
      final metadata = await _metadata();
      if (_disposed) return false;
      final request =
          http.Request('POST', activity.configUrl.resolve('playback'))
            ..followRedirects = false
            ..headers.addAll({
              'Authorization': 'Bearer ${activity.secret}',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            })
            ..body = jsonEncode({
              'event_id': eventId ?? _uuid(),
              'version': issue == PlaybackIssue.crash
                  ? previousVersion ?? appVersionName
                  : appVersionName,
              'build': issue == PlaybackIssue.crash
                  ? previousBuild ?? appBuildNumber
                  : appBuildNumber,
              ...metadata,
              'engine': engine.name,
              'decoding': decoding.name,
              'kind': kind,
              'category': issue.code,
              'source': issue.manual ? 'user' : 'automatic',
            });
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 3));
      return response.statusCode == 204;
    } catch (_) {
      return false;
    } finally {
      _clients.remove(client);
      client.close();
    }
  }

  Future<void> context({
    PlayerEngine? engine,
    DecodingMode? decoding,
    String? kind,
  }) async {
    try {
      await platform.invokeMethod<void>(
        'playbackContext',
        engine == null
            ? null
            : {'engine': engine.name, 'decoding': decoding?.name, 'kind': kind},
      );
    } catch (_) {
      /* Reporting never changes playback. */
    }
  }

  Future<void> reportPreviousCrash() async {
    try {
      final data = await platform.invokeMapMethod<String, dynamic>(
        'previousPlaybackCrash',
      );
      if (data == null) return;
      final engine = PlayerEngine.values
          .where((e) => e.name == data['engine'])
          .firstOrNull;
      final decoding = DecodingMode.values
          .where((d) => d.name == data['decoding'])
          .firstOrNull;
      if (engine == null ||
          decoding == null ||
          data['kind'] is! String ||
          data['id'] is! String) {
        return;
      }
      final sent = await report(
        PlaybackIssue.crash,
        engine: engine,
        decoding: decoding,
        kind: data['kind'] as String,
        eventId: data['id'] as String,
        previousVersion: data['version'] as String?,
        previousBuild: data['build'] as int?,
      );
      if (sent) {
        await platform.invokeMethod<void>(
          'acknowledgePlaybackCrash',
          data['id'],
        );
      }
    } catch (_) {
      /* A report is optional and bounded. */
    }
  }

  void dispose() {
    _disposed = true;
    for (final client in _clients) {
      client.close();
    }
    _clients.clear();
  }
}
