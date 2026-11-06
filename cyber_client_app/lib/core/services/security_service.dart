import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../config/app_config.dart';

/// CYB-14 — launch-time integrity gate.
///
/// Two checks before the app does anything sensitive:
///  - Signature: the APK's signing-cert SHA-256 must equal the value
///    baked in at build time (CYBER_SIGN_SHA256). A reskinned/re-signed
///    build fails the match → the app must not continue.
///  - Environment: su binaries / frida artifacts / debuggable flag on a
///    release build indicate a tampering workstation.
class SecurityService {
  static const _channel = MethodChannel('cyber.net/security');

  /// Returns null when the app is intact; an Arabic reason string when
  /// it must refuse to run. Fails OPEN when no expected signature was
  /// baked in (local/dev builds).
  static Future<String?> gate() async {
    if (kIsWeb || !Platform.isAndroid) return null;
    try {
      final sig = await _channel.invokeMethod<Map>('verifySignature', {
        'expectedSha256': AppConfig.expectedSignatureSha256,
      });
      if (sig?['ok'] == false) {
        return 'نسخة التطبيق معدّلة — ثبّت النسخة الرسمية فقط';
      }

      if (kReleaseMode && AppConfig.strictTamperCheck) {
        final t = await _channel.invokeMethod<Map>('tamperCheck');
        if (t?['rooted'] == true) {
          return 'الجهاز مكسور الحماية (Root) — لا يمكن تشغيل التطبيق';
        }
        if (t?['hooking'] == true) {
          return 'تم رصد أداة اعتراض (Frida) — لا يمكن تشغيل التطبيق';
        }
      }
      return null;
    } on PlatformException {
      // Channel missing (old native build) — degrade gracefully rather
      // than hard-crash users on a missing plugin.
      return null;
    }
  }
}
