import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/app_version.dart';

/// Anonymous per-installation presence. Never receives provider credentials.
class ManagedActivity extends ChangeNotifier {
  ManagedActivity({
    required this.configUrl,
    required this.secret,
    required this.revision,
    http.Client Function()? clientFactory,
    this.interval = const Duration(minutes: 1),
  }) : _clientFactory = clientFactory ?? http.Client.new;
  final Uri configUrl;
  final String secret;
  final int Function() revision;
  final Duration interval;
  final http.Client Function() _clientFactory;
  Timer? _timer;
  http.Client? _client;
  Future<void>? _sending;
  bool _active = false, _disposed = false;
  DateTime? lastReported;

  Map<String, String> updateHeaders(Uri uri) =>
      uri == configUrl.resolve('updates')
      ? {'Authorization': 'Bearer $secret'}
      : const {};

  void foreground(bool active) {
    _active = active;
    _timer?.cancel();
    _timer = null;
    if (!active || _disposed) {
      _client?.close();
      return;
    }
    unawaited(report());
    _timer = Timer.periodic(interval, (_) => unawaited(report()));
  }

  Future<void> report() {
    if (_disposed || !_active) return Future.value();
    return _sending ??= _report().whenComplete(() => _sending = null);
  }

  Future<void> _report() async {
    final client = _clientFactory();
    _client = client;
    try {
      final request = http.Request('POST', configUrl.resolve('activity'))
        ..followRedirects = false
        ..headers.addAll({
          'Authorization': 'Bearer $secret',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        })
        ..body = jsonEncode({
          'version': appVersionName,
          'build': appBuildNumber,
          'revision': revision(),
        });
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 3));
      if (response.statusCode == 204 && !_disposed && _active) {
        lastReported = DateTime.now();
        notifyListeners();
      }
    } catch (_) {
      // Reporting never interrupts authentication, browsing or playback.
    } finally {
      client.close();
      if (identical(_client, client)) _client = null;
    }
  }

  Future<String> pairCode() async {
    await report();
    final client = _clientFactory();
    try {
      final request = http.Request('POST', configUrl.resolve('pair'))
        ..followRedirects = false
        ..headers.addAll({
          'Authorization': 'Bearer $secret',
          'Accept': 'application/json',
        });
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 3));
      if (response.statusCode != 200) throw const FormatException();
      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 3),
      )) {
        bytes.addAll(chunk);
        if (bytes.length > 2048) throw const FormatException();
      }
      final data = jsonDecode(utf8.decode(bytes));
      final code = data['code'];
      if (code is! String || !RegExp(r'^\d{6}$').hasMatch(code)) {
        throw const FormatException();
      }
      return code;
    } finally {
      client.close();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _client?.close();
    super.dispose();
  }
}
