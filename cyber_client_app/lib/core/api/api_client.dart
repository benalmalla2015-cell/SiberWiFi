import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/app_config.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

/// Thin Dio wrapper for the CyberNet API. Injects the agent's sanctum
/// token (secure storage) on every request and unwraps the backend's
/// `{success, message, data}` envelope into a readable error message.
class ApiClient {
  late final Dio _dio;
  final _storage = const FlutterSecureStorage();

  /// Fired when the server rejects a request as unauthenticated (401)
  /// outside of the login call — the stored token died (revoked on
  /// another device), so the shell drops back to the login screen.
  static void Function()? onUnauthorized;

  ApiClient() {
    _dio = Dio(BaseOptions(
      baseUrl: AppConfig.baseUrl,
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: AppConfig.receiveTimeout,
      headers: {
        'Accept': 'application/json',
        'X-App-Type': AppConfig.appType,
        'X-App-Version': AppConfig.appVersion,
      },
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.read(key: AppConfig.agentTokenKey);
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) {
        if (error.response?.statusCode == 401 &&
            !error.requestOptions.path.startsWith('/auth/login')) {
          try {
            onUnauthorized?.call();
          } catch (_) {}
        }
        handler.next(error);
      },
    ));
  }

  Future<void> saveAgentSession(String token, String userJson) async {
    await _storage.write(key: AppConfig.agentTokenKey, value: token);
    await _storage.write(key: AppConfig.agentUserKey, value: userJson);
  }

  Future<String?> get token => _storage.read(key: AppConfig.agentTokenKey);

  Future<void> clearSession() async {
    await _storage.delete(key: AppConfig.agentTokenKey);
    await _storage.delete(key: AppConfig.agentUserKey);
  }

  Future<Response> get(String path, {Map<String, dynamic>? query}) =>
      _dio.get(path, queryParameters: query);

  Future<Response> post(String path, {Object? data}) => _dio.post(path, data: data);

  /// Pulls the most useful message out of a DioException.
  static String errorMessage(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map) {
        if (data['errors'] is Map && (data['errors'] as Map).isNotEmpty) {
          final first = (data['errors'] as Map).values.first;
          if (first is List && first.isNotEmpty) return first.first.toString();
          return first.toString();
        }
        if (data['message'] != null) return data['message'].toString();
      }
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError) {
        return 'تعذر الاتصال بالخادم — تحقق من الإنترنت';
      }
    }
    return 'حدث خطأ غير متوقع';
  }
}
