import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/date_utils.dart';
import '../providers/wallet_provider.dart';

class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balAsync = ref.watch(walletBalanceProvider);
    final txAsync  = ref.watch(walletTransactionsProvider);
    final fmt      = NumberFormat('#,##0.00', 'ar');

    return Scaffold(
      backgroundColor: Colors.white,
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () async {
          ref.invalidate(walletBalanceProvider);
          ref.invalidate(walletTransactionsProvider);
        },
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildBalanceCard(context, balAsync, fmt)),
            SliverToBoxAdapter(child: _buildActions(context)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('آخر المعاملات', style: TextStyle(fontFamily: 'Cairo', fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textDark)),
                    GestureDetector(
                      onTap: () => context.go('/transactions'),
                      child: const Text('عرض الكل', style: TextStyle(fontFamily: 'Cairo', fontSize: 13, color: AppColors.primary, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            ),
            txAsync.when(
              loading: () => SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, __) => Shimmer.fromColors(
                    baseColor: const Color(0xFFE8ECF4),
                    highlightColor: const Color(0xFFF5F7FD),
                    child: Container(height: 70, margin: const EdgeInsets.fromLTRB(16, 0, 16, 10), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14))),
                  ),
                  childCount: 5,
                ),
              ),
              error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
              data: (txs) {
                if (txs.isEmpty) {
                  return const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(
                        child: Text('لا توجد معاملات بعد', style: TextStyle(fontFamily: 'Cairo', color: AppColors.textGray)),
                      ),
                    ),
                  );
                }
                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _TxItem(tx: txs[i], fmt: fmt),
                    childCount: txs.take(10).length,
                  ),
                );
              },
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  Widget _buildBalanceCard(BuildContext context, AsyncValue<double> balAsync, NumberFormat fmt) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primaryDark, AppColors.primary, Color(0xFF243490)],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(36),
          bottomRight: Radius.circular(36),
        ),
      ),
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 16,
        left: 20, right: 20, bottom: 32,
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('محفظتي', style: TextStyle(fontFamily: 'Cairo', fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 22),
              ),
            ],
          ),
          const SizedBox(height: 28),
          const Text('رصيدك الحالي', style: TextStyle(fontFamily: 'Cairo', fontSize: 14, color: Colors.white70)),
          const SizedBox(height: 10),
          balAsync.when(
            loading: () => const SizedBox(height: 44, child: Center(child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2))),
            error: (_, __) => const Text('--', style: TextStyle(fontFamily: 'Cairo', fontSize: 40, color: Colors.white)),
            data: (b) => Text(
              '${fmt.format(b)} ر.ي',
              style: const TextStyle(fontFamily: 'Cairo', fontSize: 38, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
          const SizedBox(height: 8),
          const Text('ريال يمني', style: TextStyle(fontFamily: 'Cairo', fontSize: 13, color: Colors.white54)),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Row(
        children: [
          Expanded(
            child: _ActionButton(
              icon: Icons.add_card_rounded,
              label: 'شحن الرصيد',
              color: AppColors.primary,
              onTap: () => context.go('/wallet/topup'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _ActionButton(
              icon: Icons.receipt_long_rounded,
              label: 'سجل المعاملات',
              color: AppColors.lightBlue,
              onTap: () => context.go('/transactions'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String   label;
  final Color    color;
  final VoidCallback onTap;
  const _ActionButton({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(label, style: TextStyle(fontFamily: 'Cairo', fontSize: 13, color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _TxItem extends StatelessWidget {
  final Map<String, dynamic> tx;
  final NumberFormat fmt;
  const _TxItem({required this.tx, required this.fmt});

  @override
  Widget build(BuildContext context) {
    final type    = tx['type'] ?? '';
    final amount  = (tx['amount'] ?? 0).toDouble();
    final isPending = type == 'pending_topup';
    final isCredit = type == 'topup' || type == 'credit';
    final date    = parseUtcToLocal(tx['created_at']);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: isPending
                  ? AppColors.primary.withValues(alpha: 0.1)
                  : (isCredit ? AppColors.success.withValues(alpha: 0.1) : AppColors.accent.withValues(alpha: 0.1)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isPending
                  ? Icons.hourglass_top_rounded
                  : (isCredit ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded),
              color: isPending ? AppColors.primary : (isCredit ? AppColors.success : AppColors.accent),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_typeLabel(type), style: const TextStyle(fontFamily: 'Cairo', fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textDark)),
                if (date != null)
                  Text(
                    '${date.day}/${date.month}/${date.year}  ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, color: AppColors.textGray),
                  ),
              ],
            ),
          ),
          Text(
            isPending ? fmt.format(amount) : '${isCredit ? '+' : '-'} ${fmt.format(amount)}',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: isPending ? AppColors.primary : (isCredit ? AppColors.success : AppColors.accent),
            ),
          ),
        ],
      ),
    );
  }

  String _typeLabel(String t) {
    switch (t) {
      case 'topup':          return 'شحن رصيد';
      case 'purchase':       return 'شراء كرت';
      case 'credit':         return 'إيداع';
      case 'debit':          return 'خصم';
      case 'pending_topup':  return 'طلب شحن رصيد (بانتظار المراجعة)';
      case 'cashback':       return 'كاشباك';
      case 'referral_commission': return 'عمولة رفلينك';
      case 'refund':         return 'استرجاع';
      default:               return t;
    }
  }
}
