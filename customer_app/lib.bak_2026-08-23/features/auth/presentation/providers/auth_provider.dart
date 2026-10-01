import 'dart:async';

import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/api/api_client.dart';
import '../../../../core/cache/hive_service.dart';
import '../../../../core/models/user_model.dart';
import '../../../../core/utils/json_helpers.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthState {
  final AuthStatus status;
  final UserModel? user;
  final String? error;
  const AuthState({this.status = AuthStatus.unknown, this.user, this.error});
  AuthState copyWith({AuthStatus? status, UserModel? user, String? error}) =>
      AuthState(
        status: status ?? this.status,
        user: user ?? this.user,
        error: error ?? this.error,
      );
}

class AuthNotifier extends StateNotifier<AuthState> {
  final ApiClient _api;
  AuthNotifier(this._api) : super(const AuthState()) {
    _init();
  }

  Future<void> _init() async {
    final token = await _api.getToken();
    final cached = HiveService.getUser();
    if (token != null && cached != null) {
      state = AuthState(status: AuthStatus.authenticated, user: cached);
      refreshProfile();
    } else {
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  Future<void> refreshProfile() async {
    try {
      final res = await _api.get('/auth/me');
      final u = UserModel.fromJson(
        toMap(res.data['user'] ?? res.data['data'] ?? res.data),
      );
      await HiveService.saveUser(u);
      state = state.copyWith(user: u);
    } catch (_) {}
  }

  Future<String?> login(String phone, String password) async {
    try {
      final res = await _api.post(
        '/auth/login',
        data: {'phone': phone, 'password': password},
      );
      final token = res.data['token'] ?? res.data['data']?['token'];
      if (token == null) return 'بيانات الدخول غير صحيحة';
      await _api.saveToken(token);
      final u = UserModel.fromJson(
        toMap(res.data['user'] ?? res.data['data']?['user'] ?? {}),
      );
      await HiveService.saveUser(u);
      state = AuthState(status: AuthStatus.authenticated, user: u);
      await _registerFcmToken();
      return null;
    } on DioException catch (e) {
      return e.message ?? 'بيانات الدخول غير صحيحة';
    } on Exception catch (e) {
      return e.toString().replaceAll('Exception: ', '');
    }
  }

  Future<String?> register({
    required String name,
    required String phone,
    required String password,
    String? email,
    int? regionId,
    int? directorateId,
    String? referralCode,
  }) async {
    try {
      final res = await _api.post(
        '/auth/register',
        data: {
          'name': name,
          'phone': phone,
          'password': password,
          'password_confirmation': password,
          if (email != null && email.isNotEmpty) 'email': email,
          if (regionId != null) 'region_id': regionId,
          if (directorateId != null) 'directorate_id': directorateId,
          if (referralCode != null && referralCode.trim().isNotEmpty)
            'referral_code': referralCode.trim(),
        },
      );
      final token = res.data['token'] ?? res.data['data']?['token'];
      if (token == null) return 'فشل التسجيل، حاول مجدداً';
      await _api.saveToken(token);
      final u = UserModel.fromJson(
        toMap(res.data['user'] ?? res.data['data']?['user'] ?? {}),
      );
      await HiveService.saveUser(u);
      state = AuthState(status: AuthStatus.authenticated, user: u);
      await _registerFcmToken();
      return null;
    } on DioException catch (e) {
      return e.message ?? 'فشل التسجيل، حاول مجدداً';
    } on Exception catch (e) {
      return e.toString().replaceAll('Exception: ', '');
    }
  }

  Future<void> _registerFcmToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null)
        await _api.post('/auth/fcm-token', data: {'fcm_token': token});
    } catch (_) {}
  }

  Future<String?> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      await _api
          .put(
            '/profile/password',
            data: {
              'current_password': currentPassword,
              'password': newPassword,
              'password_confirmation': newPassword,
            },
          )
          .timeout(const Duration(seconds: 12));
      return null;
    } catch (_) {
      return 'تعذر تغيير كلمة المرور. تأكد من كلمة المرور الحالية وحاول مجدداً.';
    }
  }

  Future<void> logout() async {
    state = const AuthState(status: AuthStatus.unauthenticated);
    try {
      await _api.post('/auth/logout').timeout(const Duration(seconds: 5));
    } catch (_) {}
    await _api.clearToken();
    await HiveService.clearAll();
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.read(apiClientProvider));
});
