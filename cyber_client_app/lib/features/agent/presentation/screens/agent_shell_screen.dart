import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/agent_api.dart';
import '../providers/agent_providers.dart';
import 'agent_earnings_screen.dart';
import 'agent_topup_screen.dart';
import 'agent_topups_screen.dart';

/// Agent home: شحن رصيد / عملياتي / أرباحي.
class AgentShellScreen extends ConsumerStatefulWidget {
  const AgentShellScreen({super.key});

  @override
  ConsumerState<AgentShellScreen> createState() => _AgentShellScreenState();
}

class _AgentShellScreenState extends ConsumerState<AgentShellScreen> {
  int _index = 0;

  static const _titles = ['شحن رصيد', 'عملياتي', 'أرباحي'];
  static const _screens = [
    AgentTopupScreen(),
    AgentTopupsScreen(),
    AgentEarningsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(agentSessionProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: [
          if (profile?['name'] != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  profile!['name'].toString(),
                  style: const TextStyle(fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          IconButton(
            tooltip: 'تسجيل الخروج',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () async {
              await ref.read(agentApiProvider).logout();
              ref.read(agentSessionProvider.notifier).signOut();
            },
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.add_card_outlined),
            selectedIcon: Icon(Icons.add_card_rounded, color: AppColors.primary),
            label: 'شحن',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long_rounded, color: AppColors.primary),
            label: 'عملياتي',
          ),
          NavigationDestination(
            icon: Icon(Icons.savings_outlined),
            selectedIcon: Icon(Icons.savings_rounded, color: AppColors.primary),
            label: 'أرباحي',
          ),
        ],
      ),
    );
  }
}
