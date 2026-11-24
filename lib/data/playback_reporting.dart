import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../core/app_version.dart';
import 'app_settings.dart';
import 'managed_activity.dart';
import 'playback_evidence.dart';
import 'connection_diagnostics.dart';

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
  started,
  playing,
  fallback,
  ended,
  diagnosis,
  unknown;

  String get code => switch (this) {
    greenScreen => 'green_screen',
    noPicture => 'no_picture',
    _ => name,
  };

  bool get manual =>
      [greenScreen, noPicture, pixelation, diagnosis].contains(this);
}

class PlaybackReportSession {
  final id = PlaybackReporting.newId();
  final clock = Stopwatch()..start();
  int sequence = 0, attempt = 0;
  bool playingReported = false, ended = false;
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
  Future<void> _pipeline = Future.value();
  int _pending = 0;

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

  static String newId() {
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
    String? sessionId,
    int? sequence,
    int? elapsedMs,
    Map<String, Object> details = const {},
    DateTime? occurredAt,
  }) async {
    if (_disposed ||
        _pending >= 24 ||
        !['live', 'movie', 'series', 'catchup'].contains(kind)) {
      return false;
    }
    final occurred = (occurredAt ?? DateTime.now()).toUtc().toIso8601String();
    final key =
        '${sessionId ?? ''}/${details['attempt'] ?? ''}/${issue.code}/${engine.name}/${decoding.name}';
    final now = DateTime.now();
    _recent.removeWhere(
      (_, time) => now.difference(time) >= const Duration(minutes: 1),
    );
    if (_recent.containsKey(key) || _recent.length >= 24) return false;
    _recent[key] = now;
    final before = _pipeline;
    final finished = Completer<void>();
    _pipeline = finished.future;
    _pending++;
    try {
      await before;
      if (_disposed) return false;
      final client = _clientFactory();
      _clients.add(client);
      try {
        if (activity.lastReported == null) await activity.report();
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
                'event_id': eventId ?? newId(),
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
                'schema_version': 2,
                if (sessionId != null) 'session_id': sessionId,
                if (sequence != null) 'sequence': sequence,
                if (elapsedMs != null)
                  'elapsed_ms': elapsedMs.clamp(0, 604800000),
                'occurred_at': occurred,
                'details': {
                  ...PlaybackEvidence.sanitize(details),
                  if (details['attempt'] is int)
                    'attempt': (details['attempt'] as int).clamp(1, 1000),
                  if ([
                    'opening',
                    'playing',
                    'buffering',
                    'recovering',
                    'stopped',
                    'unknown',
                  ].contains(details['stage']))
                    'stage': details['stage'],
                  ...await _network(),
                },
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
    } finally {
      _pending--;
      finished.complete();
    }
  }

  Future<Map<String, Object>> _network() async {
    try {
      final raw = await platform
          .invokeMapMethod<String, dynamic>('networkDiagnosis')
          .timeout(const Duration(milliseconds: 400));
      final names = raw?['transports'];
      return {
        if (names is List)
          'transports': names
              .whereType<String>()
              .where(['Wi-Fi', 'Ethernet', 'Mobile', 'VPN', 'Other'].contains)
              .take(5)
              .toList(),
        if (raw?['vpn'] is bool) 'vpn': raw!['vpn'] as bool,
        if (raw?['validated'] is bool)
          'network_validated': raw!['validated'] as bool,
        if (raw?['metered'] is bool) 'metered': raw!['metered'] as bool,
      };
    } catch (_) {
      return const {};
    }
  }

  Future<bool> sendDiagnosis(
    DiagnosticReport report, {
    String? sessionId,
  }) async {
    if (_disposed || report.cancelled || report.checks.isEmpty) return false;
    final client = _clientFactory();
    _clients.add(client);
    try {
      if (activity.lastReported == null) await activity.report();
      final request =
          http.Request('POST', activity.configUrl.resolve('playback'))
            ..followRedirects = false
            ..headers.addAll({
              'Authorization': 'Bearer ${activity.secret}',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            })
            ..body = jsonEncode({
              'event_id': newId(),
              'schema_version': 2,
              'session_id': sessionId ?? newId(),
              'version': appVersionName,
              'build': appBuildNumber,
              ...await _metadata(),
              'engine': 'none',
              'decoding': 'none',
              'kind': 'none',
              'category': 'diagnosis',
              'source': 'user',
              'occurred_at': DateTime.now().toUtc().toIso8601String(),
              'details': {
                'checks': report.checks
                    .take(20)
                    .map(
                      (check) => {
                        'stage': check.stage,
                        'code': check.finding.code,
                        'status': check.finding.status.name,
                        'elapsed_ms': check.elapsedMs.clamp(0, 120000),
                      },
                    )
                    .toList(),
                ...await _network(),
              },
            });
      return (await client.send(request).timeout(const Duration(seconds: 3)))
              .statusCode ==
          204;
    } catch (_) {
      return false;
    } finally {
      _clients.remove(client);
      client.close();
    }
  }

  Future<void> context({
    String? sessionId,
    PlayerEngine? engine,
    DecodingMode? decoding,
    String? kind,
  }) async {
    try {
      await platform.invokeMethod<void>(
        'playbackContext',
        engine == null
            ? null
            : {
                'engine': engine.name,
                'decoding': decoding?.name,
                if (sessionId != null) 'session_id': sessionId,
                'kind': kind,
              },
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
        sessionId: data['session_id'] as String?,
        occurredAt: data['occurred_ms'] is int
            ? DateTime.fromMillisecondsSinceEpoch(
                data['occurred_ms'] as int,
                isUtc: true,
              )
            : null,
        details: data['native_code'] is String
            ? {'native_code': data['native_code'] as String}
            : const {},
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
