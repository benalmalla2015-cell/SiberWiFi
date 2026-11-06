import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../mikrotik/presentation/widgets/ui_states.dart';
import '../../data/pos_app_api.dart';
import '../../providers/pos_app_providers.dart';
import 'pos_collections_screen.dart';
import 'pos_exchange_screen.dart';
import 'pos_order_request_screen.dart';
import 'pos_withdrawals_screen.dart';

/// ACC-07 — the POS agent's home surface (PLAN §5).
///
/// One aggregate (`posHomeProvider`) paints the whole screen:
/// points + profit hero, quick actions, the orderable package
/// catalog, and the latest ledger/order activity feed.
class PosHomeScreen extends ConsumerWidget {
  const PosHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final homeAsync = ref.watch(posHomeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('نقطة البيع')),
      body: Container(
        color: AppColors.inputBg,
        child: homeAsync.when(
          loading: () => const LoadingState(),
          error: (e, _) => ErrorRetry(
            message: 'تعذّر تحميل نقطة البيع\n$e',
            onRetry: () => _refresh(ref),
          ),
          data: (data) => RefreshIndicator(
            onRefresh: () async => _refresh(ref),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _HeroCard(data: data),
                const SizedBox(height: 14),
                _ActionsRow(onOpen: (w) => _push(context, w)),
                const SizedBox(height: 18),
                _SectionTitle('حزم الطلب'),
                if (data.packages.isEmpty)
                  const EmptyState(
                    'لا توجد حزم مفعّلة بعد — راجع إدارة الشبكة',
                    icon: Icons.inventory_2_outlined,
                  )
                else
                  ...data.packages.map((p) => _PackageCard(
                        package: p,
                        onOrder: () =>
                            _push(context, const PosOrderRequestScreen()),
                        onExchange: () => _push(
                            context,
                            PosExchangeScreen(
                                initialCategoryId: p.id)),
                      )),
                const SizedBox(height: 18),
                _SectionTitle('آخر النشاطات'),
                if (data.recentLedger.isEmpty)
                  const EmptyState(
                    'لا حركات مسجّلة بعد',
                    icon: Icons.receipt_long_outlined,
                  )
                else
                  ...data.recentLedger
                      .map((l) => _LedgerTile(row: l)),
                if (data.recentOrders.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  _SectionTitle('آخر الطلبات'),
                  ...data.recentOrders
                      .map((o) => _OrderTile(order: o)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _refresh(WidgetRef ref) {
    ref.invalidate(posHomeProvider);
    ref.invalidate(posLedgerProvider);
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => screen));
  }
}

class _HeroCard extends StatelessWidget {
  final PosHomeData data;
  const _HeroCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.lightBlue],
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(data.pos.name,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                    if (data.agentName != null)
                      Text(data.agentName!,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.white70)),
                  ],
                ),
              ),
              if (data.pos.status != 'active')
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('موقوفة',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _BalanceChip(
                label: 'النقاط',
                value: data.pos.pointsBalance,
                icon: Icons.stars_rounded,
              ),
              const SizedBox(width: 10),
              _BalanceChip(
                label: 'الأرباح',
                value: data.pos.profitBalance,
                icon: Icons.payments_outlined,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _HeroStat(
                  'طلبات معلّقة', '${data.stats.pendingOrders}'),
              _HeroStat('استبدالات', '${data.stats.exchangesTotal}'),
              _HeroStat(
                'سحوبات معلّقة',
                data.stats.pendingWithdrawalsAmount
                    .toStringAsFixed(0),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BalanceChip extends StatelessWidget {
  final String label;
  final double value;
  final IconData icon;
  const _BalanceChip(
      {required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 14, color: Colors.white70),
                const SizedBox(width: 4),
                Text(label,
                    style: const TextStyle(
                        fontSize: 11, color: Colors.white70)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value.toStringAsFixed(0),
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  final String label;
  final String value;
  const _HeroStat(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
          Text(label,
              style: const TextStyle(
                  fontSize: 10, color: Colors.white70)),
        ],
      ),
    );
  }
}

class _ActionsRow extends StatelessWidget {
  final ValueChanged<Widget> onOpen;
  const _ActionsRow({required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Action(
          label: 'طلب حزم',
          icon: Icons.add_shopping_cart_outlined,
          color: AppColors.primary,
          onTap: () => onOpen(const PosOrderRequestScreen()),
        ),
        _Action(
          label: 'استبدال',
          icon: Icons.swap_horiz_rounded,
          color: AppColors.lightBlue,
          onTap: () => onOpen(const PosExchangeScreen()),
        ),
        _Action(
          label: 'سحب أرباح',
          icon: Icons.account_balance_wallet_outlined,
          color: AppColors.success,
          onTap: () => onOpen(const PosWithdrawalsScreen()),
        ),
        _Action(
          label: 'التحصيلات',
          icon: Icons.payments_outlined,
          color: AppColors.warning,
          onTap: () => onOpen(const PosCollectionsScreen()),
        ),
      ],
    );
  }
}

class _Action extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _Action(
      {required this.label,
      required this.icon,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(height: 6),
              Text(label,
                  style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(title,
          style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.textDark)),
    );
  }
}

