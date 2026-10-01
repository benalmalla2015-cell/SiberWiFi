import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/api/api_client.dart';
import '../../../../core/cache/hive_service.dart';
import '../../../../core/utils/connectivity_service.dart';
import '../../../../core/utils/json_helpers.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

final payoutsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final online = await ConnectivityService.isConnected();
  if (!online) {
    final cached = HiveService.payoutsBox.get('list');
    if (cached != null) return toMapList(cached);
    return [];
  }
  try {
    final api = ref.read(apiClientProvider);
    final res = await api.get('/network-owner/payouts');
    final list = toMapList(res.data['data']);
    await HiveService.payoutsBox.put('list', list);
    return list;
  } catch (_) {
    final cached = HiveService.payoutsBox.get('list');
    if (cached != null) return toMapList(cached);
    return [];
  }
});

class PayoutsScreen extends ConsumerWidget {
  const PayoutsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user    = ref.watch(currentUserProvider);
    final payouts = ref.watch(payoutsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('المدفوعات والسحب')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(payoutsProvider),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _BalanceSummary(user: user),
              const SizedBox(height: 16),
              _RequestPayoutButton(user: user, onSuccess: () => ref.invalidate(payoutsProvider)),
              const SizedBox(height: 20),
              const Text('طلبات السحب', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              payouts.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error:   (e, _) => Center(child: Text('خطأ: $e')),
                data:    (list) => list.isEmpty
                    ? _EmptyPayouts()
                    : Column(children: list.map((p) => _PayoutCard(payout: p, onConfirmed: () => ref.invalidate(payoutsProvider))).toList()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BalanceSummary extends StatelessWidget {
  final dynamic user;
  const _BalanceSummary({required this.user});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF16235F), Color(0xFF1E2D7D), Color(0xFF2A3A9A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: [0.0, 0.5, 1.0],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Color(0x331E2D7D),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('الرصيد المتاح للسحب', style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 8),
          Text(
            '${(user?.availableBalance ?? 0).toStringAsFixed(0)} ريال',
            style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _BalanceChip(label: 'مجمّد: ${(user?.frozenBalance ?? 0).toStringAsFixed(0)} ر', color: AppColors.warning),
              const SizedBox(width: 8),
              _BalanceChip(label: 'إجمالي: ${(user?.totalEarnings ?? 0).toStringAsFixed(0)} ر', color: AppColors.success),
            ],
          ),
        ],
      ),
    );
  }
}

class _BalanceChip extends StatelessWidget {
  final String label;
  final Color color;
  const _BalanceChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

class _RequestPayoutButton extends ConsumerStatefulWidget {
  final dynamic user;
  final VoidCallback onSuccess;
  const _RequestPayoutButton({required this.user, required this.onSuccess});

  @override
  ConsumerState<_RequestPayoutButton> createState() => _RequestPayoutButtonState();
}

class _RequestPayoutButtonState extends ConsumerState<_RequestPayoutButton> {
  bool _loading = false;
  final _amountCtr = TextEditingController();

