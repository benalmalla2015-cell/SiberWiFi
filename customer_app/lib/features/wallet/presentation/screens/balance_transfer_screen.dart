import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../providers/wallet_provider.dart';

class BalanceTransferScreen extends ConsumerStatefulWidget {
  const BalanceTransferScreen({super.key});

  @override
  ConsumerState<BalanceTransferScreen> createState() => _BalanceTransferScreenState();
}

class _BalanceTransferScreenState extends ConsumerState<BalanceTransferScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _amountController = TextEditingController();
  Map<String, dynamic>? _customer;
  bool _searching = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_phoneController.text.length != 9) {
      _showMessage('يجب أن يتكون رقم الجوال من 9 أرقام', error: true);
      return;
    }
    setState(() {
      _searching = true;
      _customer = null;
    });
    try {
      final customer = await ref.read(walletProvider.notifier).searchCustomer(_phoneController.text);
      if (mounted) setState(() => _customer = customer);
    } catch (e) {
      if (mounted) _showMessage(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _transfer() async {
    if (!_formKey.currentState!.validate()) return;
    if (_customer == null || _customer!['phone'] != _phoneController.text) {
      setState(() => _searching = true);
      try {
        final customer = await ref.read(walletProvider.notifier).searchCustomer(_phoneController.text);
        if (!mounted) return;
        setState(() => _customer = customer);
      } catch (e) {
        if (mounted) _showMessage(e.toString(), error: true);
        return;
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    }
    final amount = double.parse(_amountController.text);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد شحن الرصيد'),
        content: Text('سيتم تحويل ${amount.toStringAsFixed(2)} ر.ي إلى ${_customer!['name']}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('تأكيد')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final error = await ref.read(walletProvider.notifier).transfer(phone: _phoneController.text, amount: amount);
    if (!mounted) return;
    if (error != null) {
      _showMessage(error, error: true);
      return;
    }
    _amountController.clear();
    _showMessage('تم شحن الرصيد بنجاح');
  }

  void _showMessage(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? AppColors.accent : AppColors.success,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final balance = ref.watch(walletBalanceProvider);
    final transferState = ref.watch(walletProvider);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('شحن رصيد'),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textDark,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(18)),
              child: Column(
                children: [
                  const Text('رصيدي الحالي', style: TextStyle(fontFamily: 'Cairo', color: AppColors.textGray)),
                  const SizedBox(height: 6),
                  Text(
                    balance.when(data: (value) => '${value.balance.toStringAsFixed(2)} ر.ي', loading: () => '...', error: (_, __) => '—'),
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 26, fontWeight: FontWeight.bold, color: AppColors.primary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              maxLength: 9,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(9)],
              onChanged: (_) => setState(() => _customer = null),
              decoration: InputDecoration(
                labelText: 'رقم موبايل العميل',
                prefixIcon: const Icon(Icons.phone_android_rounded),
                suffixIcon: _searching
                    ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                    : IconButton(icon: const Icon(Icons.search_rounded), onPressed: _search),
              ),
              validator: (value) => value?.length == 9 ? null : 'يجب أن يتكون رقم الجوال من 9 أرقام',
            ),
            if (_customer != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  const Icon(Icons.check_circle_rounded, color: AppColors.success),
                  const SizedBox(width: 10),
                  Expanded(child: Text('${_customer!['name']}', style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold))),
                ]),
              ),
            ],
            const SizedBox(height: 16),
            TextFormField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
              decoration: const InputDecoration(labelText: 'المبلغ', prefixIcon: Icon(Icons.payments_outlined), suffixText: 'ر.ي'),
              validator: (value) {
                final amount = double.tryParse(value ?? '');
                if (amount == null || amount <= 0) return 'أدخل مبلغاً صحيحاً';
                return null;
              },
            ),
            const SizedBox(height: 24),
            AppButton(
              label: 'شحن',
              icon: Icons.send_rounded,
              isLoading: transferState.isLoading || _searching,
              onPressed: _transfer,
            ),
          ],
        ),
      ),
    );
  }
}
