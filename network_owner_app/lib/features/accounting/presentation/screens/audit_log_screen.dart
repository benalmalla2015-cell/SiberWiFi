import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../mikrotik/presentation/widgets/ui_states.dart';
import '../../data/reports_api.dart';
import '../../providers/reports_providers.dart';

/// ACC-09 — سجل التتبع (PLAN §5: audit_log_screen).
///
/// Append-only audit trail: every financial action lands here with
/// actor, entity and timing metadata — the accountant-style
/// activity monitor.
class AuditLogScreen extends ConsumerStatefulWidget {
  const AuditLogScreen({super.key});

  @override
  ConsumerState<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends ConsumerState<AuditLogScreen> {
  String? _entity;

  static const _entities = <String?, String>{
    null: 'الكل',
    'acc_journal_entries': 'قيود',
    'acc_collections': 'تحصيلات',
    'acc_sales': 'مبيعات',
    'acc_expenses': 'مصروفات',
    'acc_debts': 'ديون',
    'acc_cash_transfers': 'تحويلات',
    'acc_pos_orders': 'طلبات نقاط',
    'acc_withdrawals': 'سحوبات',
  };

  static const _actionLabels = {
    'journal.post': 'ترحيل قيد',
    'collection.create': 'تحصيل',
    'debt.create': 'تسجيل دين',
    'debt.pay': 'سداد دين',
    'cashbox.create': 'إنشاء صندوق',
    'cashbox.transfer': 'تحويل صندوق',
    'expense.create': 'مصروف',
    'expense.void': 'إلغاء مصروف',
    'dist.sale': 'بيع موزع',
    'posorder.create': 'طلب نقطة',
    'posorder.approve': 'اعتماد طلب',
    'posorder.reject': 'رفض طلب',
    'posapp.exchange': 'استبدال كروت',
    'withdrawal.request': 'طلب سحب',
    'withdrawal.decide': 'قرار سحب',
    'stock.adjust': 'تسوية مخزون',
  };

  @override
  Widget build(BuildContext context) {
    final key = (entity: _entity, agentId: null);
    final auditAsync = ref.watch(accAuditProvider(key));

    return Scaffold(
      appBar: AppBar(title: const Text('سجل التتبع')),
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
                  children: _entities.entries.map((e) {
                    final selected = e.key == _entity;
                    return Padding(
                      padding:
                          const EdgeInsetsDirectional.only(end: 8),
                      child: ChoiceChip(
                        label: Text(e.value),
                        selected: selected,
                        onSelected: (_) =>
                            setState(() => _entity = e.key),
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
            ),
            Expanded(
              child: auditAsync.when(
                loading: () => const LoadingState(),
                error: (e, _) => ErrorRetry(
                  message: 'تعذّر تحميل السجل\n$e',
                  onRetry: () =>
                      ref.invalidate(accAuditProvider(key)),
                ),
                data: (a) => a.rows.isEmpty
                    ? const EmptyState('السجل فارغ',
                        icon: Icons.history_outlined)
                    : RefreshIndicator(
                        onRefresh: () async =>
                            ref.invalidate(accAuditProvider(key)),
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: a.rows.length,
                          itemBuilder: (_, i) =>
                              _AuditTile(row: a.rows[i]),
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

class _AuditTile extends StatelessWidget {
  final AccAuditRow row;
  const _AuditTile({required this.row});

  @override
  Widget build(BuildContext context) {
    final label =
        _AuditLogScreenState._actionLabels[row.action] ?? row.action;
    final latency = row.latencyMs;
    final time = row.createdAt != null && row.createdAt!.length >= 16
        ? row.createdAt!.substring(0, 16).replaceFirst('T', ' ')
        : (row.createdAt ?? '');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        dense: true,
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.lightBlue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.fact_check_outlined,
              size: 18, color: AppColors.lightBlue),
        ),
        title: Text(label,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.textDark)),
        subtitle: Text(
          '${row.agentName} · ${row.entity}'
          '${row.entityId != null ? '#${row.entityId}' : ''}\n$time'
          '${latency != null ? ' · ${latency.toStringAsFixed(0)}ms' : ''}',
          style: const TextStyle(
              fontSize: 10, color: AppColors.textGray, height: 1.5),
        ),
        isThreeLine: true,
      ),
    );
  }
}
