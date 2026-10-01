import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/notifications/presentation/screens/notifications_screen.dart';
import '../theme/app_theme.dart';

class MainScaffold extends ConsumerWidget {
  final Widget child;
  final String location;

  const MainScaffold({super.key, required this.child, required this.location});

  int get _currentIndex {
    if (location == '/') return 0;
    if (location.startsWith('/networks')) return 1;
    if (location.startsWith('/payouts')) return 2;
    if (location.startsWith('/notifications')) return 3;
    if (location.startsWith('/profile')) return 4;
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadCount = ref
            .watch(notificationsProvider)
            .valueOrNull
            ?.where(
                (n) => !(n['is_read'] == true || n['read_at'] != null))
            .length ??
        0;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: child,
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: BottomNavigationBar(
            currentIndex: _currentIndex,
            elevation: 0,
            backgroundColor: Colors.white,
            selectedItemColor: AppColors.primary,
            unselectedItemColor: AppColors.textGray,
            selectedLabelStyle: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
            unselectedLabelStyle: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 10,
            ),
            type: BottomNavigationBarType.fixed,
            onTap: (i) {
              switch (i) {
                case 0: context.go('/'); break;
                case 1: context.go('/networks'); break;
                case 2: context.go('/payouts'); break;
                case 3: context.go('/notifications'); break;
                case 4: context.go('/profile'); break;
              }
            },
            items: [
              _navItem(Icons.dashboard_outlined, Icons.dashboard, 'الرئيسية', 0),
              _navItem(Icons.wifi_outlined, Icons.wifi, 'شبكاتي', 1),
              _navItem(Icons.account_balance_wallet_outlined, Icons.account_balance_wallet, 'المدفوعات', 2),
              _navItem(Icons.notifications_outlined, Icons.notifications, 'الإشعارات', 3, badgeCount: unreadCount),
              _navItem(Icons.person_outlined, Icons.person, 'حسابي', 4),
            ],
          ),
        ),
      ),
    );
  }

  BottomNavigationBarItem _navItem(IconData off, IconData on, String label, int index,
      {int badgeCount = 0}) {
    final isActive = _currentIndex == index;
    Widget icon = Icon(off);
    Widget activeIcon = Icon(on);
    if (badgeCount > 0) {
      final badgeLabel = Text(
        badgeCount > 99 ? '99+' : '$badgeCount',
        style: const TextStyle(fontFamily: 'Cairo', fontSize: 9, color: Colors.white),
      );
      icon = Badge(backgroundColor: AppColors.accent, label: badgeLabel, child: icon);
      activeIcon = Badge(backgroundColor: AppColors.accent, label: badgeLabel, child: activeIcon);
    }
    return BottomNavigationBarItem(
      icon: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(height: 2),
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: isActive ? 18 : 0,
            height: 2.5,
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
      activeIcon: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          activeIcon,
          const SizedBox(height: 2),
          Container(
            width: 18,
            height: 2.5,
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
      label: label,
    );
  }
}
