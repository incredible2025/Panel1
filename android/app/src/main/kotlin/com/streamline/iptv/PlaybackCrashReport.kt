package com.streamline.iptv

import android.content.Context
import java.util.UUID

/** Persist only fixed playback context when a Java exception terminates the app. */
object PlaybackCrashReport {
    @Volatile private var playback: Map<String, String>? = null
    private var installed = false

    @Synchronized
    fun install(context: Context) {
        if (installed) return
        val preferences = context.applicationContext.getSharedPreferences("playback-report", Context.MODE_PRIVATE)
        val info = context.packageManager.getPackageInfo(context.packageName, 0)
        val version = info.versionName ?: "0"
        val build = if (android.os.Build.VERSION.SDK_INT >= 28) info.longVersionCode.toInt() else info.versionCode
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            try {
                playback?.let { state ->
                    preferences.edit()
                        .putString("id", UUID.randomUUID().toString())
                        .putString("engine", state["engine"])
                        .putString("decoding", state["decoding"])
                        .putString("kind", state["kind"])
                        .putString("session_id", state["session_id"])
                        .putString("native_code", when(error) {
                            is OutOfMemoryError -> "JAVA_OUT_OF_MEMORY"
                            is IllegalStateException -> "JAVA_ILLEGAL_STATE"
                            is LinkageError -> "JAVA_LINKAGE"
                            else -> "JAVA_UNCAUGHT_EXCEPTION"
                        })
                        .putString("version", version)
                        .putInt("build", build)
                        .putLong("time", System.currentTimeMillis())
                        .commit()
                }
            } finally {
                previous?.uncaughtException(thread, error)
            }
        }
        installed = true
    }

    fun setContext(value: Map<String, String>?) {
        playback = value?.takeIf {
            it["engine"] in setOf("native", "compatibility", "vlc") &&
                it["decoding"] in setOf("automatic", "hardware", "software") &&
                it["kind"] in setOf("live", "movie", "series", "catchup")
        }
    }

    fun previous(context: Context): Map<String, Any?>? {
        val preferences = context.getSharedPreferences("playback-report", Context.MODE_PRIVATE)
        val id = preferences.getString("id", null) ?: return null
        if (System.currentTimeMillis() - preferences.getLong("time", 0) > 7 * 24 * 60 * 60 * 1000L) {
            preferences.edit().clear().apply()
            return null
        }
        return mapOf("id" to id, "engine" to preferences.getString("engine", null),
            "decoding" to preferences.getString("decoding", null), "kind" to preferences.getString("kind", null),
            "version" to preferences.getString("version", "0"), "build" to preferences.getInt("build", 1),
            "session_id" to preferences.getString("session_id", null), "native_code" to preferences.getString("native_code", null),
            "occurred_ms" to preferences.getLong("time",0))
    }

    fun acknowledge(context: Context, id: String?) {
        val preferences = context.getSharedPreferences("playback-report", Context.MODE_PRIVATE)
        if (id != null && id == preferences.getString("id", null)) preferences.edit().clear().apply()
    }
}
