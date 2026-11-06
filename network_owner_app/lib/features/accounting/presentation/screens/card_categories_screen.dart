import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../mikrotik/presentation/widgets/ui_states.dart';
import '../../data/acc_api.dart';
import '../../providers/acc_providers.dart';

/// «فئات الكروت» — the accounting catalog (PLAN §2.1): sell/cost
/// prices, unit labels and the source binding the MikroTik sync
/// uses to bucket router-generated cards.
class CardCategoriesScreen extends ConsumerWidget {
  const CardCategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catsAsync = ref.watch(accCategoriesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('فئات الكروت')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showForm(context, null),
        icon: const Icon(Icons.add_card),
        label: const Text('إضافة فئة'),
        backgroundColor: AppColors.primary,
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(accCategoriesProvider),
        child: catsAsync.when(
          loading: () => const LoadingState(),
          error: (e, _) => ErrorRetry(
            message: 'تعذّر تحميل الفئات\n$e',
            onRetry: () => ref.invalidate(accCategoriesProvider),
          ),
          data: (cats) {
            if (cats.isEmpty) {
              return const EmptyState(
                'لا توجد فئات — أضف فئة لبدء إدارة المخزون',
                icon: Icons.category_outlined,
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: cats.length,
              itemBuilder: (_, i) => _CategoryCard(
                category: cats[i],
                onEdit: () => _showForm(context, cats[i]),
                onToggle: () => _toggle(context, ref, cats[i]),
                onDelete: () => _confirmDelete(context, ref, cats[i]),
              ),
            );
          },
        ),
      ),
    );
  }

  void _showForm(BuildContext ctx, AccCardCategory? category) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _CategoryFormSheet(category: category),
    );
  }

  Future<void> _toggle(
      BuildContext ctx, WidgetRef ref, AccCardCategory c) async {
    try {
      final msg = await ref.read(accApiProvider).updateCategory(c.id, {
        'is_active': !c.isActive,
      });
      ref.invalidate(accCategoriesProvider);
      if (ctx.mounted) _toast(ctx, msg, ok: true);
    } catch (e) {
      if (ctx.mounted) _toast(ctx, '$e');
    }
  }

  Future<void> _confirmDelete(
      BuildContext ctx, WidgetRef ref, AccCardCategory c) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('حذف الفئة'),
        content: Text('حذف «${c.name}» نهائياً؟ الفئات ذات الحركات لا تُحذف.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('حذف', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final msg = await ref.read(accApiProvider).deleteCategory(c.id);
      ref.invalidate(accCategoriesProvider);
      if (ctx.mounted) _toast(ctx, msg, ok: true);
    } catch (e) {
      if (ctx.mounted) _toast(ctx, '$e');
    }
  }

  static void _toast(BuildContext ctx, String msg, {bool ok = false}) {
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: ok ? AppColors.success : AppColors.error,
    ));
  }
}

class _CategoryCard extends StatelessWidget {
  final AccCardCategory category;
  final VoidCallback onEdit, onToggle, onDelete;
  const _CategoryCard({
    required this.category,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final color = category.isActive ? AppColors.primary : AppColors.textGray;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.style_outlined, color: color, size: 26),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(category.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      Text(
                        'بيع ${category.sellPrice.toStringAsFixed(0)} · تكلفة ${category.costPrice.toStringAsFixed(0)}',
                        style: const TextStyle(
                            color: AppColors.textGray, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                _chip(
                  category.isActive ? 'نشطة' : 'معطلة',
                  category.isActive ? AppColors.success : AppColors.error,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _infoChip(Icons.inventory_2_outlined,
                    'المخزون: ${category.stockQty.toStringAsFixed(0)} ${category.unitLabel}'),
                _infoChip(Icons.link,
                    'المصدر: ${category.bindingLabel}'),
                if (category.cardCategoryId != null)
                  _infoChip(Icons.router_outlined, 'مرتبطة بفئة منصة'),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 15),
                    label: const Text('تعديل',
                        style: TextStyle(fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 8)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onToggle,
                    icon: Icon(
                        category.isActive
                            ? Icons.pause_circle_outline
                            : Icons.play_circle_outline,
                        size: 15,
                        color: AppColors.warning),
                    label: Text(
                        category.isActive ? 'تعطيل' : 'تفعيل',
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.warning)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      side: const BorderSide(color: AppColors.warning),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline,
                        size: 15, color: AppColors.error),
                    label: const Text('حذف',
                        style:
                            TextStyle(fontSize: 13, color: AppColors.error)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      side: const BorderSide(color: AppColors.error),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  Widget _infoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.inputBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.textGray),
          const SizedBox(width: 4),
          Text(label,
              style:
                  const TextStyle(fontSize: 11, color: AppColors.textGray)),
        ],
      ),
    );
  }
}

