import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../config/app_config.dart';

class WifiProfileResult {
  const WifiProfileResult({
    required this.ok,
    required this.message,
    this.viaSystem = false,
    this.code,
  });
  final bool ok;
  final String message;

  /// True when the OS asked the user to approve the suggestion —
  /// approval completes the install out-of-band.
  final bool viaSystem;

  /// Raw channel status (e.g. 'app_disallowed', 'duplicate') — the UI
  /// uses it to offer recovery paths like opening permission settings.
  final String? code;
}

/// «تفعيل الشريحة» — installs the CyberNet Wi-Fi profile once; after
/// that the device joins any CyberNet AP silently (PLAN §4.3).
///
/// Android → WifiNetworkSuggestion via the app channel (open for the
/// pilot; the EAP-TLS branch is implemented and lights up once the
/// identity endpoint serves real certificates — inject identity +
/// caCertBase64 + clientP12Base64 here and flip AppConfig.wifiSecurity).
///
/// iOS → generates a .mobileconfig (com.apple.wifi.managed) and hands
/// it to the share sheet so the user installs it from Settings.
class WifiProfileService {
  static const _channel = MethodChannel('cyber.net/wifi');

  Future<WifiProfileResult> install({
    String ssid = AppConfig.ssid,
    String security = AppConfig.wifiSecurity,
    String? password,
    String? eapIdentity,
    String? eapDomain,
    String? caCertBase64,
    String? clientP12Base64,
    String? p12Password,
  }) async {
    if (Platform.isAndroid) {
      return _suggestAndroid(
        ssid: ssid,
        security: security,
        password: password,
        eapIdentity: eapIdentity,
        eapDomain: eapDomain,
        caCertBase64: caCertBase64,
        clientP12Base64: clientP12Base64,
        p12Password: p12Password,
      );
    }
    if (Platform.isIOS) {
      return _shareMobileConfig(ssid: ssid, security: security);
    }
    return const WifiProfileResult(
      ok: false,
      message: 'تثبيت البروفايل مدعوم على أندرويد و iOS فقط',
    );
  }

  Future<WifiProfileResult> _suggestAndroid({
    required String ssid,
    required String security,
    String? password,
    String? eapIdentity,
    String? eapDomain,
    String? caCertBase64,
    String? clientP12Base64,
    String? p12Password,
  }) async {
    try {
      final res = await _channel.invokeMethod<Map>('suggest', {
        'ssid': ssid,
        'security': security,
        'interactionRequired': true,
        'password': ?password,
        'identity': ?eapIdentity,
        'domain': ?eapDomain,
        'caCertBase64': ?caCertBase64,
        'clientP12Base64': ?clientP12Base64,
        'p12Password': ?p12Password,
      });
      final ok = res?['ok'] == true;
      final status = res?['message']?.toString() ?? '';
      if (ok) {
        return const WifiProfileResult(
          ok: true,
          viaSystem: true,
          message: 'تم تثبيت شبكة CyberNet — سيتصل جهازك تلقائياً عند توفر التغطية',
        );
      }
      if (status == 'duplicate') {
        return const WifiProfileResult(
          ok: true,
          viaSystem: true,
          message: 'شبكة CyberNet مثبتة مسبقاً على جهازك',
        );
      }
      return WifiProfileResult(
        ok: false,
        code: status,
        message: 'تعذر تثبيت البروفايل ($status)',
      );
    } on PlatformException catch (e) {
      return WifiProfileResult(
          ok: false, code: 'platform_error', message: 'تعذر تثبيت البروفايل: ${e.message}');
    }
  }

