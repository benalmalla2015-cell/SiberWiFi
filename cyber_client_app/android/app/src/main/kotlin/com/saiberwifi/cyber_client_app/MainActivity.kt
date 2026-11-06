package com.saiberwifi.cyber_client_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "cyber.net/wifi",
        ).setMethodCallHandler(WifiProfileChannel(applicationContext))
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "cyber.net/security",
        ).setMethodCallHandler(SecurityChannel(applicationContext))
    }
}
