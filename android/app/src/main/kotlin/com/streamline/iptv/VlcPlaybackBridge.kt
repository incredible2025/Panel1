package com.streamline.iptv

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.view.Surface
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import org.videolan.libvlc.LibVLC
import org.videolan.libvlc.Media
import org.videolan.libvlc.MediaPlayer
import org.videolan.libvlc.interfaces.IMedia
import java.util.concurrent.Executors

/** Own every native resource and finish closing a stream before acknowledging dispose. */
class VlcPlaybackBridge(
    private val context: Context,
    messenger: BinaryMessenger,
    private val textures: TextureRegistry,
) : EventChannel.StreamHandler {
    private val methods = MethodChannel(messenger, "streamline/vlc")
    private val events = EventChannel(messenger, "streamline/vlc/events")
    private val handler = Handler(Looper.getMainLooper())
    private val closing = Executors.newSingleThreadExecutor()
    private val players = mutableMapOf<Long, Session>()
    private var sink: EventChannel.EventSink? = null
    private var closed = false
    private val languageAliases = mapOf(
        "eng" to "en", "spa" to "es", "fra" to "fr", "fre" to "fr",
        "deu" to "de", "ger" to "de", "ita" to "it", "por" to "pt",
        "ara" to "ar", "hin" to "hi", "tur" to "tr", "pol" to "pl",
        "nld" to "nl", "dut" to "nl",
    )
    private fun language(value: String?): String {
        val code = value.orEmpty().lowercase(java.util.Locale.ROOT).split('-', '_').first()
        return languageAliases[code] ?: code
    }

    init {
        events.setStreamHandler(this)
        methods.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "create" -> {
                        check(!closed)
                        val uri = Uri.parse(requireNotNull(call.argument<String>("uri")))
                        require(uri.scheme in listOf("http", "https") && !uri.host.isNullOrEmpty())
                        val session = Session(uri, call.argument<String>("decoding") ?: "automatic",
                            call.argument<Number>("subtitleSize")?.toInt() ?: 22,
                            call.argument<Boolean>("subtitleBackground") != false)
                        players[session.id] = session
                        result.success(session.id)
                    }
                    "dispose" -> {
                        val session = players.remove(call.argument<Number>("id")?.toLong())
                        if (session == null) result.success(null)
                        else session.close { result.success(null) }
                    }
                    else -> {
                        val session = players[call.argument<Number>("id")?.toLong()]
                        if (session == null) result.error("closed", "Player is closed.", null)
                        else { session.command(call); result.success(null) }
                    }
                }
            } catch (_: Exception) {
                // LibVLC exceptions may contain the media URI and credentials.
                result.error("playback", "VLC playback is unavailable.", null)
            } catch (_: LinkageError) {
                result.error("decoder", "VLC could not load on this device.", null)
            }
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        players.values.forEach { it.emit() }
    }
    override fun onCancel(arguments: Any?) { sink = null }

    fun close() {
        closed = true
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        sink = null
        players.values.toList().forEach { it.close {} }
        players.clear()
        closing.shutdown()
    }

    private inner class Session(uri: Uri, private val decoding: String, subtitleSize: Int, subtitleBackground: Boolean) {
        private val texture = textures.createSurfaceTexture()
        val id = texture.id()
        private val surface = Surface(texture.surfaceTexture())
        private lateinit var library: LibVLC
        private lateinit var player: MediaPlayer
        private var dead = false
        private var ready = false
        private var failed = false
        private var buffering = false
        private var completed = false
        private var width = 0
        private var height = 0
        private var preferences: Map<String, Any?>? = null
        private var preferencesApplied = false
        private val tick = object : Runnable {
            override fun run() {
                if (dead) return
                emit()
                handler.postDelayed(this, 500)
            }
        }

        init {
            try {
                library = LibVLC(context, arrayListOf(
                    "--quiet", "--no-video-title-show", "--no-audio-time-stretch",
                    "--freetype-rel-fontsize=" + (352 / subtitleSize.coerceIn(16, 40)),
                    "--freetype-background-opacity=" + if (subtitleBackground) "166" else "0",
                ))
                player = MediaPlayer(library)
                texture.surfaceTexture().setDefaultBufferSize(16, 9)
                player.vlcVout.setVideoSurface(surface, null)
                player.vlcVout.setWindowSize(16, 9)
                player.vlcVout.attachViews { _, w, h, _, _, _, _ ->
                    if (!dead && w > 0 && h > 0) {
                        width = w
                        height = h
                        texture.surfaceTexture().setDefaultBufferSize(w, h)
                        player.vlcVout.setWindowSize(w, h)
                        ready = true
                        emit()
                    }
                }
                player.setEventListener { event ->
                    if (!dead) {
                        when (event.type) {
                            MediaPlayer.Event.Buffering -> buffering = event.buffering < 100
                            MediaPlayer.Event.Playing -> { buffering = false; completed = false }
                            MediaPlayer.Event.EndReached -> completed = true
                            MediaPlayer.Event.EncounteredError -> failed = true
                        }
                        emit()
                    }
                }
                val media = Media(library, uri)
                try {
                    media.setHWDecoderEnabled(decoding != "software", decoding == "hardware")
                    media.addOption(":network-caching=1000")
                    // Blend subtitles into the video texture.
                    media.addOption(":avcodec-hw=" + if (decoding == "software") "none" else "any")
                    player.media = media
                } finally { media.release() }
                player.volume = 0
                handler.post(tick)
            } catch (error: Throwable) {
                try {
                    if (::player.isInitialized) {
                        player.setEventListener(null)
                        player.vlcVout.detachViews()
                        player.release()
                    }
                } finally {
                    try {
                        if (::library.isInitialized) library.release()
                    } finally {
                        surface.release()
                        texture.release()
                    }
                }
                throw error
            }
        }

        fun command(call: MethodCall) {
            check(!dead)
            when (call.method) {
                "load", "play" -> player.play()
                "pause" -> player.pause()
                "seek" -> player.time = (call.argument<Number>("position")?.toLong() ?: 0).coerceAtLeast(0)
                "volume" -> player.volume = (call.argument<Number>("volume")?.toInt() ?: 100).coerceIn(0, 100)
                "track" -> {
                    val type = call.argument<String>("type")
                    val key = call.argument<String>("key")
                    if (type == "text") {
                        val track = if (key == "off") -1 else if (key == "auto")
                            player.spuTracks?.firstOrNull { it.id >= 0 }?.id ?: -1
                            else requireNotNull(key?.toIntOrNull())
                        check(player.setSpuTrack(track))
                    } else {
                        val track = if (key == "auto")
                            player.audioTracks?.firstOrNull { it.id >= 0 }?.id ?: -1
                            else requireNotNull(key?.toIntOrNull())
                        check(player.setAudioTrack(track))
                    }
                }
                "preferences" -> {
                    @Suppress("UNCHECKED_CAST")
                    preferences = call.arguments as? Map<String, Any?>
                    preferencesApplied = false
                }
                else -> error("Unknown player command")
            }
            emit()
        }

        private fun tracks(): Map<String, Any?> {
            if (!player.hasMedia()) return emptyMap()
            val media = player.media
            val metadata = try {
                (0 until (media?.trackCount ?: 0)).mapNotNull { media?.getTrack(it) }
            } finally { media?.release() }
            val audio = metadata.filterIsInstance<IMedia.AudioTrack>()
            val video = metadata.filterIsInstance<IMedia.VideoTrack>().firstOrNull()
            if (!preferencesApplied && audio.isNotEmpty() && preferences != null) {
                preferencesApplied = true
                val options = preferences!!
                val language = options["audioLanguage"] as? String ?: ""
                val stereo = options["stereo"] == true
                audio.firstOrNull {
                    (language.isEmpty() || language(it.language) == language(language)) &&
                        (!stereo || it.channels <= 2)
                }?.let {
                    if (language.isNotEmpty() || stereo) player.setAudioTrack(it.id)
                }
                val subtitleLanguage = options["subtitleLanguage"] as? String ?: ""
                val subtitle = metadata.firstOrNull {
                    it.type == IMedia.Track.Type.Text &&
                        (subtitleLanguage.isEmpty() || language(it.language) == language(subtitleLanguage))
                }
                if (options["subtitles"] != true) player.setSpuTrack(-1)
                else if (subtitle != null) player.setSpuTrack(subtitle.id)
                preferencesApplied = true
            }
            if (video == null && audio.isNotEmpty()) ready = true
            val entries = mutableListOf<Map<String, Any?>>()
            fun add(type: String, descriptions: Array<MediaPlayer.TrackDescription>?, selected: Int) {
                descriptions?.filter { it.id >= 0 }?.forEach { track ->
                    val info = metadata.firstOrNull { it.id == track.id &&
                        it.type == if (type == "audio") IMedia.Track.Type.Audio else IMedia.Track.Type.Text }
                    entries.add(mapOf(
                        "key" to track.id.toString(), "type" to type, "label" to track.name,
                        "selected" to (track.id == selected), "supported" to true,
                        "language" to (info?.language ?: ""),
                    ))
                }
            }
            add("audio", player.audioTracks, player.audioTrack)
            add("text", player.spuTracks, player.spuTrack)
            val currentAudio = audio.firstOrNull { it.id == player.audioTrack }
            return mapOf(
                "available" to true, "tracks" to entries, "textOff" to (player.spuTrack < 0),
                "audioAuto" to false, "videoCodec" to (video?.codec ?: ""),
                "audioCodec" to (currentAudio?.codec ?: ""),
                "audioChannels" to (currentAudio?.channels ?: 0),
            )
        }

        fun emit() {
            if (dead) return
            val info = tracks()
            sink?.success(mapOf(
                "id" to id, "ready" to ready, "error" to failed,
                "playing" to player.isPlaying, "buffering" to buffering,
                "completed" to completed, "duration" to player.length.coerceAtLeast(0),
                "position" to player.time.coerceAtLeast(0), "width" to width, "height" to height,
                "tracks" to info,
            ))
        }

        fun close(done: () -> Unit) {
            if (dead) { done(); return }
            dead = true
            handler.removeCallbacks(tick)
            player.setEventListener(null)
            player.vlcVout.detachViews()
            closing.execute {
                try {
                    player.stop()
                } catch (_: Exception) {
                    // Continue releasing resources after a failed native stop.
                } finally {
                    try {
                        player.release()
                    } finally {
                        try {
                            library.release()
                        } finally {
                            handler.post {
                                surface.release()
                                texture.release()
                                done()
                            }
                        }
                    }
                }
            }
        }
    }
}
