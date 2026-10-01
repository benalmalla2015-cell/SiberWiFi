import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/auth/presentation/screens/pending_approval_screen.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/dashboard/presentation/screens/dashboard_screen.dart';
import '../../features/dashboard/presentation/screens/coming_soon_screen.dart';
import '../../features/dashboard/presentation/screens/transactions_screen.dart';
import '../../features/networks/presentation/screens/networks_screen.dart';
import '../../features/payouts/presentation/screens/payouts_screen.dart';
import '../../features/notifications/presentation/screens/notifications_screen.dart';
import '../../features/profile/presentation/screens/profile_screen.dart';
import '../../features/profile/presentation/screens/legal_info_screen.dart';
import '../../features/reviews/presentation/screens/reviews_screen.dart';
import '../../features/reports/presentation/screens/reports_screen.dart';
import '../../features/charging_points/presentation/screens/charging_points_screen.dart';
import '../../features/chat/presentation/screens/conversations_screen.dart';
import '../../features/chat/presentation/screens/chat_screen.dart';
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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_disposed) notifyListeners();
      });
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
      final isSplash = loc == '/splash';
      final isWelcome = loc == '/welcome';
      final isLogin = loc == '/login';
      final isRegister = loc == '/register';
      final isPending = loc == '/pending';
      final loggedIn = auth.status == AuthStatus.authenticated;
      final isUnknown = auth.status == AuthStatus.unknown;
      final user = auth.user;
      final isPendingOwner = user?.isPendingNetworkOwner ?? false;

      // Splash handles its own navigation — never redirect away from it
      if (isSplash) return null;
      // While auth is unknown, don't redirect (splash will navigate)
      if (isUnknown) return null;

      if (loggedIn) {
        // Pending network owner should stay on pending screen only
        if (isPendingOwner && !isPending) return '/pending';
        // Approved owner should not see pending screen
        if (!isPendingOwner && isPending) return '/';
        // Authenticated but on login/register → go home
        if (isLogin || isRegister) return '/';
        return null;
      }

      // Not authenticated: only login, register and welcome are allowed
      if (!isLogin && !isRegister && !isWelcome) return '/login';
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/welcome',
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/pending',
        builder: (context, state) => const PendingApprovalScreen(),
      ),
      GoRoute(
        path: '/about-us',
        builder: (context, state) =>
            const LegalInfoScreen(type: LegalInfoType.aboutUs),
      ),
      GoRoute(
        path: '/terms-of-service',
        builder: (context, state) =>
            const LegalInfoScreen(type: LegalInfoType.termsOfService),
      ),
      GoRoute(
        path: '/privacy-policy',
        builder: (context, state) =>
            const LegalInfoScreen(type: LegalInfoType.privacyPolicy),
      ),
      GoRoute(
        path: '/fiber-topup',
        builder: (context, state) => const ComingSoonScreen(
          title: 'شحن رصيد فايبر',
          icon: Icons.bolt_rounded,
        ),
      ),
      GoRoute(
        path: '/starlink-topup',
        builder: (context, state) => const ComingSoonScreen(
          title: 'شحن رصيد Starlink',
          icon: Icons.satellite_alt_outlined,
        ),
      ),
      ShellRoute(
        builder: (context, state, child) =>
            MainScaffold(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/networks',
            builder: (context, state) => const NetworksScreen(),
          ),
          GoRoute(
            path: '/transactions',
            builder: (context, state) => const TransactionsScreen(),
          ),
          GoRoute(
            path: '/payouts',
            builder: (context, state) => const PayoutsScreen(),
          ),
          GoRoute(
            path: '/notifications',
            builder: (context, state) => const NotificationsScreen(),
          ),
          GoRoute(
            path: '/profile',
            builder: (context, state) => const ProfileScreen(),
          ),
          GoRoute(
            path: '/reviews',
            builder: (context, state) => const ReviewsScreen(),
          ),
          GoRoute(
            path: '/reports',
            builder: (context, state) => const ReportsScreen(),
          ),
          GoRoute(
            path: '/charging-points',
            builder: (context, state) => const ChargingPointsScreen(),
          ),
          GoRoute(
            path: '/conversations',
            builder: (context, state) => const ConversationsScreen(),
          ),
          GoRoute(
            path: '/conversations/:networkId/:contactId',
            builder: (context, state) {
              final extra = state.extra as Map<String, dynamic>? ?? const {};
              return NetworkOwnerChatScreen(
                networkId: int.parse(state.pathParameters['networkId']!),
                contactId: int.parse(state.pathParameters['contactId']!),
                networkName: extra['network_name']?.toString() ?? 'شبكة',
                contactName: extra['contact_name']?.toString() ?? 'عميل',
              );
            },
          ),
        ],
      ),
    ],
  );
});
