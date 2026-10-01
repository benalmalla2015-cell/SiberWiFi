import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/app_config.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

class ApiClient {
  late final Dio _dio;
  final _storage = const FlutterSecureStorage();

  ApiClient() {
    _dio = Dio(BaseOptions(
      baseUrl: AppConfig.baseUrl,
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: AppConfig.receiveTimeout,
      headers: {'Accept': 'application/json', 'Content-Type': 'application/json'},
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.read(key: AppConfig.tokenKey);
        if (token != null) options.headers['Authorization'] = 'Bearer $token';
        handler.next(options);
      },
      onError: (error, handler) {
        if (error.response != null) {
          final data = error.response!.data;
          if (data is Map) {
            final message = data['message'] ?? '';
            final errors = data['errors'];
            if (errors is Map && errors.isNotEmpty) {
              final firstError = errors.values.first;
              final msg = firstError is List ? firstError.first : firstError.toString();
              handler.reject(DioException(
                requestOptions: error.requestOptions,
                response: error.response,
                type: error.type,
                error: msg,
                message: msg,
              ));
              return;
            }
            if (message.toString().isNotEmpty) {
              handler.reject(DioException(
                requestOptions: error.requestOptions,
                response: error.response,
                type: error.type,
                error: message,
                message: message.toString(),
              ));
              return;
            }
          }
        }
        handler.next(error);
      },
    ));
  }

  Future<Response> get(String path, {Map<String, dynamic>? params}) =>
      _dio.get(path, queryParameters: params);

  Future<Response> post(String path, {dynamic data}) =>
      _dio.post(path, data: data);

  Future<Response> put(String path, {dynamic data}) =>
      _dio.put(path, data: data);

  Future<Response> delete(String path) => _dio.delete(path);

  Future<void> saveToken(String token) =>
      _storage.write(key: AppConfig.tokenKey, value: token);

  Future<void> clearToken() => _storage.delete(key: AppConfig.tokenKey);

  Future<String?> getToken() => _storage.read(key: AppConfig.tokenKey);
}
