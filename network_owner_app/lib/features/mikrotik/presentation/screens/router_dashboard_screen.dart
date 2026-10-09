import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/router_model.dart';
import '../providers/mikrotik_provider.dart';

class RouterDashboardScreen extends ConsumerWidget {
  final MikrotikRouterConfig router;
  const RouterDashboardScreen({super.key, required this.router});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snap = ref.watch(routerSessionProvider(router));

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        title: Text(router.name.isEmpty ? router.host : router.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.invalidate(routerSessionProvider(router)),
          ),
        ],
      ),
      body: snap.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorView(
          error: e,
          onRetry: () => ref.invalidate(routerSessionProvider(router)),
          onEdit: () => context.push('/mikrotik/setup', extra: router),
        ),
        data: (s) => RefreshIndicator(
          onRefresh: () async =>
              ref.invalidate(routerSessionProvider(router)),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _HeaderCard(router: router, snap: s),
              const SizedBox(height: 16),
              _StatsGrid(snap: s),
              const SizedBox(height: 20),
              _ActionTile(
                icon: Icons.people_alt_outlined,
                color: AppColors.primary,
                title: 'مستخدمو Hotspot',
                subtitle: '${s.users.length} مستخدم',
                onTap: () => context.push('/mikrotik/users', extra: router),
              ),
              _ActionTile(
                icon: Icons.wifi_tethering,
                color: AppColors.accent,
                title: 'الجلسات النشطة',
                subtitle: '${s.active.length} متصل الآن',
                onTap: () => context.push('/mikrotik/users',
                    extra: {'router': router, 'tab': 1}),
              ),
              _ActionTile(
                icon: Icons.confirmation_number_outlined,
                color: AppColors.lightBlue,
                title: 'توليد كروت',
                subtitle: 'إنشاء دفعة كروت على الراوتر',
                onTap: () =>
                    context.push('/mikrotik/vouchers', extra: router),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final MikrotikRouterConfig router;
  final RouterSnapshot snap;
  const _HeaderCard({required this.router, required this.snap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF16235F), Color(0xFF1E2D7D), Color(0xFF2A3A9A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.router, color: Colors.white, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  snap.identity.isEmpty ? 'MikroTik RouterOS' : snap.identity,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.circle, color: Color(0xFF7BF1A8), size: 8),
                    SizedBox(width: 5),
                    Text('متصل',
                        style: TextStyle(color: Colors.white, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _InfoChip(label: 'الإصدار', value: snap.version),
              const SizedBox(width: 8),
              _InfoChip(label: 'اللوحة', value: snap.board),
              const SizedBox(width: 8),
              _InfoChip(label: 'مدة التشغيل', value: snap.uptime),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label, value;
  const _InfoChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 11),
                overflow: TextOverflow.ellipsis),
            Text(label,
                style:
                    const TextStyle(color: Colors.white70, fontSize: 9)),
          ],
        ),
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  final RouterSnapshot snap;
  const _StatsGrid({required this.snap});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _MeterCard(
            label: 'المعالج',
            percent: snap.cpuLoad,
            icon: Icons.memory,
            color: snap.cpuLoad > 80 ? AppColors.accent : AppColors.primary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MeterCard(
            label: 'الذاكرة',
            percent: snap.memoryPercent,
            icon: Icons.sd_storage_outlined,
            color:
                snap.memoryPercent > 85 ? AppColors.accent : AppColors.lightBlue,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MeterCard(
            label: 'نشطون الآن',
            percent: snap.active.length,
            icon: Icons.wifi,
            color: AppColors.success,
            rawValue: '${snap.active.length}',
          ),
        ),
      ],
    );
  }
}

class _MeterCard extends StatelessWidget {
  final String label;
  final int percent;
  final IconData icon;
  final Color color;
  final String? rawValue;
  const _MeterCard({
    required this.label,
    required this.percent,
    required this.icon,
    required this.color,
    this.rawValue,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.07),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 8),
          Text(
            rawValue ?? '$percent%',
            style: TextStyle(
                color: color, fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 4),
          if (rawValue == null)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: percent.clamp(0, 100) / 100,
                minHeight: 5,
                backgroundColor: AppColors.divider,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          const SizedBox(height: 4),
          Text(label,
              style:
                  const TextStyle(color: AppColors.textGray, fontSize: 11)),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title, subtitle;
  final VoidCallback onTap;
  const _ActionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: ListTile(
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color),
        ),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle:
            Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing:
            const Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.textLight),
        onTap: onTap,
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry, onEdit;
  const _ErrorView({
    required this.error,
    required this.onRetry,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.wifi_off,
                  size: 36, color: AppColors.accent),
            ),
            const SizedBox(height: 16),
            const Text('تعذّر الاتصال بالراوتر',
                style:
                    TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            const SizedBox(height: 8),
            Text(
              error.toString().length > 140
                  ? '${error.toString().substring(0, 140)}…'
                  : error.toString(),
              textAlign: TextAlign.center,
              style:
                  const TextStyle(color: AppColors.textGray, fontSize: 12),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('تعديل البيانات'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('إعادة المحاولة'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
