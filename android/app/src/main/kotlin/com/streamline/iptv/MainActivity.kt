package com.streamline.iptv

import android.app.UiModeManager
import android.content.Context
import android.content.res.Configuration
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "streamline/platform")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isTelevision" -> {
                        val manager = getSystemService(Context.UI_MODE_SERVICE) as UiModeManager
                        result.success(manager.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION)
                    }
                    "setKeepScreenOn" -> {
                        if (call.arguments == true) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
