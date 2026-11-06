import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../mikrotik/presentation/widgets/ui_states.dart';
import '../../data/reports_api.dart';
import '../../providers/reports_providers.dart';

/// ACC-09 — تحليل قوة نقاط البيع (PLAN §5: pos_analysis_screen).
///
/// Each point gets a 0–100 activity score (period sales +
/// collections, normalized to the busiest point) plus its live
/// ledger state: AR balance, points, profit, order pipeline.
class PosAnalysisScreen extends ConsumerStatefulWidget {
  const PosAnalysisScreen({super.key});

  @override
  ConsumerState<PosAnalysisScreen> createState() =>
      _PosAnalysisScreenState();
}

class _PosAnalysisScreenState extends ConsumerState<PosAnalysisScreen> {
  int _days = 30;

  static const _ranges = {7: '7 أيام', 30: '30 يوماً', 90: '90 يوماً'};

  @override
  Widget build(BuildContext context) {
    final perfAsync = ref.watch(accPosPerfProvider(_days));

    return Scaffold(
      appBar: AppBar(title: const Text('تحليل نقاط البيع')),
      body: Container(
        color: AppColors.inputBg,
        child: Column(
          children: [
            Container(
              color: AppColors.white,
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
              child: Row(
                children: _ranges.entries.map((e) {
                  final selected = e.key == _days;
                  return Padding(
                    padding:
                        const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(
                      label: Text(e.value),
                      selected: selected,
                      onSelected: (_) =>
                          setState(() => _days = e.key),
                      selectedColor:
                          AppColors.primary.withValues(alpha: 0.12),
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
            Expanded(
              child: perfAsync.when(
                loading: () => const LoadingState(),
                error: (e, _) => ErrorRetry(
                  message: 'تعذّر تحميل التحليل\n$e',
                  onRetry: () =>
                      ref.invalidate(accPosPerfProvider(_days)),
                ),
                data: (points) => points.isEmpty
                    ? const EmptyState('لا نقاط بيع بعد',
                        icon: Icons.storefront_outlined)
                    : RefreshIndicator(
                        onRefresh: () async => ref
                            .invalidate(accPosPerfProvider(_days)),
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: points.length,
                          itemBuilder: (_, i) =>
                              _PosCard(rank: i + 1, point: points[i]),
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

class _PosCard extends StatelessWidget {
  final int rank;
  final AccPosPerf point;
  const _PosCard({required this.rank, required this.point});

  @override
  Widget build(BuildContext context) {
    final tierColor = switch (point.tier) {
      'strong' => AppColors.success,
      'medium' => AppColors.lightBlue,
      'active' => AppColors.warning,
      _ => AppColors.textGray,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text('$rank',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: AppColors.primary)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(point.name,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textDark)),
                  if (point.location != null)
                    Text(point.location!,
                        style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.textGray)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: tierColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(point.tierLabel,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: tierColor)),
            ),
          ]),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: point.score / 100,
              minHeight: 6,
              backgroundColor: AppColors.divider,
              valueColor: AlwaysStoppedAnimation(tierColor),
            ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Text('${point.score}/100',
                style: const TextStyle(
                    fontSize: 10, color: AppColors.textGray)),
          ),
          const SizedBox(height: 8),
          Row(children: [
            _metric('مبيعات', _n(point.salesTotal)),
            _metric('تحصيل', _n(point.collectionsTotal)),
            _metric('ذمة', _n(point.arBalance)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            _metric('نقاط', _n(point.pointsBalance)),
            _metric('أرباح', _n(point.profitBalance)),
            _metric(
              'طلبات',
              '${point.ordersApproved} معتمد'
                  '${point.ordersPending > 0 ? ' · ${point.ordersPending} معلق' : ''}',
            ),
          ]),
          if (point.lastSaleAt != null) ...[
            const SizedBox(height: 6),
            Text(
              'آخر بيع: ${point.lastSaleAt!.length >= 10 ? point.lastSaleAt!.substring(0, 10) : point.lastSaleAt!}',
              style: const TextStyle(
                  fontSize: 10, color: AppColors.textGray),
            ),
          ],
        ],
      ),
    );
  }

  Widget _metric(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark)),
          Text(label,
              style: const TextStyle(
                  fontSize: 10, color: AppColors.textGray)),
        ],
      ),
    );
  }

  String _n(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}