class _PackageCard extends StatelessWidget {
  final PosPackage package;
  final VoidCallback onOrder;
  final VoidCallback onExchange;
  const _PackageCard(
      {required this.package,
      required this.onOrder,
      required this.onExchange});

  @override
  Widget build(BuildContext context) {
    final out = !package.available;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.wifi_tethering,
                color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(package.name,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark)),
                Text(
                  '${package.pointsCost.toStringAsFixed(0)} نقطة / ${package.unitLabel}'
                  ' · متاح ${package.stockQty.toStringAsFixed(0)}',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textGray),
                ),
              ],
            ),
          ),
          if (out)
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text('نفد المخزون',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: AppColors.error)),
            )
          else
            Row(
              children: [
                _MiniButton('طلب', AppColors.primary, onOrder),
                const SizedBox(width: 6),
                _MiniButton('استبدل', AppColors.success, onExchange),
              ],
            ),
        ],
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _MiniButton(this.label, this.color, this.onTap);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: color)),
      ),
    );
  }
}

class _LedgerTile extends StatelessWidget {
  final PosLedgerRow row;
  const _LedgerTile({required this.row});

  @override
  Widget build(BuildContext context) {
    final color =
        row.isCredit ? AppColors.success : AppColors.error;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            row.isCredit
                ? Icons.arrow_downward_rounded
                : Icons.arrow_upward_rounded,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.reasonLabel,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark)),
                Text(
                  '${row.isPoints ? 'نقاط' : 'أرباح'}'
                  '${row.createdAt != null ? ' · ${_ago(row.createdAt!)}' : ''}',
                  style: const TextStyle(
                      fontSize: 10, color: AppColors.textGray),
                ),
              ],
            ),
          ),
          Text(
            '${row.isCredit ? '+' : ''}${row.delta.toStringAsFixed(0)}',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: color),
          ),
        ],
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  final PosHomeOrder order;
  const _OrderTile({required this.order});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (order.status) {
      'pending' => ('بانتظار الاعتماد', AppColors.warning),
      'approved' => ('معتمد', AppColors.success),
      'rejected' => ('مرفوض', AppColors.error),
      _ => (order.status, AppColors.textGray),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(order.orderNo,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark)),
          ),
          Text('${order.pointsTotal.toStringAsFixed(0)} نقطة',
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textGray)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(label,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: color)),
          ),
        ],
      ),
    );
  }
}

String _ago(String iso) {
  final t = DateTime.tryParse(iso);
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 60) return 'منذ ${d.inMinutes} د';
  if (d.inHours < 24) return 'منذ ${d.inHours} س';
  return 'منذ ${d.inDays} يوم';
}
