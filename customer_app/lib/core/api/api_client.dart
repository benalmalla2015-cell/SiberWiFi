import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/app_config.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

class ApiClient {
  late final Dio _dio;
  final _storage = const FlutterSecureStorage();

  /// Fired when the server rejects a request because the account was
  /// suspended (HTTP 403 + code=account_suspended). Set by the app shell
  /// so the suspended screen can be shown immediately even if the FCM
  /// push was not delivered.
  static void Function()? onSuspended;

  /// Fired when the server rejects a request as unauthenticated (HTTP 401).
  /// The stored token is no longer valid (e.g. it was revoked when the same
  /// account logged in on another device), so the app shell forces a logout
  /// and returns to the login screen instead of showing endless load errors.
  static void Function()? onUnauthorized;

  static const _credentialPaths = [
    '/auth/login',
    '/auth/register',
    '/auth/register-network-owner',
    '/auth/forgot-password',
    '/auth/reset-password',
    '/auth/verify-otp',
    '/auth/logout',
  ];

  ApiClient() {
    _dio = Dio(BaseOptions(
      baseUrl: AppConfig.baseUrl,
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: AppConfig.receiveTimeout,
      headers: {'Accept': 'application/json', 'X-App-Type': AppConfig.appType, 'X-App-Version': AppConfig.appVersion},
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.read(key: AppConfig.tokenKey);
        if (token != null) options.headers['Authorization'] = 'Bearer $token';

        options.headers['X-App-Type']    = AppConfig.appType;
        options.headers['X-App-Version'] = AppConfig.appVersion;

        if (Platform.isAndroid) {
          try {
            final deviceInfo = await DeviceInfoPlugin().androidInfo;
            options.headers['X-Device-Model'] =
                '${deviceInfo.manufacturer} ${deviceInfo.model}'.trim();
          } catch (_) {}
        }

        handler.next(options);
      },
      onError: (error, handler) {
        if (error.response != null) {
          final data = error.response!.data;
          if (error.response!.statusCode == 403 &&
              data is Map &&
              data['code'] == 'account_suspended') {
            try { onSuspended?.call(); } catch (_) {}
          }
          if (error.response!.statusCode == 401 &&
              !_credentialPaths.any(
                (p) => error.requestOptions.path.startsWith(p),
              )) {
            try { onUnauthorized?.call(); } catch (_) {}
          }
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
      _dio.post(path, data: _encodeBody(data));

  /// PHP does not populate the request body for multipart/form-data on PUT
  /// requests, so plain maps must be sent urlencoded (file uploads keep
  /// using multipart POST + _method spoofing elsewhere).
  Future<Response> put(String path, {dynamic data}) {
    if (data is Map<String, dynamic>) {
      return _dio.put(
        path,
        data: Map<String, dynamic>.fromEntries(
          data.entries
              .where((e) => e.value != null)
              .map((e) => MapEntry(e.key, e.value.toString())),
        ),
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
    }
    return _dio.put(path, data: data);
  }

  Future<Response> delete(String path) => _dio.delete(path);

  /// The live backend expects multipart/form-data bodies for POST/PUT
  /// requests (application/json payloads are not parsed). Convert plain
  /// maps to [FormData] so Dio sends the correct Content-Type.
  dynamic _encodeBody(dynamic data) {
    if (data is Map<String, dynamic>) {
      return FormData.fromMap(data);
    }
    return data;
  }

  Future<void> saveToken(String token) =>
      _storage.write(key: AppConfig.tokenKey, value: token);

  Future<void> clearToken() => _storage.delete(key: AppConfig.tokenKey);

  Future<String?> getToken() => _storage.read(key: AppConfig.tokenKey);
}
