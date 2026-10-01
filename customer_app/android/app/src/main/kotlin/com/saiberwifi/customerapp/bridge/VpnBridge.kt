package com.saiberwifi.customerapp.bridge

import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.net.TrafficStats
import android.net.VpnService
import android.os.Build
import android.util.Base64
import android.util.Log
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import com.saiberwifi.customerapp.vpn.NetworkBoosterVpnService
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

/**
 * VpnBridge — MethodChannel + EventChannel handler for the network booster feature.
 * Channel name: "com.saiberwifi.customerapp/vpn"
 * EventChannel name: "com.saiberwifi.customerapp/vpn_stats"
 */
class VpnBridge(private val context: Context) : MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {

    companion object {
        private const val TAG = "VpnBridge"
        const val METHOD_CHANNEL = "com.saiberwifi.customerapp/vpn"
        const val EVENT_CHANNEL = "com.saiberwifi.customerapp/vpn_stats"
    }

    private val executor = Executors.newScheduledThreadPool(1)
    private var statsTask: ScheduledFuture<*>? = null
    private var eventSink: EventChannel.EventSink? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startVpn" -> handleStartVpn(call, result)
            "stopVpn" -> handleStopVpn(result)
            "getInstalledApps" -> handleGetApps(result)
            else -> result.notImplemented()
        }
    }

    private fun handleStartVpn(call: MethodCall, result: MethodChannel.Result) {
        val packages = call.argument<List<String>>("allowedPackages") ?: emptyList()
        val profile   = call.argument<String>("profile") ?: "CELLULAR"

        val prepareIntent = VpnService.prepare(context)
        if (prepareIntent != null) {
            result.error("VPN_PERMISSION_REQUIRED", "VPN permission required", null)
            return
        }

        val targetPkg = packages.firstOrNull() ?: ""
        val targetUid: Int = if (targetPkg.isNotEmpty()) {
            try {
                context.packageManager.getPackageUid(targetPkg, 0)
            } catch (e: Exception) {
                Log.w(TAG, "Cannot resolve UID for $targetPkg: ${e.message}")
                TrafficStats.UNSUPPORTED
            }
        } else {
            TrafficStats.UNSUPPORTED
        }

        val intent = Intent(context, NetworkBoosterVpnService::class.java).apply {
            action = NetworkBoosterVpnService.ACTION_START
            putExtra(NetworkBoosterVpnService.EXTRA_TARGET_PKG, targetPkg)
            putExtra(NetworkBoosterVpnService.EXTRA_TARGET_UID, targetUid)
            putExtra(NetworkBoosterVpnService.EXTRA_PROFILE, profile)
        }
        context.startForegroundService(intent)
        Log.i(TAG, "VPN start requested | profile=$profile | target=$targetPkg | uid=$targetUid")
        result.success(true)
    }

    private fun handleStopVpn(result: MethodChannel.Result) {
        val intent = Intent(context, NetworkBoosterVpnService::class.java).apply {
            action = NetworkBoosterVpnService.ACTION_STOP
        }
        context.startService(intent)
        result.success(true)
    }

    private fun handleGetApps(result: MethodChannel.Result) {
        executor.execute {
            try {
                val pm = context.packageManager
                val launchablePackages = pm.getInstalledApplications(PackageManager.GET_META_DATA)
                    .filter { pm.getLaunchIntentForPackage(it.packageName) != null }
                val preferredSystemPackages = setOf(
                    "com.google.android.youtube",
                    "com.android.chrome",
                )
                val packages = launchablePackages
                    .filter {
                        (it.flags and ApplicationInfo.FLAG_SYSTEM) == 0 ||
                            it.packageName in preferredSystemPackages
                    }
                    .sortedBy { pm.getApplicationLabel(it).toString() }

                val appList = packages.map { info ->
                    val name = pm.getApplicationLabel(info).toString()
                    val icon = try {
                        val drawable = pm.getApplicationIcon(info.packageName)
                        encodeIconToBase64(drawable)
                    } catch (_: Exception) { null }

                    mapOf(
                        "pkg" to info.packageName,
                        "name" to name,
                        "icon" to icon,
                    )
                }
                result.success(appList)
            } catch (e: Exception) {
                Log.e(TAG, "getInstalledApps error", e)
                result.error("APPS_ERROR", e.message, null)
            }
        }
    }

    private fun encodeIconToBase64(drawable: Drawable): String? {
        return try {
            val bitmap = drawableToBitmap(drawable)
            val stream = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 70, stream)
            Base64.encodeToString(stream.toByteArray(), Base64.NO_WRAP)
        } catch (e: Exception) {
            null
        }
    }

    private fun drawableToBitmap(drawable: Drawable): Bitmap {
        if (drawable is BitmapDrawable && drawable.bitmap != null) {
            return Bitmap.createScaledBitmap(drawable.bitmap, 64, 64, true)
        }
        val bitmap = Bitmap.createBitmap(64, 64, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, canvas.width, canvas.height)
        drawable.draw(canvas)
        return bitmap
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        statsTask = executor.scheduleAtFixedRate({
            try {
                val downKbps = NetworkBoosterVpnService.downloadBytes / 1024.0
                val upKbps   = NetworkBoosterVpnService.uploadBytes   / 1024.0
                val stats = mapOf(
                    "down_kbps" to downKbps,
                    "up_kbps"   to upKbps,
                    "latency"   to NetworkBoosterVpnService.lastLatencyMs,
                    "is_active" to NetworkBoosterVpnService.isRunning,
                    "target_pkg" to NetworkBoosterVpnService.targetPkg,
                )
                eventSink?.success(stats)
            } catch (e: Exception) {
                Log.e(TAG, "Stats event error", e)
            }
        }, 0, 1, TimeUnit.SECONDS)
    }

    override fun onCancel(arguments: Any?) {
        statsTask?.cancel(false)
        eventSink = null
    }

    fun dispose() {
        statsTask?.cancel(false)
        executor.shutdownNow()
    }
}
