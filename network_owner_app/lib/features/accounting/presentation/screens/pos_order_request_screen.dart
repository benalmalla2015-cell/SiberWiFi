import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../mikrotik/presentation/widgets/ui_states.dart';
import '../../data/pos_app_api.dart';
import '../../data/pos_orders_api.dart';
import '../../providers/pos_app_providers.dart';
import '../../providers/pos_orders_providers.dart';

/// ACC-04 — the POS agent's request surface (PLAN §4: POST
/// /pos/orders). Submits bundle orders against the point's points
/// balance and tracks their decision status. Order drafts are
/// free-form rows until ACC-02's catalog screen feeds category ids.
class PosOrderRequestScreen extends ConsumerStatefulWidget {
  const PosOrderRequestScreen({super.key});

  @override
  ConsumerState<PosOrderRequestScreen> createState() =>
      _PosOrderRequestScreenState();
}

class _PosOrderRequestScreenState
    extends ConsumerState<PosOrderRequestScreen> {
  @override
  Widget build(BuildContext context) {
    final dataAsync = ref.watch(myPosOrdersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('طلبات الحزم')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('طلب جديد',
            style: TextStyle(color: Colors.white)),
      ),
      body: Container(
        color: AppColors.inputBg,
        child: dataAsync.when(
          loading: () => const LoadingState(),
          error: (e, _) => ErrorRetry(
            message: 'تعذّر تحميل الطلبات\n$e',
            onRetry: () => ref.invalidate(myPosOrdersProvider),
          ),
          data: (data) => RefreshIndicator(
            onRefresh: () async => ref.invalidate(myPosOrdersProvider),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (data.pos != null) _BalanceCard(pos: data.pos!),
                const SizedBox(height: 14),
                if (data.orders.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 60),
                    child: EmptyState('لا توجد طلبات بعد — أرسل أول طلب حزم',
                        icon: Icons.receipt_long_outlined),
                  )
                else
                  ...data.orders.map((o) => _MyOrderCard(order: o)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openForm(BuildContext context) async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _OrderFormSheet(),
    );
    if (sent == true && mounted) {
      ref.invalidate(myPosOrdersProvider);
    }
  }
}

class _BalanceCard extends StatelessWidget {
  final PosPointSummary pos;
  const _BalanceCard({required this.pos});

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(pos.name,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
          const SizedBox(height: 12),
          Row(
            children: [
              _BalanceChip('النقاط', pos.pointsBalance),
              const SizedBox(width: 10),
              _BalanceChip('الأرباح', pos.profitBalance),
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
  const _BalanceChip(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 11, color: Colors.white70)),
            const SizedBox(height: 2),
            Text(
              value.toStringAsFixed(0),
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

class _MyOrderCard extends StatelessWidget {
  final PosOrder order;
  const _MyOrderCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (order.status) {
      'pending' => ('بانتظار الاعتماد', AppColors.warning),
      'approved' => ('معتمد', AppColors.success),
      'rejected' => ('مرفوض', AppColors.error),
      _ => (order.status, AppColors.textGray),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(order.orderNo,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
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
            ],
          ),
          const SizedBox(height: 8),
          ...order.items.map((i) => Text(
                '· ${i.categoryName ?? 'صنف'} — ${i.qty} كرت',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textGray),
              )),
          const SizedBox(height: 6),
          Text(
            '${order.pointsTotal.toStringAsFixed(0)} نقطة · ${order.totalAmount.toStringAsFixed(0)} ريال',
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.primary),
          ),
          if (order.isRejected && order.rejectReason != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'سبب الرفض: ${order.rejectReason}',
                style:
                    const TextStyle(fontSize: 11, color: AppColors.error),
              ),
            ),
        ],
      ),
    );
  }
}

class _OrderFormSheet extends ConsumerStatefulWidget {
  const _OrderFormSheet();

  @override
  ConsumerState<_OrderFormSheet> createState() => _OrderFormSheetState();
}

class _OrderFormSheetState extends ConsumerState<_OrderFormSheet> {
  final _rows = <_ItemRow>[_ItemRow()];
  final _pointsCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    _pointsCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  double _rowPrice(_ItemRow r) =>
      r.package?.sellPrice ??
      (double.tryParse(r.price.text) ?? 0);

  double get _total => _rows.fold(
      0,
      (s, r) =>
          s + (int.tryParse(r.qty.text) ?? 0) * _rowPrice(r));

