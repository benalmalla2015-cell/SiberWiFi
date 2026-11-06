import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../mikrotik/presentation/widgets/ui_states.dart';
import '../../data/money_api.dart';
import '../../providers/acc_providers.dart';
import '../../providers/money_providers.dart';

/// ACC-05 — debts + settlement (PLAN §5: debts_screen).
///
/// Receivables (they owe us) and payables (suppliers — we owe) in
/// one list; tapping a debt opens its details with a settle action
/// that posts Dr box / Cr AR (or the inverse for payables).
class DebtsScreen extends ConsumerStatefulWidget {
  const DebtsScreen({super.key});

  @override
  ConsumerState<DebtsScreen> createState() => _DebtsScreenState();
}

class _DebtsScreenState extends ConsumerState<DebtsScreen> {
  String? _status;

  static const _filters = <String?, String>{
    null: 'الكل',
    'open': 'قائمة',
    'partial': 'جزئية',
    'paid': 'مسددة',
  };

  @override
  Widget build(BuildContext context) {
    final listAsync = ref.watch(accDebtsProvider(_status));

    return Scaffold(
      appBar: AppBar(title: const Text('المديونيات')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('دين جديد',
            style: TextStyle(color: Colors.white)),
      ),
      body: Container(
        color: AppColors.inputBg,
        child: Column(
          children: [
            _FilterBar(
              filters: _filters,
              current: _status,
              onSelect: (v) => setState(() => _status = v),
            ),
            Expanded(
              child: listAsync.when(
                loading: () => const LoadingState(),
                error: (e, _) => ErrorRetry(
                  message: 'تعذّر تحميل الديون\n$e',
                  onRetry: () =>
                      ref.invalidate(accDebtsProvider(_status)),
                ),
                data: (items) => items.isEmpty
                    ? const EmptyState('لا توجد ديون',
                        icon: Icons.handshake_outlined)
                    : RefreshIndicator(
                        onRefresh: () async =>
                            ref.invalidate(accDebtsProvider(_status)),
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: items.length,
                          itemBuilder: (_, i) => _DebtCard(
                            debt: items[i],
                            onTap: () => _openDetails(items[i]),
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

  Future<void> _openDetails(AccDebt debt) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _DebtDetailsSheet(debt: debt),
    );
    if (changed == true) {
      ref.invalidate(accDebtsProvider(_status));
      ref.invalidate(accCollectionsProvider(null));
      ref.invalidate(accCashBoxesProvider);
    }
  }

  Future<void> _openCreate() async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _DebtCreateSheet(),
    );
    if (changed == true) {
      ref.invalidate(accDebtsProvider(_status));
    }
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

class _DebtCard extends StatelessWidget {
  final AccDebt debt;
  final VoidCallback onTap;
  const _DebtCard({required this.debt, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = debt.isSettled
        ? AppColors.success
        : (debt.isPayable ? AppColors.error : AppColors.warning);
    final progress = debt.amountDue > 0
        ? (debt.amountPaid / debt.amountDue).clamp(0.0, 1.0)
        : 0.0;

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
        onTap: onTap,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Row(
          children: [
            Expanded(
              child: Text(
                debt.partyName,
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: AppColors.textDark),
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                debt.isPayable ? 'مستحق له' : 'مدين لنا',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: color),
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(
                value: progress,
                minHeight: 5,
                borderRadius: BorderRadius.circular(4),
                backgroundColor: AppColors.inputBg,
                color: color,
              ),
              const SizedBox(height: 6),
              Text(
                'المدفوع ${debt.amountPaid.toStringAsFixed(0)} من ${debt.amountDue.toStringAsFixed(0)} · المتبقي ${debt.remaining.toStringAsFixed(0)}',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textGray),
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

class _DebtDetailsSheet extends ConsumerStatefulWidget {
  final AccDebt debt;
  const _DebtDetailsSheet({required this.debt});

  @override
  ConsumerState<_DebtDetailsSheet> createState() =>
      _DebtDetailsSheetState();
}

class _DebtDetailsSheetState extends ConsumerState<_DebtDetailsSheet> {
  final _amountCtrl = TextEditingController();
  int? _boxId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _amountCtrl.text = widget.debt.remaining.toStringAsFixed(0);
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final debt = widget.debt;
    final boxesAsync = ref.watch(accCashBoxesProvider);

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
          Text(
            debt.partyName,
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.primary),
          ),
          const SizedBox(height: 4),
          Text(
            debt.isPayable ? 'مستحق له (مورد/طرف)' : 'مدين لنا',
            style: const TextStyle(
                fontSize: 12, color: AppColors.textGray),
          ),
          const Divider(height: 24),
          _Row('الإجمالي', debt.amountDue.toStringAsFixed(0)),
          _Row('المدفوع', debt.amountPaid.toStringAsFixed(0)),
          _Row('المتبقي', debt.remaining.toStringAsFixed(0)),
          if (debt.dueDate != null) _Row('الاستحقاق', debt.dueDate!),
          if (debt.note != null) _Row('ملاحظة', debt.note!),
          if (!debt.isSettled) ...[
            const SizedBox(height: 16),
            const Text('تسجيل سداد',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _amountCtrl,
                    decoration: const InputDecoration(
                        labelText: 'المبلغ',
                        border: OutlineInputBorder()),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 3,
                  child: boxesAsync.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => const SizedBox.shrink(),
                    data: (boxes) => DropdownButtonFormField<int?>(
                      initialValue: _boxId,
                      decoration: const InputDecoration(
                          labelText: 'الصندوق',
                          border: OutlineInputBorder()),
                      items: [
                        const DropdownMenuItem<int?>(
                            value: null, child: Text('الرئيسي')),
                        ...boxes.map((b) => DropdownMenuItem<int?>(
                            value: b.id, child: Text(b.name))),
                      ],
                      onChanged: (v) => setState(() => _boxId = v),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : _pay,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.success,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('سداد'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pay() async {
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      _toast('أدخل مبلغاً صحيحاً');
      return;
    }
    setState(() => _busy = true);
    try {
      final msg = await ref.read(moneyApiProvider).payDebt(
          widget.debt.id, {'amount': amount, 'cash_box_id': _boxId});
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

class _DebtCreateSheet extends ConsumerStatefulWidget {
  const _DebtCreateSheet();

  @override
  ConsumerState<_DebtCreateSheet> createState() => _DebtCreateSheetState();
}

class _DebtCreateSheetState extends ConsumerState<_DebtCreateSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  String _partyType = 'person';
  String _currency = 'north';
  int? _partyId;
  bool _busy = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  bool get _needsName =>
      _partyType == 'customer' ||
      _partyType == 'person' ||
      _partyType == 'supplier';

  @override
  Widget build(BuildContext context) {
    final posAsync = ref.watch(accPosPointsProvider);
    final agentsAsync = ref.watch(accAgentsProvider);

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
              const Text('تسجيل دين',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary)),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _partyType,
                decoration: const InputDecoration(
                    labelText: 'نوع الطرف', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'pos', child: Text('نقطة بيع')),
                  DropdownMenuItem(
                      value: 'distributor', child: Text('موزع')),
                  DropdownMenuItem(value: 'customer', child: Text('عميل')),
                  DropdownMenuItem(value: 'person', child: Text('شخص')),
                  DropdownMenuItem(
                      value: 'supplier', child: Text('مورد (مستحق له)')),
                ],
                onChanged: (v) => setState(() {
                  _partyType = v ?? 'person';
                  _partyId = null;
                }),
              ),
              const SizedBox(height: 12),
              if (_partyType == 'pos')
                posAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text('تعذر تحميل النقاط: $e'),
                  data: (points) => DropdownButtonFormField<int>(
                    initialValue: _partyId,
                    decoration: const InputDecoration(
                        labelText: 'نقطة البيع',
                        border: OutlineInputBorder()),
                    items: points
                        .map((p) => DropdownMenuItem(
                            value: p.id, child: Text(p.name)))
                        .toList(),
                    onChanged: (v) => setState(() => _partyId = v),
                    validator: (v) => v == null ? 'اختر النقطة' : null,
                  ),
                )
              else if (_partyType == 'distributor')
                agentsAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text('تعذر تحميل الموزعين: $e'),
                  data: (agents) {
                    final dists = agents
                        .where((a) => a.role == 'distributor' && a.isActive)
                        .toList();
                    return DropdownButtonFormField<int>(
                      initialValue: _partyId,
                      decoration: const InputDecoration(
                          labelText: 'الموزع',
                          border: OutlineInputBorder()),
                      items: dists
                          .map((a) => DropdownMenuItem(
                              value: a.id, child: Text(a.displayName)))
                          .toList(),
                      onChanged: (v) => setState(() => _partyId = v),
                      validator: (v) => v == null ? 'اختر الموزع' : null,
                    );
                  },
                )
              else
                TextFormField(
                  controller: _nameCtrl,
                  decoration: InputDecoration(
                      labelText: _partyType == 'supplier'
                          ? 'اسم المورد'
                          : 'اسم الطرف',
                      border: const OutlineInputBorder()),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'الاسم مطلوب' : null,
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
                      : const Text('تسجيل الدين'),
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
      final msg = await ref.read(moneyApiProvider).createDebt({
        'party_type': _partyType,
        'party_id': _partyId,
        'party_name': _needsName ? _nameCtrl.text.trim() : null,
        'phone': _phoneCtrl.text.trim().isEmpty
            ? null
            : _phoneCtrl.text.trim(),
        'amount_due': double.parse(_amountCtrl.text.trim()),
        'currency': _currency,
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

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textGray)),
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
