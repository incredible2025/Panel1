import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_update.dart';

final updateControllerProvider = ChangeNotifierProvider<UpdateController>(
  (ref) => UpdateController(AndroidUpdatePlatform(), UpdateTransport()),
);

enum UpdateStage {
  idle,
  checking,
  available,
  current,
  downloading,
  ready,
  permission,
  installer,
  failed,
}

class UpdateController extends ChangeNotifier {
  UpdateController(this.platform, this.transport);
  final UpdatePlatform platform;
  final UpdateTransport transport;
  UpdateDevice? device;
  AppUpdate? update;
  UpdateStage stage = UpdateStage.idle;
  String get url => appUpdateManifestUrl;
  DateTime? lastCheck;
  String? error, _path;
  int received = 0;
  bool _disposed = false, _cancelled = false, _installing = false;
  Future<void>? _loading;
  bool get busy =>
      _installing ||
      stage == UpdateStage.checking ||
      stage == UpdateStage.downloading;
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() => _loading ??= _load();
  Future<void> _load() async {
    try {
      device = await platform.load();
      lastCheck = device!.url == url ? device!.lastCheck : null;
      if (device!.url != url || !device!.automatic) {
        await platform.preferences(url, true, lastCheck);
      }
    } catch (_) {
      _loading = null;
      rethrow;
    } finally {
      _changed();
    }
  }

  Future<void> autoCheck() async {
    try {
      await load();
      final elapsed = lastCheck == null
          ? null
          : DateTime.now().difference(lastCheck!);
      if (!busy &&
          (elapsed == null ||
              elapsed.isNegative ||
              elapsed >= const Duration(hours: 12))) {
        await check(quiet: true);
      }
    } catch (_) {
      /* Unsupported platforms must not prevent app startup. */
    }
  }

  Future<void> check({
    bool quiet = false,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (busy) return;
    stage = UpdateStage.checking;
    error = null;
    _changed();
    var expired = false;
    try {
      final candidate =
          await (() async {
            await load();
            if (expired || _disposed) {
              throw const UpdateFailure('Update check ended.');
            }
            return transport.check(url);
          })().timeout(
            timeout,
            onTimeout: () {
              expired = true;
              transport.cancel();
              throw TimeoutException('Update check deadline exceeded.');
            },
          );
      if (_disposed) return;
      if (candidate.code > device!.code && candidate.minSdk > device!.sdk) {
        throw UpdateFailure(
          'Version ${candidate.version} needs Android API ${candidate.minSdk} or newer. This device uses API ${device!.sdk}.',
        );
      }
      // Throttle failed automatic attempts too, without claiming they succeeded.
      lastCheck = DateTime.now();
      await platform
          .preferences(url, true, lastCheck)
          .timeout(const Duration(seconds: 3));
      update = candidate.code > device!.code ? candidate : null;
      _path = null;
      stage = update == null ? UpdateStage.current : UpdateStage.available;
    } catch (e) {
      error = describe(e);
      stage = UpdateStage.failed;
      if (quiet) {
        lastCheck = DateTime.now();
        try {
          await platform
              .preferences(url, true, lastCheck)
              .timeout(const Duration(seconds: 3));
        } catch (_) {
          /* Manual retry remains available. */
        }
      }
    }
    _changed();
  }

  Future<void> download() async {
    if (busy || update == null || device == null) return;
    stage = UpdateStage.downloading;
    received = 0;
    error = null;
    _cancelled = false;
    _changed();
    try {
      final path = await transport.download(update!, device!.directory, (
        bytes,
      ) {
        received = bytes;
        _changed();
      });
      await platform.validate(path, update!);
      if (_cancelled || _disposed) {
        throw const UpdateFailure('Download cancelled.');
      }
      _path = path;
      stage = UpdateStage.ready;
    } catch (e) {
      error = _cancelled
          ? 'Download cancelled. You can try again when ready.'
          : describe(e);
      stage = UpdateStage.failed;
    }
    _changed();
  }

  void cancel() {
    _cancelled = true;
    transport.cancel();
  }

  Future<void> install() async {
    if (_path == null || update == null || busy) return;
    _installing = true;
    _changed();
    try {
      error = null;
      await platform.validate(_path!, update!);
      if (!await platform.canInstall()) {
        stage = UpdateStage.permission;
        _changed();
        await platform.requestInstallPermission();
        return;
      }
      await platform.install(_path!, update!);
      stage = UpdateStage.installer;
    } catch (e) {
      error = describe(e);
      stage = UpdateStage.failed;
    } finally {
      _installing = false;
      _changed();
    }
  }

  static String describe(Object e) {
    if (e is UpdateFailure) return e.message;
    if (e is MissingPluginException) {
      return 'App updates are available in the Android app.';
    }
    if (e is TimeoutException) {
      return 'The update server took too long to respond. Check your connection and try again.';
    }
    if (e is PlatformException) {
      return e.message ??
          'Android could not open the update. Please try again.';
    }
    if (e is SocketException) {
      return 'Cannot reach the update server. Check your internet connection or run Connection diagnosis.';
    }
    if (e is HandshakeException) {
      return 'The update server has a TLS certificate problem. Check the device date and ask the administrator to check HTTPS.';
    }
    if (e is FileSystemException) {
      return 'The APK could not be saved. Free some device storage and try again.';
    }
    return 'The update could not finish. Check your connection and update address, then try again.';
  }

  @override
  void dispose() {
    _disposed = true;
    transport.cancel();
    super.dispose();
  }
}
