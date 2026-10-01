package com.saiberwifi.customerapp.receiver

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.util.Log
import com.saiberwifi.customerapp.ai.NetworkClassifier

/**
 * ConnectivityWatcher — BroadcastReceiver that monitors network changes.
 * Triggers AI classification only when connectivity type changes to save battery.
 */
class ConnectivityWatcher : BroadcastReceiver() {

    companion object {
        private const val TAG = "ConnectivityWatcher"

        @Volatile var lastNetworkType: String = "UNKNOWN"
        @Volatile var lastQuality: String = "GOOD"

        var onQualityChanged: ((String) -> Unit)? = null
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ConnectivityManager.CONNECTIVITY_ACTION) return

        val newType = getCurrentNetworkType(context)
        if (newType == lastNetworkType) return

        Log.i(TAG, "Network changed: $lastNetworkType -> $newType")
        lastNetworkType = newType

        Thread {
            try {
                val classifier = NetworkClassifier(context)
                classifier.initialize()
                val quality = classifier.classify()
                classifier.close()

                if (quality != lastQuality) {
                    lastQuality = quality
                    Log.i(TAG, "Quality updated: $quality")
                    onQualityChanged?.invoke(quality)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Classification error", e)
            }
        }.also {
            it.isDaemon = true
            it.name = "saiberwifi-ai-classify"
        }.start()
    }

    private fun getCurrentNetworkType(context: Context): String {
        return try {
            val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE)
                    as? ConnectivityManager ?: return "NONE"
            val network = cm.activeNetwork ?: return "NONE"
            val caps = cm.getNetworkCapabilities(network) ?: return "NONE"
            when {
                caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "WIFI"
                caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "CELLULAR"
                caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ETHERNET"
                else -> "OTHER"
            }
        } catch (e: Exception) {
            "NONE"
        }
    }
}
