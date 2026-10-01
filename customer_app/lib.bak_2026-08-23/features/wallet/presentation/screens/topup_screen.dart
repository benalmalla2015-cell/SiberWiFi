import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/wallet_provider.dart';

class TopupScreen extends ConsumerStatefulWidget {
  const TopupScreen({super.key});

  @override
  ConsumerState<TopupScreen> createState() => _TopupScreenState();
}

class _TopupScreenState extends ConsumerState<TopupScreen> {
  final _amountCt = TextEditingController();
  final _receiptCt = TextEditingController();
  final _senderNameCt = TextEditingController();
  int? _selectedAccountId;
  bool _loading = false;

  @override
  void dispose() {
    _amountCt.dispose();
    _receiptCt.dispose();
    _senderNameCt.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final raw = double.tryParse(_amountCt.text.trim().replaceAll(',', ''));
    if (raw == null || raw <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل مبلغاً صحيحاً'), backgroundColor: AppColors.accent),
      );
      return;
    }

    if (_selectedAccountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اختر الحساب المصرفي المُراد التحويل إليه'), backgroundColor: AppColors.accent),
      );
      return;
    }

    setState(() => _loading = true);
    final err = await ref.read(walletProvider.notifier).topup(
          amount: raw,
          bankAccountId: _selectedAccountId,
          transferReceiptNumber: _receiptCt.text.trim(),
          senderName: _senderNameCt.text.trim(),
        );
    if (!mounted) return;
    setState(() => _loading = false);
    if (err == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم طلب شحن الرصيد بنجاح ✅'), backgroundColor: AppColors.success),
      );
      context.go('/wallet');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), backgroundColor: AppColors.accent),
      );
    }
  }

  Widget _buildAccounts(List<Map<String, dynamic>> accounts) {
    if (accounts.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.inputBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        child: const Row(
          children: [
            Icon(Icons.info_outline, color: AppColors.textGray),
            SizedBox(width: 10),
            Expanded(child: Text('لا توجد حسابات مصرفية مضافة حالياً.', style: TextStyle(fontFamily: 'Cairo', fontSize: 13, color: AppColors.textGray))),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: accounts.map((a) {
        final id = a['id'];
        final isSelected = _selectedAccountId == id;
        return GestureDetector(
          onTap: () => setState(() => _selectedAccountId = id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.primary.withValues(alpha: 0.08) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: isSelected ? AppColors.primary : AppColors.divider, width: isSelected ? 2 : 1),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                  color: isSelected ? AppColors.primary : AppColors.textGray,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a['owner_name']?.toString() ?? '',
                        style: const TextStyle(fontFamily: 'Cairo', fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textDark),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        a['bank_name']?.toString() ?? '',
                        style: const TextStyle(fontFamily: 'Cairo', fontSize: 13, color: AppColors.textGray),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Text('رقم الحساب: ', style: TextStyle(fontFamily: 'Cairo', fontSize: 13, color: AppColors.textGray)),
                          Expanded(
                            child: Text(
                              a['account_number']?.toString() ?? '',
                              style: const TextStyle(fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textDark),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(bankAccountsProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('شحن الرصيد'),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textDark,
        elevation: 0,
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Container(height: 1, color: AppColors.divider)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [AppColors.primaryDark, AppColors.primary], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: Colors.white70, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'اختر الحساب المصرفي ثم أدخل المبلغ ورقم سند الإيداع أو الحوالة',
                      style: TextStyle(fontFamily: 'Cairo', fontSize: 13, color: Colors.white, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text('الحسابات المصرفية', style: TextStyle(fontFamily: 'Cairo', fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textDark)),
            const SizedBox(height: 12),
            accountsAsync.when(
              data: _buildAccounts,
              loading: () => const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator())),
              error: (_, __) => _buildAccounts([]),
            ),
            const SizedBox(height: 24),
            const Text('إيداع مبلغ الشحن', style: TextStyle(fontFamily: 'Cairo', fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textDark)),
            const SizedBox(height: 12),
            TextField(
              controller: _amountCt,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'المبلغ (ر.ي)',
                prefixIcon: Icon(Icons.attach_money_rounded),
              ),
            ),
            const SizedBox(height: 20),
            const Text('بيانات التحويل', style: TextStyle(fontFamily: 'Cairo', fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textDark)),
            const SizedBox(height: 12),
            TextField(
              controller: _receiptCt,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'رقم الحوالة / رقم سند الإيداع المصرفي',
                prefixIcon: Icon(Icons.receipt_long_rounded),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _senderNameCt,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'اسم المودع / اسم المرسل',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _loading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: _loading
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                    : const Text('طلب الشحن', style: TextStyle(fontFamily: 'Cairo', fontSize: 17, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
