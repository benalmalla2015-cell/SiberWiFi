import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/dashboard_provider.dart';

class RecentTransactionsWidget extends ConsumerWidget {
  const RecentTransactionsWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashAsync = ref.watch(dashboardDataProvider);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('آخر المعاملات', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                TextButton(
                  onPressed: () => context.push('/transactions'),
                  child: const Text('عرض الكل', style: TextStyle(color: AppColors.primary, fontSize: 12)),
                ),
              ],
            ),
            dashAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('تعذّر التحميل', style: TextStyle(color: AppColors.textGray))),
              ),
              data: (data) {
                final txns = (data['recent_transactions'] as List? ?? [])
                    .whereType<Map>()
                    .map((transaction) => Map<String, dynamic>.from(transaction))
                    .toList();
                if (txns.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(Icons.receipt_long_outlined, size: 40, color: AppColors.divider),
                          SizedBox(height: 8),
                          Text('لا توجد معاملات', style: TextStyle(color: AppColors.textGray)),
                        ],
                      ),
                    ),
                  );
                }
                return Column(
                  children: txns.take(5).map((t) => _TransactionTile(txn: t)).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

double _asDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

class _TransactionTile extends StatelessWidget {
  final Map<String, dynamic> txn;
  const _TransactionTile({required this.txn});

  @override
  Widget build(BuildContext context) {
    final amount = _asDouble(txn['owner_amount'] ?? txn['network_owner_amount'] ?? txn['amount']);
    final cardName = txn['card_category']?['name'] ?? txn['category_name'] ?? 'بطاقة';
    final clientName = txn['user']?['name'] ?? txn['client_name'] ?? 'عميل';
    final createdAt = txn['created_at']?.toString() ?? '';
    final date = createdAt.length >= 16 ? createdAt.substring(0, 16) : createdAt;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.credit_card, color: AppColors.success, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(cardName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(clientName, style: const TextStyle(color: AppColors.textGray, fontSize: 12)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('+${amount.toStringAsFixed(0)} ر', style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.bold, fontSize: 13)),
              Text(date, style: const TextStyle(color: AppColors.textGray, fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }
}
