import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../mikrotik/presentation/widgets/ui_states.dart';
import '../../data/acc_api.dart';
import '../../providers/acc_providers.dart';

/// «المخزون» — per-category balances, the immutable movements log,
/// manual recount adjustments, and the one-tap router-card sync
/// (cards with source=mikrotik enter stock automatically — PLAN
/// §2.1 / ACC-02 acceptance).
class InventoryScreen extends ConsumerWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stockAsync = ref.watch(accStockProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('المخزون'),
        actions: [
          IconButton(
            tooltip: 'ترحيل كروت الراوتر',
            icon: const Icon(Icons.sync),
            onPressed: () => _sync(context, ref),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAdjust(context, ref),
        icon: const Icon(Icons.tune),
        label: const Text('تسوية جرد'),
        backgroundColor: AppColors.primary,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(accStockProvider);
          ref.invalidate(accMovementsProvider);
        },
        child: stockAsync.when(
          loading: () => const LoadingState(),
          error: (e, _) => ErrorRetry(
            message: 'تعذّر تحميل المخزون\n$e',
            onRetry: () => ref.invalidate(accStockProvider),
          ),
          data: (stock) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _TotalsCard(qty: stock.totalQty, value: stock.totalValue),
              const SizedBox(height: 14),
              if (stock.rows.isEmpty)
                const EmptyState(
                  'المخزون فارغ — سجّل شراءً أو اضبط الجرد\nوسُتدرج كروت الراوتر تلقائياً عند توليدها',
                  icon: Icons.inventory_2_outlined,
                )
              else
                ...stock.rows.map((r) => _StockCard(
                      row: r,
                      onMovements: () => _showMovements(context, r),
                    )),
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _sync(BuildContext ctx, WidgetRef ref) async {
    try {
      final msg = await ref.read(accApiProvider).syncRouterCards();
      ref.invalidate(accStockProvider);
      ref.invalidate(accCategoriesProvider);
      ref.invalidate(accMovementsProvider);
      if (ctx.mounted) _toast(ctx, msg, ok: true);
    } catch (e) {
      if (ctx.mounted) _toast(ctx, '$e');
    }
  }

  void _showMovements(BuildContext ctx, AccStockRow row) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _MovementsSheet(row: row),
    );
  }

  void _showAdjust(BuildContext ctx, WidgetRef ref) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _AdjustSheet(),
    );
  }

  static void _toast(BuildContext ctx, String msg, {bool ok = false}) {
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: ok ? AppColors.success : AppColors.error,
    ));
  }
}

class _TotalsCard extends StatelessWidget {
  final double qty, value;
  const _TotalsCard({required this.qty, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.lightBlue],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          const Icon(Icons.warehouse_outlined, color: Colors.white, size: 34),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('إجمالي المخزون',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
                Text('${qty.toStringAsFixed(0)} وحدة',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('قيمة المخزون',
                  style: TextStyle(color: Colors.white70, fontSize: 11)),
              Text(value.toStringAsFixed(0),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }
}

class _StockCard extends StatelessWidget {
  final AccStockRow row;
  final VoidCallback onMovements;
  const _StockCard({required this.row, required this.onMovements});

  @override
  Widget build(BuildContext context) {
    final low = row.qty <= 5;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 3)),
        ],
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: (low ? AppColors.warning : AppColors.primary)
                .withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(Icons.style_outlined,
              color: low ? AppColors.warning : AppColors.primary, size: 24),
        ),
        title: Text(row.categoryName,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text(
          'متوسط تكلفة ${row.avgCost.toStringAsFixed(1)} · قيمة ${row.stockValue.toStringAsFixed(0)}',
          style: const TextStyle(fontSize: 11, color: AppColors.textGray),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(row.qty.toStringAsFixed(0),
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: low ? AppColors.warning : AppColors.primary)),
            Text(row.unitLabel,
                style:
                    const TextStyle(fontSize: 10, color: AppColors.textGray)),
          ],
        ),
        onTap: onMovements,
      ),
    );
  }
}