  /// «إيقاف الاتصال التلقائي» — removes our CyberNet suggestion so the
  /// phone stops auto-joining it. iOS profiles are user-installed from
  /// Settings, so there is nothing to undo programmatically.
  Future<WifiProfileResult> uninstall({String ssid = AppConfig.ssid}) async {
    if (Platform.isIOS) {
      return const WifiProfileResult(
        ok: true,
        message: 'احذف بروفايل CyberNet من الإعدادات ← عام ← إدارة VPN والجهاز',
      );
    }
    if (!Platform.isAndroid) {
      return const WifiProfileResult(ok: false, message: 'غير مدعوم على هذه المنصة');
    }
    try {
      final res = await _channel.invokeMethod<Map>('unsuggest', {'ssid': ssid});
      final ok = res?['ok'] == true;
      return WifiProfileResult(
        ok: ok,
        message: ok
            ? 'تم إيقاف الاتصال التلقائي بـ CyberNet'
            : 'تعذر إيقاف الشبكة — أزلها من إعدادات الواي فاي',
      );
    } on PlatformException catch (e) {
      return WifiProfileResult(ok: false, message: 'تعذر إيقاف الشبكة: ${e.message}');
    }
  }

  /// Opens the OS screen where the user can re-allow Wi-Fi control —
  /// MIUI's app-permission editor on Xiaomi, app details elsewhere.
  /// Called when suggest returns 'app_disallowed' (accidental «لا شكراً»).
  Future<void> openPermissionSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('openPermSettings');
    } on PlatformException {
      // nothing recoverable — the dialog already explains the manual path
    }
  }

  /// Builds a minimal .mobileconfig carrying a managed Wi-Fi payload and
  /// hands the file to the user (installs from Settings). The EAP-TLS
  /// payload keys (EAPClientConfiguration → EAP/TLS + payload certs)
  /// drop in here later the same way as Android.
  Future<WifiProfileResult> _shareMobileConfig({
    required String ssid,
    required String security,
  }) async {
    try {
      final file = await _writeMobileConfig(ssid: ssid, security: security);
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'بروفايل شبكة سايبر نت — ثبّته من الإعدادات',
      );
      return const WifiProfileResult(
        ok: true,
        viaSystem: true,
        message: 'افتح الملف المشارك ثم ثبّت البروفايل من الإعدادات ← عام ← إدارة VPN والجهاز',
      );
    } catch (e) {
      return WifiProfileResult(ok: false, message: 'تعذر توليد البروفايل: $e');
    }
  }

  Future<File> _writeMobileConfig({
    required String ssid,
    required String security,
  }) async {
    const uuid = Uuid();
    final profileUuid = uuid.v4();
    final payloadUuid = uuid.v4();
    // EncryptionType 'Any' = open network for the pilot. For WPA2-Enterprise
    // add: <key>EAPClientConfiguration</key><dict>…AcceptEAPTypes 13 (TLS),
    // TLSMinimumVersion, TLSTrustedServerNames, UserName/identity …</dict>
    // plus PayloadCertificate entries for the CA/client cert.
    final xml = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>PayloadType</key>
	<string>Configuration</string>
	<key>PayloadVersion</key>
	<integer>1</integer>
	<key>PayloadIdentifier</key>
	<string>com.saiberwifi.cybernet.profile</string>
	<key>PayloadUUID</key>
	<string>$profileUuid</string>
	<key>PayloadDisplayName</key>
	<string>سايبر نت — CyberNet</string>
	<key>PayloadDescription</key>
	<string>اتصال تلقائي بشبكات CyberNet</string>
	<key>PayloadOrganization</key>
	<string>CyberNet</string>
	<key>PayloadContent</key>
	<array>
		<dict>
			<key>PayloadType</key>
			<string>com.apple.wifi.managed</string>
			<key>PayloadVersion</key>
			<integer>1</integer>
			<key>PayloadIdentifier</key>
			<string>com.saiberwifi.cybernet.wifi</string>
			<key>PayloadUUID</key>
			<string>$payloadUuid</string>
			<key>PayloadDisplayName</key>
			<string>Wi-Fi (CyberNet)</string>
			<key>SSID_STR</key>
			<string>$ssid</string>
			<key>HIDDEN_NETWORK</key>
			<false/>
			<key>AutoJoin</key>
			<true/>
			<key>EncryptionType</key>
			<string>Any</string>
			<key>IsHotspot</key>
			<false/>
		</dict>
	</array>
</dict>
</plist>
''';
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/cybernet.mobileconfig');
    return file.writeAsString(xml);
  }
}
