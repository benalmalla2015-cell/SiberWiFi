import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../mikrotik/presentation/widgets/ui_states.dart';
import '../../data/collections_daily_pdf.dart';
import '../../data/money_api.dart';
import '../../providers/acc_providers.dart';
import '../../providers/money_providers.dart';
import '../../providers/reports_providers.dart';

/// ACC-05 — cash collections (PLAN §5: collections_screen).
///
/// Management surface: every collection posts Dr box / Cr party in
/// one backend transaction. The form resolves the party — a POS
/// point, a distributor, or a named customer/person — and the box.
class CollectionsScreen extends ConsumerStatefulWidget {
  const CollectionsScreen({super.key});

  @override
  ConsumerState<CollectionsScreen> createState() =>
      _CollectionsScreenState();
}

class _CollectionsScreenState extends ConsumerState<CollectionsScreen> {
  String? _partyType;

  static const _filters = <String?, String>{
    null: 'الكل',
    'pos': 'نقاط بيع',
    'distributor': 'موزعون',
    'customer': 'عملاء',
    'person': 'أشخاص',
  };

  @override
  Widget build(BuildContext context) {
    final listAsync = ref.watch(accCollectionsProvider(_partyType));

    return Scaffold(
      appBar: AppBar(
        title: const Text('التحصيلات'),
        actions: [
          IconButton(
            tooltip: 'كشف اليوم PDF',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: _dailyStatement,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openForm,
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('تحصيل', style: TextStyle(color: Colors.white)),
      ),
      body: Container(
        color: AppColors.inputBg,
        child: Column(
          children: [
            _FilterBar(
              filters: _filters,
              current: _partyType,
              onSelect: (v) => setState(() => _partyType = v),
            ),
            Expanded(
              child: listAsync.when(
                loading: () => const LoadingState(),
                error: (e, _) => ErrorRetry(
                  message: 'تعذّر تحميل التحصيلات\n$e',
                  onRetry: () =>
                      ref.invalidate(accCollectionsProvider(_partyType)),
                ),
                data: (items) => items.isEmpty
                    ? const EmptyState('لا توجد تحصيلات بعد',
                        icon: Icons.payments_outlined)
                    : RefreshIndicator(
                        onRefresh: () async => ref
                            .invalidate(accCollectionsProvider(_partyType)),
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: items.length,
                          itemBuilder: (_, i) =>
                              _CollectionCard(item: items[i]),
                        ),
                      ),
              ),
            ),
          ],
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
      builder: (_) => const _CollectionSheet(),
    );
    if (done == true) {
      ref.invalidate(accCollectionsProvider(_partyType));
      ref.invalidate(accCashBoxesProvider);
    }
  }

  /// كشف تحصيل يومي — pick the day, fetch its register, then
  /// print or share the generated A4 statement (ACC-09).
  Future<void> _dailyStatement() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2025),
      lastDate: DateTime.now(),
    );
    if (picked == null || !mounted) return;
    final date = picked.toIso8601String().substring(0, 10);

    final messenger = ScaffoldMessenger.of(context);
    try {
      final day = await ref
          .read(reportsApiProvider)
          .collectionsDaily(date: date);
      if (!mounted) return;
      final action = await showModalBottomSheet<String>(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (_) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('كشف تحصيل $date',
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary)),
                const SizedBox(height: 6),
                Text(
                  '${day.count} تحصيلاً — إجمالي ${day.totalBase.toStringAsFixed(0)} (بالأساس)',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textGray),
                ),
                const SizedBox(height: 18),
                Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () =>
                          Navigator.of(context).pop('print'),
                      icon: const Icon(Icons.print_outlined),
                      label: const Text('طباعة'),
                      style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          Navigator.of(context).pop('share'),
                      icon: const Icon(Icons.share_outlined),
                      label: const Text('مشاركة'),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      );
      if (action == 'print') {
        await CollectionsDailyPdf.print(day);
      } else if (action == 'share') {
        await CollectionsDailyPdf.sharePdf(day);
      }
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('تعذّر إنشاء الكشف: $e')));
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

class _CollectionCard extends StatelessWidget {
  final AccCollection item;
  const _CollectionCard({required this.item});

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
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.south_west,
              color: AppColors.success, size: 22),
        ),
        title: Text(
          item.partyName,
          style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: AppColors.textDark),
        ),
        subtitle: Text(
          '${item.partyLabel} · ${item.boxName ?? 'الصندوق'}'
          '${item.debtId != null ? ' · سداد دين' : ''}',
          style: const TextStyle(fontSize: 11, color: AppColors.textGray),
        ),
        trailing: Text(
          '+${item.amount.toStringAsFixed(0)}',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: AppColors.success,
          ),
        ),
      ),
    );
  }
}

class _CollectionSheet extends ConsumerStatefulWidget {
  const _CollectionSheet();

  @override
  ConsumerState<_CollectionSheet> createState() => _CollectionSheetState();
}

class _CollectionSheetState extends ConsumerState<_CollectionSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  String _partyType = 'person';
  String _currency = 'north';
  int? _partyId;
  int? _boxId;
  bool _busy = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  bool get _needsName => _partyType == 'customer' || _partyType == 'person';

  @override
  Widget build(BuildContext context) {
    final boxesAsync = ref.watch(accCashBoxesProvider);
    final posAsync = ref.watch(accPosPointsProvider);
    final distAsync = ref.watch(accAgentsProvider);

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
              const Text('تسجيل تحصيل',
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
                distAsync.when(
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
                  decoration: const InputDecoration(
                      labelText: 'اسم الطرف',
                      border: OutlineInputBorder()),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'الاسم مطلوب' : null,
                ),
              if (_needsName) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneCtrl,
                  decoration: const InputDecoration(
                      labelText: 'الهاتف (اختياري)',
                      border: OutlineInputBorder()),
                  keyboardType: TextInputType.phone,
                ),
              ],
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
                        value: b.id, child: Text(b.name))),
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
                      : const Text('تسجيل التحصيل'),
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
      final msg = await ref.read(moneyApiProvider).collect({
        'party_type': _partyType,
        'party_id': _partyId,
        'party_name': _needsName ? _nameCtrl.text.trim() : null,
        'phone': _phoneCtrl.text.trim().isEmpty
            ? null
            : _phoneCtrl.text.trim(),
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
