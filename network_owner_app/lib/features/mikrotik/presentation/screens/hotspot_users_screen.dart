import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/router_model.dart';
import '../providers/mikrotik_provider.dart';

class HotspotUsersScreen extends ConsumerWidget {
  final MikrotikRouterConfig router;
  final int initialTab;
  const HotspotUsersScreen(
      {super.key, required this.router, this.initialTab = 0});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snap = ref.watch(routerSessionProvider(router));

    return DefaultTabController(
      length: 3,
      initialIndex: initialTab,
      child: Scaffold(
        backgroundColor: AppColors.white,
        appBar: AppBar(
          title: const Text('مستخدمو Hotspot'),
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: 'المستخدمون'),
              Tab(text: 'النشطون'),
              Tab(text: 'الباقات'),
            ],
          ),
        ),
        body: snap.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('خطأ: $e')),
          data: (s) => TabBarView(
            children: [
              _UsersTab(users: s.users),
              _ActiveTab(active: s.active),
              _ProfilesTab(profiles: s.profiles),
            ],
          ),
        ),
      ),
    );
  }
}

class _UsersTab extends StatelessWidget {
  final List<Map<String, String>> users;
  const _UsersTab({required this.users});

  @override
  Widget build(BuildContext context) {
    if (users.isEmpty) return const _EmptyHint('لا يوجد مستخدمون على الراوتر');
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: users.length,
      itemBuilder: (_, i) {
        final u = users[i];
        final disabled = u['disabled'] == 'true';
        return _ListCard(
          leading: Icon(
            Icons.person_outline,
            color: disabled ? AppColors.textLight : AppColors.primary,
          ),
          title: u['name'] ?? '—',
          subtitle: 'الباقة: ${u['profile'] ?? 'default'}'
              '${(u['limit-uptime'] ?? '').isNotEmpty ? ' • المدة: ${u['limit-uptime']}' : ''}',
          trailing: disabled
              ? _Badge(text: 'معطّل', color: AppColors.textGray)
              : _Badge(text: 'مفعّل', color: AppColors.success),
        );
      },
    );
  }
}

class _ActiveTab extends StatelessWidget {
  final List<Map<String, String>> active;
  const _ActiveTab({required this.active});

  @override
  Widget build(BuildContext context) {
    if (active.isEmpty) return const _EmptyHint('لا توجد جلسات نشطة حالياً');
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: active.length,
      itemBuilder: (_, i) {
        final a = active[i];
        return _ListCard(
          leading:
              const Icon(Icons.wifi, color: AppColors.success),
          title: a['user'] ?? '—',
          subtitle:
              'IP: ${a['address'] ?? '—'} • منذ ${a['uptime'] ?? '—'}',
          trailing: _Badge(
            text: '${a['bytes-in'] ?? '0'}↓',
            color: AppColors.lightBlue,
          ),
        );
      },
    );
  }
}

class _ProfilesTab extends StatelessWidget {
  final List<Map<String, String>> profiles;
  const _ProfilesTab({required this.profiles});

  @override
  Widget build(BuildContext context) {
    if (profiles.isEmpty) return const _EmptyHint('لا توجد باقات');
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: profiles.length,
      itemBuilder: (_, i) {
        final p = profiles[i];
        return _ListCard(
          leading: const Icon(Icons.speed, color: AppColors.accent),
          title: p['name'] ?? '—',
          subtitle: 'السرعة: ${p['rate-limit'] ?? 'غير محددة'}'
              '${(p['shared-users'] ?? '').isNotEmpty ? ' • مستخدمون: ${p['shared-users']}' : ''}',
        );
      },
    );
  }
}

class _ListCard extends StatelessWidget {
  final Widget leading;
  final String title, subtitle;
  final Widget? trailing;
  const _ListCard({
    required this.leading,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: ListTile(
        dense: true,
        leading: leading,
        title: Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(subtitle,
            style: const TextStyle(
                color: AppColors.textGray, fontSize: 11)),
        trailing: trailing,
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  const _Badge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String text;
  const _EmptyHint(this.text);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.inbox_outlined,
              size: 48, color: AppColors.divider),
          const SizedBox(height: 12),
          Text(text, style: const TextStyle(color: AppColors.textGray)),
        ],
      ),
    );
  }
}
