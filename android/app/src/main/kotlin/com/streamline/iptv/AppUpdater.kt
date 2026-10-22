package com.streamline.iptv

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Executors

/** Exposes only our private update folder; no arbitrary file or external URL installation. */
class AppUpdater(private val activity: Activity, messenger: BinaryMessenger) {
    private val executor = Executors.newSingleThreadExecutor()
    private val channel = MethodChannel(messenger, "ultravpn/updates")
    private val prefs = activity.getSharedPreferences("app_updates", Activity.MODE_PRIVATE)
    private val folder get() = File(activity.cacheDir, "updates")
    private val pm get() = activity.packageManager

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "load" -> {
                    @Suppress("DEPRECATION")
                    val info = pm.getPackageInfo(activity.packageName, 0)
                    result.success(mapOf("version" to info.versionName, "code" to code(info),
                        "sdk" to Build.VERSION.SDK_INT, "directory" to folder.absolutePath,
                        "url" to prefs.getString("url", null),
                        "automatic" to prefs.getBoolean("automatic", true),
                        "lastCheck" to prefs.getString("lastCheck", null)))
                }
                "preferences" -> {
                    val url = call.argument<String>("url") ?: ""
                    val uri = Uri.parse(url)
                    if (uri.scheme != "https" || uri.host.isNullOrEmpty() || uri.userInfo != null || uri.fragment != null) {
                        result.error("address", "Use a valid HTTPS update address.", null)
                    } else {
                        val saved = prefs.edit().putString("url", url)
                            .putBoolean("automatic", call.argument<Boolean>("automatic") ?: true)
                            .putString("lastCheck", call.argument<String>("lastCheck")).commit()
                        if (saved) result.success(null)
                        else result.error("storage", "Update preferences could not be saved. Check device storage.", null)
                    }
                }
                "canInstall" -> result.success(canInstall())
                "permission" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= 26) {
                            activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:${activity.packageName}")))
                        }
                        result.success(null)
                    } catch (_: Exception) {
                        result.error("permission", "Open Android Settings > Apps > Special app access > Install unknown apps and allow ULTRAVPN PLAYER, then return here.", null)
                    }
                }
                "validate", "install" -> executor.execute {
                    try {
                        val apk = validate(call)
                        activity.runOnUiThread {
                            try {
                                if (call.method == "install") {
                                    check(canInstall()) { "Allow installation from ULTRAVPN PLAYER in Android Settings, then try again." }
                                    val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.updates", apk)
                                    activity.startActivity(Intent(Intent.ACTION_VIEW)
                                        .setDataAndType(uri, "application/vnd.android.package-archive")
                                        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
                                }
                                result.success(null)
                            } catch (e: Exception) {
                                result.error("installer", e.message ?: "This device has no available APK installer.", null)
                            }
                        }
                    } catch (e: Exception) {
                        activity.runOnUiThread { result.error("verification", e.message ?: "APK verification failed. Download the update again.", null) }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun canInstall() = Build.VERSION.SDK_INT < 26 || pm.canRequestPackageInstalls()
    @Suppress("DEPRECATION")
    private fun code(info: PackageInfo): Long = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()

    @Suppress("DEPRECATION")
    private fun signers(info: PackageInfo): Set<String> {
        val signatures = if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners else info.signatures
        return signatures?.map { digest(it.toByteArray()) }?.toSet() ?: emptySet()
    }
    private fun digest(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes)
        .joinToString("") { "%02x".format(it) }

    @Suppress("DEPRECATION")
    private fun validate(call: MethodCall): File {
        val apk = File(call.argument<String>("path") ?: "").canonicalFile
        check(apk == File(folder, "update.apk").canonicalFile && apk.isFile) { "The private update download is missing. Download it again." }
        val expected = call.argument<String>("sha256") ?: ""
        val digest = MessageDigest.getInstance("SHA-256")
        apk.inputStream().use { input ->
            val buffer = ByteArray(65536)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        check(digest.digest().joinToString("") { "%02x".format(it) } == expected) { "The APK changed after download. Download it again." }
        val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
        val archive = pm.getPackageArchiveInfo(apk.path, flags)
            ?: error("Android cannot read this APK. Download it again or contact the app administrator.")
        val installed = pm.getPackageInfo(activity.packageName, flags)
        check(archive.packageName == activity.packageName) { "This APK belongs to a different app. Installation was stopped." }
        check(code(archive) == call.argument<Number>("code")?.toLong() && code(archive) > code(installed)) {
            "The APK version does not match the update file, or is not newer than the installed app."
        }
        check(archive.applicationInfo?.minSdkVersion?.let { it <= Build.VERSION.SDK_INT } == true) { "This update requires a newer version of Android." }
        val current = signers(installed)
        check(current.isNotEmpty() && signers(archive) == current) {
            "This APK uses a different signing key. It cannot safely update this installation. Ask the app administrator for a compatible signed build. Testing builds may require a one-time migration; uninstalling clears local app data."
        }
        return apk
    }

    fun close() {
        channel.setMethodCallHandler(null)
        executor.shutdown()
    }
}
