import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../config/app_config.dart';
import '../services/subscriber_store.dart';

/// CYB-14 — request signing + transport pinning for /cyber/* calls.
///
/// Every request carries:
///   X-Cyber-Ts    unix seconds
///   X-Cyber-Nonce random per request (replay window defense)
///   X-Cyber-Sig   hex HMAC-SHA256(key, "METHOD|PATH|TS|NONCE|SHA256(body)|deviceId")
/// The backend's CyberHmacMiddleware recomputes the same string and
/// rejects mismatches/stale timestamps — Postman/repackaged clients
/// cannot forge it without the build-time key.
class ApiGuard extends Interceptor {
  ApiGuard();

  @override
  Future<void> onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    if (AppConfig.hmacKey.isNotEmpty) {
      final deviceId = await SubscriberStore.deviceId() ?? '';
      final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final nonce = const Uuid().v4();
      final body = options.data == null
          ? ''
          : (options.data is FormData
              ? 'multipart' // multipart streams are consumed once — sign the marker
              : jsonEncode(options.data));
      final bodyHash = sha256.convert(utf8.encode(body)).toString();
      final canonical =
          '${options.method}|${options.path}|$ts|$nonce|$bodyHash|$deviceId';
      final sig = Hmac(sha256, utf8.encode(AppConfig.hmacKey))
          .convert(utf8.encode(canonical))
          .toString();
      options.headers['X-Cyber-Ts'] = '$ts';
      options.headers['X-Cyber-Nonce'] = nonce;
      options.headers['X-Cyber-Sig'] = sig;
      options.headers['X-Cyber-Device'] = deviceId;
    }
    handler.next(options);
  }
}

/// Backwards-compat alias — screens construct `ApiGuard()` parameterless.
typedef RequestSigner = ApiGuard;

/// Pins the API host's leaf certificate by DER SHA-256 (dart-define
/// CYBER_TLS_PIN). When unset (dev/LAN), standard validation applies.
HttpClient pinnedHttpClient() {
  final context = SecurityContext();
  final client = HttpClient(context: context);
  if (AppConfig.tlsPin.isNotEmpty) {
    client.badCertificateCallback = (cert, host, port) {
      final actual = sha256.convert(cert.der).toString();
      return actual == AppConfig.tlsPin;
    };
  }
  return client;
}
