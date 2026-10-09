import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/models/user_model.dart';
import '../../../../core/cache/hive_service.dart';
import '../../data/auth_repository.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthState {
  final AuthStatus status;
  final UserModel? user;
  final String? error;
  final bool isLoading;

  const AuthState({
    this.status = AuthStatus.unknown,
    this.user,
    this.error,
    this.isLoading = false,
  });

  AuthState copyWith({
    AuthStatus? status,
    UserModel? user,
    String? error,
    bool? isLoading,
  }) => AuthState(
    status: status ?? this.status,
    user: user ?? this.user,
    error: error,
    isLoading: isLoading ?? this.isLoading,
  );
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _repo;
  AuthNotifier(this._repo) : super(const AuthState()) {
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    try {
      final cached = HiveService.getUser();
      if (cached != null && (cached.isNetworkOwner || cached.role == 'network_owner')) {
        state = AuthState(status: AuthStatus.authenticated, user: cached);
        _refreshUser();
        _syncFcmToken();
      } else if (cached != null) {
        await _repo.logout();
        state = const AuthState(status: AuthStatus.unauthenticated, error: 'هذا الحساب ليس حساب صاحب شبكة');
      } else {
        state = const AuthState(status: AuthStatus.unauthenticated);
      }
    } catch (_) {
      // Hive not ready / box missing — treat as logged out.
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  Future<void> _refreshUser() async {
    final user = await _repo.me();
    if (user != null) {
      state = state.copyWith(user: user, status: AuthStatus.authenticated);
    }
  }

  Future<void> refreshUser() => _refreshUser();

  Future<bool> login(String phone, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final user = await _repo.login(phone, password);
      if (!user.isNetworkOwner && user.role != 'network_owner') {
        await _repo.logout();
        state = state.copyWith(
          isLoading: false,
          status: AuthStatus.unauthenticated,
          error: 'هذا الحساب ليس حساب صاحب شبكة',
        );
        return false;
      }
      state = AuthState(status: AuthStatus.authenticated, user: user);
      _syncFcmToken();
      return true;
    } catch (e) {
      String msg = e.toString();
      if (msg.startsWith('Exception: ')) msg = msg.substring(11);
      if (msg.contains('DioException') || msg.contains('SocketException')) {
        msg = 'خطأ في الاتصال بالخادم';
      }
      state = state.copyWith(
        isLoading: false,
        status: AuthStatus.unauthenticated,
        error: msg,
      );
      return false;
    }
  }

  Future<bool> registerNetworkOwner(dynamic data) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final user = await _repo.registerNetworkOwner(data);
      state = AuthState(status: AuthStatus.authenticated, user: user);
      _syncFcmToken();
      return true;
    } catch (e) {
      String msg = e.toString();
      if (msg.startsWith('Exception: ')) msg = msg.substring(11);
      state = state.copyWith(
        isLoading: false,
        status: AuthStatus.unauthenticated,
        error: msg,
      );
      return false;
    }
  }

  Future<void> _syncFcmToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _repo.updateFcmToken(token);
    } catch (_) {}
  }

  Future<bool> updateProfile({required String name, String? email}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _repo.updateProfile(name: name, email: email);
      await _refreshUser();
      state = state.copyWith(isLoading: false);
      return true;
    } catch (error) {
      String msg = error.toString();
      if (msg.startsWith('Exception: ')) msg = msg.substring(11);
      if (msg.contains('DioException') || msg.contains('SocketException')) {
        msg = 'تعذر الاتصال بالخادم';
      }
      state = state.copyWith(isLoading: false, error: msg);
      return false;
    }
  }

  Future<bool> updateAvatar(String filePath) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _repo.updateAvatar(filePath);
      await _refreshUser();
      state = state.copyWith(isLoading: false);
      return true;
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error.toString());
      return false;
    }
  }

  Future<bool> changePassword({
    required String currentPassword,
    required String password,
    required String passwordConfirmation,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _repo.changePassword(
        currentPassword: currentPassword,
        password: password,
        passwordConfirmation: passwordConfirmation,
      );
      state = state.copyWith(isLoading: false);
      return true;
    } catch (error) {
      String msg = error.toString();
      if (msg.startsWith('Exception: ')) msg = msg.substring(11);
      if (msg.contains('DioException') || msg.contains('SocketException')) {
        msg = 'تعذر الاتصال بالخادم';
      }
      state = state.copyWith(isLoading: false, error: msg);
      return false;
    }
  }

  Future<bool> deleteAccount({required String password}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _repo.deleteAccount(password: password);
      state = const AuthState(status: AuthStatus.unauthenticated);
      return true;
    } catch (e) {
      String msg = e.toString();
      if (msg.startsWith('Exception: ')) msg = msg.substring(11);
      if (msg.contains('DioException') || msg.contains('SocketException')) {
        msg = 'تعذر الاتصال بالخادم';
      }
      state = state.copyWith(isLoading: false, error: msg);
      return false;
    }
  }

  Future<void> logout() async {
    try {
      await _repo.logout();
    } finally {
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(ref.read(authRepositoryProvider)),
);

final currentUserProvider = Provider<UserModel?>((ref) {
  return ref.watch(authProvider).user;
});
