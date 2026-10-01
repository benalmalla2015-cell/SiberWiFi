import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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
import '../../features/wallet/presentation/screens/balance_transfer_screen.dart';
import '../../features/transactions/presentation/screens/transactions_screen.dart';
import '../../features/profile/presentation/screens/profile_screen.dart';
import '../../features/profile/presentation/screens/edit_profile_screen.dart';
import '../../features/profile/presentation/screens/support_tickets_screen.dart';
import '../../features/profile/presentation/screens/change_password_screen.dart';
import '../../features/profile/presentation/screens/services_screen.dart';
import '../../features/notifications/presentation/screens/notifications_screen.dart';
import '../../features/pos/presentation/screens/points_of_sale_screen.dart';
import '../../features/offers/presentation/screens/offers_screen.dart';
import '../../features/bills/presentation/screens/bill_payment_screen.dart';
import '../../features/booster/presentation/screens/network_booster_screen.dart';
import '../../features/booster/presentation/screens/apps_picker_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/main_scaffold.dart';
import '../widgets/splash_screen.dart';
import '../widgets/welcome_screen.dart';

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
      // Notify immediately when the scheduler is idle, otherwise defer to the
      // next frame. This ensures the redirect runs both after auth state changes
      // and after navigation/dismissal races.
      final binding = SchedulerBinding.instance;
      if (binding.schedulerPhase == SchedulerPhase.idle) {
        notifyListeners();
      } else {
        binding.addPostFrameCallback((_) {
          if (!_disposed) notifyListeners();
        });
      }
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
    initialLocation: '/splash',
    refreshListenable: refreshListenable,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final loc = state.matchedLocation;
      // Don't redirect from splash - let splash handle navigation
      if (loc == '/splash') return null;
      if (auth.status == AuthStatus.unknown) return null;
      final loggedIn = auth.status == AuthStatus.authenticated;
      if (loggedIn && (loc == '/login' || loc == '/register' || loc == '/welcome')) return '/';
      if (!loggedIn && loc != '/login' && loc != '/register' && loc != '/welcome') return '/login';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/welcome', builder: (_, __) => const WelcomeScreen()),
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
            path: '/wallet/transfer',
            builder: (_, __) => const BalanceTransferScreen(),
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
          GoRoute(path: '/pos', builder: (_, __) => const PointsOfSaleScreen()),
          GoRoute(path: '/offers', builder: (_, __) => const OffersScreen()),
          GoRoute(path: '/bills', builder: (_, __) => const BillPaymentScreen()),
          GoRoute(path: '/booster', builder: (_, __) => const NetworkBoosterScreen()),
        ],
      ),
      GoRoute(
        path: '/booster/apps',
        builder: (_, __) => const AppsPickerScreen(),
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
