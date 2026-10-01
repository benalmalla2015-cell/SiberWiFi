import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';
import '../../features/networks/presentation/providers/networks_provider.dart';
import 'offline_banner.dart';

class MainScaffold extends ConsumerWidget {
  final Widget child;
  final String location;
  const MainScaffold({super.key, required this.child, required this.location});

  int get _currentIndex {
    if (location.startsWith('/networks')) return 1;
    if (location.startsWith('/wallet'))   return 2;
    if (location.startsWith('/profile'))  return 3;
    return 0;
  }

  void _onTap(BuildContext context, WidgetRef ref, int index) {
    switch (index) {
      case 0: context.go('/'); break;
      case 1:
        // Reset search/filters every time the networks tab is explicitly tapped
        // so the user always returns to the full networks list.
        ref.read(networkSearchProvider.notifier).state = '';
        ref.read(networkRegionIdProvider.notifier).state = null;
        ref.read(networkDirectorateIdProvider.notifier).state = null;
        ref.read(networkFilterModeProvider.notifier).state = NetworkFilterMode.all;
        context.go('/networks');
        break;
      case 2: context.go('/wallet'); break;
      case 3: context.go('/profile'); break;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(child: child),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 16, offset: const Offset(0, -4)),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (i) => _onTap(context, ref, i),
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: AppColors.textGray,
          selectedLabelStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 11),
          elevation: 0,
          items: [
            _navItem(icon: Icons.home_outlined, activeIcon: Icons.home_rounded, label: 'الرئيسية', index: 0),
            _navItem(icon: Icons.wifi_outlined, activeIcon: Icons.wifi_rounded, label: 'الشبكات', index: 1),
            _navItem(icon: Icons.account_balance_wallet_outlined, activeIcon: Icons.account_balance_wallet_rounded, label: 'المحفظة', index: 2),
            _navItem(icon: Icons.person_outline_rounded, activeIcon: Icons.person_rounded, label: 'حسابي', index: 3),
          ],
        ),
      ),
    );
  }

  BottomNavigationBarItem _navItem({
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required int index,
  }) {
    final isActive = _currentIndex == index;
    return BottomNavigationBarItem(
      icon: Stack(
        alignment: Alignment.topCenter,
        children: [
          Padding(padding: const EdgeInsets.only(top: 4), child: Icon(icon, size: 26)),
          if (isActive)
            Positioned(
              top: 0,
              child: Container(
                width: 5, height: 5,
                decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
              ),
            ),
        ],
      ),
      activeIcon: Stack(
        alignment: Alignment.topCenter,
        children: [
          Padding(padding: const EdgeInsets.only(top: 4), child: Icon(activeIcon, size: 26)),
          Positioned(
            top: 0,
            child: Container(
              width: 5, height: 5,
              decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
            ),
          ),
        ],
      ),
      label: label,
    );
  }
}