  Future<void> _submit() async {
    final amount = double.tryParse(_amountCtr.text.trim());
    final available = (widget.user?.availableBalance ?? 0).toDouble();
    if (amount == null || amount < 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل مبلغاً صحيحاً (الحد الأدنى 100 ريال)'), backgroundColor: AppColors.error),
      );
      return;
    }
    if (amount > available) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('المبلغ يتجاوز الرصيد المتاح ($available ريال)'), backgroundColor: AppColors.error),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.post('/network-owner/payouts', data: {'amount': amount});
      if (!mounted) return;
      if (res.data['success'] == true) {
        Navigator.pop(context);
        widget.onSuccess();
        await ref.read(authProvider.notifier).refreshUser();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إرسال طلب السحب بنجاح'), backgroundColor: AppColors.success),
        );
      }
    } on DioException catch (error) {
      if (mounted) {
        final data = error.response?.data;
        final errors = data is Map ? data['errors'] : null;
        final message = data is Map && data['message'] != null
            ? data['message'].toString()
            : errors is Map && errors.isNotEmpty
                ? errors.values.expand((value) => value is List ? value : [value]).join('\n')
                : 'تعذر إرسال طلب السحب. حاول مرة أخرى.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: AppColors.error),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر إرسال طلب السحب. حاول مرة أخرى.'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showDialog() {
    _amountCtr.clear();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('طلب سحب رصيد', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text('الرصيد المتاح: ${(widget.user?.availableBalance ?? 0).toStringAsFixed(0)} ريال',
                style: const TextStyle(color: AppColors.textGray, fontSize: 13), textAlign: TextAlign.center),
            const SizedBox(height: 20),
            TextField(
              controller: _amountCtr,
              keyboardType: TextInputType.number,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(
                labelText: 'المبلغ المراد سحبه (ريال)',
                prefixIcon: Icon(Icons.monetization_on_outlined),
              ),
            ),
            const SizedBox(height: 20),
            AppButton(
              label: 'إرسال الطلب',
              height: 48,
              isLoading: _loading,
              onPressed: _submit,
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppButton(
      label: 'طلب سحب رصيد',
      icon: Icons.send_to_mobile,
      onPressed: _showDialog,
    );
  }
}

class _PayoutCard extends ConsumerStatefulWidget {
  final Map<String, dynamic> payout;
  final VoidCallback onConfirmed;
  const _PayoutCard({required this.payout, required this.onConfirmed});

  @override
  ConsumerState<_PayoutCard> createState() => _PayoutCardState();
}

class _PayoutCardState extends ConsumerState<_PayoutCard> {
  bool _confirming = false;

  String _formatAmount(dynamic value) => ((value as num?) ?? 0).toStringAsFixed(0);

  Color _statusColor(String s) {
    switch (s) {
      case 'pending': return AppColors.warning;
      case 'approved': return AppColors.lightBlue;
      case 'paid_unconfirmed': return AppColors.accent;
      case 'received': return AppColors.success;
      case 'rejected': return AppColors.error;
      default: return AppColors.textGray;
    }
  }

  Future<void> _confirmReceipt() async {
    setState(() => _confirming = true);
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.post('/network-owner/payouts/${widget.payout['id']}/confirm-receipt');
      if (!mounted) return;
      if (res.data['success'] == true) {
        await HiveService.payoutsBox.delete('list');
        await ref.read(authProvider.notifier).refreshUser();
        if (!mounted) return;
        widget.onConfirmed();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تأكيد استلام المبلغ بنجاح'), backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p      = widget.payout;
    final status = p['status'] ?? '';
    final requiresConfirm = p['requires_confirmation'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: requiresConfirm
            ? Border.all(color: AppColors.accent, width: 2)
            : Border.all(color: AppColors.divider),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    p['request_number'] ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _statusColor(status).withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      p['status_label'] ?? status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: _statusColor(status), fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _InfoChip(label: 'المطلوب', value: '${_formatAmount(p['requested_amount'])} ر'),
                const SizedBox(width: 8),
                if (p['paid_amount'] != null)
                  _InfoChip(label: 'المصروف', value: '${_formatAmount(p['paid_amount'])} ر', color: AppColors.success),
              ],
            ),
            if (p['service_name'] != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.payments_outlined, size: 14, color: AppColors.textGray),
                  const SizedBox(width: 4),
                  Text('${p['service_name']} - ${p['transaction_number'] ?? ''}',
                      style: const TextStyle(fontSize: 12, color: AppColors.textGray)),
                ],
              ),
            ],
            if (p['rejection_reason'] != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('سبب الرفض: ${p['rejection_reason']}',
                    style: const TextStyle(fontSize: 11, color: AppColors.error)),
              ),
            ],
            if (requiresConfirm) ...[
              const SizedBox(height: 14),
              AppButton(
                label: 'تأكيد استلام المبلغ',
                icon: Icons.check_circle_outline,
                height: 48,
                backgroundColor: AppColors.success,
                isLoading: _confirming,
                onPressed: _confirmReceipt,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label, value;
  final Color color;
  const _InfoChip({required this.label, required this.value, this.color = AppColors.primary});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text('$label: $value', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

class _EmptyPayouts extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: const Column(
        children: [
          Icon(Icons.inbox_outlined, size: 48, color: AppColors.textGray),
          SizedBox(height: 12),
          Text('لا توجد طلبات سحب', style: TextStyle(color: AppColors.textGray, fontSize: 15)),
        ],
      ),
    );
  }
}
