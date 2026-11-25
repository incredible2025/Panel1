import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:streamline_iptv/data/managed_activity.dart';
import 'package:streamline_iptv/data/managed_configuration.dart';

void main() {
  test(
    'foreground reports anonymous version/revision and background stops reporting',
    () async {
      final requests = <http.Request>[];
      var revision = 1;
      final activity = ManagedActivity(
        configUrl: Uri.parse(
          'https://manager.example.test/api/v1/apps/example/config',
        ),
        secret: 'a' * 64,
        revision: () => revision,
        clientFactory: () => MockClient((request) async {
          requests.add(request);
          return http.Response('', 204);
        }),
      );
      addTearDown(activity.dispose);
      await activity.report();
      expect(requests, isEmpty);
      activity.foreground(true);
      await activity.report();
      expect(requests, hasLength(1));
      expect(requests.single.url.path, endsWith('/activity'));
      expect(jsonDecode(requests.single.body).keys.toSet(), {
        'version',
        'build',
        'revision',
      });
      expect(requests.single.headers['Authorization'], 'Bearer ${'a' * 64}');
      expect(activity.lastReported, isNotNull);
      revision = 2;
      await activity.report();
      expect(jsonDecode(requests.last.body)['revision'], 2);
      activity.foreground(false);
      await activity.report();
      expect(requests, hasLength(2));
    },
  );

  test(
    'installation credential is restricted to the exact managed update endpoint',
    () {
      final activity = ManagedActivity(
        configUrl: Uri.parse('https://manager.example.test/apps/one/config'),
        secret: 'b' * 64,
        revision: () => 1,
      );
      addTearDown(activity.dispose);
      expect(
        activity.updateHeaders(
          Uri.parse('https://manager.example.test/apps/one/updates'),
        ),
        isNotEmpty,
      );
      for (final address in [
        'https://manager.example.test/apps/two/updates',
        'https://manager.example.test/apps/one/updates?q=1',
        'https://other.example.test/apps/one/updates',
        'https://manager.example.test/downloads/player.apk',
        'http://manager.example.test/apps/one/updates',
      ]) {
        expect(activity.updateHeaders(Uri.parse(address)), isEmpty);
      }
    },
  );

  test(
    'report failures are silent and do not acknowledge configuration',
    () async {
      final activity = ManagedActivity(
        configUrl: Uri.parse('https://manager.example.test/config'),
        secret: 'c' * 64,
        revision: () => 1,
        clientFactory: () =>
            MockClient((_) async => http.Response('error', 503)),
      );
      addTearDown(activity.dispose);
      activity.foreground(true);
      await activity.report();
      expect(activity.lastReported, isNull);
    },
  );

  test(
    'pairing requires a bounded six digit code and never follows redirects',
    () async {
      final activity = ManagedActivity(
        configUrl: Uri.parse('https://manager.example.test/config'),
        secret: 'd' * 64,
        revision: () => 1,
        clientFactory: () => MockClient((request) async {
          expect(request.followRedirects, false);
          return request.url.path == '/pair'
              ? http.Response('{"code":"123456"}', 200)
              : http.Response('', 204);
        }),
      );
      addTearDown(activity.dispose);
      activity.foreground(true);
      expect(await activity.pairCode(), '123456');
    },
  );

  test(
    'maintenance notices expire and invalid support transport is rejected',
    () {
      final notice = ManagedNotice.parse({
        'id': '2',
        'title': 'Maintenance',
        'body': 'Back shortly.',
        'expiresAt': '2026-11-10T10:00:00Z',
      })!;
      expect(notice.activeAt(DateTime.parse('2026-11-10T09:59:59Z')), true);
      expect(notice.activeAt(DateTime.parse('2026-11-10T10:00:00Z')), false);
      expect(ManagedNotice.parse(null), isNull);
      expect(ManagedSupport.parse(null).email, isEmpty);
      expect(
        () => ManagedSupport.parse({'website': 'http://insecure.example.test'}),
        throwsFormatException,
      );
    },
  );
}
