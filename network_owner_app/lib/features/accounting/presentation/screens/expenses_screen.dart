import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../mikrotik/presentation/widgets/ui_states.dart';
import '../../data/money_api.dart';
import '../../providers/money_providers.dart';

/// ACC-05 — daily expenses (PLAN §5: expenses_screen).
///
/// Posting an expense debits the expense account and credits the
/// chosen box atomically; a long-press voids the document through
/// a reversal entry — rows are never deleted.
class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  int? _categoryId;

  @override
  Widget build(BuildContext context) {
    final listAsync = ref.watch(accExpensesProvider(_categoryId));
    final catsAsync = ref.watch(accExpenseCategoriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('المصروفات'),
        actions: [
          IconButton(
            tooltip: 'فئة جديدة',
            onPressed: _openCategoryDialog,
            icon: const Icon(Icons.playlist_add),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openForm,
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label:
            const Text('مصروف', style: TextStyle(color: Colors.white)),
      ),
      body: Container(
        color: AppColors.inputBg,
        child: Column(
          children: [
            catsAsync.when(
              loading: () => const SizedBox(height: 52),
              error: (e, _) => const SizedBox.shrink(),
              data: (cats) => Container(
                color: AppColors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _chip(null, 'الكل'),
                      ...cats
                          .where((c) => c.isActive)
                          .map((c) => _chip(c.id, c.name)),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: listAsync.when(
                loading: () => const LoadingState(),
                error: (e, _) => ErrorRetry(
                  message: 'تعذّر تحميل المصروفات\n$e',
                  onRetry: () =>
                      ref.invalidate(accExpensesProvider(_categoryId)),
                ),
                data: (items) => items.isEmpty
                    ? const EmptyState('لا توجد مصروفات',
                        icon: Icons.money_off_outlined)
                    : RefreshIndicator(
                        onRefresh: () async => ref
                            .invalidate(accExpensesProvider(_categoryId)),
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: items.length,
                          itemBuilder: (_, i) => _ExpenseCard(
                            expense: items[i],
                            onVoid: () => _voidExpense(items[i]),
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(int? id, String label) {
    final selected = id == _categoryId;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _categoryId = id),
        selectedColor: AppColors.primary.withValues(alpha: 0.12),
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: selected ? AppColors.primary : AppColors.textGray,
        ),
      ),
    );
  }

  Future<void> _openForm() async {
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _ExpenseSheet(),
    );
    if (done == true) {
      ref.invalidate(accExpensesProvider(_categoryId));
      ref.invalidate(accCashBoxesProvider);
    }
  }

  Future<void> _openCategoryDialog() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title:
            const Text('فئة مصروف جديدة', style: TextStyle(fontSize: 15)),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
              hintText: 'اسم الفئة', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      final msg =
          await ref.read(moneyApiProvider).createExpenseCategory(name);
      _toast(msg);
      ref.invalidate(accExpenseCategoriesProvider);
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _voidExpense(AccExpense expense) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إلغاء المصروف', style: TextStyle(fontSize: 15)),
        content: Text(
            'سيتم إلغاء مصروف «${expense.categoryName ?? ''}» بقيد عكسي وإعادة المبلغ للصندوق.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('تراجع'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.error),
            child: const Text('إلغاء المصروف'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final msg =
          await ref.read(moneyApiProvider).voidExpense(expense.id);
      _toast(msg);
      ref.invalidate(accExpensesProvider(_categoryId));
      ref.invalidate(accCashBoxesProvider);
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }
}

class _ExpenseCard extends StatelessWidget {
  final AccExpense expense;
  final VoidCallback onVoid;
  const _ExpenseCard({required this.expense, required this.onVoid});

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
            const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        onLongPress: expense.isVoid ? null : onVoid,
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.north_east,
              color: AppColors.error, size: 22),
        ),
        title: Text(
          expense.categoryName ?? 'مصروف',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: AppColors.textDark,
            decoration:
                expense.isVoid ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Text(
          '${expense.boxName ?? 'الصندوق'}'
          '${expense.note != null ? ' · ${expense.note}' : ''}'
          '${expense.isVoid ? ' · ملغى' : ''}',
          style: const TextStyle(fontSize: 11, color: AppColors.textGray),
        ),
        trailing: Text(
          '-${expense.amount.toStringAsFixed(0)}',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: AppColors.error,
          ),
        ),
      ),
    );
  }
}

class _ExpenseSheet extends ConsumerStatefulWidget {
  const _ExpenseSheet();

  @override
  ConsumerState<_ExpenseSheet> createState() => _ExpenseSheetState();
}

class _ExpenseSheetState extends ConsumerState<_ExpenseSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  int? _categoryId;
  int? _boxId;
  String _currency = 'north';
  bool _busy = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catsAsync = ref.watch(accExpenseCategoriesProvider);
    final boxesAsync = ref.watch(accCashBoxesProvider);

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('تسجيل مصروف',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary)),
              const SizedBox(height: 16),
              catsAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('تعذر تحميل الفئات: $e'),
                data: (cats) => DropdownButtonFormField<int>(
                  initialValue: _categoryId,
                  decoration: const InputDecoration(
                      labelText: 'الفئة', border: OutlineInputBorder()),
                  items: cats
                      .where((c) => c.isActive)
                      .map((c) => DropdownMenuItem(
                          value: c.id, child: Text(c.name)))
                      .toList(),
                  onChanged: (v) => setState(() => _categoryId = v),
                  validator: (v) => v == null ? 'اختر الفئة' : null,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _amountCtrl,
                      decoration: const InputDecoration(
                          labelText: 'المبلغ',
                          border: OutlineInputBorder()),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        final a = double.tryParse(v ?? '');
                        return (a == null || a <= 0)
                            ? 'مبلغ غير صحيح'
                            : null;
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _currency,
                      decoration: const InputDecoration(
                          labelText: 'العملة',
                          border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(
                            value: 'north', child: Text('شمال')),
                        DropdownMenuItem(
                            value: 'south', child: Text('جنوب')),
                      ],
                      onChanged: (v) =>
                          setState(() => _currency = v ?? 'north'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              boxesAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => const SizedBox.shrink(),
                data: (boxes) => DropdownButtonFormField<int?>(
                  initialValue: _boxId,
                  decoration: const InputDecoration(
                      labelText: 'الصندوق (افتراضي: الرئيسي)',
                      border: OutlineInputBorder()),
                  items: [
                    const DropdownMenuItem<int?>(
                        value: null, child: Text('الصندوق الرئيسي')),
                    ...boxes.map((b) => DropdownMenuItem<int?>(
                        value: b.id,
                        child: Text(
                            '${b.name} (${b.balance.toStringAsFixed(0)})'))),
                  ],
                  onChanged: (v) => setState(() => _boxId = v),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _noteCtrl,
                decoration: const InputDecoration(
                    labelText: 'ملاحظة (اختياري)',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 18),
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
                      : const Text('تسجيل المصروف'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      final msg = await ref.read(moneyApiProvider).createExpense({
        'category_id': _categoryId,
        'amount': double.parse(_amountCtrl.text.trim()),
        'currency': _currency,
        'cash_box_id': _boxId,
        'note': _noteCtrl.text.trim().isEmpty
            ? null
            : _noteCtrl.text.trim(),
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
