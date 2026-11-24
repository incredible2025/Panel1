import 'package:flutter_test/flutter_test.dart';
import 'package:streamline_iptv/data/playback_evidence.dart';

void main() {
  test('only bounded technical evidence survives sanitization', () {
    final result = PlaybackEvidence.sanitize({
      'video_codec': 'video/hevc',
      'audio_codec': 'audio/eac3',
      'width': 1920,
      'height': 1080,
      'fps': 50.0,
      'actual_decoding': 'hardware',
      'decoder': 'OMX.vendor.hevc.decoder',
      'native_code': 'ERROR_CODE_DECODER_INIT_FAILED',
      'error_number': 4001,
      'url': 'https://private.example.test/user/pass',
      'message': 'secret',
      'http_status': 999,
      'buffer_ms': double.infinity,
      'bitrate': -10,
    });
    expect(result['video_codec'], 'hevc');
    expect(result['audio_codec'], 'eac3');
    expect(result['decoder'], 'OMX.vendor.hevc.decoder');
    for (final field in [
      'url',
      'message',
      'http_status',
      'buffer_ms',
      'bitrate',
    ]) {
      expect(result, isNot(contains(field)));
    }
  });
  test('an address cannot masquerade as a codec or decoder', () {
    expect(
      PlaybackEvidence.codec('https://private.example.test/hevc'),
      'unknown',
    );
    expect(
      PlaybackEvidence.sanitize({
        'decoder': 'https://private.example.test',
        'native_code': 'secret-token',
      }),
      isEmpty,
    );
  });
  test(
    'MPV classification emits fixed evidence and discards the error message',
    () {
      final result = PlaybackEvidence.failure(
        'HTTP error 403 at https://private.example.test/user/pass',
      );
      expect(result, {
        'cause': 'http',
        'http_status': 403,
        'native_code': 'MPV_HTTP',
      });
      expect(
        PlaybackEvidence.failure('Failed to initialize decoder')['cause'],
        'decoder',
      );
    },
  );
}
