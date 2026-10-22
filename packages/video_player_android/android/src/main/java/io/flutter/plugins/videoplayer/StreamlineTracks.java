package io.flutter.plugins.videoplayer;

import android.graphics.Bitmap;
import androidx.annotation.OptIn;
import androidx.media3.common.C;
import androidx.media3.common.Format;
import androidx.media3.common.Player;
import androidx.media3.common.TrackSelectionOverride;
import androidx.media3.common.Tracks;
import androidx.media3.common.text.Cue;
import androidx.media3.common.text.CueGroup;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.exoplayer.ExoPlayer;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodChannel;
import java.io.ByteArrayOutputStream;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.function.LongFunction;

/** App-scoped track controls. No stream URI or native exception is sent to Flutter. */
@OptIn(markerClass = UnstableApi.class)
final class StreamlineTracks implements EventChannel.StreamHandler {
  private final MethodChannel methods;
  private final EventChannel events;
  private final LongFunction<ExoPlayer> players;
  private ExoPlayer observed;
  private long observedId = -1;
  private EventChannel.EventSink sink;
  private final Player.Listener listener = new Player.Listener() {
    @Override public void onTracksChanged(Tracks tracks) { emit(); }
    @Override public void onCues(CueGroup cues) { emit(); }
  };

  StreamlineTracks(BinaryMessenger messenger, LongFunction<ExoPlayer> players) {
    this.players = players;
    methods = new MethodChannel(messenger, "streamline/player_tracks");
    events = new EventChannel(messenger, "streamline/player_tracks/events");
    events.setStreamHandler(this);
    methods.setMethodCallHandler((call, result) -> {
      try {
        Number id = call.argument("playerId");
        if (id == null) throw new IllegalArgumentException();
        ExoPlayer player = players.apply(id.longValue());
        if (call.method.equals("snapshot")) {
          result.success(snapshot(player));
        } else if (call.method.equals("select")) {
          String type = call.argument("type");
          String key = call.argument("key");
          select(player, "audio".equals(type) ? C.TRACK_TYPE_AUDIO : C.TRACK_TYPE_TEXT, key);
          result.success(snapshot(player));
        } else { result.notImplemented(); }
      } catch (RuntimeException error) {
        result.error("tracks_unavailable", "Audio and subtitles are unavailable for this stream.", null);
      }
    });
  }

  private void select(ExoPlayer player, int type, String key) {
    if (key == null) throw new IllegalArgumentException();
    if (key.equals("off") && type != C.TRACK_TYPE_TEXT) throw new IllegalArgumentException();
    androidx.media3.common.TrackSelectionParameters.Builder builder = player.getTrackSelectionParameters()
        .buildUpon().clearOverridesOfType(type).setTrackTypeDisabled(type, key.equals("off"));
    if (!key.equals("off") && !key.equals("auto")) {
      String[] parts = key.split(":");
      if (parts.length != 2) throw new IllegalArgumentException();
      int groupIndex = Integer.parseInt(parts[0]);
      int index = Integer.parseInt(parts[1]);
      Tracks tracks = player.getCurrentTracks();
      if (groupIndex < 0 || groupIndex >= tracks.getGroups().size()) throw new IllegalArgumentException();
      Tracks.Group group = tracks.getGroups().get(groupIndex);
      if (group.getType() != type || index < 0 || index >= group.length || !group.isTrackSupported(index)) {
        throw new IllegalArgumentException();
      }
      builder.setOverrideForType(new TrackSelectionOverride(group.getMediaTrackGroup(), index));
    }
    player.setTrackSelectionParameters(builder.build());
  }

  private Map<String, Object> snapshot(ExoPlayer player) {
    Map<String, Object> data = new HashMap<>();
    List<Map<String, Object>> available = new ArrayList<>();
    Tracks tracks = player.getCurrentTracks();
    for (int g = 0; g < tracks.getGroups().size(); g++) {
      Tracks.Group group = tracks.getGroups().get(g);
      int type = group.getType();
      if (type != C.TRACK_TYPE_AUDIO && type != C.TRACK_TYPE_TEXT) continue;
      for (int i = 0; i < group.length; i++) {
        Format format = group.getTrackFormat(i);
        Map<String, Object> track = new HashMap<>();
        track.put("key", g + ":" + i);
        track.put("type", type == C.TRACK_TYPE_AUDIO ? "audio" : "text");
        String label = format.label;
        if (label == null || label.trim().isEmpty()) label = format.language;
        if (label == null || label.trim().isEmpty()) label = (type == C.TRACK_TYPE_AUDIO ? "Audio " : "Subtitles ") + (i + 1);
        track.put("label", label);
        track.put("language", format.language == null ? "" : format.language);
        track.put("selected", group.isTrackSelected(i));
        track.put("supported", group.isTrackSupported(i));
        available.add(track);
      }
    }
    data.put("tracks", available);
    data.put("textOff", player.getTrackSelectionParameters().disabledTrackTypes.contains(C.TRACK_TYPE_TEXT));
    boolean audioAuto = true;
    for (TrackSelectionOverride override : player.getTrackSelectionParameters().overrides.values()) {
      if (override.getType() == C.TRACK_TYPE_AUDIO) audioAuto = false;
    }
    data.put("audioAuto", audioAuto);
    StringBuilder caption = new StringBuilder();
    List<byte[]> images = new ArrayList<>();
    for (Cue cue : player.getCurrentCues().cues) {
      if (cue.text != null) {
        if (caption.length() > 0) caption.append('\n');
        caption.append(cue.text);
      }
      if (cue.bitmap != null) {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        cue.bitmap.compress(Bitmap.CompressFormat.PNG, 100, output);
        images.add(output.toByteArray());
      }
    }
    data.put("caption", caption.toString());
    data.put("images", images);
    return data;
  }

  @Override public void onListen(Object arguments, EventChannel.EventSink eventSink) {
    stopObserving();
    try {
      Number id = (Number) ((Map<?, ?>) arguments).get("playerId");
      observedId = id.longValue();
      observed = players.apply(observedId);
      sink = eventSink;
      observed.addListener(listener);
      emit();
    } catch (RuntimeException error) {
      stopObserving();
      eventSink.error("tracks_unavailable", "Track information is unavailable.", null);
    }
  }

  private void emit() {
    if (observed == null || sink == null) return;
    try { sink.success(snapshot(observed)); }
    catch (RuntimeException ignored) { /* The active player can be released during a zap. */ }
  }

  private void stopObserving() {
    if (observed != null) observed.removeListener(listener);
    observed = null;
    observedId = -1;
    sink = null;
  }

  @Override public void onCancel(Object arguments) { stopObserving(); }
  void playerDisposed(long id) { if (id == observedId) stopObserving(); }
  void detach() {
    stopObserving();
    methods.setMethodCallHandler(null);
    events.setStreamHandler(null);
  }
}
