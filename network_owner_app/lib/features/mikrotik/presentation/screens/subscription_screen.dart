import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/api/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/subscription_service.dart';
import '../providers/entitlement_provider.dart';
import '../widgets/ui_states.dart';

/// Everything the subscription screen needs in one round of parallel
/// reads — separate refresh lets "pull to refresh" reload all of it.
class _SubscriptionData {
  const _SubscriptionData({
    required this.entitlements,
    required this.plans,
    required this.requests,
    required this.bankAccounts,
    this.walletBalance,
  });

  final MikrotikEntitlementState? entitlements;
  final List<MikrotikPlan> plans;
  final List<MikrotikPaymentRequest> requests;
  final List<BankAccountOption> bankAccounts;
  final double? walletBalance;
}

final _subscriptionDataProvider = FutureProvider<_SubscriptionData>((ref) async {
  final api = ref.read(apiClientProvider);
  final results = await Future.wait([
    SubscriptionService.entitlements(api),
    SubscriptionService.plans(api),
    SubscriptionService.paymentRequests(api),
    SubscriptionService.bankAccounts(api),
    SubscriptionService.walletBalance(api),
  ]);
  return _SubscriptionData(
    entitlements: results[0] as MikrotikEntitlementState?,
    plans: results[1] as List<MikrotikPlan>,
    requests: results[2] as List<MikrotikPaymentRequest>,
    bankAccounts: results[3] as List<BankAccountOption>,
    walletBalance: results[4] as double?,
  );
});

/// MikroTik manager subscription — trial status, paid plans, wallet
/// checkout and the manual bank/e-wallet transfer request.
class SubscriptionScreen extends ConsumerWidget {
  const SubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(_subscriptionDataProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('اشتراك MikroTik')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(_subscriptionDataProvider);
          await ref.read(entitlementProvider.notifier).refresh();
        },
        child: data.when(
          loading: () => const LoadingState(),
          error: (e, _) => ErrorRetry(
            message: 'تعذّر تحميل بيانات الاشتراك',
            onRetry: () => ref.invalidate(_subscriptionDataProvider),
          ),
          data: (d) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _StatusCard(state: d.entitlements),
              if (d.requests.any((r) => r.status == 'pending')) ...[
                const SizedBox(height: 14),
                _PendingNotice(
                  request:
                      d.requests.firstWhere((r) => r.status == 'pending'),
                ),
              ],
              const SizedBox(height: 20),
              const _SectionTitle('الباقات المتاحة'),
              const SizedBox(height: 10),
              if (d.plans.isEmpty)
                const EmptyState(
                  'لا توجد باقات مفعّلة حالياً',
                  icon: Icons.inventory_2_outlined,
                )
              else
                for (final p in d.plans)
                  _PlanCard(
                    plan: p,
                    walletBalance: d.walletBalance,
                    hasPending:
                        d.requests.any((r) => r.status == 'pending'),
                  ),
              if (d.requests.isNotEmpty) ...[
                const SizedBox(height: 20),
                const _SectionTitle('طلبات الدفع السابقة'),
                const SizedBox(height: 10),
                for (final r in d.requests) _RequestTile(request: r),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
      );
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.state});
  final MikrotikEntitlementState? state;

  @override
  Widget build(BuildContext context) {
    final st = state;
    final (label, icon) = switch (st?.status) {
      'active' => ('اشتراك نشط', Icons.check_circle),
      'trial' => ('فترة تجريبية', Icons.timelapse),
      'expired' => ('انتهى الاشتراك', Icons.error_outline),
      _ => ('الحالة غير معروفة', Icons.help_outline),
    };

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white, size: 24),
              const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
              ),
              const Spacer(),
              if (st?.planName != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    st!.planName!,
                    style:
                        const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (st?.trialEndsAt != null)
            Text(
              'تنتهي التجربة في ${_fmtDate(st!.trialEndsAt!)}'
              '${_daysLeft(st.trialEndsAt!) != null ? ' — بقي ${_daysLeft(st.trialEndsAt!)} يوم' : ''}',
              style: const TextStyle(color: Colors.white70, fontSize: 12.5),
            )
          else if (st?.endsAt != null)
            Text(
              'تاريخ الانتهاء: ${_fmtDate(st!.endsAt!)}',
              style: const TextStyle(color: Colors.white70, fontSize: 12.5),
            ),
          if (st != null && !st.enforced) ...[
            const SizedBox(height: 8),
            const Text(
              'كل الميزات متاحة حالياً — سيُطلب الاشتراك عند تفعيل الباقات.',
              style: TextStyle(color: Colors.white60, fontSize: 11.5),
            ),
          ],
          if (st == null)
            const Text(
              'تعذّر الوصول لخادم الاشتراكات — تأكد من اتصالك ثم اسحب للتحديث.',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
        ],
      ),
    );
  }

  static String _fmtDate(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

  static int? _daysLeft(DateTime end) {
    final d = end.difference(DateTime.now()).inDays;
    return d < 0 ? null : d;
  }
}

