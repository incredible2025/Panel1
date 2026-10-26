import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/app_version.dart';
import 'app_update.dart';

class WindowsUpdatePlatform implements UpdatePlatform {
  WindowsUpdatePlatform({this.directoryProvider});
  final Future<Directory> Function()? directoryProvider;
  Future<Directory> _root() async {
    final root = await (directoryProvider ?? getApplicationSupportDirectory)();
    await root.create(recursive: true);
    return root;
  }

  @override
  Future<UpdateDevice> load() async {
    final root = await _root();
    DateTime? checked;
    try {
      final saved =
          jsonDecode(
                await File(
                  p.join(root.path, 'windows-updates.json'),
                ).readAsString(),
              )
              as Map;
      checked = DateTime.tryParse(saved['lastCheck'] as String? ?? '');
    } catch (_) {
      // Missing or damaged check metadata must not prevent manual updates.
    }
    final match = RegExp(
      r'\b(?:10\.0\.|Build\s+)(\d+)',
    ).firstMatch(Platform.operatingSystemVersion);
    return UpdateDevice(
      version: appVersionName,
      code: appBuildNumber,
      sdk: int.tryParse(match?.group(1) ?? '') ?? 19041,
      directory: p.join(root.path, 'updates'),
      url: windowsUpdateManifestUrl,
      automatic: true,
      lastCheck: checked,
    );
  }

  @override
  Future<void> preferences(
    String url,
    bool automatic,
    DateTime? checked,
  ) async {
    final root = await _root();
    await File(p.join(root.path, 'windows-updates.json')).writeAsString(
      jsonEncode({'lastCheck': checked?.toUtc().toIso8601String()}),
      flush: true,
    );
  }

  @override
  Future<void> validate(String path, AppUpdate update) async {
    final expected = p.join((await _root()).path, 'updates', 'update.exe');
    if (update.target != UpdateTarget.windows ||
        update.packageId != 'com.streamline.iptv.windows' ||
        p.normalize(p.absolute(path)) != p.normalize(expected)) {
      throw const UpdateFailure('This is not a compatible Windows update.');
    }
    final file = File(path);
    if (await file.length() != update.bytes ||
        (await sha256.bind(file.openRead()).first).toString() !=
            update.sha256) {
      throw const UpdateFailure(
        'Installer verification failed. Download the update again.',
      );
    }
    final handle = await file.open();
    try {
      final header = await handle.read(64);
      if (header.length < 64 || header[0] != 0x4d || header[1] != 0x5a) {
        throw const UpdateFailure('The download is not a Windows installer.');
      }
    } finally {
      await handle.close();
    }
    final powershell = p.join(
      Platform.environment['SystemRoot'] ?? r'C:\Windows',
      'System32',
      'WindowsPowerShell',
      'v1.0',
      'powershell.exe',
    );
    final metadata = await Process.run(
      powershell,
      [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r'$v=(Get-Item -LiteralPath $env:ULTRAVPN_UPDATE_INSTALLER).VersionInfo; $n=@($v.FileMajorPart,$v.FileMinorPart,$v.FileBuildPart,$v.FilePrivatePart)-join "."; [Console]::Write(($v.ProductName.Trim()+"|"+$n))',
      ],
      environment: {'ULTRAVPN_UPDATE_INSTALLER': path},
    ).timeout(const Duration(seconds: 10));
    if (metadata.exitCode != 0 ||
        metadata.stdout.toString().trim() !=
            'Ultravpn-player|${update.version}.${update.code}') {
      throw const UpdateFailure(
        'The Windows installer identity or version does not match the update.',
      );
    }
  }

  @override
  Future<bool> canInstall() async => true;
  @override
  Future<void> requestInstallPermission() async {}
  @override
  Future<void> install(String path, AppUpdate update) async {
    await validate(path, update);
    await Process.start(path, [
      '/SP-',
      '/NORESTART',
    ], mode: ProcessStartMode.detached);
  }
}
