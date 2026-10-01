import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

/// "خدمة سداد باقات الإنترنت وشركات الإتصالات" — placeholder screen shown
/// while the feature is under development, matching the design provided.
class BillPaymentScreen extends StatelessWidget {
  const BillPaymentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('خدمة سداد باقات الإنترنت وشركات الإتصالات'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
            decoration: BoxDecoration(
              color: AppColors.inputBg,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.primaryDark, AppColors.primary],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(Icons.receipt_long_rounded, color: Colors.white, size: 44),
                ),
                const SizedBox(height: 24),
                const Text(
                  'خدمة سداد باقات الإنترنت\nوشركات الإتصالات',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Cairo', fontSize: 19, fontWeight: FontWeight.bold, color: AppColors.primary, height: 1.4),
                ),
                const SizedBox(height: 14),
                const Text(
                  'قيد التطوير',
                  style: TextStyle(fontFamily: 'Cairo', fontSize: 15, color: AppColors.textGray),
                ),
                const SizedBox(height: 4),
                const Text(
                  'سيتم إتاحة الخدمة قريباً',
                  style: TextStyle(fontFamily: 'Cairo', fontSize: 15, color: AppColors.textGray),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: const Text(
                    'نعمل على توفير تجربة آمنة وسهلة',
                    style: TextStyle(fontFamily: 'Cairo', fontSize: 13, color: AppColors.success, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
