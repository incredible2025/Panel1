import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:streamline_iptv/data/app_update.dart';
import 'package:streamline_iptv/data/public_release_notes.dart';

import 'app_update_test.dart' show manifest;

void main() {
  final vectors =
      jsonDecode(
            File('test/fixtures/public_release_notes.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
  test('customer summaries remain brief and headings are removed', () {
    for (final source in vectors['safe'] as List) {
      expect(publicReleaseNotes(source as String), isNot(defaultReleaseNotes));
    }
    expect(publicReleaseNotes(vectors['safe'].last), '- Improved browsing.');
  });
  test('unsafe legacy notes never prevent a valid update being offered', () {
    for (final source in [
      ...vectors['unsafe'] as List,
      'x' * 161,
      'x\n' * 301,
      '',
      '# Version',
    ]) {
      final update = AppUpdate.parse(
        jsonEncode({...manifest(), 'releaseNotes': source}),
      );
      expect(update.code, 9);
      expect(update.publicNotes, defaultReleaseNotes);
      expect(update.url, Uri.parse(manifest()['apkUrl']));
    }
  });
  test('directly constructed updates use the same display protection', () {
    final update = AppUpdate(
      version: '0.8.7',
      code: 27,
      url: Uri.parse('https://updates.example/app.apk'),
      sha256: '0' * 64,
      bytes: 3,
      minSdk: 24,
      notes: vectors['unsafe'].first,
      packageId: 'com.streamline.iptv',
    );
    expect(update.publicNotes, defaultReleaseNotes);
  });
}
