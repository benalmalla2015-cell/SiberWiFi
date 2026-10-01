import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../core/cache/hive_service.dart';
import '../../../core/models/user_model.dart';
import '../../../core/services/device_identity_service.dart';

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.read(apiClientProvider)),
);

class AuthRepository {
  final ApiClient _api;
  AuthRepository(this._api);

  Future<UserModel> login(String phone, String password) async {
    try {
      final deviceId = await DeviceIdentityService.getId();
      final response = await _api.post(
        '/auth/login',
        data: {'phone': phone, 'password': password, 'device_id': deviceId},
      );
      final data = response.data;
      if (data['success'] != true) {
        throw data['message'] ?? 'فشل تسجيل الدخول';
      }
      final user = UserModel.fromJson(data['user']);
      await _api.setToken(data['token']);
      await HiveService.saveUser(user);
      return user;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw 'رقم الهاتف أو كلمة المرور غير صحيحة';
      }
      if (e.response?.statusCode == 403 ||
          e.response?.statusCode == 409) {
        final body = e.response?.data;
        if (body is Map && body['message'] != null) {
          throw body['message'].toString();
        }
        throw 'الحساب موقوف. تواصل مع الدعم';
      }
      if (e.response?.statusCode == 422) {
        final body = e.response?.data;
        if (body is Map) {
          final errors = body['errors'];
          if (errors is Map && errors.isNotEmpty) {
            final msgs = errors.values
                .expand((v) => v is List ? v : [v])
                .join('\n');
            throw msgs;
          }
          if (body['message'] != null) throw body['message'].toString();
        }
        throw 'بيانات غير صحيحة';
      }
      throw 'خطأ في الاتصال بالخادم';
    }
  }

  Future<UserModel> registerNetworkOwner(dynamic data) async {
    try {
      final deviceId = await DeviceIdentityService.getId();
      if (data is FormData) {
        data.fields.add(MapEntry('device_id', deviceId));
      } else if (data is Map<String, dynamic>) {
        data['device_id'] = deviceId;
      }
      final response = await _api.post(
        '/auth/register-network-owner',
        data: data,
      );
      final res = response.data;
      if (res['success'] != true) {
        throw res['message'] ?? 'فشل إنشاء الحساب';
      }
      final user = UserModel.fromJson(res['user']);
      await _api.setToken(res['token']);
      await HiveService.saveUser(user);
      return user;
    } on DioException catch (e) {
      final body = e.response?.data;
      if (body is Map) {
        final errors = body['errors'];
        if (errors is Map && errors.isNotEmpty) {
          final msgs = errors.values
              .expand((v) => v is List ? v : [v])
              .join('\n');
          throw msgs;
        }
        final msg = body['message'];
        if (msg != null) throw msg.toString();
      }
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError ||
          e.error is SocketException) {
        throw 'انقطع الاتصال بالإنترنت. تحقق من اتصالك ثم حاول مرة أخرى.';
      }
      throw 'تعذر الاتصال بالخادم. حاول مرة أخرى.';
    }
  }

  Future<void> logout() async {
    try {
      await _api.post('/auth/logout');
    } catch (_) {}
    await _api.clearToken();
    await HiveService.clearAll();
  }

  Future<UserModel?> me() async {
    try {
      final response = await _api.get('/auth/me');
      if (response.data['success'] == true) {
        final user = UserModel.fromJson(response.data['user']);
        await HiveService.saveUser(user);
        if (!user.isActive) {
          ApiClient.onSuspended?.call();
        }
        return user;
      }
    } catch (_) {}
    return HiveService.getUser();
  }

  Future<void> updateProfile({required String name, String? email}) async {
    try {
      final response = await _api.put(
        '/profile',
        data: {
          'name': name,
          'email': email?.trim().isEmpty ?? true ? null : email?.trim(),
        },
      );
      if (response.data['success'] != true) {
        throw response.data['message'] ?? 'تعذر تحديث بيانات الحساب';
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 422) {
        final body = e.response?.data;
        if (body is Map) {
          final errors = body['errors'];
          if (errors is Map && errors.isNotEmpty) {
            final msgs = errors.values
                .expand((v) => v is List ? v : [v])
                .join('\n');
            throw msgs;
          }
          if (body['message'] != null) throw body['message'].toString();
        }
      }
      final body = e.response?.data;
      if (body is Map && body['message'] != null)
        throw body['message'].toString();
      throw 'تعذر تحديث بيانات الحساب';
    }
  }

  Future<void> updateAvatar(String filePath) async {
    try {
      final response = await _api.post(
        '/profile/avatar',
        data: FormData.fromMap({
          'avatar': await MultipartFile.fromFile(filePath),
        }),
      );
      if (response.data['success'] != true) {
        throw response.data['message'] ?? 'تعذر تحديث الصورة الشخصية';
      }
    } on DioException catch (e) {
      final body = e.response?.data;
      if (body is Map) {
        final errors = body['errors'];
        if (errors is Map && errors.isNotEmpty) {
          throw errors.values
              .expand((value) => value is List ? value : [value])
              .join('\n');
        }
        if (body['message'] != null) throw body['message'].toString();
      }
      throw 'تعذر تحديث الصورة الشخصية';
    }
  }

  Future<void> changePassword({
    required String currentPassword,
    required String password,
    required String passwordConfirmation,
  }) async {
    try {
      final response = await _api.put(
        '/profile/password',
        data: {
          'current_password': currentPassword,
          'password': password,
          'password_confirmation': passwordConfirmation,
        },
      );
      if (response.data['success'] != true) {
        throw response.data['message'] ?? 'تعذر تغيير كلمة المرور';
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 422) {
        final body = e.response?.data;
        if (body is Map) {
          final errors = body['errors'];
          if (errors is Map && errors.isNotEmpty) {
            final msgs = errors.values
                .expand((v) => v is List ? v : [v])
                .join('\n');
            throw msgs;
          }
          if (body['message'] != null) throw body['message'].toString();
        }
      }
      if (e.response?.statusCode == 401) {
        throw 'كلمة المرور الحالية غير صحيحة';
      }
      final body = e.response?.data;
      if (body is Map && body['message'] != null)
        throw body['message'].toString();
      throw 'تعذر تغيير كلمة المرور';
    }
  }

  Future<Map<String, dynamic>> getPayoutDetails() async {
    final response = await _api.get('/auth/payout-details');
    return Map<String, dynamic>.from(response.data['data'] ?? {});
  }

  Future<void> updatePayoutDetails({
    required String fullName,
    String? provider,
    String? accountNumber,
  }) async {
    try {
      final response = await _api.put(
        '/auth/payout-details',
        data: {
          'full_name': fullName,
          'provider': provider?.trim().isEmpty ?? true
              ? null
              : provider?.trim(),
          'account_number': accountNumber?.trim().isEmpty ?? true
              ? null
              : accountNumber?.trim(),
        },
      );
      if (response.data['success'] != true)
        throw response.data['message'] ?? 'تعذر حفظ بيانات المدفوعات والسحب';
    } on DioException catch (e) {
      final body = e.response?.data;
      if (body is Map) {
        final errors = body['errors'];
        if (errors is Map && errors.isNotEmpty) {
          throw errors.values
              .expand((value) => value is List ? value : [value])
              .join('\n');
        }
        if (body['message'] != null) throw body['message'].toString();
      }
      throw 'تعذر حفظ بيانات المدفوعات والسحب';
    }
  }

  Future<void> updateFcmToken(String token) async {
    try {
      await _api.post('/auth/fcm-token', data: {'fcm_token': token});
    } catch (_) {}
  }
}
