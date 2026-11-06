import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../screens/acc_subscription_screen.dart';

/// Unified paywall shown inside an `AccFeatureGate` when an
/// accounting feature requires a paid plan (ACC-11). Same brand
/// language as the mikrotik PremiumLockCard: navy surface, red
/// accent CTA, Cairo typography.
///
/// The CTA pushes the accounting subscription screen directly —
/// accounting sections navigate with MaterialPageRoute, so no
/// shared-router change is needed.
class AccPremiumLockCard extends StatelessWidget {
  const AccPremiumLockCard({super.key, this.title, this.message});

  final String? title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.primary, AppColors.primaryDark],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.25),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.workspace_premium_outlined,
                  color: Colors.white, size: 42),
            ),
            const SizedBox(height: 18),
            Text(
              title ?? 'ميزة ضمن باقة المحاسبة المدفوعة',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              message ??
                  'هذه الميزة متاحة لعملاء باقة المحاسبة المدفوعة.\nرقِّ حسابك لتفعيلها واستخدامها فوراً.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 13.5,
                height: 1.6,
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AccSubscriptionScreen(),
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text('ترقية الحساب'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
