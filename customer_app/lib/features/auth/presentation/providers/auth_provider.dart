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
      await _registerFcmToken();
    } else {
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  Future<void> refreshProfile() async {
    try {
      final res = await _api.get('/auth/me');
      var u = UserModel.fromJson(
        toMap(res.data['user'] ?? res.data['data'] ?? res.data),
      );
      u = await _syncBalanceAndAdvance(u);
      await HiveService.saveUser(u);
      state = state.copyWith(user: u);
      if (!u.isActive) {
        ApiClient.onSuspended?.call();
      }
    } catch (_) {}
  }

  void updateUser(UserModel u) {
    state = state.copyWith(user: u);
  }

  Future<UserModel> _syncBalanceAndAdvance(UserModel u) async {
    try {
      final res = await _api.get('/wallet/balance');
      final data = toMap(res.data['data'] ?? {});
      return u.copyWith(
        balance: (data['balance'] ?? u.balance).toDouble(),
        advanceBalance: (data['advance_balance'] ?? 0).toDouble(),
        isEligibleForAdvance: data['is_eligible_for_advance'] == true,
      );
    } catch (_) {
      return u;
    }
  }

  Future<String?> login(
    String phone,
    String password, {
    String? deviceId,
  }) async {
    try {
      final res = await _api.post(
        '/auth/login',
        data: {
          'phone': phone,
          'password': password,
          if (deviceId != null && deviceId.isNotEmpty) 'device_id': deviceId,
        },
      );
      final token = res.data['token'] ?? res.data['data']?['token'];
      if (token == null) return 'بيانات الدخول غير صحيحة';
      await _api.saveToken(token);
      var u = UserModel.fromJson(
        toMap(res.data['user'] ?? res.data['data']?['user'] ?? {}),
      );
      u = await _syncBalanceAndAdvance(u);
      await HiveService.saveUser(u);
      state = AuthState(status: AuthStatus.authenticated, user: u);
      await _registerFcmToken();
      return null;
    } on DioException catch (e) {
      return _authErrorMessage(e, 'بيانات الدخول غير صحيحة');
    } on Exception catch (e) {
      return e.toString().replaceAll('Exception: ', '');
    }
  }

  /// Maps a [DioException] to a user-facing Arabic message. Connectivity
  /// failures (no response received at all) get a dedicated message instead
  /// of Dio's English system text.
  String _authErrorMessage(DioException e, String fallback) {
    if (e.type == DioExceptionType.badResponse && e.response != null) {
      final msg = e.message;
      if (msg != null && msg.isNotEmpty) return msg;
      return fallback;
    }
    return 'لا يوجد اتصال بالإنترنت. تأكد من اتصالك ثم أعد المحاولة';
  }

  Future<String?> register({
    required String name,
    required String phone,
    required String password,
    String? email,
    int? regionId,
    int? directorateId,
    int? subDirectorateId,
    String? referralCode,
    String? deviceId,
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
          if (subDirectorateId != null) 'sub_directorate_id': subDirectorateId,
          if (referralCode != null && referralCode.trim().isNotEmpty)
            'referral_code': referralCode.trim(),
          if (deviceId != null && deviceId.isNotEmpty) 'device_id': deviceId,
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
      return _authErrorMessage(e, 'فشل التسجيل، حاول مجدداً');
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

  Future<String?> deleteAccount({required String password}) async {
    try {
      await _api.post('/auth/account/delete', data: {'password': password});
      await logout();
      return null;
    } on DioException catch (e) {
      return _authErrorMessage(e, 'تعذر حذف الحساب، حاول مجدداً');
    }
  }

  Future<void> logout() async {
    state = const AuthState(status: AuthStatus.unauthenticated);
    await _api.clearToken();
    await HiveService.clearAll();
    // Server logout is non-blocking so the UI can navigate immediately.
    _api
        .post('/auth/logout')
        .timeout(const Duration(seconds: 3))
        .catchError((_) {});
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.read(apiClientProvider));
});
