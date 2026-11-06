import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../mikrotik/presentation/widgets/ui_states.dart';
import '../../data/money_api.dart';
import '../../providers/pos_app_providers.dart';

/// ACC-07 — read-only list of collections recorded against this
/// point (PLAN §5: GET /pos/collections-received — ACC-05 data).
class PosCollectionsScreen extends ConsumerWidget {
  const PosCollectionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(posCollectionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('سجل التحصيلات')),
      body: Container(
        color: AppColors.inputBg,
        child: listAsync.when(
          loading: () => const LoadingState(),
          error: (e, _) => ErrorRetry(
            message: 'تعذّر تحميل التحصيلات\n$e',
            onRetry: () =>
                ref.invalidate(posCollectionsProvider),
          ),
          data: (rows) {
            final total = rows.fold<double>(
                0, (s, r) => s + r.baseAmount);
            return RefreshIndicator(
              onRefresh: () async =>
                  ref.invalidate(posCollectionsProvider),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _TotalCard(
                      total: total, count: rows.length),
                  const SizedBox(height: 14),
                  if (rows.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 60),
                      child: EmptyState(
                        'لا توجد تحصيلات مسجّلة على هذه النقطة',
                        icon: Icons.payments_outlined,
                      ),
                    )
                  else
                    ...rows.map(
                        (c) => _CollectionCard(collection: c)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  final double total;
  final int count;
  const _TotalCard({required this.total, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.lightBlue],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('إجمالي ما تم تحصيله',
                    style: TextStyle(
                        fontSize: 11, color: Colors.white70)),
                const SizedBox(height: 4),
                Text(total.toStringAsFixed(0),
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('عدد العمليات',
                  style: TextStyle(
                      fontSize: 11, color: Colors.white70)),
              const SizedBox(height: 4),
              Text('$count',
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
            ],
          ),
        ],
      ),
    );
  }
}

class _CollectionCard extends StatelessWidget {
  final AccCollection collection;
  const _CollectionCard({required this.collection});

  @override
  Widget build(BuildContext context) {
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
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color:
                  AppColors.success.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.payments_outlined,
                color: AppColors.success, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${collection.amount.toStringAsFixed(0)} '
                  '${AccCurrencyInfo.label(collection.currency)}',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark),
                ),
                Text(
                  '${collection.partyLabel}: ${collection.partyName}'
                  '${collection.boxName != null ? ' · ${collection.boxName}' : ''}'
                  '${collection.collectedAt != null ? ' · ${_ago(collection.collectedAt!)}' : ''}',
                  style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textGray),
                ),
                if (collection.note != null &&
                    collection.note!.isNotEmpty)
                  Text(collection.note!,
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textGray)),
              ],
            ),
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
