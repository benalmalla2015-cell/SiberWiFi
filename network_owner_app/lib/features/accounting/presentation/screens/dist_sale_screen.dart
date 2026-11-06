import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../mikrotik/presentation/widgets/ui_states.dart';
import '../../data/dist_api.dart';
import '../../providers/dist_providers.dart';
import '../../providers/money_providers.dart';

/// ACC-06 — a cash/credit/partial sale to a POS point.
///
/// One atomic backend posting: stock out + cash box + POS receivable
/// + revenue + COGS + commission, all inside AccDistService and
/// journaled by AccPostingService. The idempotency key is generated
/// once per form open so a retried submit replays safely.
class DistSaleScreen extends ConsumerStatefulWidget {
  const DistSaleScreen({super.key});

  @override
  ConsumerState<DistSaleScreen> createState() => _DistSaleScreenState();
}

class _ItemRow {
  int? categoryId;
  final qtyCtrl = TextEditingController(text: '1');
  final priceCtrl = TextEditingController();

  double get qty => double.tryParse(qtyCtrl.text.trim()) ?? 0;
  double get price => double.tryParse(priceCtrl.text.trim()) ?? 0;
  double get total => qty * price;

  void dispose() {
    qtyCtrl.dispose();
    priceCtrl.dispose();
  }
}

class _DistSaleScreenState extends ConsumerState<DistSaleScreen> {
  final _formKey = GlobalKey<FormState>();
  final _paidCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  final List<_ItemRow> _items = [_ItemRow()];
  int? _posId;
  String _kind = 'cash';
  String _currency = 'north';
  bool _busy = false;

  /// Generated once — a retried submit replays against the same key.
  late final String _idem =
      'dist-sale-${DateTime.now().microsecondsSinceEpoch}';

  @override
  void dispose() {
    _paidCtrl.dispose();
    _noteCtrl.dispose();
    for (final i in _items) {
      i.dispose();
    }
    super.dispose();
  }

  double get _total => _items.fold(0.0, (s, i) => s + i.total);

  bool get _needsPaid => _kind == 'partial';

