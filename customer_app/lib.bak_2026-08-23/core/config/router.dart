import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/networks/presentation/screens/networks_screen.dart';
import '../../features/networks/presentation/screens/network_detail_screen.dart';
import '../../features/networks/presentation/screens/cards_screen.dart';
import '../../features/wallet/presentation/screens/wallet_screen.dart';
import '../../features/wallet/presentation/screens/topup_screen.dart';
import '../../features/transactions/presentation/screens/transactions_screen.dart';
import '../../features/profile/presentation/screens/profile_screen.dart';
import '../../features/profile/presentation/screens/edit_profile_screen.dart';
import '../../features/profile/presentation/screens/support_tickets_screen.dart';
import '../../features/profile/presentation/screens/change_password_screen.dart';
import '../../features/profile/presentation/screens/services_screen.dart';
import '../../features/notifications/presentation/screens/notifications_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/main_scaffold.dart';
import '../widgets/splash_screen.dart';

/// Bridge between Riverpod and GoRouter's refreshListenable.
/// Listens to authProvider and notifies GoRouter to re-run redirects
/// WITHOUT recreating the router instance.
/// Uses addPostFrameCallback to avoid notifying during widget disposal.
class _AuthRefreshListenable extends ChangeNotifier {
  final Ref _ref;
  late final ProviderSubscription<AuthState> _sub;
  bool _disposed = false;

  _AuthRefreshListenable(this._ref) {
    _sub = _ref.listen<AuthState>(authProvider, (previous, next) {
      if (_disposed) return;
      // Defer past the current frame. addPostFrameCallback only runs if a
      // frame is actually scheduled, so explicitly request one in case the
      // app is idle after a Navigator operation (e.g. popping the logout
      // dialog) — otherwise the redirect would never fire.
      final binding = WidgetsBinding.instance;
      binding.addPostFrameCallback((_) {
        if (!_disposed) notifyListeners();
      });
      binding.scheduleFrame();
    }, fireImmediately: false);
  }

  @override
  void dispose() {
    _disposed = true;
    _sub.close();
    super.dispose();
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refreshListenable = _AuthRefreshListenable(ref);
  ref.onDispose(refreshListenable.dispose);

  return GoRouter(
    debugLogDiagnostics: false,
    initialLocation: '/login',
    refreshListenable: refreshListenable,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final loc = state.matchedLocation;
      if (loc == '/splash') return '/login';
      if (auth.status == AuthStatus.unknown)
        return loc == '/login' ? null : '/login';
      final loggedIn = auth.status == AuthStatus.authenticated;
      if (loggedIn && (loc == '/login' || loc == '/register')) return '/';
      if (!loggedIn && loc != '/login' && loc != '/register') return '/login';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
      ShellRoute(
        builder: (context, state, child) =>
            MainScaffold(child: child, location: state.matchedLocation),
        routes: [
          GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
          GoRoute(
            path: '/networks',
            builder: (_, __) => const NetworksScreen(),
          ),
          GoRoute(
            path: '/networks/:id',
            builder: (_, state) {
              final id = int.tryParse(state.pathParameters['id'] ?? '');
              if (id == null) return const _InvalidRouteScreen('رابط الشبكة غير صالح');
              return NetworkDetailScreen(networkId: id);
            },
          ),
          GoRoute(
            path: '/networks/:id/cards',
            builder: (_, state) {
              final id = int.tryParse(state.pathParameters['id'] ?? '');
              if (id == null) return const _InvalidRouteScreen('رابط الشبكة غير صالح');
              return CardsScreen(networkId: id);
            },
          ),
          GoRoute(path: '/wallet', builder: (_, __) => const WalletScreen()),
          GoRoute(
            path: '/wallet/topup',
            builder: (_, __) => const TopupScreen(),
          ),
          GoRoute(
            path: '/transactions',
            builder: (_, __) => const TransactionsScreen(),
          ),
          GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
          GoRoute(
            path: '/profile/edit',
            builder: (_, __) => const EditProfileScreen(),
          ),
          GoRoute(
            path: '/profile/change-password',
            builder: (_, __) => const ChangePasswordScreen(),
          ),
          GoRoute(
            path: '/services',
            builder: (_, __) => const ServicesScreen(),
          ),
          GoRoute(
            path: '/support',
            builder: (_, __) => const SupportTicketsScreen(),
          ),
          GoRoute(
            path: '/notifications',
            builder: (_, __) => const NotificationsScreen(),
          ),
        ],
      ),
    ],
  );
});

class _InvalidRouteScreen extends StatelessWidget {
  final String message;
  const _InvalidRouteScreen(this.message);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('خطأ'), backgroundColor: Colors.white, foregroundColor: AppColors.textDark),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 56, color: AppColors.accent),
            const SizedBox(height: 16),
            Text(message, style: const TextStyle(fontFamily: 'Cairo', color: AppColors.textGray)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => GoRouter.of(context).go('/'),
              child: const Text('العودة للرئيسية', style: TextStyle(fontFamily: 'Cairo')),
            ),
          ],
        ),
      ),
    );
  }
}
