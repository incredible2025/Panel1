import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_update.dart';
import '../data/windows_update_platform.dart';
import '../data/managed_configuration.dart';
import 'providers.dart';

final updateControllerProvider = ChangeNotifierProvider<UpdateController>(
  (ref) => Platform.isWindows
      ? UpdateController(
          WindowsUpdatePlatform(),
          UpdateTransport(target: UpdateTarget.windows),
          manifestUrl: windowsUpdateManifestUrl,
        )
      : UpdateController(
          AndroidUpdatePlatform(),
          UpdateTransport(
            expectedAndroidApplicationId: androidApplicationId,
            headersFor: (uri) =>
                ref
                    .read(managedConfigurationProvider)
                    ?.activity
                    ?.updateHeaders(uri) ??
                const {},
          ),
          manifestUrlProvider: () =>
              ref
                  .read(managedConfigurationProvider)
                  ?.current
                  .updateManifestUrl ??
              appUpdateManifestUrl,
        ),
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
  UpdateController(
    this.platform,
    this.transport, {
    this.manifestUrl = appUpdateManifestUrl,
    this.manifestUrlProvider,
  });
  final UpdatePlatform platform;
  final UpdateTransport transport;
  UpdateDevice? device;
  AppUpdate? update;
  UpdateStage stage = UpdateStage.idle;
  final String manifestUrl;
  final String Function()? manifestUrlProvider;
  String get url => manifestUrlProvider?.call() ?? manifestUrl;
  int _generation = 0;
  void sourceChanged() {
    _generation++;
    cancel();
    update = null;
    _path = null;
    lastCheck = null;
    error = null;
    stage = UpdateStage.idle;
    _changed();
  }

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
        try {
          await platform
              .preferences(url, true, lastCheck)
              .timeout(const Duration(seconds: 3));
        } catch (_) {
          /* Optional preferences must not disable updates. */
        }
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
    final generation = _generation;
    final source = url;
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
            return transport.check(source);
          })().timeout(
            timeout,
            onTimeout: () {
              expired = true;
              transport.cancel();
              throw TimeoutException('Update check deadline exceeded.');
            },
          );
      if (_disposed || generation != _generation || source != url) return;
      if (candidate.code > device!.code && candidate.minSdk > device!.sdk) {
        throw UpdateFailure(
          candidate.target == UpdateTarget.windows
              ? 'This update needs Windows build ${candidate.minSdk} or newer. Update Windows and try again.'
              : 'Version ${candidate.version} needs Android API ${candidate.minSdk} or newer. This device uses API ${device!.sdk}.',
        );
      }
      // Throttle failed automatic attempts too, without claiming they succeeded.
      lastCheck = DateTime.now();
      try {
        await platform
            .preferences(url, true, lastCheck)
            .timeout(const Duration(seconds: 3));
      } catch (_) {
        /* A valid update remains available without saved preferences. */
      }
      if (_disposed || generation != _generation || source != url) return;
      update = candidate.code > device!.code ? candidate : null;
      _path = null;
      stage = update == null ? UpdateStage.current : UpdateStage.available;
    } catch (e) {
      if (_disposed || generation != _generation) return;
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
    final generation = _generation;
    final candidate = update!;
    stage = UpdateStage.downloading;
    received = 0;
    error = null;
    _cancelled = false;
    _changed();
    try {
      final path = await transport.download(candidate, device!.directory, (
        bytes,
      ) {
        if (generation != _generation) return;
        received = bytes;
        _changed();
      });
      if (generation != _generation) return;
      await platform.validate(path, candidate);
      if (_cancelled || _disposed || generation != _generation) {
        throw const UpdateFailure('Download cancelled.');
      }
      _path = path;
      stage = UpdateStage.ready;
    } catch (e) {
      if (_disposed || generation != _generation) return;
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
    final generation = _generation;
    final candidate = update!;
    final path = _path!;
    _installing = true;
    _changed();
    try {
      error = null;
      await platform.validate(path, candidate);
      if (generation != _generation) return;
      if (!await platform.canInstall()) {
        stage = UpdateStage.permission;
        _changed();
        await platform.requestInstallPermission();
        return;
      }
      if (generation != _generation) return;
      await platform.install(path, candidate);
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
      return 'App updates are unavailable in this build.';
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
      return 'The update file could not be saved. Free some device storage and try again.';
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
