import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/connectivity_service.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/dashboard_provider.dart';
import '../widgets/sales_chart_widget.dart';
import '../widgets/recent_transactions_widget.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final online = ref.watch(isOnlineProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('لوحة التحكم'),
        actions: [
          IconButton(
            onPressed: () => context.push('/conversations'),
            icon: const Icon(Icons.forum_outlined),
            tooltip: 'رسائل العملاء',
          ),
          if (!online)
            Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.wifi_off, size: 14, color: AppColors.warning),
                  SizedBox(width: 4),
                  Text(
                    'offline',
                    style: TextStyle(fontSize: 11, color: AppColors.warning),
                  ),
                ],
              ),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(dashboardDataProvider);
          ref.invalidate(statsDataProvider);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _WelcomeCard(name: user?.name ?? ''),
              const SizedBox(height: 16),
              _DashboardStatsRow(),
              const SizedBox(height: 16),
              _BalanceRow(
                available: user?.availableBalance ?? 0,
                frozen: user?.frozenBalance ?? 0,
                total: user?.totalEarnings ?? 0,
              ),
              const SizedBox(height: 16),
              _QuickActionsRow(),
              const SizedBox(height: 12),
              _OwnerManagementActionsRow(),
              const SizedBox(height: 14),
              _TopUpActionsRow(),
              const SizedBox(height: 20),
              const SalesChartWidget(),
              const SizedBox(height: 16),
              const _CategoryInsightsCard(),
              const SizedBox(height: 16),
              const RecentTransactionsWidget(),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryInsightsCard extends ConsumerWidget {
  const _CategoryInsightsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(dashboardDataProvider);
    return dashboard.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (data) {
        final insights = data['category_insights'];
        if (insights is! List || insights.isEmpty) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.insights, color: AppColors.primary),
                  SizedBox(width: 8),
                  Text('الفئات الأكثر طلباً ومبيعاً', style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 12),
              ...insights.map((item) {
                final insight = Map<String, dynamic>.from(item as Map);
                final requested = insight['most_requested'] is List && (insight['most_requested'] as List).isNotEmpty
                    ? Map<String, dynamic>.from((insight['most_requested'] as List).first as Map)
                    : null;
                final sold = insight['most_sold'] is List && (insight['most_sold'] as List).isNotEmpty
                    ? Map<String, dynamic>.from((insight['most_sold'] as List).first as Map)
                    : null;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(insight['network_name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text('الأكثر طلباً: ${requested?['category_name'] ?? 'لا توجد بيانات'} (${requested?['count'] ?? 0})', style: const TextStyle(fontSize: 12, color: AppColors.textGray)),
                      Text('الأكثر مبيعاً: ${sold?['category_name'] ?? 'لا توجد بيانات'} (${sold?['count'] ?? 0})', style: const TextStyle(fontSize: 12, color: AppColors.textGray)),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}

class _DashboardStatsRow extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dash = ref.watch(dashboardDataProvider);
    return dash.when(
      loading: () => Row(
        children: List.generate(
          3,
          (_) => Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: _ShimmerCard(),
            ),
          ),
        ),
      ),
      error: (_, __) => const SizedBox(),
      data: (data) {
        final stats = data['stats'] is Map
            ? Map<String, dynamic>.from(data['stats'] as Map)
            : data;
        final networks =
            stats['total_networks'] ?? stats['networks_count'] ?? 0;
        final cards =
            stats['available_cards'] ??
            stats['total_cards'] ??
            stats['cards_count'] ??
            0;
        final sales = _asDouble(
          stats['today_sales'] ??
              stats['today_revenue'] ??
              stats['total_sales'],
        );
        return Row(
          children: [
            Expanded(
              child: _StatCard(
                label: 'شبكاتي',
                value: '$networks',
                icon: Icons.wifi,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatCard(
                label: 'كروت متاحة',
                value: '$cards',
                icon: Icons.credit_card,
                color: AppColors.lightBlue,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatCard(
                label: 'مبيعات اليوم',
                value: '${sales.toStringAsFixed(0)}ر',
                icon: Icons.trending_up,
                color: AppColors.success,
              ),
            ),
          ],
        );
      },
    );
  }
}

double _asDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

class _ShimmerCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: AppColors.divider,
        borderRadius: BorderRadius.circular(14),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.20)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          Text(
            label,
            style: const TextStyle(color: AppColors.textGray, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _WelcomeCard extends StatelessWidget {
  final String name;
  const _WelcomeCard({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF16235F), Color(0xFF1E2D7D), Color(0xFF2A3A9A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: [0.0, 0.5, 1.0],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E2D7D).withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'مرحباً، $name',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'صاحب الشبكة',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.20),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.asset(
                'logo/logo.png',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.wifi, color: Colors.white, size: 32),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BalanceRow extends StatelessWidget {
  final double available, frozen, total;
  const _BalanceRow({
    required this.available,
    required this.frozen,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _BalanceCard(
            label: 'الرصيد المتاح',
            amount: available,
            color: AppColors.success,
            icon: Icons.account_balance_wallet,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _BalanceCard(
            label: 'مجمّد',
            amount: frozen,
            color: AppColors.warning,
            icon: Icons.lock_clock,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _BalanceCard(
            label: 'إجمالي الأرباح',
            amount: total,
            color: AppColors.lightBlue,
            icon: Icons.trending_up,
          ),
        ),
      ],
    );
  }
}

class _BalanceCard extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;
  final IconData icon;
  const _BalanceCard({
    required this.label,
    required this.amount,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.22)),
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
          const SizedBox(height: 6),
          Text(
            '${(amount / 1000).toStringAsFixed(1)}K',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: AppColors.textGray),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _QuickActionsRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _QuickAction(
          icon: Icons.wifi,
          label: 'شبكاتي',
          color: AppColors.primary,
          onTap: () => context.go('/networks'),
        ),
        const SizedBox(width: 8),
        _QuickAction(
          icon: Icons.credit_card,
          label: 'الكروت',
          color: AppColors.lightBlue,
          onTap: () => context.go('/networks'),
        ),
        const SizedBox(width: 8),
        _QuickAction(
          icon: Icons.account_balance_wallet,
          label: 'السحب',
          color: AppColors.success,
          onTap: () => context.go('/payouts'),
        ),
        const SizedBox(width: 8),
        _QuickAction(
          icon: Icons.report_outlined,
          label: 'البلاغات',
          color: AppColors.warning,
          onTap: () => context.go('/reports'),
        ),
      ],
    );
  }
}

class _OwnerManagementActionsRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _TopUpAction(
            icon: Icons.router_outlined,
            label: 'أجهزة MikroTik',
            color: AppColors.primary,
            onTap: () => context.push('/mikrotik'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _TopUpAction(
            icon: Icons.ev_station,
            label: 'نقاط الشحن',
            color: AppColors.lightBlue,
            onTap: () => context.push('/charging-points'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _TopUpAction(
            icon: Icons.star_outline,
            label: 'تقييمات العملاء',
            color: AppColors.warning,
            onTap: () => context.push('/reviews'),
          ),
        ),
      ],
    );
  }
}

class _TopUpActionsRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _TopUpAction(
            icon: Icons.bolt_rounded,
            label: 'شحن رصيد فايبر',
            color: AppColors.lightBlue,
            onTap: () => context.push('/fiber-topup'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _TopUpAction(
            icon: Icons.satellite_alt_outlined,
            label: 'شحن رصيد Starlink',
            color: AppColors.primary,
            onTap: () => context.push('/starlink-topup'),
          ),
        ),
      ],
    );
  }
}

class _TopUpAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _TopUpAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          border: Border.all(color: color.withValues(alpha: 0.24)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
