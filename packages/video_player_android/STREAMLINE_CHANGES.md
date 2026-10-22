# Streamline Android player extension

Based on Flutter's `video_player_android` 2.9.5, copied from the locked pub.dev package. The original BSD license is retained in LICENSE. Dart rendering, texture handling and existing playback APIs are unchanged.

StreamlineTracks.java adds an app-scoped MethodChannel/EventChannel for supported audio/text tracks and current subtitle cues. VideoPlayerPlugin owns its lifecycle, supplies the current ExoPlayer by player ID, and detaches listeners before disposal. This avoids reflection or a second playback engine.

The app pins video_player 2.10.1 and isolates its player-ID integration in lib/core/player_tracks.dart. Review these integration points when updating the upstream player. Text cues and bitmap subtitle images are rendered by Flutter; complex provider-specific subtitle styling is not preserved.

Version 0.5 also applies saved audio/text language preferences, stereo-track preference and subtitle defaults through TrackSelectionParameters, and exposes codec/channel metadata for the diagnostics panel.