class _CategoryFormSheet extends ConsumerStatefulWidget {
  final AccCardCategory? category;
  const _CategoryFormSheet({this.category});

  @override
  ConsumerState<_CategoryFormSheet> createState() =>
      _CategoryFormSheetState();
}

class _CategoryFormSheetState extends ConsumerState<_CategoryFormSheet> {
  final _nameCtr = TextEditingController();
  final _sellCtr = TextEditingController();
  final _costCtr = TextEditingController();
  final _unitCtr = TextEditingController();
  String _binding = 'any';
  bool _active = true;
  bool _loading = false;

  bool get _isEdit => widget.category != null;

  @override
  void initState() {
    super.initState();
    final c = widget.category;
    if (c != null) {
      _nameCtr.text = c.name;
      _sellCtr.text = c.sellPrice.toStringAsFixed(0);
      _costCtr.text = c.costPrice.toStringAsFixed(0);
      _unitCtr.text = c.unitLabel;
      _binding = c.sourceBinding;
      _active = c.isActive;
    } else {
      _unitCtr.text = 'كرت';
    }
  }

  @override
  void dispose() {
    _nameCtr.dispose();
    _sellCtr.dispose();
    _costCtr.dispose();
    _unitCtr.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_nameCtr.text.trim().isEmpty) {
      CardCategoriesScreen._toast(context, 'أدخل اسم الفئة');
      return;
    }
    setState(() => _loading = true);
    try {
      final api = ref.read(accApiProvider);
      final data = <String, dynamic>{
        'name': _nameCtr.text.trim(),
        'sell_price': num.tryParse(_sellCtr.text.trim()) ?? 0,
        'cost_price': num.tryParse(_costCtr.text.trim()) ?? 0,
        'unit_label': _unitCtr.text.trim().isEmpty
            ? 'كرت'
            : _unitCtr.text.trim(),
        'source_binding': _binding,
        if (_isEdit) 'is_active': _active,
      };
      final msg = _isEdit
          ? await api.updateCategory(widget.category!.id, data)
          : await api.createCategory(data);
      if (mounted) {
        Navigator.pop(context);
        ref.invalidate(accCategoriesProvider);
        CardCategoriesScreen._toast(context, msg, ok: true);
      }
    } catch (e) {
      if (mounted) CardCategoriesScreen._toast(context, '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
            Text(_isEdit ? 'تعديل الفئة' : 'فئة جديدة',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            TextField(
              controller: _nameCtr,
              decoration: const InputDecoration(
                labelText: 'اسم الفئة *',
                hintText: 'مثال: باقة ساعة',
                prefixIcon: Icon(Icons.style_outlined),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _sellCtr,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'سعر البيع',
                      prefixIcon: Icon(Icons.sell_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _costCtr,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'سعر التكلفة',
                      prefixIcon: Icon(Icons.shopping_bag_outlined),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _unitCtr,
              decoration: const InputDecoration(
                labelText: 'وحدة القياس',
                hintText: 'كرت / باقة / يوم',
                prefixIcon: Icon(Icons.straighten_outlined),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _binding,
              decoration: const InputDecoration(
                labelText: 'مصدر الكروت',
                prefixIcon: Icon(Icons.input_outlined),
              ),
              items: AccCardCategory.bindings.entries
                  .map((e) =>
                      DropdownMenuItem(value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: (v) => setState(() => _binding = v ?? 'any'),
            ),
            if (_isEdit)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title:
                    const Text('فئة نشطة', style: TextStyle(fontSize: 14)),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
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
                  : Text(_isEdit ? 'حفظ التعديلات' : 'إنشاء الفئة'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
