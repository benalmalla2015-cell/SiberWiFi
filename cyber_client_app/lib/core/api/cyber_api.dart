import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../models/models.dart';
import 'api_guard.dart';

/// Typed failure carrying the backend's Arabic messages. `fieldErrors`
/// maps validation field → first message for form red-marking (422).
class CyberApiException implements Exception {
  CyberApiException(this.message, {this.statusCode, this.fieldErrors = const {}});
  final String message;
  final int? statusCode;
  final Map<String, String> fieldErrors;

  @override
  String toString() => message;
}

/// EAP-TLS provisioning payload served by GET /cyber/identity/certificate
/// (ops-staged bundles until the CYB-01 issuer lands).
class IdentityCert {
  IdentityCert({
    required this.identity,
    required this.domain,
    required this.p12Base64,
    required this.p12Password,
    required this.caBase64,
  });

  final String identity;
  final String domain;
  final String p12Base64;
  final String p12Password;
  final String caBase64;

  factory IdentityCert.fromJson(Map<String, dynamic> j) => IdentityCert(
        identity: j['identity'] as String,
        domain: j['domain'] as String,
        p12Base64: j['p12_base64'] as String,
        p12Password: j['p12_password'] as String,
        caBase64: j['ca_base64'] as String,
      );
}

/// Thin client over the CyberNet API (contracts: routes/cyber/*.php).
/// Subscriber calls carry sim_no + device_id — the enrolled device is
/// the credential; there is no user account (CYB-04 convention).
class CyberApi {
  CyberApi({String? baseUrl})
      : _dio = Dio(
          BaseOptions(
            baseUrl: baseUrl ?? AppConfig.baseUrl,
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 20),
            headers: {'Accept': 'application/json'},
          ),
        ) {
    // CYB-14: HMAC request signing + optional leaf-cert pinning. Both
    // no-op when their dart-defines are unset (dev/pilot builds).
    _dio.interceptors.add(ApiGuard());
    if (AppConfig.tlsPin.isNotEmpty && !kIsWeb) {
      _dio.httpClientAdapter =
          IOHttpClientAdapter(createHttpClient: pinnedHttpClient);
    }
  }

  final Dio _dio;

  // ---------- public lookups (shared routes/api.php, read-only) ----------

  Future<List<Governorate>> governorates() async {
    final j = await _get('/governorates');
    return _list(j).map(Governorate.fromJson).toList();
  }

  Future<List<District>> districts(int governorateId) async {
    final j = await _get('/directorates/$governorateId/sub-directorates');
    return _list(j).map(District.fromJson).toList();
  }

  // ---------- registration (CYB-03) ----------

  Future<SimIssue> register({
    required String fullName,
    required String documentType, // national_id | passport
    required int directorateId,
    required int subDirectorateId,
    required String deviceId,
    required File idFront,
    File? idBack,
  }) async {
    final form = FormData.fromMap({
      'full_name': fullName,
      'document_type': documentType,
      'directorate_id': directorateId,
      'sub_directorate_id': subDirectorateId,
      'device_id': deviceId,
      'id_front_image': await MultipartFile.fromFile(
        idFront.path,
        filename: 'id_front.jpg',
      ),
      if (idBack != null)
        'id_back_image': await MultipartFile.fromFile(
          idBack.path,
          filename: 'id_back.jpg',
        ),
    });
    final j = await _post('/cyber/register', form);
    return SimIssue.fromJson(j);
  }

  // ---------- device binding (CYB-05) ----------

  Future<void> bindDevice({
    required String simNo,
    required String deviceId,
    String? fcmToken,
  }) async {
    await _post('/cyber/identity/bind', {
      'sim_no': simNo,
      'device_id': deviceId,
      if (fcmToken != null && fcmToken.isNotEmpty) 'fcm_token': fcmToken,
    });
  }

  // ---------- billing (CYB-04) ----------

  Future<List<CyberPackage>> packages() async {
    final j = await _get('/cyber/packages');
    return _list(j).map(CyberPackage.fromJson).toList();
  }

  Future<SubscriberStatus> current({
    required String simNo,
    required String deviceId,
  }) async {
    final j = await _get(
      '/cyber/subscriptions/current',
      query: {'sim_no': simNo, 'device_id': deviceId},
    );
    final d = j['data'] as Map<String, dynamic>;
    return SubscriberStatus(
      balance: (d['balance'] as num?)?.toDouble() ?? 0,
      subscription: d['subscription'] == null
          ? null
          : SubscriptionInfo.fromJson(d['subscription'] as Map<String, dynamic>),
    );
  }

  Future<SubscriptionInfo> subscribe({
    required String simNo,
    required String deviceId,
    required int packageId,
    required String idempotencyKey,
  }) async {
    final j = await _post('/cyber/subscriptions', {
      'sim_no': simNo,
      'device_id': deviceId,
      'package_id': packageId,
      'idempotency_key': idempotencyKey,
    });
    return SubscriptionInfo.fromJson(j['data'] as Map<String, dynamic>);
  }

  // ---------- identity certificate (CYB-01/02 pilot) ----------

  /// EAP-TLS material staged by ops (storage/app/cyber/certs). 404 →
  /// returns null so the caller can fall back to an open suggestion.
  Future<IdentityCert?> certificate({
    required String simNo,
    required String deviceId,
  }) async {
    try {
      final j = await _get(
        '/cyber/identity/certificate',
        query: {'sim_no': simNo, 'device_id': deviceId},
      );
      return IdentityCert.fromJson(j['data'] as Map<String, dynamic>);
    } on CyberApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  // ---------- account deletion (CYB-13, Google Play) ----------

  Future<void> deleteAccount({
    required String simNo,
    required String deviceId,
  }) async {
    await _delete('/cyber/account', {
      'sim_no': simNo,
      'device_id': deviceId,
    });
  }

  // ---------- transaction log (CYB-05) ----------

  Future<ActivityData> activity({
    required String simNo,
    required String deviceId,
  }) async {
    final j = await _get(
      '/cyber/activity',
      query: {'sim_no': simNo, 'device_id': deviceId},
    );
    return ActivityData.fromJson(j);
  }

  // ---------- plumbing ----------

  List<Map<String, dynamic>> _list(Map<String, dynamic> j) =>
      ((j['data'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

  Future<Map<String, dynamic>> _get(String path,
      {Map<String, dynamic>? query}) async {
    try {
      final r = await _dio.get(path, queryParameters: query);
      return _unwrap(r.data);
    } on DioException catch (e) {
      throw _err(e);
    }
  }

  Future<Map<String, dynamic>> _post(String path, Object body) async {
    try {
      final r = await _dio.post(path, data: body);
      return _unwrap(r.data);
    } on DioException catch (e) {
      throw _err(e);
    }
  }

  Future<Map<String, dynamic>> _delete(String path, Object body) async {
    try {
      final r = await _dio.delete(path, data: body);
      return _unwrap(r.data);
    } on DioException catch (e) {
      throw _err(e);
    }
  }

  Map<String, dynamic> _unwrap(dynamic data) {
    final j = Map<String, dynamic>.from(data as Map);
    if (j['success'] == false) {
      throw CyberApiException(
        (j['message'] ?? 'حدث خطأ').toString(),
        fieldErrors: _fieldErrors(j),
      );
    }
    return j;
  }

  CyberApiException _err(DioException e) {
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return CyberApiException('تعذر الاتصال بالخادم — تحقق من الشبكة');
    }
    final data = e.response?.data;
    if (data is Map) {
      return CyberApiException(
        (data['message'] ?? 'حدث خطأ في الخادم').toString(),
        statusCode: e.response?.statusCode,
        fieldErrors: _fieldErrors(Map<String, dynamic>.from(data)),
      );
    }
    return CyberApiException('حدث خطأ في الخادم (${e.response?.statusCode ?? '؟'})');
  }

  Map<String, String> _fieldErrors(Map<String, dynamic> j) {
    final errors = j['errors'];
    if (errors is! Map) return const {};
    return {
      for (final e in errors.entries)
        e.key.toString(): (e.value is List && (e.value as List).isNotEmpty)
            ? (e.value as List).first.toString()
            : e.value.toString(),
    };
  }
}
