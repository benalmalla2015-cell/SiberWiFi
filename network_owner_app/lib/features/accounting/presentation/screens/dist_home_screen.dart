import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../mikrotik/data/feature_keys.dart';
import '../../../mikrotik/presentation/widgets/ui_states.dart';
import '../widgets/acc_feature_gate.dart';
import '../../data/dist_api.dart';
import '../../providers/dist_providers.dart';
import 'collections_screen.dart';
import 'debts_screen.dart';
import 'dist_report_screen.dart';
import 'dist_sale_screen.dart';
import 'dist_sales_screen.dart';
import 'pos_orders_screen.dart';

/// ACC-06 — the distributor home (PLAN §5: dist_home).
///
/// One read model drives the surface: sellable stock with the daily
/// remaining per category, POS points with their receivables, and
/// today's counters. Sales/collections/debts reuse the ACC-05
/// surfaces — the backend scopes every query to the acting agent.
class DistHomeScreen extends ConsumerWidget {
  const DistHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final homeAsync = ref.watch(distHomeProvider);

    return homeAsync.when(
      loading: () => const LoadingState(),
      error: (e, _) => ErrorRetry(
        message: 'تعذّر تحميل واجهة الموزع\n$e',
        onRetry: () => ref.invalidate(distHomeProvider),
      ),
      data: (home) => RefreshIndicator(
        onRefresh: () async => ref.invalidate(distHomeProvider),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _HeroCard(home: home),
            const SizedBox(height: 16),
            _ActionsGrid(home: home),
            const SizedBox(height: 16),
            _SectionTitle('فئاتي اليوم', Icons.style_outlined),
            const SizedBox(height: 8),
            if (home.categories.isEmpty)
              const _InlineHint('لا توجد فئات بيع متاحة')
            else
              ...home.categories.map((c) => _CategoryRow(cat: c)),
            const SizedBox(height: 16),
            _SectionTitle('نقاط البيع', Icons.storefront_outlined),
            const SizedBox(height: 8),
            if (home.posPoints.isEmpty)
              const _InlineHint('لا توجد نقاط بيع نشطة')
            else
              ...home.posPoints.map((p) => _PosRow(pos: p)),
          ],
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  final DistHome home;
  const _HeroCard({required this.home});

  @override
  Widget build(BuildContext context) {
    final t = home.today;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.12),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.lightBlue],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.delivery_dining_outlined,
                    color: Colors.white, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      home.agent?.displayName ?? 'موزع',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (home.agent?.cashAllowed == true) 'نقدي',
                        if (home.agent?.creditAllowed == true) 'آجل',
                        if (home.agent?.commissionLabel != null)
                          'عمولة: ${home.agent!.commissionLabel}',
                      ].join(' · '),
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textGray),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _Stat('مبيعات اليوم', _fmt(t.salesTotal),
                  Icons.point_of_sale_outlined, AppColors.primary),
              _Stat('نقدي', _fmt(t.cashTotal),
                  Icons.payments_outlined, AppColors.success),
              _Stat('آجل', _fmt(t.creditTotal),
                  Icons.schedule_outlined, AppColors.warning),
              _Stat('تحصيلات', _fmt(t.collectionsTotal),
                  Icons.south_west, AppColors.lightBlue),
            ],
          ),
        ],
      ),
    );
  }

  static String _fmt(double v) =>
      v >= 1000 ? '${(v / 1000).toStringAsFixed(1)}k' : v.toStringAsFixed(0);
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _Stat(this.label, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  fontSize: 10, color: AppColors.textGray)),
        ],
      ),
    );
  }
}

