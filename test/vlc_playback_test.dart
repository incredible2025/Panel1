import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streamline_iptv/core/vlc_playback.dart';
import 'package:streamline_iptv/data/app_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const methods = MethodChannel('streamline/vlc');
  const events = MethodChannel('streamline/vlc/events');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  Future<void> send(Map<String, Object?> value) async {
    await messenger.handlePlatformMessage(
      'streamline/vlc/events',
      const StandardMethodCodec().encodeSuccessEnvelope(value),
      (_) {},
    );
  }

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(events, (_) async => null);
    messenger.setMockMethodCallHandler(methods, (call) async {
      calls.add(call);
      if (call.method == 'create') return 7;
      if (call.method == 'load') {
        await send({
          'id': 7,
          'ready': true,
          'playing': true,
          'duration': 60000,
          'width': 1920,
          'height': 1080,
        });
      }
      return null;
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(methods, null);
    messenger.setMockMethodCallHandler(events, null);
  });
  test(
    'VLC loads muted, pauses after probing and preserves preview mute on Play',
    () async {
      final handle = VlcPlayback(Uri.parse('https://example.invalid/live'));
      handle.configure(DecodingMode.software);
      await handle.initialize();
      expect(handle.value.isInitialized, true);
      expect(calls.first.arguments['decoding'], 'software');
      expect(
        calls.map((c) => c.method),
        containsAllInOrder(['create', 'load', 'pause']),
      );
      await handle.setVolume(0);
      await handle.play();
      expect(
        calls.where((c) => c.method == 'volume').last.arguments['volume'],
        0,
      );
      await handle.dispose();
      await handle.dispose();
      expect(calls.where((c) => c.method == 'dispose').length, 1);
    },
  );
  test(
    'a late creation after disposal is closed without loading media',
    () async {
      final gate = Completer<int>();
      messenger.setMockMethodCallHandler(methods, (call) async {
        calls.add(call);
        if (call.method == 'create') return gate.future;
        return null;
      });
      final handle = VlcPlayback(Uri.parse('https://example.invalid/live'));
      final opening = handle.initialize();
      await Future<void>.delayed(Duration.zero);
      await handle.dispose();
      gate.complete(8);
      await opening;
      expect(calls.map((c) => c.method), ['create', 'dispose']);
      expect(calls.last.arguments['id'], 8);
    },
  );
  test(
    'VLC errors expose a safe failure without native connection details',
    () async {
      final handle = VlcPlayback(Uri.parse('https://example.invalid/private'));
      await handle.initialize();
      await send({
        'id': 7,
        'error': true,
        'uri': 'https://private.example/password',
      });
      expect(handle.value.hasError, true);
      expect(handle.value.errorDescription, 'VLC playback unavailable.');
      await handle.dispose();
    },
  );
}
