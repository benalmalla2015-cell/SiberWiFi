import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../mikrotik/presentation/widgets/ui_states.dart';
import '../../data/pos_orders_api.dart';
import '../../providers/pos_orders_providers.dart';

/// ACC-04 — POS order decisions (PLAN §5: pos_orders_screen).
///
/// Owner/admin/distributor surface: pending orders arrive from POS
/// agents, approval posts stock + points + profit + a journal
/// entry in one backend transaction, rejection asks for a reason.
class PosOrdersScreen extends ConsumerStatefulWidget {
  const PosOrdersScreen({super.key});

  @override
  ConsumerState<PosOrdersScreen> createState() => _PosOrdersScreenState();
}

class _PosOrdersScreenState extends ConsumerState<PosOrdersScreen> {
  String? _status; // null = all

  static const _filters = <String?, String>{
    null: 'الكل',
    'pending': 'معلّقة',
    'approved': 'معتمدة',
    'rejected': 'مرفوضة',
  };

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(posOrdersProvider(_status));

    return Scaffold(
      appBar: AppBar(title: const Text('طلبات نقاط البيع')),
      body: Container(
        color: AppColors.inputBg,
        child: Column(
          children: [
            _FilterBar(
              filters: _filters,
              current: _status,
              onSelect: (s) => setState(() => _status = s),
            ),
            Expanded(
              child: ordersAsync.when(
                loading: () => const LoadingState(),
                error: (e, _) => ErrorRetry(
                  message: 'تعذّر تحميل الطلبات\n$e',
                  onRetry: () => ref.invalidate(posOrdersProvider(_status)),
                ),
                data: (orders) => orders.isEmpty
                    ? const EmptyState('لا توجد طلبات',
                        icon: Icons.receipt_long_outlined)
                    : RefreshIndicator(
                        onRefresh: () async =>
                            ref.invalidate(posOrdersProvider(_status)),
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: orders.length,
                          itemBuilder: (_, i) =>
                              _OrderCard(order: orders[i], onTap: () => _openDetails(orders[i])),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openDetails(PosOrder order) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _OrderDetailsSheet(
        order: order,
        onDecided: () {
          ref.invalidate(posOrdersProvider(_status));
          Navigator.of(context).pop();
        },
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final Map<String?, String> filters;
  final String? current;
  final ValueChanged<String?> onSelect;

  const _FilterBar({
    required this.filters,
    required this.current,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: filters.entries.map((e) {
            final selected = e.key == current;
            return Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: ChoiceChip(
                label: Text(e.value),
                selected: selected,
                onSelected: (_) => onSelect(e.key),
                selectedColor: AppColors.primary.withValues(alpha: 0.12),
                labelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: selected ? AppColors.primary : AppColors.textGray,
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final PosOrder order;
  final VoidCallback onTap;

  const _OrderCard({required this.order, required this.onTap});

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
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        onTap: onTap,
        title: Row(
          children: [
            Expanded(
              child: Text(
                order.orderNo,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: AppColors.textDark,
                ),
              ),
            ),
            _StatusBadge(status: order.status),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                order.posName ?? 'نقطة بيع #${order.posId}',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textGray),
              ),
              const SizedBox(height: 4),
              Text(
                '${order.totalQty} كرت · ${order.totalAmount.toStringAsFixed(0)} ريال · ${order.pointsTotal.toStringAsFixed(0)} نقطة',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary),
              ),
            ],
          ),
        ),
        trailing: const Icon(Icons.chevron_left,
            size: 18, color: AppColors.textGray),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'pending' => ('معلّق', AppColors.warning),
      'approved' => ('معتمد', AppColors.success),
      'rejected' => ('مرفوض', AppColors.error),
      _ => (status, AppColors.textGray),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }
}

class _OrderDetailsSheet extends ConsumerStatefulWidget {
  final PosOrder order;
  final VoidCallback onDecided;

  const _OrderDetailsSheet({required this.order, required this.onDecided});

  @override
  ConsumerState<_OrderDetailsSheet> createState() =>
      _OrderDetailsSheetState();
}

class _OrderDetailsSheetState extends ConsumerState<_OrderDetailsSheet> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  order.orderNo,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ),
              _StatusBadge(status: order.status),
            ],
          ),
          const SizedBox(height: 4),
          Text(order.posName ?? '',
              style: const TextStyle(fontSize: 12, color: AppColors.textGray)),
          if (order.posPointsBalance != null)
            Text(
              'رصيد النقطة: ${order.posPointsBalance!.toStringAsFixed(0)} نقطة',
              style: const TextStyle(fontSize: 12, color: AppColors.textGray),
            ),
          const SizedBox(height: 14),
          const Text('الأصناف',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark)),
          const SizedBox(height: 6),
          ...order.items.map((i) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        i.categoryName ?? 'صنف #${i.categoryId ?? '-'}',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textDark),
                      ),
                    ),
                    Text(
                      '${i.qty} × ${i.unitPrice.toStringAsFixed(0)}',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textGray),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      i.lineTotal.toStringAsFixed(0),
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textDark),
                    ),
                  ],
                ),
              )),
          const Divider(height: 24),
          _TotalRow('الإجمالي', '${order.totalAmount.toStringAsFixed(0)} ريال'),
          _TotalRow('بالنقاط', '${order.pointsTotal.toStringAsFixed(0)} نقطة'),
          if (order.distributorName != null)
            _TotalRow('الموزع', order.distributorName!),
          if (order.note != null && order.note!.isNotEmpty)
            _TotalRow('ملاحظة', order.note!),
          if (order.rejectReason != null && order.rejectReason!.isNotEmpty)
            _TotalRow('سبب الرفض', order.rejectReason!),
          if (order.isPending) ...[
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _approve,
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('اعتماد'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.success,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _reject,
                    icon: const Icon(Icons.cancel_outlined,
                        size: 18, color: AppColors.error),
                    label: const Text('رفض',
                        style: TextStyle(color: AppColors.error)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.error),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _approve() async {
    setState(() => _busy = true);
    try {
      final msg =
          await ref.read(posOrdersApiProvider).approve(widget.order.id);
      _toast(msg);
      widget.onDecided();
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''));
      setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => const _RejectDialog(),
    );
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final msg = await ref
          .read(posOrdersApiProvider)
          .reject(widget.order.id, reason: reason.isEmpty ? null : reason);
      _toast(msg);
      widget.onDecided();
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''));
      setState(() => _busy = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }
}

class _TotalRow extends StatelessWidget {
  final String label;
  final String value;
  const _TotalRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(label,
              style:
                  const TextStyle(fontSize: 12, color: AppColors.textGray)),
          const Spacer(),
          Text(value,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark)),
        ],
      ),
    );
  }
}

class _RejectDialog extends StatefulWidget {
  const _RejectDialog();

  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('رفض الطلب', style: TextStyle(fontSize: 15)),
      content: TextField(
        controller: _ctrl,
        decoration: const InputDecoration(
          hintText: 'سبب الرفض (اختياري)',
          border: OutlineInputBorder(),
        ),
        maxLines: 2,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_ctrl.text.trim()),
          style: FilledButton.styleFrom(backgroundColor: AppColors.error),
          child: const Text('رفض'),
        ),
      ],
    );
  }
}