  @override
  Widget build(BuildContext context) {
    final homeAsync = ref.watch(distHomeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('بيع لنقطة بيع')),
      body: Container(
        color: AppColors.inputBg,
        child: homeAsync.when(
          loading: () => const LoadingState(),
          error: (e, _) => ErrorRetry(
            message: 'تعذّر تحميل البيانات\n$e',
            onRetry: () => ref.invalidate(distHomeProvider),
          ),
          data: (home) => Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('نقطة البيع'),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<int>(
                        initialValue: _posId,
                        decoration: const InputDecoration(
                          hintText: 'اختر النقطة',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: home.posPoints
                            .map((p) => DropdownMenuItem(
                                value: p.id, child: Text(p.name)))
                            .toList(),
                        onChanged: (v) => setState(() => _posId = v),
                        validator: (v) => v == null ? 'اختر النقطة' : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: _label('الأصناف')),
                          TextButton.icon(
                            onPressed: () =>
                                setState(() => _items.add(_ItemRow())),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('إضافة'),
                          ),
                        ],
                      ),
                      ..._items.asMap().entries.map(
                            (e) => _itemEditor(e.key, home.categories),
                          ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('طريقة الدفع'),
                      const SizedBox(height: 8),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                              value: 'cash',
                              label: Text('نقدي'),
                              icon: Icon(Icons.payments_outlined)),
                          ButtonSegment(
                              value: 'credit',
                              label: Text('آجل'),
                              icon: Icon(Icons.schedule_outlined)),
                          ButtonSegment(
                              value: 'partial',
                              label: Text('جزئي'),
                              icon: Icon(Icons.pie_chart_outline)),
                        ],
                        selected: {_kind},
                        onSelectionChanged: (s) =>
                            setState(() => _kind = s.first),
                      ),
                      if (_needsPaid) ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _paidCtrl,
                          decoration: const InputDecoration(
                            labelText: 'المبلغ المدفوع الآن',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          keyboardType: TextInputType.number,
                          validator: (v) {
                            final a = double.tryParse(v ?? '');
                            if (a == null || a < 0) {
                              return 'مبلغ غير صحيح';
                            }
                            if (a >= _total) {
                              return 'المدفوع يغطي كامل البيع — اختر نقدي';
                            }
                            return null;
                          },
                        ),
                      ],
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _currency,
                        decoration: const InputDecoration(
                          labelText: 'العملة',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(
                              value: 'north', child: Text('شمال')),
                          DropdownMenuItem(
                              value: 'south', child: Text('جنوب')),
                        ],
                        onChanged: (v) =>
                            setState(() => _currency = v ?? 'north'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _noteCtrl,
                        decoration: const InputDecoration(
                          labelText: 'ملاحظة (اختياري)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _TotalBar(
                  total: _total,
                  paid: _kind == 'cash'
                      ? _total
                      : _kind == 'credit'
                          ? 0
                          : (double.tryParse(_paidCtrl.text.trim()) ?? 0),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _busy ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('تسجيل البيع',
                            style: TextStyle(fontSize: 15)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _itemEditor(int index, List<DistCategory> cats) {
    final row = _items[index];
    final selected = row.categoryId == null
        ? null
        : cats.where((c) => c.id == row.categoryId).firstOrNull;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<int>(
              initialValue: row.categoryId,
              isExpanded: true,
              decoration: const InputDecoration(
                hintText: 'الفئة',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: cats
                  .map((c) => DropdownMenuItem(
                        value: c.id,
                        child: Text(
                          '${c.name} (${c.stockQty.toStringAsFixed(0)})',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ))
                  .toList(),
              onChanged: (v) => setState(() {
                row.categoryId = v;
                final c = cats.where((x) => x.id == v).firstOrNull;
                if (c != null && row.priceCtrl.text.isEmpty) {
                  row.priceCtrl.text = c.sellPrice.toStringAsFixed(0);
                }
              }),
              validator: (v) => v == null ? 'اختر' : null,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: TextFormField(
              controller: row.qtyCtrl,
              decoration: const InputDecoration(
                labelText: 'الكمية',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              validator: (v) {
                final q = double.tryParse(v ?? '');
                if (q == null || q <= 0 || q != q.roundToDouble()) {
                  return 'غير صحيح';
                }
                if (selected != null && q > selected.stockQty) {
                  return 'يتجاوز المخزون';
                }
                if (selected?.remainingToday != null &&
                    q > selected!.remainingToday!) {
                  return 'يتجاوز المتبقي';
                }
                return null;
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: TextFormField(
              controller: row.priceCtrl,
              decoration: const InputDecoration(
                labelText: 'السعر',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              validator: (v) {
                final p = double.tryParse(v ?? '');
                return (p == null || p < 0) ? 'غير صحيح' : null;
              },
            ),
          ),
          IconButton(
            onPressed: _items.length > 1
                ? () => setState(() {
                      row.dispose();
                      _items.removeAt(index);
                    })
                : null,
            icon: Icon(Icons.remove_circle_outline,
                size: 20,
                color: _items.length > 1
                    ? AppColors.error
                    : AppColors.textLight),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      final paid = _kind == 'cash'
          ? _total
          : _kind == 'credit'
              ? 0.0
              : double.parse(_paidCtrl.text.trim());
      final msg = await ref.read(distApiProvider).sale({
        'pos_id': _posId,
        'items': _items
            .map((i) => {
                  'category_id': i.categoryId,
                  'qty': i.qty.round(),
                  'unit_price': i.price,
                })
            .toList(),
        'payment_kind': _kind,
        'paid_amount': paid,
        'currency': _currency,
        'note': _noteCtrl.text.trim().isEmpty
            ? null
            : _noteCtrl.text.trim(),
        'idempotency_key': _idem,
      });
      _toast(msg);
      ref.invalidate(distHomeProvider);
      ref.invalidate(distSalesProvider(null));
      ref.invalidate(accCashBoxesProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''));
      setState(() => _busy = false);
    }
  }

  Widget _card({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: child,
      );

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: AppColors.textDark,
        ),
      );

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }
}

class _TotalBar extends StatelessWidget {
  final double total;
  final double paid;
  const _TotalBar({required this.total, required this.paid});

  @override
  Widget build(BuildContext context) {
    final remaining = total - paid;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                const Text('الإجمالي',
                    style:
                        TextStyle(fontSize: 11, color: AppColors.textGray)),
                Text(total.toStringAsFixed(0),
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary)),
              ],
            ),
          ),
          Container(width: 1, height: 32, color: AppColors.divider),
          Expanded(
            child: Column(
              children: [
                const Text('يُدفع الآن',
                    style:
                        TextStyle(fontSize: 11, color: AppColors.textGray)),
                Text(paid.toStringAsFixed(0),
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.success)),
              ],
            ),
          ),
          Container(width: 1, height: 32, color: AppColors.divider),
          Expanded(
            child: Column(
              children: [
                const Text('يُسجَّل آجلاً',
                    style:
                        TextStyle(fontSize: 11, color: AppColors.textGray)),
                Text(remaining.toStringAsFixed(0),
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.warning)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
