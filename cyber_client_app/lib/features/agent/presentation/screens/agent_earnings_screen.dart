import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../providers/agent_providers.dart';

/// «أرباحي» — commission summary + ledger (CYB-07).
class AgentEarningsScreen extends ConsumerWidget {
  const AgentEarningsScreen({super.key});

  String _fmt(Object? v) {
    final n = v is num ? v : num.tryParse('$v') ?? 0;
    return NumberFormat('#,##0.##').format(n);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final earnings = ref.watch(agentEarningsProvider);

    return earnings.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('تعذّر تحميل الأرباح', style: TextStyle(color: AppColors.textGray)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => ref.invalidate(agentEarningsProvider),
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
      data: (data) {
        final summary = (data['summary'] as Map?)?.cast<String, dynamic>() ?? {};
        final commissions = ((data['commissions'] as Map?)?['data'] as List? ?? [])
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(agentEarningsProvider),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ── Summary cards ─────────────────────────────
              Row(
                children: [
                  _SummaryCard(
                    title: 'عمولات مستحقة',
                    value: '${_fmt(summary['accrued'])} ريال',
                    icon: Icons.savings_outlined,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 10),
                  _SummaryCard(
                    title: 'عمولات اليوم',
                    value: '${_fmt(summary['today'])} ريال',
                    icon: Icons.today_outlined,
                    color: AppColors.success,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _SummaryCard(
                    title: 'مصروفة لي',
                    value: '${_fmt(summary['paid_out'])} ريال',
                    icon: Icons.paid_outlined,
                    color: AppColors.accent,
                  ),
                  const SizedBox(width: 10),
                  _SummaryCard(
                    title: 'إجمالي المبيعات',
                    value: '${_fmt(summary['topup_volume'])} ريال',
                    icon: Icons.trending_up_rounded,
                    color: AppColors.textDark,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                'سجل العمولات',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 10),
              if (commissions.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      'لا توجد عمولات بعد — ستُقيد تلقائياً مع كل عملية شحن',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textGray),
                    ),
                  ),
                )
              else
                ...commissions.map((c) => _CommissionTile(commission: c)),
            ],
          ),
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  const _SummaryCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(color: AppColors.textGray, fontSize: 12)),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _CommissionTile extends StatelessWidget {
  final Map<String, dynamic> commission;
  const _CommissionTile({required this.commission});

  @override
  Widget build(BuildContext context) {
    final amount = (commission['amount'] as num?)?.toDouble() ?? 0;
    final topupAmount = (commission['topup_amount'] as num?)?.toDouble() ?? 0;
    final percent = (commission['percent'] as num?)?.toDouble() ?? 0;
    final createdAt = DateTime.tryParse(commission['created_at']?.toString() ?? '');
    final date = createdAt != null
        ? DateFormat('yyyy/MM/dd – HH:mm').format(createdAt.toLocal())
        : '';
    final status = commission['status']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.percent_rounded, color: AppColors.success),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'شحن ${commission['sim_no'] ?? ''}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  '${topupAmount.toStringAsFixed(0)} ريال × ${percent.toStringAsFixed(0)}%  ·  $date',
                  style: const TextStyle(color: AppColors.textGray, fontSize: 12),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '+${amount.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: AppColors.success,
                ),
              ),
              Text(
                status == 'paid_out' ? 'مصروفة' : 'مستحقة',
                style: const TextStyle(fontSize: 11, color: AppColors.textGray),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
