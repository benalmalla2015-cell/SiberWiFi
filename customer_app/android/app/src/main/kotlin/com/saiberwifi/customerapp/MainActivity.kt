package com.saiberwifi.customerapp

import android.app.Activity
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.VpnService
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import com.saiberwifi.customerapp.bridge.VpnBridge
import com.saiberwifi.customerapp.receiver.ConnectivityWatcher

class MainActivity : FlutterActivity() {

    private lateinit var vpnBridge: VpnBridge
    private val connectivityWatcher = ConnectivityWatcher()
    private var pendingResult: MethodChannel.Result? = null

    companion object {
        private const val VPN_REQUEST_CODE = 100
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        vpnBridge = VpnBridge(applicationContext)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            VpnBridge.METHOD_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method == "startVpn") {
                val prepareIntent = VpnService.prepare(this)
                if (prepareIntent != null) {
                    pendingResult = result
                    startActivityForResult(prepareIntent, VPN_REQUEST_CODE)
                    return@setMethodCallHandler
                }
            }
            vpnBridge.onMethodCall(call, result)
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            VpnBridge.EVENT_CHANNEL,
        ).setStreamHandler(vpnBridge)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.saiberwifi.customerapp/device",
        ).setMethodCallHandler { call, result ->
            if (call.method == "getDeviceId") {
                result.success(Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID))
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_REQUEST_CODE) {
            if (resultCode == Activity.RESULT_OK) {
                pendingResult?.success(true)
            } else {
                pendingResult?.success(false)
            }
            pendingResult = null
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            registerReceiver(
                connectivityWatcher,
                @Suppress("DEPRECATION")
                IntentFilter(ConnectivityManager.CONNECTIVITY_ACTION),
            )
        } catch (_: Exception) {}
    }

    override fun onDestroy() {
        super.onDestroy()
        try { unregisterReceiver(connectivityWatcher) } catch (_: Exception) {}
        if (::vpnBridge.isInitialized) vpnBridge.dispose()
    }
}