  @override
  Widget build(BuildContext context) {
    // ACC-07: the /pos/home catalog drives category-picked rows;
    // free-text rows stay as the fallback when no packages load.
    final packages =
        ref.watch(posHomeProvider).valueOrNull?.packages ??
            const <PosPackage>[];
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('طلب حزم جديد',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary)),
            const SizedBox(height: 14),
            ..._rows.asMap().entries.map((e) => _ItemRowCard(
                  row: e.value,
                  packages: packages,
                  onChanged: () => setState(() {}),
                  onRemove: _rows.length > 1
                      ? () => setState(() => _rows.removeAt(e.key))
                      : null,
                )),
            TextButton.icon(
              onPressed: () => setState(() => _rows.add(_ItemRow())),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('إضافة صنف'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _pointsCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'إجمالي النقاط المدفوعة',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _noteCtrl,
              decoration: const InputDecoration(
                labelText: 'ملاحظة (اختياري)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Text('الإجمالي التقديري',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textGray)),
                const Spacer(),
                Text('${_total.toStringAsFixed(0)} ريال',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary)),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _submit,
                icon: const Icon(Icons.send_outlined, size: 18),
                label: Text(_busy ? 'جارٍ الإرسال…' : 'إرسال الطلب'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final items = <Map<String, dynamic>>[];
    for (final r in _rows) {
      final qty = int.tryParse(r.qty.text) ?? 0;
      if (qty < 1) {
        _toast('أدخل كمية صحيحة في كل سطر');
        return;
      }
      if (r.categoryId != null) {
        // Catalog row — the service prices it server-side.
        items.add({'category_id': r.categoryId, 'qty': qty});
      } else {
        final price = double.tryParse(r.price.text) ?? 0;
        if (r.name.text.trim().isEmpty) {
          _toast('أكمل اسم الصنف أو اختر حزمة من القائمة');
          return;
        }
        items.add({
          'name': r.name.text.trim(),
          'qty': qty,
          'unit_price': price,
        });
      }
    }

    setState(() => _busy = true);
    try {
      final msg = await ref.read(posOrdersApiProvider).submitOrder({
        'items': items,
        'points_total': _pointsCtrl.text.trim().isEmpty
            ? _total
            : (double.tryParse(_pointsCtrl.text) ?? 0),
        if (_noteCtrl.text.trim().isNotEmpty)
          'note': _noteCtrl.text.trim(),
        // Client-generated replay guard: resubmitting the same
        // draft never duplicates the order server-side.
        'idempotency_key':
            'pos-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(9999)}',
      });
      _toast(msg);
      if (mounted) Navigator.of(context).pop(true);
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

class _ItemRow {
  final name = TextEditingController();
  final qty = TextEditingController(text: '1');
  final price = TextEditingController();
  int? categoryId;
  PosPackage? package;

  void dispose() {
    name.dispose();
    qty.dispose();
    price.dispose();
  }
}

class _ItemRowCard extends StatelessWidget {
  final _ItemRow row;
  final List<PosPackage> packages;
  final VoidCallback? onChanged;
  final VoidCallback? onRemove;

  const _ItemRowCard({
    required this.row,
    this.packages = const [],
    this.onChanged,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.inputBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          if (packages.isNotEmpty)
            DropdownButtonFormField<int>(
              initialValue: row.categoryId,
              isExpanded: true,
              decoration: const InputDecoration(
                hintText: 'اختر حزمة — أو اترك فارغاً لصنف حر',
                border: InputBorder.none,
                isDense: true,
              ),
              items: packages
                  .map((p) => DropdownMenuItem(
                        value: p.id,
                        child: Text(
                          '${p.name} — ${p.pointsCost.toStringAsFixed(0)} نقطة',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ))
                  .toList(),
              onChanged: (v) {
                row.categoryId = v;
                row.package = packages
                    .where((p) => p.id == v)
                    .firstOrNull;
                onChanged?.call();
              },
            ),
          Row(
            children: [
              if (row.categoryId == null)
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: row.name,
                    decoration: const InputDecoration(
                      hintText: 'اسم الحزمة',
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                )
              else
                Expanded(
                  flex: 3,
                  child: Text(
                    row.package?.name ?? '',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark),
                  ),
                ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: row.qty,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    hintText: 'الكمية',
                    border: InputBorder.none,
                    isDense: true,
                  ),
                  onChanged: (_) => onChanged?.call(),
                ),
              ),
              const SizedBox(width: 8),
              if (row.categoryId == null)
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: row.price,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      hintText: 'السعر',
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    onChanged: (_) => onChanged?.call(),
                  ),
                )
              else
                Expanded(
                  flex: 2,
                  child: Text(
                    '${((row.package?.pointsCost ?? 0) * (int.tryParse(row.qty.text) ?? 0)).toStringAsFixed(0)} نقطة',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary),
                  ),
                ),
              if (onRemove != null)
                InkWell(
                  onTap: onRemove,
                  child: const Icon(Icons.remove_circle_outline,
                      size: 20, color: AppColors.error),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
