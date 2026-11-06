import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../mikrotik/presentation/widgets/ui_states.dart';
import '../../data/money_api.dart';
import '../../providers/money_providers.dart';

/// ACC-05 — cash boxes + inter-box transfers (PLAN §5:
/// cash_boxes_screen). Boxes list on top, transfer history below;
/// the FAB opens the transfer form, the header button adds a box.
class CashBoxesScreen extends ConsumerWidget {
  const CashBoxesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boxesAsync = ref.watch(accCashBoxesProvider);
    final transfersAsync = ref.watch(accTransfersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('الصناديق'),
        actions: [
          IconButton(
            tooltip: 'صندوق جديد',
            onPressed: () => _openCreateBox(context, ref),
            icon: const Icon(Icons.add_business_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openTransfer(context, ref),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.swap_horiz, color: Colors.white),
        label:
            const Text('تحويل', style: TextStyle(color: Colors.white)),
      ),
      body: Container(
        color: AppColors.inputBg,
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(accCashBoxesProvider);
            ref.invalidate(accTransfersProvider);
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              boxesAsync.when(
                loading: () => const LoadingState(),
                error: (e, _) => ErrorRetry(
                  message: 'تعذّر تحميل الصناديق\n$e',
                  onRetry: () => ref.invalidate(accCashBoxesProvider),
                ),
                data: (boxes) => Column(
                  children: boxes
                      .map((b) => _BoxCard(box: b))
                      .toList(),
                ),
              ),
              const SizedBox(height: 16),
              const Text('سجل التحويلات',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark)),
              const SizedBox(height: 8),
              transfersAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('تعذّر تحميل التحويلات: $e',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.error)),
                ),
                data: (items) => items.isEmpty
                    ? const EmptyState('لا توجد تحويلات',
                        icon: Icons.swap_horiz)
                    : Column(
                        children: items
                            .map((t) => _TransferTile(transfer: t))
                            .toList(),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openCreateBox(BuildContext context, WidgetRef ref) async {
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _CreateBoxSheet(),
    );
    if (done == true) ref.invalidate(accCashBoxesProvider);
  }

  Future<void> _openTransfer(BuildContext context, WidgetRef ref) async {
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _TransferSheet(),
    );
    if (done == true) {
      ref.invalidate(accCashBoxesProvider);
      ref.invalidate(accTransfersProvider);
    }
  }
}

class _BoxCard extends StatelessWidget {
  final AccCashBox box;
  const _BoxCard({required this.box});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
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
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.lightBlue],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.account_balance_wallet_outlined,
                color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        box.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: AppColors.textDark),
                      ),
                    ),
                    if (box.isDefault) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color:
                              AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text('رئيسي',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  AccCurrencyInfo.label(box.currency),
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textGray),
                ),
              ],
            ),
          ),
          Text(
            box.balance.toStringAsFixed(0),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: box.balance < 0
                  ? AppColors.error
                  : AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _TransferTile extends StatelessWidget {
  final AccTransfer transfer;
  const _TransferTile({required this.transfer});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.swap_horiz,
            color: AppColors.lightBlue, size: 22),
        title: Text(
          '${transfer.fromBoxName ?? '?'} ← ${transfer.toBoxName ?? '?'}',
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppColors.textDark),
        ),
        subtitle: transfer.note != null
            ? Text(transfer.note!,
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textGray))
            : null,
        trailing: Text(
          transfer.amount == transfer.toAmount
              ? transfer.amount.toStringAsFixed(0)
              : '${transfer.amount.toStringAsFixed(0)} ← ${transfer.toAmount.toStringAsFixed(0)}',
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppColors.textDark),
        ),
      ),
    );
  }
}

class _CreateBoxSheet extends ConsumerStatefulWidget {
  const _CreateBoxSheet();

  @override
  ConsumerState<_CreateBoxSheet> createState() => _CreateBoxSheetState();
}

class _CreateBoxSheetState extends ConsumerState<_CreateBoxSheet> {
  final _nameCtrl = TextEditingController();
  final _balanceCtrl = TextEditingController();
  String _currency = 'north';
  bool _busy = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _balanceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
          const Text('صندوق جديد',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary)),
          const SizedBox(height: 16),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
                labelText: 'اسم الصندوق',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _balanceCtrl,
                  decoration: const InputDecoration(
                      labelText: 'رصيد افتتاحي',
                      border: OutlineInputBorder()),
                  keyboardType: TextInputType.number,
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
                  : const Text('إنشاء'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _toast('أدخل اسم الصندوق');
      return;
    }
    setState(() => _busy = true);
    try {
      final msg = await ref.read(moneyApiProvider).createBox({
        'name': name,
        'currency': _currency,
        'opening_balance':
            double.tryParse(_balanceCtrl.text.trim()) ?? 0,
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

class _TransferSheet extends ConsumerStatefulWidget {
  const _TransferSheet();

  @override
  ConsumerState<_TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends ConsumerState<_TransferSheet> {
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  int? _fromId;
  int? _toId;
  bool _busy = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final boxesAsync = ref.watch(accCashBoxesProvider);

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: boxesAsync.when(
        loading: () => const SizedBox(
            height: 200, child: Center(child: CircularProgressIndicator())),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(24),
          child: Text('تعذّر تحميل الصناديق: $e'),
        ),
        data: (boxes) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('تحويل بين الصناديق',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary)),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: _fromId,
              decoration: const InputDecoration(
                  labelText: 'من صندوق', border: OutlineInputBorder()),
              items: boxes
                  .map((b) => DropdownMenuItem(
                      value: b.id,
                      child:
                          Text('${b.name} (${b.balance.toStringAsFixed(0)})')))
                  .toList(),
              onChanged: (v) => setState(() => _fromId = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _toId,
              decoration: const InputDecoration(
                  labelText: 'إلى صندوق', border: OutlineInputBorder()),
              items: boxes
                  .where((b) => b.id != _fromId)
                  .map((b) =>
                      DropdownMenuItem(value: b.id, child: Text(b.name)))
                  .toList(),
              onChanged: (v) => setState(() => _toId = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountCtrl,
              decoration: const InputDecoration(
                  labelText: 'المبلغ', border: OutlineInputBorder()),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
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
                    : const Text('تحويل'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (_fromId == null || _toId == null) {
      _toast('حدد الصندوقين');
      return;
    }
    if (amount == null || amount <= 0) {
      _toast('أدخل مبلغاً صحيحاً');
      return;
    }
    setState(() => _busy = true);
    try {
      final msg = await ref.read(moneyApiProvider).transfer({
        'from_box_id': _fromId,
        'to_box_id': _toId,
        'amount': amount,
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
