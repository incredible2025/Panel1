package io.flutter.plugins.videoplayer;

import androidx.annotation.OptIn;
import androidx.media3.common.Format;
import androidx.media3.common.PlaybackException;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.datasource.HttpDataSource;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.exoplayer.ExoPlaybackException;
import androidx.media3.exoplayer.analytics.AnalyticsListener;
import androidx.media3.exoplayer.mediacodec.MediaCodecInfo;
import androidx.media3.exoplayer.mediacodec.MediaCodecUtil;
import java.net.ConnectException;
import java.net.SocketTimeoutException;
import java.net.UnknownHostException;
import javax.net.ssl.SSLException;
import java.util.HashMap;
import java.util.Map;
import java.util.WeakHashMap;

/** Numeric observations and fixed codes only. Never exports exceptions, URIs or headers. */
@OptIn(markerClass = UnstableApi.class)
final class PlaybackDiagnostics implements AnalyticsListener {
  private static final Map<ExoPlayer, PlaybackDiagnostics> states = new WeakHashMap<>();
  private String decoder = "";
  private int dropped = 0;
  private boolean firstFrame = false;
  private long bandwidth = 0;
  @Override public void onBandwidthEstimate(EventTime time, int elapsedMs, long bytes, long estimate) {
    bandwidth = Math.max(0L, estimate);
  }

  static void install(ExoPlayer player) {
    PlaybackDiagnostics state = new PlaybackDiagnostics();
    states.put(player, state);
    player.addAnalyticsListener(state);
  }

  @Override public void onVideoDecoderInitialized(EventTime time, String name, long timestamp, long duration) {
    decoder = name;
  }

  @Override public void onDroppedVideoFrames(EventTime time, int count, long elapsed) {
    dropped += Math.max(0, count);
  }

  @Override public void onRenderedFirstFrame(EventTime time, Object output, long renderTime) {
    firstFrame = true;
  }

  static Map<String, Object> snapshot(ExoPlayer player) {
    Map<String, Object> result = new HashMap<>();
    PlaybackDiagnostics state = states.get(player);
    PlaybackException error = player.getPlayerError();
    Format video = player.getVideoFormat(), audio = player.getAudioFormat();
    if (error instanceof ExoPlaybackException) {
      Format failedFormat = ((ExoPlaybackException) error).rendererFormat;
      if (failedFormat != null && failedFormat.sampleMimeType != null) {
        if (video == null && failedFormat.sampleMimeType.startsWith("video/")) video = failedFormat;
        if (audio == null && failedFormat.sampleMimeType.startsWith("audio/")) audio = failedFormat;
      }
    }
    if (video != null) {
      result.put("video_codec", video.sampleMimeType);
      if (video.codecs != null) result.put("codec_string", video.codecs);
      if (video.width > 0) result.put("width", video.width);
      if (video.height > 0) result.put("height", video.height);
      if (video.frameRate > 0) result.put("fps", (double) video.frameRate);
      if (video.bitrate > 0) result.put("bitrate", video.bitrate);
    }
    if (audio != null) result.put("audio_codec", audio.sampleMimeType);
    if (state != null) {
      result.put("decoder", state.decoder);
      result.put("dropped_frames", state.dropped);
      result.put("first_frame", state.firstFrame);
      if (state.bandwidth > 0) result.put("bandwidth_bps", state.bandwidth);
      if (video != null && video.sampleMimeType != null && !state.decoder.isEmpty()) {
        try {
          for (MediaCodecInfo info : MediaCodecUtil.getDecoderInfos(video.sampleMimeType, false, false)) {
            if (info.name.equals(state.decoder)) {
              result.put("actual_decoding", info.hardwareAccelerated ? "hardware" : "software");
              break;
            }
          }
        } catch (MediaCodecUtil.DecoderQueryException ignored) { }
      }
    }
    result.put("buffer_ms", Math.max(0L, player.getTotalBufferedDuration()));
    if (error != null) {
      result.put("native_code", error.getErrorCodeName());
      result.put("error_number", error.errorCode);
      String cause = "unknown";
      Throwable current = error;
      for (int i = 0; current != null && i < 8; i++, current = current.getCause()) {
        if (current instanceof HttpDataSource.InvalidResponseCodeException) {
          result.put("http_status", ((HttpDataSource.InvalidResponseCodeException) current).responseCode);
          cause = "http";
          break;
        }
        if (current instanceof UnknownHostException) cause = "dns";
        else if (current instanceof SSLException) cause = "tls";
        else if (current instanceof SocketTimeoutException) cause = "timeout";
        else if (current instanceof ConnectException) cause = "connection";
      }
      if (cause.equals("unknown") && error.errorCode >= 4000 && error.errorCode < 5000) cause = "decoder";
      if (cause.equals("unknown") && error.errorCode >= 3000 && error.errorCode < 4000) cause = "format";
      result.put("cause", cause);
    }
    return result;
  }
}
