import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

const defaultUpdateUrl =
    'https://github.com/incredible2025/Panel1/releases/latest/download/update.json';
const maxApkBytes = 512 * 1024 * 1024;

class UpdateFailure implements Exception {
  const UpdateFailure(this.message);
  final String message;
}

Uri updateUri(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment) {
    throw const UpdateFailure(
      'Use a valid HTTPS address without a username, password or fragment.',
    );
  }
  return uri;
}

class AppUpdate {
  const AppUpdate({
    required this.version,
    required this.code,
    required this.url,
    required this.sha256,
    required this.bytes,
    required this.minSdk,
    required this.notes,
    required this.packageId,
  });
  final String version, sha256, notes, packageId;
  final int code, bytes, minSdk;
  final Uri url;

  factory AppUpdate.parse(String source) {
    try {
      final json = jsonDecode(source) as Map<String, dynamic>;
      final version = json['versionName'] as String;
      final code = json['versionCode'] as int;
      final size = json['sizeBytes'] as int;
      final minSdk = json['minSdk'] as int;
      final hash = json['sha256'] as String;
      final notes = json['releaseNotes'] as String? ?? '';
      final packageId = json['applicationId'] as String;
      if (json['schemaVersion'] != 1 ||
          version.isEmpty ||
          version.length > 80 ||
          code <= 0 ||
          size <= 0 ||
          size > maxApkBytes ||
          minSdk < 24 ||
          notes.length > 20000 ||
          packageId != 'com.streamline.iptv' ||
          !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(hash)) {
        throw const FormatException();
      }
      return AppUpdate(
        version: version,
        code: code,
        url: updateUri(json['apkUrl'] as String),
        sha256: hash.toLowerCase(),
        bytes: size,
        minSdk: minSdk,
        notes: notes,
        packageId: packageId,
      );
    } on UpdateFailure {
      rethrow;
    } catch (_) {
      throw const UpdateFailure(
        'The server returned an invalid update file. Ask the app administrator to check update.json.',
      );
    }
  }
}

class UpdateDevice {
  const UpdateDevice({
    required this.version,
    required this.code,
    required this.sdk,
    required this.directory,
    required this.url,
    required this.automatic,
    this.lastCheck,
  });
  final String version, directory, url;
  final int code, sdk;
  final bool automatic;
  final DateTime? lastCheck;
}

abstract class UpdatePlatform {
  Future<UpdateDevice> load();
  Future<void> preferences(String url, bool automatic, DateTime? checked);
  Future<void> validate(String path, AppUpdate update);
  Future<bool> canInstall();
  Future<void> requestInstallPermission();
  Future<void> install(String path, AppUpdate update);
}

class AndroidUpdatePlatform implements UpdatePlatform {
  static const _channel = MethodChannel('ultravpn/updates');
  @override
  Future<UpdateDevice> load() async {
    final value = await _channel.invokeMapMethod<String, dynamic>('load');
    if (value == null) {
      throw const UpdateFailure(
        'App updates are available on Android devices.',
      );
    }
    return UpdateDevice(
      version: value['version'] as String,
      code: value['code'] as int,
      sdk: value['sdk'] as int,
      directory: value['directory'] as String,
      url: value['url'] as String? ?? defaultUpdateUrl,
      automatic: value['automatic'] as bool? ?? true,
      lastCheck: DateTime.tryParse(value['lastCheck'] as String? ?? ''),
    );
  }

  @override
  Future<void> preferences(String url, bool automatic, DateTime? checked) =>
      _channel.invokeMethod('preferences', {
        'url': url,
        'automatic': automatic,
        'lastCheck': checked?.toUtc().toIso8601String(),
      });
  Map<String, dynamic> _args(String path, AppUpdate update) => {
    'path': path,
    'code': update.code,
    'sha256': update.sha256,
  };
  @override
  Future<void> validate(String path, AppUpdate update) =>
      _channel.invokeMethod('validate', _args(path, update));
  @override
  Future<bool> canInstall() async =>
      await _channel.invokeMethod<bool>('canInstall') ?? false;
  @override
  Future<void> requestInstallPermission() =>
      _channel.invokeMethod('permission');
  @override
  Future<void> install(String path, AppUpdate update) =>
      _channel.invokeMethod('install', _args(path, update));
}

/// A separate client per operation makes cancellation close the active socket.
class UpdateTransport {
  UpdateTransport({HttpClient Function()? clientFactory})
    : _clientFactory = clientFactory ?? HttpClient.new;
  final HttpClient Function() _clientFactory;
  HttpClient? _active;
  bool _cancelled = false;
  void cancel() {
    _cancelled = true;
    _active?.close(force: true);
  }

  Future<T> _run<T>(Future<T> Function(HttpClient) operation) async {
    _cancelled = false;
    final client = _clientFactory()
      ..connectionTimeout = const Duration(seconds: 15);
    _active = client;
    try {
      return await operation(client).timeout(const Duration(minutes: 15));
    } finally {
      client.close(force: true);
      if (identical(_active, client)) _active = null;
    }
  }

  Future<HttpClientResponse> _get(HttpClient client, Uri url) async {
    for (var redirects = 0; redirects <= 5; redirects++) {
      final request = await client
          .getUrl(updateUri(url.toString()))
          .timeout(const Duration(seconds: 20));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        if (location == null) {
          throw const UpdateFailure(
            'The update server sent an invalid redirect.',
          );
        }
        url = updateUri(url.resolve(location).toString());
        continue;
      }
      if (response.statusCode != 200) {
        throw UpdateFailure(
          response.statusCode == 404
              ? 'The update file is not published yet (HTTP 404). Your installed app can still be used.'
              : 'The update server returned HTTP ${response.statusCode}. Please try again later.',
        );
      }
      return response;
    }
    throw const UpdateFailure('The update server redirected too many times.');
  }

  Future<AppUpdate> check(String url) => _run((client) async {
    final response = await _get(client, updateUri(url));
    final buffer = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 30))) {
      buffer.addAll(chunk);
      if (buffer.length > 65536) {
        throw const UpdateFailure('The update file exceeds the 64 KB limit.');
      }
    }
    return AppUpdate.parse(utf8.decode(buffer));
  });
  Future<String> download(
    AppUpdate update,
    String directory,
    void Function(int) progress,
  ) => _run((client) async {
    final folder = Directory(directory);
    await folder.create(recursive: true);
    final partial = File('$directory/update.part');
    final apk = File('$directory/update.apk');
    if (await apk.exists()) await apk.delete();
    final output = partial.openWrite();
    try {
      final response = await _get(client, update.url);
      if (response.contentLength >= 0 &&
          response.contentLength != update.bytes) {
        throw const UpdateFailure(
          'The APK size does not match the update file. No installation was started.',
        );
      }
      var received = 0;
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        if (_cancelled) throw const UpdateFailure('Download cancelled.');
        received += chunk.length;
        if (received > update.bytes) {
          throw const UpdateFailure(
            'The APK is larger than expected. No installation was started.',
          );
        }
        output.add(chunk);
        await output.flush();
        progress(received);
      }
      await output.close();
      if (received != update.bytes ||
          (await sha256.bind(partial.openRead()).first).toString() !=
              update.sha256) {
        throw const UpdateFailure(
          'APK verification failed. The download is incomplete or changed. Please download it again.',
        );
      }
      if (_cancelled) throw const UpdateFailure('Download cancelled.');
      await partial.rename(apk.path);
      return apk.path;
    } finally {
      await output.close();
      if (await partial.exists()) await partial.delete();
    }
  });
}
