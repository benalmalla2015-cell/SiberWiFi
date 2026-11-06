/// CyberNet client app (CYB-05) — build-time configuration.
///
/// The default base URL targets the local API served by
/// `testapp/tools/cyber_local_api.php --serve` and tunnelled to a USB
/// device with `adb reverse tcp:8090 tcp:8090`.
/// Override for LAN/staging builds:
///   flutter run --dart-define=CYBER_API_URL=https://staging.saiberwifi.net/api
class AppConfig {
  static const String appName = 'سايبر نت';
  static const String appVersion = '0.1.0';

  /// Identifies this app to shared middleware (same header the other
  /// saiberwifi apps send).
  static const String appType = 'cyber_client_app';

  static const String baseUrl = String.fromEnvironment(
    'CYBER_API_URL',
    defaultValue: 'http://127.0.0.1:8090/api',
  );

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 20);

  /// SSID suggested by «تفعيل الشريحة» — matches the CYB-02 host template.
  static const String ssid = 'CyberNet';

  /// SIM numbers are 9 digits starting with 74 (config('cyber.sim_*')).
  static const String simPrefix = '74';
  static const int simLength = 9;
  static final RegExp simRegex = RegExp(r'^74[0-9]{7}$');

  /// Secure-storage keys for the agent session (CYB-07 screens share
  /// this app). Keyed under cyber.* to never collide with other apps'
  /// secure entries on the same device.
  static const String agentTokenKey = 'cyber.agent.token';
  static const String agentUserKey = 'cyber.agent.user';

  /// Pilot profile security. The CyberNet APs are WPA2-Enterprise
  /// (EAP-TLS), but certificate issuance is still a stub — until the
  /// identity endpoint returns a real cert the suggestion goes out as
  /// `open`. Flip to 'eap-tls' and feed identity/certs when CYB-01 lands.
  static const String wifiSecurity = 'open';

  // ---------- CYB-14 hardening (build-time secrets, never in repo) ----------

  /// Expected SHA-256 of the release signing certificate. Empty on dev
  /// builds — the gate then reports the actual digest without failing.
  static const String expectedSignatureSha256 = String.fromEnvironment(
    'CYBER_SIGN_SHA256',
    defaultValue: '',
  );

  /// Root/frida enforcement — release builds set it via
  /// --dart-define=CYBER_STRICT_TAMPER=true.
  static const bool strictTamperCheck = bool.fromEnvironment(
    'CYBER_STRICT_TAMPER',
    defaultValue: false,
  );

  /// Request-signing key for /cyber/* calls. Empty disables signing so
  /// dev builds keep working against local backends without the key.
  static const String hmacKey = String.fromEnvironment(
    'CYBER_HMAC_KEY',
    defaultValue: '',
  );

  /// Leaf-cert DER SHA-256 pin for the API host (empty = standard TLS).
  static const String tlsPin = String.fromEnvironment(
    'CYBER_TLS_PIN',
    defaultValue: '',
  );

  /// Firebase project shared with the rest of the saiberwifi apps.
  /// The cyber package is not registered in google-services.json, so we
  /// initialise manually with the staging app's registered appId — FCM
  /// tokens are project-scoped and the backend pushes via
  /// NotificationService::sendToTokens which only needs the token.
  static const String firebaseApiKey =
      'AIzaSyBJQDv4E3Qi5JIiVrOA2F5VJfgto2er4vg';
  static const String firebaseAppId =
      '1:904789743936:android:f8d7227e513baa6cfc02a6';
  static const String firebaseSenderId = '904789743936';
  static const String firebaseProjectId = 'siberwifi-73234';
}