class _PendingNotice extends StatelessWidget {
  const _PendingNotice({required this.request});
  final MikrotikPaymentRequest request;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFE0A3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.hourglass_top, color: Color(0xFFF59E0B)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'لديك طلب دفع قيد المراجعة'
              '${request.plan != null ? ' — ${request.plan}' : ''}. '
              'سيُفعّل الاشتراك بعد اعتماد الإيصال.',
              style: const TextStyle(fontSize: 12.5, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends ConsumerWidget {
  const _PlanCard({
    required this.plan,
    required this.walletBalance,
    required this.hasPending,
  });

  final MikrotikPlan plan;
  final double? walletBalance;
  final bool hasPending;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  plan.name,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
              Text(
                '${_fmtAmount(plan.price)} ${plan.currency == 'YER' ? 'ر.ي' : plan.currency}',
                style: const TextStyle(
                  color: AppColors.accent,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${plan.durationDays} يوم'
            '${plan.description?.isNotEmpty == true ? ' — ${plan.description}' : ''}',
            style: const TextStyle(color: AppColors.textGray, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _payWithWallet(context, ref),
                  icon: const Icon(Icons.account_balance_wallet_outlined,
                      size: 18),
                  label: const Text('دفع من المحفظة'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: hasPending
                      ? null
                      : () => _showTransferSheet(context, ref),
                  icon: const Icon(Icons.account_balance_outlined, size: 18),
                  label: const Text('تحويل بنكي'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _payWithWallet(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الاشتراك'),
        content: Text(
          'سيُخصم ${_fmtAmount(plan.price)} ر.ي من محفظتك'
          '${walletBalance != null ? ' (رصيدك الحالي: ${_fmtAmount(walletBalance!)} ر.ي)' : ''}'
          ' لتفعيل «${plan.name}» لمدة ${plan.durationDays} يوم.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
            ),
            child: const Text('تأكيد الدفع'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    try {
      final msg = await SubscriptionService.subscribe(
          ref.read(apiClientProvider), plan.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
      ref.invalidate(_subscriptionDataProvider);
      await ref.read(entitlementProvider.notifier).refresh();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  void _showTransferSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _TransferSheet(plan: plan, parentRef: ref),
    );
  }

  static String _fmtAmount(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
}

class _TransferSheet extends ConsumerStatefulWidget {
  const _TransferSheet({required this.plan, required this.parentRef});

  final MikrotikPlan plan;

  /// Parent's [WidgetRef] — the sheet's own ref dies when it closes.
  final WidgetRef parentRef;

  @override
  ConsumerState<_TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends ConsumerState<_TransferSheet> {
  final _senderCtrl = TextEditingController();
  final _receiptCtrl = TextEditingController();
  int? _bankId;
  String? _imagePath;
  bool _submitting = false;

  @override
  void dispose() {
    _senderCtrl.dispose();
    _receiptCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(_subscriptionDataProvider);
    final accounts = data.valueOrNull?.bankAccounts ?? const [];

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'تحويل بنكي / محفظة — ${widget.plan.name}',
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              'حوّل ${_PlanCard._fmtAmount(widget.plan.price)} ر.ي إلى أحد الحسابات ثم أرسل بيانات الإيصال.',
              style: const TextStyle(color: AppColors.textGray, fontSize: 12),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: _bankId,
              decoration: const InputDecoration(
                labelText: 'الحساب المحوّل إليه',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final a in accounts)
                  DropdownMenuItem(
                    value: a.id,
                    child: Text(
                      '${a.bankName} — ${a.accountNumber}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => _bankId = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _senderCtrl,
              decoration: const InputDecoration(
                labelText: 'الاسم الكامل للمودع *',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _receiptCtrl,
              decoration: const InputDecoration(
                labelText: 'رقم السند / الحوالة',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickImage,
              icon: Icon(_imagePath == null
                  ? Icons.image_outlined
                  : Icons.check_circle_outline),
              label: Text(_imagePath == null
                  ? 'إرفاق صورة الإيصال'
                  : 'تم إرفاق صورة الإيصال'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : const Text('إرسال طلب الدفع'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage() async {
    final picked =
        await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) setState(() => _imagePath = picked.path);
  }

  Future<void> _submit() async {
    final sender = _senderCtrl.text.trim();
    if (sender.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل الاسم الكامل للمودع')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final msg = await SubscriptionService.submitPaymentRequest(
        ref.read(apiClientProvider),
        planId: widget.plan.id,
        senderName: sender,
        bankAccountId: _bankId,
        receiptNumber:
            _receiptCtrl.text.trim().isEmpty ? null : _receiptCtrl.text.trim(),
        receiptImagePath: _imagePath,
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
      widget.parentRef.invalidate(_subscriptionDataProvider);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }
}

class _RequestTile extends StatelessWidget {
  const _RequestTile({required this.request});
  final MikrotikPaymentRequest request;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (request.status) {
      'approved' => ('مقبول', AppColors.success, Icons.check_circle),
      'rejected' => ('مرفوض', AppColors.accent, Icons.cancel_outlined),
      _ => ('قيد المراجعة', const Color(0xFFF59E0B), Icons.hourglass_top),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${request.plan ?? 'اشتراك'} — ${_PlanCard._fmtAmount(request.amount)} ر.ي',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13),
                ),
                if (request.createdAt != null)
                  Text(
                    request.createdAt!.split(' ').first,
                    style: const TextStyle(
                        color: AppColors.textGray, fontSize: 11),
                  ),
                if (request.status == 'rejected' &&
                    request.adminNote?.isNotEmpty == true)
                  Text(
                    'سبب الرفض: ${request.adminNote}',
                    style: const TextStyle(
                        color: AppColors.accent, fontSize: 11.5),
                  ),
              ],
            ),
          ),
          Text(
            label,
            style: TextStyle(
                color: color, fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
