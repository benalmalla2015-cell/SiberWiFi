package com.saiberwifi.cyber_client_app

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.net.wifi.WifiEnterpriseConfig
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSuggestion
import android.os.Build
import android.provider.Settings
import android.util.Base64
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayInputStream
import java.security.KeyStore
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import javax.net.ssl.TrustManagerFactory
import javax.net.ssl.X509TrustManager

/**
 * CYB-05 — «تفعيل الشريحة»: installs the CyberNet Wi-Fi profile through
 * WifiNetworkSuggestion (Android 10+/API 29+). Once the user approves the
 * system prompt, the device auto-joins any AP broadcasting the suggested
 * SSID — no captive portal, no manual join, which is the whole point of
 * the digital-SIM experience (cyber_plan/PLAN.md §4.3).
 *
 * Channel: cyber.net/wifi
 *   suggest   {ssid, security: open|wpa2|wpa3|eap-tls, password?,
 *              identity?, domain?, caCertBase64?, clientP12Base64?,
 *              p12Password?, interactionRequired?}
 *           → {ok: bool, status: int, message: string}
 *   unsuggest {ssid} → {ok: bool}
 *
 * EAP-TLS path (WPA2-Enterprise) is implemented now but only activated
 * when the identity endpoint starts returning a real certificate —
 * CYB-01 stub today. Until then the pilot suggests an OPEN profile for
 * SSID "CyberNet" so the flow never crashes; security is a Dart-side
 * constant (wifi_profile.dart → kPilotSecurity).
 */
