import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:streamline_iptv/data/app_update.dart';
import 'package:streamline_iptv/core/update_controller.dart';
import 'app_update_test.dart'
    show manifest, FakePlatform, FakeTransport, Client, bytes;

Map<String, dynamic> windowsManifest() =>
    {
        ...manifest(code: 29),
        'applicationId': 'com.streamline.iptv.windows',
        'platform': 'windows-x64',
        'minWindowsBuild': 19041,
        'installerUrl': 'Ultravpn-player-Setup-0.8.9.exe',
      }
      ..remove('apkUrl')
      ..remove('minSdk');

void main() {
  test('Windows and Android updates cannot be installed interchangeably', () {
    final source = jsonEncode(windowsManifest());
    final update = AppUpdate.parse(
      source,
      sourceUri: Uri.parse('https://updates.example/windows-update.json'),
      target: UpdateTarget.windows,
    );
    expect(update.target, UpdateTarget.windows);
    expect(update.fileExtension, 'exe');
    expect(update.url.path, '/Ultravpn-player-Setup-0.8.9.exe');
    expect(() => AppUpdate.parse(source), throwsA(isA<UpdateFailure>()));
    expect(
      () =>
          AppUpdate.parse(jsonEncode(manifest()), target: UpdateTarget.windows),
      throwsA(isA<UpdateFailure>()),
    );
    expect(windowsUpdateManifestUrl, isNot(appUpdateManifestUrl));
    expect(
      Uri.parse(windowsUpdateManifestUrl).path,
      endsWith('/windows-update.json'),
    );
  });
  test('Windows requirements explain Windows compatibility', () async {
    final transport = FakeTransport()
      ..next = AppUpdate.parse(
        jsonEncode(windowsManifest()),
        sourceUri: Uri.parse('https://updates.example/windows-update.json'),
        target: UpdateTarget.windows,
      );
    final controller = UpdateController(
      FakePlatform(),
      transport,
      manifestUrl: windowsUpdateManifestUrl,
    );
    addTearDown(controller.dispose);
    await controller.check();
    expect(transport.checkedUrl, windowsUpdateManifestUrl);
    expect(controller.stage, UpdateStage.failed);
    expect(controller.error, contains('Windows build'));
    expect(controller.error, isNot(contains('Android')));
  });
  test('installer transport uses the correct Windows extension', () async {
    final directory = await Directory.systemTemp.createTemp(
      'windows-update-test',
    );
    addTearDown(() => directory.delete(recursive: true));
    final source = windowsManifest();
    final update = AppUpdate.parse(
      jsonEncode(source),
      sourceUri: Uri.parse('https://updates.example/windows-update.json'),
      target: UpdateTarget.windows,
    );
    final transport = UpdateTransport(
      target: UpdateTarget.windows,
      clientFactory: () => Client([
        bytes([1, 2, 3], length: 3),
      ]),
    );
    final file = await transport.download(update, directory.path, (_) {});
    expect(file, endsWith('update.exe'));
    expect(await File(file).readAsBytes(), [1, 2, 3]);
    expect(await File('${directory.path}/update.part').exists(), false);
  });
}
