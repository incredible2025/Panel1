import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:streamline_iptv/data/app_settings.dart';
import 'package:streamline_iptv/data/managed_activity.dart';
import 'package:streamline_iptv/data/playback_reporting.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    messenger.setMockMethodCallHandler(PlaybackReporting.platform, (
      call,
    ) async {
      if (call.method == 'playbackDevice') {
        return {'model': 'Example TV', 'release': '14', 'tv': true};
      }
      return null;
    });
  });
  tearDown(
    () => messenger.setMockMethodCallHandler(PlaybackReporting.platform, null),
  );

  ManagedActivity presence() {
    final activity = ManagedActivity(
      configUrl: Uri.parse(
        'https://management.example.test/api/v1/apps/brand/config',
      ),
      secret: 'a' * 64,
      revision: () => 1,
      clientFactory: () => MockClient((_) async => http.Response('', 204)),
    );
    addTearDown(activity.dispose);
    return activity;
  }

  test(
    'reports contain fixed metadata and suppress duplicate error storms',
    () async {
      final requests = <http.Request>[];
      final reporting = PlaybackReporting(
        presence(),
        clientFactory: () => MockClient((request) async {
          requests.add(request);
          return http.Response('', 204);
        }),
      );
      addTearDown(reporting.dispose);
      Future<bool> send() => reporting.report(
        PlaybackIssue.decoder,
        engine: PlayerEngine.vlc,
        decoding: DecodingMode.hardware,
        kind: 'live',
      );
      expect(await send(), isTrue);
      expect(await send(), isFalse);
      expect(requests, hasLength(1));
      final request = requests.single;
      expect(request.followRedirects, isFalse);
      expect(request.url.path, '/api/v1/apps/brand/playback');
      final body = jsonDecode(request.body) as Map;
      expect(body.keys.toSet(), {
        'event_id',
        'version',
        'build',
        'device_model',
        'os_version',
        'form_factor',
        'engine',
        'decoding',
        'kind',
        'category',
        'source',
      });
      expect(body['category'], 'decoder');
      expect(body['device_model'], 'Example TV');
      expect(body['source'], 'automatic');
      expect(body['event_id'], matches(RegExp(r'^[a-f0-9-]{36}$')));
    },
  );

  test(
    'manual reports stay distinct and network rejection stays nonfatal',
    () async {
      http.Request? sent;
      final reporting = PlaybackReporting(
        presence(),
        clientFactory: () => MockClient((request) async {
          sent = request;
          return http.Response('', 503);
        }),
      );
      addTearDown(reporting.dispose);
      expect(
        await reporting.report(
          PlaybackIssue.greenScreen,
          engine: PlayerEngine.native,
          decoding: DecodingMode.automatic,
          kind: 'movie',
        ),
        isFalse,
      );
      expect(jsonDecode(sent!.body)['source'], 'user');
      expect(jsonDecode(sent!.body)['category'], 'green_screen');
      reporting.dispose();
      expect(
        await reporting.report(
          PlaybackIssue.buffering,
          engine: PlayerEngine.native,
          decoding: DecodingMode.automatic,
          kind: 'live',
        ),
        isFalse,
      );
    },
  );

  test(
    'crash acknowledgement happens only after successful ingestion',
    () async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(PlaybackReporting.platform, (
        call,
      ) async {
        calls.add(call.method);
        if (call.method == 'previousPlaybackCrash') {
          return {
            'id': '11111111-1111-4111-8111-111111111111',
            'engine': 'vlc',
            'decoding': 'hardware',
            'kind': 'live',
          };
        }
        if (call.method == 'playbackDevice') {
          return {'model': 'Example Phone', 'release': '15', 'tv': false};
        }
        return null;
      });
      var success = false;
      PlaybackReporting reporter() => PlaybackReporting(
        presence(),
        clientFactory: () =>
            MockClient((_) async => http.Response('', success ? 204 : 503)),
      );
      final first = reporter();
      await first.reportPreviousCrash();
      first.dispose();
      expect(calls, isNot(contains('acknowledgePlaybackCrash')));
      success = true;
      final second = reporter();
      await second.reportPreviousCrash();
      second.dispose();
      expect(calls, contains('acknowledgePlaybackCrash'));
    },
  );
}
