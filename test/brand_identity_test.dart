import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:streamline_iptv/core/app_brand.dart';
import 'package:streamline_iptv/core/app_version.dart';
import 'package:streamline_iptv/data/app_update.dart';
import 'package:streamline_iptv/data/managed_configuration.dart';
import 'package:streamline_iptv/data/provider_addresses.dart';

void main() {
  test('selected package verifies only its own signed bootstrap', () async {
    final profile = ManagedProfile.parse(managedProfileJson);
    final configuration = await profile.verify(profile.bootstrap);
    expect(profile.packageId, androidApplicationId);
    expect(configuration.endpoints, isNotEmpty);
    if (profile.appId != 'ultravpn-player') {
      expect(appBrandName, isNot('Ultravpn-player'));
      expect(managedLegacyServiceId, isEmpty);
      expect(providerPortalUrl, configuration.endpoints.first.toString());
      expect(providerFallbackUrl, configuration.endpoints.last.toString());
      expect(appUpdateManifestUrl, configuration.updateManifestUrl);
      final primary = ManagedProfile.parse(
        primaryManagedProfileJson,
        packageId: 'com.streamline.iptv',
      );
      await expectLater(
        profile.verify(primary.bootstrap),
        throwsFormatException,
      );
    }
  });

  test(
    'selected brand update identity and version match the compiled display',
    () {
      final update = {
        'schemaVersion': 1,
        'applicationId': androidApplicationId,
        'versionName': appVersionName,
        'versionCode': appBuildNumber,
        'minSdk': 24,
        'apkUrl': 'https://updates.example.test/app.apk',
        'sizeBytes': 100,
        'sha256': 'a' * 64,
        'releaseNotes': '- Improvements.\n- Fixes.\n',
      };
      expect(
        AppUpdate.parse(
          jsonEncode(update),
          expectedAndroidApplicationId: androidApplicationId,
        ).code,
        appBuildNumber,
      );
      final other = androidApplicationId == 'com.streamline.iptv'
          ? 'com.example.other'
          : 'com.streamline.iptv';
      expect(
        () => AppUpdate.parse(
          jsonEncode({...update, 'applicationId': other}),
          expectedAndroidApplicationId: androidApplicationId,
        ),
        throwsA(isA<UpdateFailure>()),
      );
    },
  );
}
