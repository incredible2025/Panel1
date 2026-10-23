package com.streamline.iptv

import android.content.Context
import android.net.ConnectivityManager
import android.net.DnsResolver
import android.net.Network
import android.os.Build
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.system.ErrnoException
import android.system.OsConstants
import androidx.annotation.RequiresApi
import io.flutter.plugin.common.MethodChannel
import java.net.InetAddress
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.Executor
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

/** DNS evidence comes from this device's active network and configured resolver.
 * No external diagnosis service or alternate public DNS resolver is used.
 * Only addresses needed internally, numeric codes and fixed enums cross the bridge.
 */
class NetworkDnsDiagnostics(context: Context) {
    private val manager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    private val handler = Handler(Looper.getMainLooper())
    private val callbacks = Executor { handler.post(it) }
    private val legacy = ThreadPoolExecutor(2, 2, 0L, TimeUnit.MILLISECONDS, ArrayBlockingQueue(2))
    private val pending = mutableMapOf<String, Pending>()
    private var closed = false

    private inner class Pending(
        val id: String,
        val network: Network,
        val result: MethodChannel.Result,
        val modern: Boolean,
    ) {
        val started = SystemClock.elapsedRealtime()
        val signals = mutableListOf<CancellationSignal>()
        val answers = mutableMapOf<String, List<InetAddress>>()
        val queries = mutableMapOf<String, Map<String, Any>>()
        val expected = if (modern) listOf("A", "AAAA") else listOf("System")
        var finished = false
        val timeout = Runnable {
            for (family in expected) {
                if (!queries.containsKey(family)) record(family, emptyList(), mapOf("error" to "timeout"))
            }
        }

        fun record(family: String, addresses: List<InetAddress>, detail: Map<String, Any>) {
            if (finished || queries.containsKey(family)) return
            answers[family] = addresses.take(64)
            queries[family] = detail + mapOf(
                "family" to family,
                "count" to addresses.size,
                "elapsedMs" to (SystemClock.elapsedRealtime() - started).coerceIn(0L, 60000L).toInt(),
            )
            if (queries.size == expected.size) finish()
        }

        fun finish(cancelled: Boolean = false) {
            if (finished) return
            finished = true
            handler.removeCallbacks(timeout)
            pending.remove(id)
            for (signal in signals) signal.cancel()
            val changed = try { manager.activeNetwork != network } catch (_: Exception) { true }
            val addresses = if (cancelled || changed) emptyList() else
                answers.values.flatten().mapNotNull { it.hostAddress }.distinct().take(64)
            result.success(mapOf(
                "mode" to if (modern) "android" else "system",
                "cacheBypassed" to modern,
                "networkChanged" to changed,
                "addresses" to addresses,
                "queries" to if (cancelled) listOf(mapOf("family" to "System", "error" to "system"))
                    else expected.mapNotNull { queries[it] },
            ))
        }
    }

    fun lookup(host: String?, id: String?, timeoutMs: Int?, result: MethodChannel.Result) {
        if (closed || host.isNullOrBlank() || host.length > 253 || id.isNullOrBlank() ||
            id.length > 80 || pending.containsKey(id)) {
            result.error("dns_unavailable", "DNS check unavailable.", null)
            return
        }
        val network = manager.activeNetwork
        if (network == null || pending.size >= 4) {
            result.success(mapOf("addresses" to emptyList<String>(), "queries" to listOf(
                mapOf("family" to "System", "error" to if (network == null) "noNetwork" else "busy"),
            )))
            return
        }
        val call = Pending(id, network, result, Build.VERSION.SDK_INT >= 29)
        pending[id] = call
        handler.postDelayed(call.timeout, (timeoutMs ?: 8000).coerceIn(100, 8000).toLong())
        if (Build.VERSION.SDK_INT >= 29) modernLookup(call, host) else {
            try {
                legacy.execute {
                    try {
                        val addresses = network.getAllByName(host).toList()
                        handler.post { call.record("System", addresses, if (addresses.isEmpty())
                            mapOf("error" to "noAddress") else emptyMap()) }
                    } catch (error: Exception) {
                        val detail = systemFailure(error)
                        handler.post { call.record("System", emptyList(), detail) }
                    }
                }
            } catch (_: Exception) {
                call.record("System", emptyList(), mapOf("error" to "busy"))
            }
        }
    }

    @RequiresApi(29)
    private fun modernLookup(call: Pending, host: String) {
        for ((family, type) in listOf("A" to DnsResolver.TYPE_A, "AAAA" to DnsResolver.TYPE_AAAA)) {
            val signal = CancellationSignal()
            call.signals.add(signal)
            try {
                DnsResolver.getInstance().query(
                    call.network, host, type,
                    DnsResolver.FLAG_NO_CACHE_LOOKUP or DnsResolver.FLAG_NO_CACHE_STORE,
                    callbacks, signal, object : DnsResolver.Callback<List<InetAddress>> {
                        override fun onAnswer(answer: List<InetAddress>, rcode: Int) {
                            call.record(family, if (rcode == 0) answer else emptyList(), mapOf("rcode" to rcode))
                        }
                        override fun onError(error: DnsResolver.DnsException) {
                            call.record(family, emptyList(), if (error.code == DnsResolver.ERROR_PARSE)
                                mapOf("error" to "parse") else systemFailure(error))
                        }
                    },
                )
            } catch (error: Exception) {
                call.record(family, emptyList(), systemFailure(error))
            }
        }
    }

    private fun systemFailure(error: Throwable): Map<String, Any> {
        var current: Throwable? = error
        repeat(6) {
            val value = current
            if (value is ErrnoException) {
                return mapOf("osCode" to value.errno, "error" to when (value.errno) {
                    OsConstants.ETIMEDOUT -> "timeout"
                    OsConstants.ENETUNREACH, OsConstants.EHOSTUNREACH -> "unreachable"
                    OsConstants.ECONNREFUSED -> "refused"
                    OsConstants.EACCES, OsConstants.EPERM -> "permission"
                    else -> "system"
                })
            }
            if (value is SecurityException) return mapOf("error" to "permission")
            current = value?.cause
        }
        return mapOf("error" to "system")
    }

    fun cancel(id: String?) { pending[id]?.finish(cancelled = true) }

    fun close() {
        closed = true
        for (call in pending.values.toList()) call.finish(cancelled = true)
        legacy.shutdownNow()
    }
}
