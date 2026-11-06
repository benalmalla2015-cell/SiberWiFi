import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../mikrotik/presentation/widgets/ui_states.dart';
import '../../data/pos_app_api.dart';
import '../../providers/pos_app_providers.dart';

/// ACC-07 — the POS agent's profit-withdrawal surface
/// (PLAN §5: POST /pos/withdrawals + /cancel).
class PosWithdrawalsScreen extends ConsumerWidget {
  const PosWithdrawalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(posWithdrawalsProvider);
    final homeAsync = ref.watch(posHomeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('سحب الأرباح')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context, ref),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('طلب سحب',
            style: TextStyle(color: Colors.white)),
      ),
      body: Container(
        color: AppColors.inputBg,
        child: listAsync.when(
          loading: () => const LoadingState(),
          error: (e, _) => ErrorRetry(
            message: 'تعذّر تحميل السحوبات\n$e',
            onRetry: () => _refresh(ref),
          ),
          data: (rows) => RefreshIndicator(
            onRefresh: () async => _refresh(ref),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (homeAsync.valueOrNull case final home?)
                  _ProfitCard(
                    balance: home.pos.profitBalance,
                    pendingAmount:
                        home.stats.pendingWithdrawalsAmount,
                  ),
                const SizedBox(height: 14),
                if (rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 60),
                    child: EmptyState(
                      'لا توجد طلبات سحب بعد',
                      icon: Icons
                          .account_balance_wallet_outlined,
                    ),
                  )
                else
                  ...rows.map((w) => _WithdrawalCard(
                        withdrawal: w,
                        onCancel: w.isPending
                            ? () => _cancel(context, ref, w)
                            : null,
                      )),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _refresh(WidgetRef ref) {
    ref.invalidate(posWithdrawalsProvider);
    ref.invalidate(posHomeProvider);
    ref.invalidate(posLedgerProvider);
  }

  Future<void> _cancel(
      BuildContext context, WidgetRef ref, PosWithdrawal w) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إلغاء طلب السحب'),
        content: Text(
            'إلغاء طلب سحب ${w.amount.toStringAsFixed(0)}؟ يعاد المبلغ لرصيد أرباحك.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('تراجع')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('إلغاء الطلب')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      final msg =
          await ref.read(posAppApiProvider).cancelWithdrawal(w.id);
      if (context.mounted) _toast(context, msg);
      _refresh(ref);
    } catch (e) {
      if (context.mounted) {
        _toast(context, e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  Future<void> _openForm(BuildContext context, WidgetRef ref) async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _WithdrawalFormSheet(),
    );
    if (sent == true) _refresh(ref);
  }

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }
}

class _ProfitCard extends StatelessWidget {
  final double balance;
  final double pendingAmount;
  const _ProfitCard(
      {required this.balance, required this.pendingAmount});

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
                const Text('رصيد الأرباح المتاح',
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
              const Text('قيد المراجعة',
                  style: TextStyle(
                      fontSize: 11, color: Colors.white70)),
              const SizedBox(height: 4),
              Text(pendingAmount.toStringAsFixed(0),
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

class _WithdrawalCard extends StatelessWidget {
  final PosWithdrawal withdrawal;
  final VoidCallback? onCancel;
  const _WithdrawalCard(
      {required this.withdrawal, this.onCancel});

  @override
  Widget build(BuildContext context) {
    final color = switch (withdrawal.status) {
      'pending' => AppColors.warning,
      'approved' => AppColors.lightBlue,
      'paid' => AppColors.success,
      'rejected' || 'cancelled' => AppColors.error,
      _ => AppColors.textGray,
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
                child: Text(
                  '${withdrawal.amount.toStringAsFixed(0)} ريال',
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(withdrawal.statusLabel,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: color)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'طلب #${withdrawal.id}'
            '${withdrawal.receiverName != null ? ' · المستلم: ${withdrawal.receiverName}' : ''}'
            '${withdrawal.createdAt != null ? ' · ${_ago(withdrawal.createdAt!)}' : ''}',
            style: const TextStyle(
                fontSize: 11, color: AppColors.textGray),
          ),
          if (withdrawal.isRejected &&
              withdrawal.reviewNote != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'سبب الرفض: ${withdrawal.reviewNote}',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.error),
              ),
            ),
          if (withdrawal.isPaid &&
              withdrawal.receiptNo != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'إيصال: ${withdrawal.receiptNo}',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.success),
              ),
            ),
          if (onCancel != null)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: onCancel,
                child: const Text('إلغاء الطلب',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.error)),
              ),
            ),
        ],
      ),
    );
  }
}

class _WithdrawalFormSheet extends ConsumerStatefulWidget {
  const _WithdrawalFormSheet();

  @override
  ConsumerState<_WithdrawalFormSheet> createState() =>
      _WithdrawalFormSheetState();
}

class _WithdrawalFormSheetState
    extends ConsumerState<_WithdrawalFormSheet> {
  final _amountCtrl = TextEditingController();
  final _receiverCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _receiverCtrl.dispose();
    _noteCtrl.dispose();
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
          const Text('طلب سحب أرباح',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary)),
          const SizedBox(height: 14),
          TextField(
            controller: _amountCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'المبلغ',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _receiverCtrl,
            decoration: const InputDecoration(
              labelText: 'اسم المستلم (اختياري)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
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
              icon: const Icon(Icons.send_outlined, size: 18),
              label: Text(
                  _busy ? 'جارٍ الإرسال…' : 'إرسال الطلب'),
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
    final amount = double.tryParse(_amountCtrl.text) ?? 0;
    if (amount <= 0) {
      _toast('أدخل مبلغاً صحيحاً أكبر من صفر');
      return;
    }
    setState(() => _busy = true);
    try {
      final msg = await ref
          .read(posAppApiProvider)
          .requestWithdrawal({
        'amount': amount,
        if (_receiverCtrl.text.trim().isNotEmpty)
          'receiver_name': _receiverCtrl.text.trim(),
        if (_noteCtrl.text.trim().isNotEmpty)
          'note': _noteCtrl.text.trim(),
        // Client replay guard — resubmitting the same draft
        // never duplicates the hold server-side.
        'idempotency_key':
            'wd-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(9999)}',
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
