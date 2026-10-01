package com.saiberwifi.customerapp.ai

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.WifiManager
import android.os.SystemClock
import android.util.Log
import com.saiberwifi.customerapp.vpn.AiState
import java.net.InetAddress
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * NetworkClassifierV2 — Custom binary Decision Tree classifier.
 * Model: assets/models/net_quality.aden (~1.2 KB)
 * No TFLite Interpreter needed — pure Kotlin inference.
 *
 * Input features: [throughput_kbps, latency_ms, jitter_ms, packet_loss_pct, conn_type]
 * Output classes:
 *   0 = NORMAL      (> 500 KB/s)
 *   1 = DEGRADED    (50–500 KB/s)
 *   2 = EMERGENCY   (20–50 KB/s)
 *   3 = DEEP_FREEZE (< 20 KB/s)
 */
class NetworkClassifierV2(private val context: Context) {

    companion object {
        private const val TAG = "NetworkClassifierV2"
        private const val MODEL_FILE = "models/net_quality.aden"
        private val MAGIC = byteArrayOf(0x41, 0x44, 0x45, 0x4E) // "ADEN"

        val LABELS = arrayOf(
            AiState.NORMAL,
            AiState.DEGRADED,
            AiState.EMERGENCY,
            AiState.DEEP_FREEZE,
        )
    }

    private var nNodes: Int = 0
    private var features: IntArray    = intArrayOf()
    private var thresholds: FloatArray = floatArrayOf()
    private var leftChildren: IntArray  = intArrayOf()
    private var rightChildren: IntArray = intArrayOf()
    private var values: IntArray       = intArrayOf()
    private var modelLoaded = false

    private val throughputWindow = ArrayDeque<Float>(3)

    fun initialize() {
        try {
            val bytes = context.assets.open(MODEL_FILE).readBytes()
            val buf   = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)

            val magic = ByteArray(4)
            buf.get(magic)
            if (!magic.contentEquals(MAGIC)) {
                Log.e(TAG, "Invalid model magic")
                return
            }

            val version = buf.get().toInt() and 0xFF
            Log.d(TAG, "Model version: $version")

            nNodes = buf.int
            features      = IntArray(nNodes) { buf.int }
            thresholds     = FloatArray(nNodes) { buf.float }
            leftChildren   = IntArray(nNodes) { buf.int }
            rightChildren  = IntArray(nNodes) { buf.int }
            values         = IntArray(nNodes) { buf.int }

            modelLoaded = true
            Log.i(TAG, "Model loaded: $nNodes nodes")
        } catch (e: Exception) {
            Log.e(TAG, "Model load failed, using heuristic", e)
            modelLoaded = false
        }
    }

    fun classify(realtimeThroughputKbps: Float? = null): AiState {
        val features = collectFeatures(realtimeThroughputKbps)
        val rawState = if (modelLoaded) runTree(features) else heuristic(features)

        throughputWindow.addLast(features[0])
        if (throughputWindow.size > 3) throughputWindow.removeFirst()

        return if (throughputWindow.size >= 3) {
            val minThroughput = throughputWindow.min()
            val windowState = heuristic(floatArrayOf(minThroughput, features[1],
                features[2], features[3], features[4]))
            if (windowState.ordinal > rawState.ordinal) windowState else rawState
        } else rawState
    }

    private fun runTree(feats: FloatArray): AiState {
        var node = 0
        repeat(64) {
            val feat = features[node]
            if (feat == -2) return LABELS.getOrElse(values[node]) { AiState.NORMAL }
            node = if (feats[feat] <= thresholds[node]) leftChildren[node] else rightChildren[node]
            if (node < 0 || node >= nNodes) return AiState.NORMAL
        }
        return LABELS.getOrElse(values[node]) { AiState.NORMAL }
    }

    private fun collectFeatures(realtimeThroughput: Float?): FloatArray {
        val latency  = measureLatencyMs()
        val jitter   = measureJitterMs(latency)
        val (_, linkSpeed) = getWifiInfo()
        val connType = getConnectionType()

        val throughput = realtimeThroughput
            ?: (linkSpeed * 0.1f).coerceAtLeast(0f)

        return floatArrayOf(
            throughput,
            latency.toFloat(),
            jitter.toFloat(),
            0f,
            connType.toFloat(),
        )
    }

    private fun heuristic(feats: FloatArray): AiState {
        val throughput = feats[0]
        val latency    = feats[1]
        val jitter     = feats[2]
        return when {
            throughput < 20 || (latency > 600 && jitter > 100) -> AiState.DEEP_FREEZE
            throughput < 50 || latency > 350                    -> AiState.EMERGENCY
            throughput < 500 || latency > 150                   -> AiState.DEGRADED
            else                                                 -> AiState.NORMAL
        }
    }

    private fun measureLatencyMs(): Long {
        return try {
            val start = SystemClock.elapsedRealtime()
            InetAddress.getByName("8.8.8.8")
            (SystemClock.elapsedRealtime() - start).coerceAtMost(999L)
        } catch (_: Exception) { 999L }
    }

    private fun measureJitterMs(base: Long): Long {
        return try {
            val start = SystemClock.elapsedRealtime()
            InetAddress.getByName("8.8.4.4")
            val l2 = SystemClock.elapsedRealtime() - start
            Math.abs(l2 - base)
        } catch (_: Exception) { 50L }
    }

    private fun getWifiInfo(): Pair<Int, Int> {
        return try {
            val wm = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            val info = wm?.connectionInfo
            Pair(info?.rssi ?: -100, info?.linkSpeed ?: 0)
        } catch (_: Exception) { Pair(-100, 0) }
    }

    private fun getConnectionType(): Int {
        return try {
            val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return 0
            val caps = cm.getNetworkCapabilities(cm.activeNetwork ?: return 0) ?: return 0
            when {
                caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)     -> 1
                caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> 2
                else -> 0
            }
        } catch (_: Exception) { 0 }
    }

    fun close() {}
}
