package com.saiberwifi.customerapp.vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.TrafficStats
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import android.util.Log
import androidx.core.app.NotificationCompat
import com.saiberwifi.customerapp.MainActivity
import com.saiberwifi.customerapp.ai.NetworkClassifierV2
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.Socket
import java.net.InetSocketAddress
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * NetworkBoosterVpnService — "محرك تسريع الشبكة" engine (ported from aden_data).
 *
 * Architecture (Inverted VPN / WRAPPER_MODE):
 *  - Target app → addDisallowedApplication → bypasses VPN → 100% native speed.
 *  - All other apps → enter VPN tunnel → packets are silently DROPPED.
 *  - In EMERGENCY/DEEP_FREEZE: additionally inject TCP RST to disconnect other
 *    apps' heavy connections immediately instead of letting them time-out.
 *  - Bandwidth measured via TrafficStats for real KB/s.
 */
class NetworkBoosterVpnService : VpnService() {

    companion object {
        const val CHANNEL_ID    = "saiberwifi_booster_channel"
        const val NOTIF_ID      = 2001
        const val TAG           = "SaiberBoosterVPN"
        const val ACTION_START  = "com.saiberwifi.customerapp.START_VPN"
        const val ACTION_STOP   = "com.saiberwifi.customerapp.STOP_VPN"
        const val EXTRA_PROFILE     = "profile"
        const val EXTRA_TARGET_PKG  = "target_pkg"
        const val EXTRA_TARGET_UID  = "target_uid"

        @Volatile var isRunning     = false
        @Volatile var downloadBytes : Long = 0L
        @Volatile var uploadBytes   : Long = 0L
        @Volatile var lastLatencyMs : Int  = 0

        @Volatile var currentAiState : AiState = AiState.NORMAL
        @Volatile var targetPkg      : String  = ""
        @Volatile var targetUid      : Int     = TrafficStats.UNSUPPORTED
    }

    private var vpnInterface  : ParcelFileDescriptor? = null
    private val running         = AtomicBoolean(false)
    private var readerThread  : Thread? = null
    private var classifier    : NetworkClassifierV2? = null

    private val aiExecutor  = Executors.newSingleThreadScheduledExecutor()
    private val bwExecutor  = Executors.newSingleThreadScheduledExecutor()
    private var bwTask      : ScheduledFuture<*>? = null
    private val mainHandler   = Handler(Looper.getMainLooper())

    private var prevRxBytes   = 0L
    private var prevTxBytes   = 0L
    private val throughputWindow = ArrayDeque<Long>(5)