class _ActionsGrid extends StatelessWidget {
  final DistHome home;
  const _ActionsGrid({required this.home});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            _Action(
              title: 'بيع جديد',
              icon: Icons.add_shopping_cart,
              color: AppColors.primary,
              onTap: () => _push(context, const DistSaleScreen()),
            ),
            const SizedBox(width: 10),
            _Action(
              title: 'مبيعاتي',
              icon: Icons.receipt_long_outlined,
              color: AppColors.lightBlue,
              onTap: () => _push(context, const DistSalesScreen()),
            ),
            const SizedBox(width: 10),
            _Action(
              title: 'طلبات النقاط',
              icon: Icons.playlist_add_check_outlined,
              color: AppColors.warning,
              onTap: () => _push(context, const PosOrdersScreen()),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _Action(
              title: 'التحصيلات',
              icon: Icons.payments_outlined,
              color: AppColors.success,
              onTap: () => _push(context, const CollectionsScreen()),
            ),
            const SizedBox(width: 10),
            _Action(
              title: 'المديونيات',
              icon: Icons.handshake_outlined,
              color: AppColors.error,
              onTap: () => _push(context, const DebtsScreen()),
            ),
            const SizedBox(width: 10),
            _Action(
              title: 'تقريري وعمولاتي',
              icon: Icons.assessment_outlined,
              color: AppColors.primary,
              onTap: () => _push(context, const DistReportScreen()),
            ),
          ],
        ),
      ],
    );
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AccFeatureGate(
        feature: AccFeatures.distributor,
        child: screen,
      ),
    ));
  }
}

class _Action extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _Action({
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(
              children: [
                Icon(icon, color: color, size: 26),
                const SizedBox(height: 6),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionTitle(this.title, this.icon);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: AppColors.textDark,
          ),
        ),
      ],
    );
  }
}

class _InlineHint extends StatelessWidget {
  final String text;
  const _InlineHint(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12, color: AppColors.textGray),
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  final DistCategory cat;
  const _CategoryRow({required this.cat});

  @override
  Widget build(BuildContext context) {
    final remaining = cat.remainingToday;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: (cat.isSoldOut ? AppColors.textLight : AppColors.primary)
                .withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.style_outlined,
              size: 20,
              color: cat.isSoldOut
                  ? AppColors.textLight
                  : AppColors.primary),
        ),
        title: Text(
          cat.name,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: cat.isSoldOut
                ? AppColors.textGray
                : AppColors.textDark,
          ),
        ),
        subtitle: Text(
          'سعر ${cat.sellPrice.toStringAsFixed(0)} · '
          'مخزون ${cat.stockQty.toStringAsFixed(0)} ${cat.unitLabel}'
          '${remaining != null ? ' · متبقٍّ ${remaining.toStringAsFixed(0)}' : ''}',
          style: const TextStyle(fontSize: 11, color: AppColors.textGray),
        ),
        trailing: remaining != null
            ? Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (remaining > 0
                          ? AppColors.success
                          : AppColors.error)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  remaining > 0
                      ? remaining.toStringAsFixed(0)
                      : 'اكتمل',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color:
                        remaining > 0 ? AppColors.success : AppColors.error,
                  ),
                ),
              )
            : null,
      ),
    );
  }
}

class _PosRow extends StatelessWidget {
  final DistPosPoint pos;
  const _PosRow({required this.pos});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.storefront_outlined,
              size: 20, color: AppColors.success),
        ),
        title: Text(
          pos.name,
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppColors.textDark),
        ),
        subtitle: Text(
          [
            if (pos.location != null && pos.location!.isNotEmpty)
              pos.location!,
            'نقاط ${pos.pointsBalance.toStringAsFixed(0)}',
            'حد ائتمان ${pos.creditLimit.toStringAsFixed(0)}',
          ].join(' · '),
          style: const TextStyle(fontSize: 11, color: AppColors.textGray),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              pos.arBalance.toStringAsFixed(0),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: pos.arBalance > 0
                    ? AppColors.warning
                    : AppColors.success,
              ),
            ),
            const Text(
              'مستحق عليه',
              style: TextStyle(fontSize: 9, color: AppColors.textGray),
            ),
          ],
        ),
      ),
    );
  }
}