class WifiProfileChannel(private val context: Context) : MethodChannel.MethodCallHandler {

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "suggest" -> suggest(call, result)
            "unsuggest" -> unsuggest(call, result)
            "openPermSettings" -> openPermSettings(result)
            "deviceId" -> result.success(androidId())
            else -> result.notImplemented()
        }
    }

    /**
     * ANDROID_ID — stable per device (and per signing key), survives
     * reinstall. It is the device_id half of the sim_no+device_id
     * credential bound on cyber_identities.
     */
    private fun androidId(): String = android.provider.Settings.Secure.getString(
        context.contentResolver,
        android.provider.Settings.Secure.ANDROID_ID,
    ) ?: ""

    private fun suggest(call: MethodCall, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.success(
                mapOf(
                    "ok" to false,
                    "status" to -1,
                    "message" to "تثبيت البروفايل يتطلب أندرويد 10 أو أحدث",
                )
            )
            return
        }

        val ssid = call.argument<String>("ssid")
        if (ssid.isNullOrBlank()) {
            result.error("bad_args", "ssid required", null)
            return
        }
        val security = (call.argument<String>("security") ?: "open").lowercase()

        val builder = WifiNetworkSuggestion.Builder().setSsid(ssid)
        call.argument<Boolean>("interactionRequired")?.let {
            builder.setIsAppInteractionRequired(it)
        }

        try {
            when (security) {
                "open" -> {
                    // Open network — no extra config needed.
                }
                "wpa2" -> {
                    val password = call.argument<String>("password")
                        ?: throw IllegalArgumentException("password required")
                    builder.setWpa2Passphrase(password)
                }
                "wpa3" -> {
                    val password = call.argument<String>("password")
                        ?: throw IllegalArgumentException("password required")
                    builder.setWpa3Passphrase(password)
                }
                "eap-tls" -> {
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
                        result.success(
                            mapOf(
                                "ok" to false,
                                "status" to -2,
                                "message" to "اقتراح شبكة مؤسسة (EAP-TLS) يتطلب أندرويد 11 أو أحدث",
                            )
                        )
                        return
                    }
                    builder.setWpa2EnterpriseConfig(buildEnterpriseConfig(call))
                }
                else -> throw IllegalArgumentException("unknown security: $security")
            }
        } catch (e: Exception) {
            result.success(mapOf("ok" to false, "status" to -3, "message" to e.message))
            return
        }

        val wifiManager =
            context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val suggestion = builder.build()
        var status = wifiManager.addNetworkSuggestions(listOf(suggestion))

        // «لا شكراً» on the approval prompt latches APP_DISALLOWED while a
        // stale suggestion stays queued — drop it and retry once so the
        // system re-posts the approval dialog instead of dead-ending.
        if (status == WifiManager.STATUS_NETWORK_SUGGESTIONS_ERROR_APP_DISALLOWED) {
            wifiManager.removeNetworkSuggestions(listOf(suggestion))
            status = wifiManager.addNetworkSuggestions(listOf(suggestion))
        }

        result.success(
            mapOf(
                "ok" to (status == WifiManager.STATUS_NETWORK_SUGGESTIONS_SUCCESS),
                "status" to status,
                "message" to statusMessage(status),
            )
        )
    }

    /**
     * Opens the screen where the user can re-allow Wi-Fi control after
     * an accidental «لا شكراً» — MIUI records the denial permanently
     * (APP_DISALLOWED on every later addNetworkSuggestions), so the app
     * must take the user to the toggle itself. On MIUI the permission
     * editor lists «تغيير اتصال شبكة Wi-Fi»; on other ROMs we land on
     * the system app-details page as the closest equivalent.
     */
    private fun openPermSettings(result: MethodChannel.Result) {
        val intents = listOf(
            Intent("miui.intent.action.APP_PERM_EDITOR")
                .putExtra("extra_pkgname", context.packageName),
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:${context.packageName}"),
            ),
        )
        for (intent in intents) {
            try {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(intent)
                result.success(mapOf("ok" to true))
                return
            } catch (_: ActivityNotFoundException) {
                // try the fallback
            }
        }
        result.success(mapOf("ok" to false))
    }

    private fun unsuggest(call: MethodCall, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.success(mapOf("ok" to false))
            return
        }
        val ssid = call.argument<String>("ssid") ?: ""
        val wifiManager =
            context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val status = wifiManager.removeNetworkSuggestions(
            listOf(WifiNetworkSuggestion.Builder().setSsid(ssid).build())
        )
        result.success(mapOf("ok" to (status == WifiManager.STATUS_NETWORK_SUGGESTIONS_SUCCESS)))
    }

    /**
     * WPA2-Enterprise EAP-TLS config. Wired for the future identity
     * payload: CA cert (base64 X.509), optional client PKCS#12 bundle,
     * server domain + identity. Android 11+ enforces a Root CA and a
     * domain name for TLS enterprise suggestions, so both are required
     * before this branch can be switched on.
     */
    private fun buildEnterpriseConfig(call: MethodCall): WifiEnterpriseConfig {
        val enterprise = WifiEnterpriseConfig()
        enterprise.eapMethod = WifiEnterpriseConfig.Eap.TLS
        enterprise.setPhase2Method(WifiEnterpriseConfig.Phase2.NONE)
        enterprise.identity = call.argument<String>("identity")
            ?: throw IllegalArgumentException("identity required for eap-tls")
        enterprise.anonymousIdentity = enterprise.identity

        call.argument<String>("domain")?.let { enterprise.domainSuffixMatch = it }
        call.argument<String>("caCertBase64")?.let {
            enterprise.caCertificate = decodeX509(it)
        }
        call.argument<String>("clientP12Base64")?.let { p12 ->
            installClientBundle(enterprise, p12, call.argument<String>("p12Password"))
        }
        return enterprise
    }

    private fun decodeX509(b64: String): X509Certificate {
        val bytes = Base64.decode(b64, Base64.DEFAULT)
        return CertificateFactory.getInstance("X.509")
            .generateCertificate(ByteArrayInputStream(bytes)) as X509Certificate
    }

    /** Extracts the private key + client cert chain out of a PKCS#12. */
    private fun installClientBundle(
        enterprise: WifiEnterpriseConfig,
        p12Base64: String,
        password: String?,
    ) {
        val ks = KeyStore.getInstance("PKCS12")
        ks.load(
            ByteArrayInputStream(Base64.decode(p12Base64, Base64.DEFAULT)),
            password?.toCharArray(),
        )
        val alias = ks.aliases().asSequence().firstOrNull { ks.isKeyEntry(it) }
            ?: throw IllegalArgumentException("pkcs12 has no key entry")
        val key = ks.getKey(alias, password?.toCharArray()) as java.security.PrivateKey
        val chain = ks.getCertificateChain(alias)
            .map { it as X509Certificate }
            .toTypedArray()
        enterprise.setClientKeyEntryWithCertificateChain(key, chain)

        // Cross-check the presented chain against the CA when provided.
        try {
            val tmf = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm())
            tmf.init(ks)
        } catch (_: Exception) { /* best-effort */ }
    }

    private fun statusMessage(status: Int): String = when (status) {
        WifiManager.STATUS_NETWORK_SUGGESTIONS_SUCCESS -> "ok"
        WifiManager.STATUS_NETWORK_SUGGESTIONS_ERROR_INTERNAL -> "internal"
        WifiManager.STATUS_NETWORK_SUGGESTIONS_ERROR_APP_DISALLOWED -> "app_disallowed"
        WifiManager.STATUS_NETWORK_SUGGESTIONS_ERROR_ADD_DUPLICATE -> "duplicate"
        WifiManager.STATUS_NETWORK_SUGGESTIONS_ERROR_ADD_EXCEEDS_MAX_PER_APP -> "exceeds_max"
        WifiManager.STATUS_NETWORK_SUGGESTIONS_ERROR_ADD_INVALID -> "invalid"
        WifiManager.STATUS_NETWORK_SUGGESTIONS_ERROR_ADD_NOT_ALLOWED -> "not_allowed"
        else -> "status_$status"
    }
}