    private var networkCallback : ConnectivityManager.NetworkCallback? = null
    private var lastActiveNetType = -1

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) { stopEngine(); return START_NOT_STICKY }

        val tPkg  = intent?.getStringExtra(EXTRA_TARGET_PKG)  ?: ""
        val tUid  = intent?.getIntExtra(EXTRA_TARGET_UID, TrafficStats.UNSUPPORTED)
                    ?: TrafficStats.UNSUPPORTED
        val profile = intent?.getStringExtra(EXTRA_PROFILE) ?: "CELLULAR"

        startEngine(tPkg, tUid, profile)
        return START_STICKY
    }

    private fun startEngine(tPkg: String, tUid: Int, profile: String) {
        if (running.getAndSet(true)) return

        createNotificationChannel()
        targetPkg = tPkg
        targetUid = tUid

        startForeground(NOTIF_ID, buildNotification(AiState.NORMAL, tPkg))

        if (!buildVpnInterface(tPkg)) {
            running.set(false)
            stopSelf()
            return
        }

        isRunning = true
        currentAiState = AiState.NORMAL

        classifier = NetworkClassifierV2(applicationContext).also { it.initialize() }

        startDropAllLoop()
        startBandwidthMonitor(tUid)
        startAiMonitor(tPkg, tUid)
        registerNetworkCallback(tPkg, tUid)

        Log.i(TAG, "VPN started | profile=$profile | target=$tPkg | uid=$tUid")
    }

    private fun buildVpnInterface(tPkg: String): Boolean {
        return try {
            val builder = Builder()
                .setSession("سايبر WiFi")
                .addAddress("10.0.0.2", 24)
                .addRoute("0.0.0.0", 0)
                .addDnsServer("8.8.8.8")
                .addDnsServer("1.1.1.1")
                .setMtu(1280)
                .setBlocking(true)

            try { builder.addDisallowedApplication(packageName) } catch (_: Exception) {}

            if (tPkg.isNotEmpty()) {
                try {
                    builder.addDisallowedApplication(tPkg)
                    Log.i(TAG, "Target $tPkg will bypass VPN (native speed)")
                } catch (e: Exception) {
                    Log.w(TAG, "addDisallowedApplication($tPkg) failed: ${e.message}")
                }
            }

            val fd = builder.establish()
            if (fd == null) {
                Log.e(TAG, "establish() returned null — VPN permission not granted?")
                return false
            }
            protect(fd.fd)
            vpnInterface?.close()
            vpnInterface = fd
            true
        } catch (e: Exception) {
            Log.e(TAG, "buildVpnInterface error", e)
            false
        }
    }

    private fun startDropAllLoop() {
        readerThread?.interrupt()
        readerThread = Thread({
            val fd           = vpnInterface?.fileDescriptor ?: return@Thread
            val inputStream  = FileInputStream(fd)
            val outputStream = FileOutputStream(fd)
            val rawBuf       = ByteArray(32_767)
            Log.i(TAG, "DROP-ALL loop started")

            while (running.get()) {
                try {
                    val length = inputStream.read(rawBuf)
                    if (length <= 0) continue
                    val packet = rawBuf.copyOf(length)

                    val state = currentAiState
                    if (state == AiState.EMERGENCY || state == AiState.DEEP_FREEZE) {
                        if (isTcpPacket(packet)) {
                            try { PacketSurgeon.killTcp(packet, outputStream) } catch (_: Exception) {}
                        }
                    }
                } catch (e: Exception) {
                    if (running.get()) Log.e(TAG, "DROP loop error", e)
                }
            }
            Log.i(TAG, "DROP-ALL loop exited")
        }, "saiber-booster-drop-loop")
        readerThread?.isDaemon = true
        readerThread?.start()
    }

    private fun isTcpPacket(packet: ByteArray): Boolean =
        packet.size >= 20 && (packet[9].toInt() and 0xFF) == 6

    private fun startBandwidthMonitor(uid: Int) {
        bwTask?.cancel(false)

        prevRxBytes = TrafficStats.getTotalRxBytes().coerceAtLeast(0)
        prevTxBytes = TrafficStats.getTotalTxBytes().coerceAtLeast(0)

        var latencyTick = 0

        bwTask = bwExecutor.scheduleAtFixedRate({
            try {
                val rx = TrafficStats.getTotalRxBytes().coerceAtLeast(0)
                val tx = TrafficStats.getTotalTxBytes().coerceAtLeast(0)
                val deltaRx = (rx - prevRxBytes).coerceAtLeast(0)
                val deltaTx = (tx - prevTxBytes).coerceAtLeast(0)
                prevRxBytes = rx
                prevTxBytes = tx

                downloadBytes = deltaRx
                uploadBytes   = deltaTx

                latencyTick++
                if (latencyTick >= 10) {
                    latencyTick = 0
                    measureLatency()
                }
            } catch (e: Exception) {
                Log.e(TAG, "BW monitor error", e)
            }
        }, 1, 1, TimeUnit.SECONDS)
    }

    private fun measureLatency() {
        try {
            val socket = Socket()
            protect(socket)
            val start = SystemClock.elapsedRealtime()
            socket.connect(InetSocketAddress("8.8.8.8", 53), 3000)
            lastLatencyMs = (SystemClock.elapsedRealtime() - start).toInt()
            socket.close()
        } catch (_: Exception) {
            lastLatencyMs = 999
        }
    }

    private fun startAiMonitor(tPkg: String, tUid: Int) {
        aiExecutor.scheduleAtFixedRate({
            try {
                val kbps = downloadBytes / 1024f
                throughputWindow.addLast(kbps.toLong())
                if (throughputWindow.size > 5) throughputWindow.removeFirst()

                val newState = classifier?.classify(kbps) ?: AiState.NORMAL
                if (newState != currentAiState) {
                    currentAiState = newState
                    Log.i(TAG, "AI -> $newState | ${kbps.toInt()} KB/s")
                    mainHandler.post { updateNotification(newState, tPkg) }
                }
            } catch (e: Exception) {
                Log.e(TAG, "AI monitor error", e)
            }
        }, 2, 1, TimeUnit.SECONDS)
    }

    private fun registerNetworkCallback(tPkg: String, tUid: Int) {
        try {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return
            unregisterNetworkCallback()
            val cb = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    val caps = cm.getNetworkCapabilities(network) ?: return
                    val netType = when {
                        caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)     -> 1
                        caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> 2
                        else -> 0
                    }
                    if (lastActiveNetType != -1 && lastActiveNetType != netType) {
                        Log.i(TAG, "Network switched ${lastActiveNetType}->$netType | rebuilding tunnel")
                        mainHandler.post {
                            try {
                                vpnInterface?.close()
                                vpnInterface = null
                                if (buildVpnInterface(tPkg)) {
                                    startDropAllLoop()
                                    startBandwidthMonitor(tUid)
                                    Log.i(TAG, "Tunnel rebuilt on network switch")
                                }
                            } catch (e: Exception) {
                                Log.e(TAG, "Tunnel rebuild failed", e)
                            }
                        }
                    }
                    lastActiveNetType = netType
                }
            }
            networkCallback = cb
            val request = NetworkRequest.Builder()
                .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                .build()
            cm.registerNetworkCallback(request, cb)
        } catch (e: Exception) {
            Log.e(TAG, "registerNetworkCallback error", e)
        }
    }

    private fun unregisterNetworkCallback() {
        try {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return
            networkCallback?.let { cm.unregisterNetworkCallback(it) }
            networkCallback = null
            lastActiveNetType = -1
        } catch (_: Exception) {}
    }

    fun stopEngine() {
        if (!running.getAndSet(false)) return
        bwTask?.cancel(false)
        aiExecutor.shutdownNow()
        readerThread?.interrupt()
        readerThread = null
        try { vpnInterface?.close() } catch (_: Exception) {}
        vpnInterface = null
        unregisterNetworkCallback()
        classifier?.close()
        classifier = null
        isRunning      = false
        currentAiState = AiState.NORMAL
        downloadBytes  = 0L
        uploadBytes    = 0L
        lastLatencyMs  = 0
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
        Log.i(TAG, "VPN stopped")
    }

    override fun onRevoke() { stopEngine(); super.onRevoke() }
    override fun onDestroy() { stopEngine(); super.onDestroy() }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(
                CHANNEL_ID,
                "سايبر WiFi — محرك تسريع الشبكة",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "إشعار تشغيل محرك التركيز"
                setShowBadge(false)
            }
            getSystemService(NotificationManager::class.java)?.createNotificationChannel(ch)
        }
    }

    private fun appLabel(pkg: String): String = try {
        packageManager.getApplicationLabel(
            packageManager.getApplicationInfo(pkg, 0)
        ).toString()
    } catch (_: Exception) { pkg }

    private fun buildNotification(state: AiState, tPkg: String): Notification {
        val pi = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE,
        )
        val label = if (tPkg.isNotEmpty()) appLabel(tPkg) else "بدون هدف"
        val (title, text) = when (state) {
            AiState.DEEP_FREEZE ->
                "محرك التسريع — وضع الإنقاذ" to "شبكة حرجة"
            AiState.EMERGENCY   ->
                "محرك التسريع — وضع الطوارئ" to "شبكة ضعيفة جداً"
            AiState.DEGRADED    ->
                "محرك التسريع — شبكة ضعيفة" to "مُركَّز على: $label"
            AiState.NORMAL      ->
                "محرك التسريع يعمل" to "مُركَّز على: $label"
        }
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentIntent(pi)
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun updateNotification(state: AiState, tPkg: String) {
        getSystemService(NotificationManager::class.java)
            ?.notify(NOTIF_ID, buildNotification(state, tPkg))
    }
}