/// The immutable movements log for one category.
class _MovementsSheet extends ConsumerWidget {
  final AccStockRow row;
  const _MovementsSheet({required this.row});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final movesAsync = ref.watch(accMovementsProvider(row.categoryId));

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      builder: (_, controller) => Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('حركات «${row.categoryName}»',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: movesAsync.when(
              loading: () => const LoadingState(),
              error: (e, _) => ErrorRetry(
                message: '$e',
                onRetry: () =>
                    ref.invalidate(accMovementsProvider(row.categoryId)),
              ),
              data: (moves) {
                if (moves.isEmpty) {
                  return const EmptyState('لا حركات بعد',
                      icon: Icons.receipt_long_outlined);
                }
                return ListView.separated(
                  controller: controller,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  itemCount: moves.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, color: AppColors.divider),
                  itemBuilder: (_, i) => _MovementTile(move: moves[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MovementTile extends StatelessWidget {
  final AccStockMovement move;
  const _MovementTile({required this.move});

  @override
  Widget build(BuildContext context) {
    final color = move.isIn ? AppColors.success : AppColors.error;

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          move.isIn ? Icons.south_west : Icons.north_east,
          color: color,
          size: 18,
        ),
      ),
      title: Text(move.typeLabel,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
      subtitle: Text(
        [
          if (move.note != null && move.note!.isNotEmpty) move.note!,
          if (move.createdAt != null)
            move.createdAt!.substring(0, 16).replaceAll('T', ' '),
        ].join(' · '),
        style: const TextStyle(fontSize: 11, color: AppColors.textGray),
      ),
      trailing: Text(
        '${move.isIn ? '+' : ''}${move.qty.toStringAsFixed(0)}',
        style: TextStyle(
            fontSize: 15, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }
}

/// Manual recount — sets the absolute balance via a signed `adjust`
/// movement (the backend rejects negative targets).
class _AdjustSheet extends ConsumerStatefulWidget {
  const _AdjustSheet();

  @override
  ConsumerState<_AdjustSheet> createState() => _AdjustSheetState();
}

class _AdjustSheetState extends ConsumerState<_AdjustSheet> {
  final _qtyCtr = TextEditingController();
  final _noteCtr = TextEditingController();
  int? _categoryId;
  bool _loading = false;

  @override
  void dispose() {
    _qtyCtr.dispose();
    _noteCtr.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final qty = num.tryParse(_qtyCtr.text.trim());
    if (_categoryId == null) {
      InventoryScreen._toast(context, 'اختر الفئة');
      return;
    }
    if (qty == null || qty < 0) {
      InventoryScreen._toast(context, 'أدخل رصيداً صحيحاً (صفر أو أكثر)');
      return;
    }
    setState(() => _loading = true);
    try {
      final msg = await ref
          .read(accApiProvider)
          .adjustStock(_categoryId!, qty.toDouble(), _noteCtr.text.trim());
      if (mounted) {
        Navigator.pop(context);
        ref.invalidate(accStockProvider);
        ref.invalidate(accMovementsProvider);
        InventoryScreen._toast(context, msg, ok: true);
      }
    } catch (e) {
      if (mounted) InventoryScreen._toast(context, '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final catsAsync = ref.watch(accCategoriesProvider);

    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 20,
          right: 20,
          top: 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('تسوية جرد',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            const Text(
              'أدخل الرصيد الفعلي — سيُسجَّل فرق التسوية في سجل الحركات',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.textGray),
            ),
            const SizedBox(height: 20),
            catsAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('$e',
                  style: const TextStyle(color: AppColors.error)),
              data: (cats) => DropdownButtonFormField<int>(
                initialValue: _categoryId,
                decoration: const InputDecoration(
                  labelText: 'الفئة *',
                  prefixIcon: Icon(Icons.style_outlined),
                ),
                items: cats
                    .map((c) => DropdownMenuItem(
                        value: c.id,
                        child: Text(
                            '${c.name} (الحالي ${c.stockQty.toStringAsFixed(0)})')))
                    .toList(),
                onChanged: (v) => setState(() => _categoryId = v),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _qtyCtr,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'الرصيد الفعلي الجديد *',
                prefixIcon: Icon(Icons.pin_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteCtr,
              decoration: const InputDecoration(
                labelText: 'ملاحظة (اختياري)',
                prefixIcon: Icon(Icons.notes),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('تنفيذ التسوية'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
