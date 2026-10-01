package com.saiberwifi.customerapp.ai

import android.content.Context
import com.saiberwifi.customerapp.vpn.AiState

/**
 * NetworkClassifier — legacy stub.
 * Delegates to NetworkClassifierV2 (custom binary Decision Tree, no TFLite).
 * Kept for backward-compat with ConnectivityWatcher references.
 */
@Deprecated("Use NetworkClassifierV2 directly")
class NetworkClassifier(context: Context) {

    private val v2 = NetworkClassifierV2(context)

    fun initialize() = v2.initialize()

    fun classify(): String = when (v2.classify()) {
        AiState.NORMAL      -> "GOOD"
        AiState.DEGRADED    -> "WEAK"
        AiState.EMERGENCY   -> "CONGESTED"
        AiState.DEEP_FREEZE -> "CONGESTED"
    }

    fun close() = v2.close()
}
