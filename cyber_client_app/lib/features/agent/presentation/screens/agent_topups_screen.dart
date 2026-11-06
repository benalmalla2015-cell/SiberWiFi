import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../providers/agent_providers.dart';

/// «سجل عملياتي» — the agent's own top-up history, newest first.
class AgentTopupsScreen extends ConsumerWidget {
  const AgentTopupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final topups = ref.watch(agentTopupsProvider);

    return topups.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _Retry(
        message: 'تعذّر تحميل السجل',
        onRetry: () => ref.invalidate(agentTopupsProvider),
      ),
      data: (items) => items.isEmpty
          ? const Center(
              child: Text(
                'لا توجد عمليات شحن بعد',
                style: TextStyle(color: AppColors.textGray, fontSize: 15),
              ),
            )
          : RefreshIndicator(
              onRefresh: () async => ref.invalidate(agentTopupsProvider),
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _TopupTile(topup: items[i]),
              ),
            ),
    );
  }
}

class _TopupTile extends StatelessWidget {
  final Map<String, dynamic> topup;
  const _TopupTile({required this.topup});

  @override
  Widget build(BuildContext context) {
    final amount = (topup['amount'] as num?)?.toDouble() ?? 0;
    final status = topup['status']?.toString() ?? '';
    final createdAt = DateTime.tryParse(topup['created_at']?.toString() ?? '');
    final date = createdAt != null
        ? DateFormat('yyyy/MM/dd – HH:mm').format(createdAt.toLocal())
        : '';

    return Container(
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
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.bolt_rounded, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  topup['sim_no']?.toString() ?? '',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 2),
                Text(date, style: const TextStyle(color: AppColors.textGray, fontSize: 12)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${amount.toStringAsFixed(0)} ${topup['currency'] ?? ''}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              Text(
                status == 'completed' ? 'مكتمل' : status,
                style: TextStyle(
                  fontSize: 11,
                  color: status == 'completed' ? AppColors.success : AppColors.error,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Retry extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _Retry({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(message, style: const TextStyle(color: AppColors.textGray)),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
        ],
      ),
    );
  }
}
