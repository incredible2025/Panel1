/// Only approved technical observations can leave the device.
class PlaybackEvidence {
  static const causes = {
    'unknown',
    'http',
    'dns',
    'tls',
    'timeout',
    'connection',
    'decoder',
    'format',
  };
  static String codec(Object? raw) {
    final value = '$raw'.toLowerCase();
    if (value.contains('://') || value.contains('@')) return 'unknown';
    for (final entry in const {
      'hevc': ['hevc', 'h265', 'hvc1', 'hev1'],
      'h264': ['h264', 'avc'],
      'av1': ['av01', 'av1'],
      'vp9': ['vp9', 'vp09'],
      'vp8': ['vp8'],
      'mpeg2': ['mpeg2', 'mp2v'],
      'mpeg4': ['mpeg4', 'mp4v'],
      'eac3': ['eac3', 'e-ac-3', 'ec-3'],
      'ac3': ['ac3', 'ac-3', 'a52'],
      'aac': ['aac', 'mp4a'],
      'dts': ['dts'],
      'opus': ['opus'],
      'vorbis': ['vorbis'],
      'mp3': ['mp3', 'mpeg-l3'],
      'pcm': ['pcm'],
    }.entries) {
      if (entry.value.any(value.contains)) return entry.key;
    }
    return 'unknown';
  }

  static Map<String, Object> sanitize(Map<dynamic, dynamic> raw) {
    final result = <String, Object>{};
    for (final key in ['video_codec', 'audio_codec']) {
      if (raw[key] != null) result[key] = codec(raw[key]);
    }
    if (causes.contains(raw['cause'])) result['cause'] = raw['cause'] as String;
    if (['hardware', 'software', 'unknown'].contains(raw['actual_decoding'])) {
      result['actual_decoding'] = raw['actual_decoding'] as String;
    }
    final decoder = raw['decoder'];
    final codecString = raw['codec_string'];
    if (codecString is String &&
        codecString.length <= 80 &&
        RegExp(
          r'^(?:avc1|avc3|hev1|hvc1|av01|vp09|mp4a)[A-Za-z0-9.,]*$',
        ).hasMatch(codecString)) {
      result['codec_string'] = codecString;
    }
    if (decoder is String &&
        RegExp(
          r'^(?:OMX\.|c2\.|mediacodec|h264|hevc|av1|vp8|vp9|mpeg|ffmpeg)[A-Za-z0-9_.-]{0,70}$',
          caseSensitive: false,
        ).hasMatch(decoder)) {
      result['decoder'] = decoder;
    }
    final code = raw['native_code'];
    if (code is String &&
        code.length <= 90 &&
        RegExp(
          r'^(?:ERROR_CODE_[A-Z0-9_]+|MPV_(?:HTTP|DECODER|FORMAT|NETWORK|GENERIC)|VLC_ENCOUNTERED_ERROR|INITIALIZATION_TIMEOUT|JAVA_(?:OUT_OF_MEMORY|ILLEGAL_STATE|LINKAGE|UNCAUGHT_EXCEPTION))$',
        ).hasMatch(code)) {
      result['native_code'] = code;
    }
    const limits = {
      'width': 16384,
      'height': 16384,
      'bitrate': 1000000000,
      'bandwidth_bps': 1000000000,
      'buffer_ms': 3600000,
      'dropped_frames': 1000000000,
      'error_number': 100000,
      'http_status': 599,
      'buffering_ms': 86400000,
    };
    for (final entry in limits.entries) {
      final value = raw[entry.key];
      if (value is num &&
          value.isFinite &&
          value >= 0 &&
          value <= entry.value &&
          (entry.key != 'http_status' || value >= 100)) {
        result[entry.key] = value.toInt();
      }
    }
    final fps = raw['fps'];
    if (fps is num && fps.isFinite && fps > 0 && fps <= 240) {
      result['fps'] = (fps * 100).round() / 100;
    }
    if (raw['first_frame'] is bool) {
      result['first_frame'] = raw['first_frame'] as bool;
    }
    return result;
  }

  static Map<String, Object> failure(String? message) {
    final value = (message ?? '')
        .replaceAll(RegExp(r'https?://\S+'), '')
        .toLowerCase();
    final http = RegExp(
      r'(?:http[^\d]{0,30}|server returned\s+|status[^\d]{0,8})([45]\d{2})\b',
    ).firstMatch(value);
    if (http != null) {
      return {
        'cause': 'http',
        'http_status': int.parse(http[1]!),
        'native_code': 'MPV_HTTP',
      };
    }
    if (RegExp(
      'decoder|mediacodec|failed to decode|unsupported codec',
    ).hasMatch(value)) {
      return {'cause': 'decoder', 'native_code': 'MPV_DECODER'};
    }
    if (RegExp('invalid data|demux|unsupported format').hasMatch(value)) {
      return {'cause': 'format', 'native_code': 'MPV_FORMAT'};
    }
    if (RegExp('network|connection|socket|timed out').hasMatch(value)) {
      return {'cause': 'connection', 'native_code': 'MPV_NETWORK'};
    }
    return {'cause': 'unknown', 'native_code': 'MPV_GENERIC'};
  }
}
