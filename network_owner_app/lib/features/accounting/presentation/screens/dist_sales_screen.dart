import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../mikrotik/presentation/widgets/ui_states.dart';
import '../../data/dist_api.dart';
import '../../providers/dist_providers.dart';
import 'dist_sale_screen.dart';

/// ACC-06 — the distributor's sales register (cash/credit/partial).
class DistSalesScreen extends ConsumerStatefulWidget {
  const DistSalesScreen({super.key});

  @override
  ConsumerState<DistSalesScreen> createState() => _DistSalesScreenState();
}

class _DistSalesScreenState extends ConsumerState<DistSalesScreen> {
  String? _kind;

  static const _filters = <String?, String>{
    null: 'الكل',
    'cash': 'نقدي',
    'credit': 'آجل',
    'partial': 'جزئي',
  };

  static const _kindColors = {
    'cash': AppColors.success,
    'credit': AppColors.warning,
    'partial': AppColors.lightBlue,
  };

  @override
  Widget build(BuildContext context) {
    final listAsync = ref.watch(distSalesProvider(_kind));

    return Scaffold(
      appBar: AppBar(title: const Text('مبيعاتي')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const DistSaleScreen()),
        ),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('بيع', style: TextStyle(color: Colors.white)),
      ),
      body: Container(
        color: AppColors.inputBg,
        child: Column(
          children: [
            Container(
              color: AppColors.white,
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _filters.entries.map((e) {
                    final selected = e.key == _kind;
                    return Padding(
                      padding:
                          const EdgeInsetsDirectional.only(end: 8),
                      child: ChoiceChip(
                        label: Text(e.value),
                        selected: selected,
                        onSelected: (_) =>
                            setState(() => _kind = e.key),
                        selectedColor: AppColors.primary
                            .withValues(alpha: 0.12),
                        labelStyle: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: selected
                              ? AppColors.primary
                              : AppColors.textGray,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            Expanded(
              child: listAsync.when(
                loading: () => const LoadingState(),
                error: (e, _) => ErrorRetry(
                  message: 'تعذّر تحميل المبيعات\n$e',
                  onRetry: () =>
                      ref.invalidate(distSalesProvider(_kind)),
                ),
                data: (items) => items.isEmpty
                    ? const EmptyState('لا توجد مبيعات بعد',
                        icon: Icons.receipt_long_outlined)
                    : RefreshIndicator(
                        onRefresh: () async =>
                            ref.invalidate(distSalesProvider(_kind)),
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: items.length,
                          itemBuilder: (_, i) => _SaleCard(
                            sale: items[i],
                            kindColor:
                                _kindColors[items[i].paymentKind] ??
                                    AppColors.textGray,
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SaleCard extends StatelessWidget {
  final DistSale sale;
  final Color kindColor;
  const _SaleCard({required this.sale, required this.kindColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sale.posName ?? 'نقطة #${sale.posId}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        sale.saleNo,
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textGray),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: kindColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    sale.kindLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: kindColor,
                    ),
                  ),
                ),
              ],
            ),
            if (sale.items.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                sale.items
                    .map((i) => '${i.categoryName} ×${i.qty}')
                    .join(' · '),
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textGray),
              ),
            ],
            const Divider(height: 18),
            Row(
              children: [
                _cell('الإجمالي', sale.totalAmount, AppColors.primary),
                _cell('المدفوع', sale.paidAmount, AppColors.success),
                _cell('المتبقي', sale.creditRemaining,
                    sale.creditRemaining > 0
                        ? AppColors.warning
                        : AppColors.textGray),
                if (sale.commissionAmount > 0)
                  _cell('عمولتي', sale.commissionAmount,
                      AppColors.lightBlue),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _cell(String label, double value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 10, color: AppColors.textGray)),
          const SizedBox(height: 2),
          Text(
            value.toStringAsFixed(0),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
