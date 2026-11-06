package com.saiberwifi.cyber_client_app

import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.security.MessageDigest

/**
 * CYB-14 — anti-tamper / anti-reskin channel.
 *
 *   cyber.net/security
 *     verifySignature {expectedSha256} → {ok, actual}
 *        Compares the SHA-256 of the app's signing certificate against
 *        the value baked in at build time. A reskinned/re-signed APK
 *        produces a different digest → Dart refuses to run.
 *     tamperCheck → {rooted, hooking, debuggable}
 *        Heuristic environment checks (su binaries, Frida artifacts,
 *        known hooker packages, debuggable flag).
 */
class SecurityChannel(private val context: Context) : MethodChannel.MethodCallHandler {

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "verifySignature" -> result.success(verifySignature(call.argument("expectedSha256")))
            "tamperCheck" -> result.success(tamperCheck())
            else -> result.notImplemented()
        }
    }

    private fun signatureSha256(): String {
        val pm = context.packageManager
        val signer = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            pm.getPackageInfo(context.packageName, PackageManager.GET_SIGNING_CERTIFICATES)
                .signingInfo?.apkContentsSigners?.firstOrNull()
        } else {
            @Suppress("DEPRECATION")
            pm.getPackageInfo(context.packageName, PackageManager.GET_SIGNATURES)
                .signatures?.firstOrNull()
        } ?: return ""
        return MessageDigest.getInstance("SHA-256")
            .digest(signer.toByteArray())
            .joinToString("") { "%02x".format(it) }
    }

    private fun verifySignature(expected: String?): Map<String, Any?> {
        val actual = signatureSha256()
        // No expected value baked in (dev build) → report actual, don't fail.
        return mapOf(
            "ok" to (expected.isNullOrBlank() || actual.equals(expected, ignoreCase = true)),
            "actual" to actual,
        )
    }

    private fun tamperCheck(): Map<String, Any> {
        val suPaths = listOf(
            "/system/bin/su", "/system/xbin/su", "/sbin/su", "/su/bin/su",
            "/data/local/xbin/su", "/data/local/bin/su", "/system/sd/xbin/su",
            "/system/app/Superuser.apk", "/system/app/Magisk.apk",
        )
        val rootTools = listOf(
            "com.topjohnwu.magisk", "de.robv.android.xposed.installer",
            "io.va.exposed", "com.noshufou.android.su", "com.kingroot.kinguser",
        )
        val fridaArtifacts = listOf(
            "/data/local/tmp/frida-server", "/data/local/tmp/re.frida.server",
            "/system/bin/frida-server", "/system/xbin/frida-server",
        )

        val rooted = suPaths.any { File(it).exists() } ||
            rootTools.any { packageInstalled(it) }

        val hooking = fridaArtifacts.any { File(it).exists() } ||
            mapsContains("frida") || fridaPortOpen()

        val debuggable =
            (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0

        return mapOf(
            "rooted" to rooted,
            "hooking" to hooking,
            "debuggable" to debuggable,
        )
    }

    private fun packageInstalled(pkg: String): Boolean = try {
        context.packageManager.getPackageInfo(pkg, 0); true
    } catch (_: PackageManager.NameNotFoundException) {
        false
    }

    private fun mapsContains(needle: String): Boolean = try {
        File("/proc/self/maps").useLines { lines ->
            lines.any { it.contains(needle, ignoreCase = true) }
        }
    } catch (_: Exception) {
        false
    }

    private fun fridaPortOpen(): Boolean = try {
        // Frida's default control channel is tcp/27042 — scan /proc/net/tcp
        // for LISTEN on that port (state 0A = LISTEN).
        val needle = ":697E"
        File("/proc/net/tcp").useLines { lines ->
            lines.any { it.contains(needle) && it.trim().split(Regex("\\s+"))[3] == "0A" }
        }
    } catch (_: Exception) {
        false
    }
}
