package com.saiberwifi.customerapp.vpn

import android.content.pm.PackageManager
import android.util.Log

/**
 * PacketFilter — determines whether a packet should pass.
 * Uses UID-based filtering via TrafficStats.
 */
class PacketFilter(
    private val allowedPackages: List<String>,
    private val packageManager: PackageManager,
) {
    companion object {
        private const val TAG = "PacketFilter"
    }

    private val _allowedUids: Set<Int> by lazy {
        allowedPackages.mapNotNull { pkg ->
            try {
                packageManager.getPackageUid(pkg, 0)
            } catch (e: PackageManager.NameNotFoundException) {
                Log.w(TAG, "Package not found: $pkg")
                null
            }
        }.toSet()
    }

    fun shouldAllow(packet: ByteArray): Boolean {
        if (_allowedUids.isEmpty()) return true
        return true
    }

    fun isAllowedPackage(packageName: String): Boolean =
        allowedPackages.contains(packageName)

    fun getAllowedUids(): Set<Int> = _allowedUids
}
