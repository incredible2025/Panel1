package com.streamline.iptv

import android.app.UiModeManager
import android.content.Context
import android.content.res.Configuration
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Network
import android.net.LinkProperties
import android.os.Build
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var updater: AppUpdater? = null
    private var dnsDiagnostics: NetworkDnsDiagnostics? = null
    private var platformChannel: MethodChannel? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        networkCallback?.let { callback ->
            try {
                (getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager).unregisterNetworkCallback(callback)
            } catch (_: Exception) { }
        }
        networkCallback = null
        platformChannel?.setMethodCallHandler(null)
        platformChannel = null
        updater?.close()
        updater = null
        dnsDiagnostics?.close()
        dnsDiagnostics = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        updater = AppUpdater(this, flutterEngine.dartExecutor.binaryMessenger)
        dnsDiagnostics = NetworkDnsDiagnostics(this)
        platformChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "streamline/platform")
        platformChannel!!
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "dnsDiagnosis" -> dnsDiagnostics?.lookup(
                        call.argument<String>("host"), call.argument<String>("id"),
                        call.argument<Int>("timeoutMs"), result,
                    ) ?: result.error("dns_unavailable", "DNS check unavailable.", null)
                    "cancelDnsDiagnosis" -> {
                        dnsDiagnostics?.cancel(call.argument<String>("id"))
                        result.success(null)
                    }
                    "isTelevision" -> {
                        val manager = getSystemService(Context.UI_MODE_SERVICE) as UiModeManager
                        result.success(manager.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION)
                    }
                    "networkDiagnosis" -> {
                        try {
                            val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                            val network = manager.activeNetwork
                            val caps = network?.let { manager.getNetworkCapabilities(it) }
                            val links = network?.let { manager.getLinkProperties(it) }
                            val transports = mutableListOf<String>()
                            if (caps?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true) transports.add("Wi-Fi")
                            if (caps?.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) == true) transports.add("Ethernet")
                            if (caps?.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) == true) transports.add("Mobile")
                            if (caps?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true) transports.add("VPN")
                            result.success(mapOf(
                                "connected" to (network != null),
                                "validated" to caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED),
                                "captivePortal" to caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_CAPTIVE_PORTAL),
                                "vpn" to caps?.hasTransport(NetworkCapabilities.TRANSPORT_VPN),
                                "privateDns" to if (Build.VERSION.SDK_INT >= 28) links?.isPrivateDnsActive else null,
                                "privateDnsStrict" to if (Build.VERSION.SDK_INT >= 28) links?.privateDnsServerName?.let { true } ?: false else null,
                                "dnsServerCount" to links?.dnsServers?.size,
                                "metered" to manager.isActiveNetworkMetered,
                                "transports" to transports
                            ))
                        } catch (_: Exception) {
                            result.error("network_unavailable", "Network information is unavailable.", null)
                        }
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
        val callback = object : ConnectivityManager.NetworkCallback() {
            private fun changed() {
                runOnUiThread { platformChannel?.invokeMethod("networkChanged", null) }
            }
            override fun onAvailable(network: Network) = changed()
            override fun onLost(network: Network) = changed()
            override fun onLinkPropertiesChanged(network: Network, properties: LinkProperties) = changed()
        }
        try {
            (getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager).registerDefaultNetworkCallback(callback)
            networkCallback = callback
        } catch (_: Exception) { /* Resume and bounded cooldown still recheck HTTPS. */ }
    }
}
