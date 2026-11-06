import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../mikrotik/presentation/widgets/ui_states.dart';
import '../../data/pos_app_api.dart';
import '../../providers/pos_app_providers.dart';

/// ACC-07 — redeem points for card packages
/// (PLAN §5: POST /pos/exchange-cards + history).
class PosExchangeScreen extends ConsumerWidget {
  const PosExchangeScreen({super.key, this.initialCategoryId});

  /// When launched from a package card, preselect that category.
  final int? initialCategoryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final homeAsync = ref.watch(posHomeProvider);
    final listAsync = ref.watch(posExchangesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('استبدال النقاط')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context, ref),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.swap_horiz_rounded,
            color: Colors.white),
        label: const Text('استبدال جديد',
            style: TextStyle(color: Colors.white)),
      ),
      body: Container(
        color: AppColors.inputBg,
        child: listAsync.when(
          loading: () => const LoadingState(),
          error: (e, _) => ErrorRetry(
            message: 'تعذّر تحميل الاستبدالات\n$e',
            onRetry: () => _refresh(ref),
          ),
          data: (rows) => RefreshIndicator(
            onRefresh: () async => _refresh(ref),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (homeAsync.valueOrNull case final home?)
                  _PointsCard(
                    balance: home.pos.pointsBalance,
                    spent: rows.fold<double>(
                        0, (s, r) => s + r.pointsSpent),
                  ),
                const SizedBox(height: 14),
                if (rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 60),
                    child: EmptyState(
                      'لا توجد استبدالات بعد — حوّل نقاطك إلى حزم',
                      icon: Icons.swap_horiz_rounded,
                    ),
                  )
                else
                  ...rows.map((x) => _ExchangeCard(exchange: x)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _refresh(WidgetRef ref) {
    ref.invalidate(posExchangesProvider);
    ref.invalidate(posHomeProvider);
    ref.invalidate(posLedgerProvider);
  }

  Future<void> _openForm(BuildContext context, WidgetRef ref) async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _ExchangeFormSheet(
          initialCategoryId: initialCategoryId),
    );
    if (sent == true) _refresh(ref);
  }
}

class _PointsCard extends StatelessWidget {
  final double balance;
  final double spent;
  const _PointsCard({required this.balance, required this.spent});

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
                const Text('رصيد النقاط',
                    style: TextStyle(
                        fontSize: 11, color: Colors.white70)),
                const SizedBox(height: 4),
                Text(balance.toStringAsFixed(0),
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
              const Text('إجمالي المستبدَل',
                  style: TextStyle(
                      fontSize: 11, color: Colors.white70)),
              const SizedBox(height: 4),
              Text(spent.toStringAsFixed(0),
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

class _ExchangeCard extends StatelessWidget {
  final PosExchange exchange;
  const _ExchangeCard({required this.exchange});

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
              color: AppColors.lightBlue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.swap_horiz_rounded,
                color: AppColors.lightBlue, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(exchange.categoryName,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark)),
                Text(
                  '×${exchange.qty}'
                  '${exchange.createdAt != null ? ' · ${_ago(exchange.createdAt!)}' : ''}',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textGray),
                ),
              ],
            ),
          ),
          Text(
            '-${exchange.pointsSpent.toStringAsFixed(0)}',
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.error),
          ),
        ],
      ),
    );
  }
}

class _ExchangeFormSheet extends ConsumerStatefulWidget {
  const _ExchangeFormSheet({this.initialCategoryId});

  final int? initialCategoryId;

  @override
  ConsumerState<_ExchangeFormSheet> createState() =>
      _ExchangeFormSheetState();
}

class _ExchangeFormSheetState
    extends ConsumerState<_ExchangeFormSheet> {
  int? _categoryId;
  final _qtyCtrl = TextEditingController(text: '1');
  final _noteCtrl = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _categoryId = widget.initialCategoryId;
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final homeAsync = ref.watch(posHomeProvider);

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
          const Text('استبدال نقاط بحزمة',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary)),
          const SizedBox(height: 14),
          homeAsync.when(
            loading: () =>
                const LinearProgressIndicator(minHeight: 2),
            error: (e, _) => Text('تعذّر تحميل الحزم: $e',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.error)),
            data: (home) {
              final available = home.packages
                  .where((p) => p.available)
                  .toList();
              if (available.isEmpty) {
                return const Text(
                  'لا توجد حزم متاحة للاستبدال حالياً',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textGray),
                );
              }
              final selected = available
                  .where((p) => p.id == _categoryId)
                  .firstOrNull;
              final qty = int.tryParse(_qtyCtrl.text) ?? 0;
              final cost =
                  (selected?.pointsCost ?? 0) * qty;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: selected?.id,
                    decoration: const InputDecoration(
                      labelText: 'الحزمة',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: available
                        .map((p) => DropdownMenuItem(
                              value: p.id,
                              child: Text(
                                '${p.name} — ${p.pointsCost.toStringAsFixed(0)} نقطة'
                                ' (متاح ${p.stockQty.toStringAsFixed(0)})',
                                style:
                                    const TextStyle(fontSize: 12),
                              ),
                            ))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _categoryId = v),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _qtyCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'الكمية',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  if (selected != null && qty > 0) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.inputBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Text('التكلفة',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textGray)),
                          const Spacer(),
                          Text(
                            '${cost.toStringAsFixed(0)} نقطة',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: cost >
                                        home.pos.pointsBalance
                                    ? AppColors.error
                                    : AppColors.primary),
                          ),
                        ],
                      ),
                    ),
                    if (cost > home.pos.pointsBalance)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          'رصيد النقاط غير كافٍ لهذا الاستبدال',
                          style: TextStyle(
                              fontSize: 11,
                              color: AppColors.error),
                        ),
                      ),
                    if (qty > selected.stockQty)
                      Padding(
                        padding:
                            const EdgeInsets.only(top: 4),
                        child: Text(
                          'المخزون المتاح ${selected.stockQty.toStringAsFixed(0)} فقط',
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.error),
                        ),
                      ),
                  ],
                ],
              );
            },
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
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy ? null : _submit,
              icon: const Icon(Icons.swap_horiz_rounded,
                  size: 18),
              label: Text(_busy
                  ? 'جارٍ التنفيذ…'
                  : 'تأكيد الاستبدال'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding:
                    const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final qty = int.tryParse(_qtyCtrl.text) ?? 0;
    if (_categoryId == null) {
      _toast('اختر الحزمة أولاً');
      return;
    }
    if (qty < 1) {
      _toast('أدخل كمية صحيحة');
      return;
    }
    setState(() => _busy = true);
    try {
      final msg =
          await ref.read(posAppApiProvider).exchangeCards({
        'category_id': _categoryId,
        'qty': qty,
        if (_noteCtrl.text.trim().isNotEmpty)
          'note': _noteCtrl.text.trim(),
        'idempotency_key':
            'ex-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(9999)}',
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

String _ago(String iso) {
  final t = DateTime.tryParse(iso);
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 60) return 'منذ ${d.inMinutes} د';
  if (d.inHours < 24) return 'منذ ${d.inHours} س';
  return 'منذ ${d.inDays} يوم';
}
