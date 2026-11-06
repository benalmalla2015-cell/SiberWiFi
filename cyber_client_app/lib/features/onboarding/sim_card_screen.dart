import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';
import '../home/home_screen.dart';

/// Shown right after enrolment: the issued 74XXXXXXX presented as a
/// physical SIM card, with copy + «ابدأ» into the home screen.
class SimCardScreen extends StatelessWidget {
  const SimCardScreen({super.key, required this.issue});

  final SimIssue issue;

  String get _spacedSim => issue.simNo.split('').join(' ');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.check_circle, color: CyberColors.success, size: 56),
              const SizedBox(height: 14),
              const Text(
                'تم التسجيل بنجاح',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                issue.fullName,
                textAlign: TextAlign.center,
                style: const TextStyle(color: CyberColors.textGray, fontSize: 14),
              ),
              const SizedBox(height: 8),
              const Text(
                'هذا رقم شريحتك الدائم — اشحن به عند أي وكيل',
                textAlign: TextAlign.center,
                style: TextStyle(color: CyberColors.textGray, fontSize: 13.5),
              ),
              const SizedBox(height: 32),
              _simCard(context),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () => _copy(context),
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('نسخ الرقم'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const HomeScreen()),
                  (_) => false,
                ),
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('الانتقال إلى حسابي'),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _simCard(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.62,
      child: Container(
        decoration: BoxDecoration(
          gradient: CyberColors.simGradient,
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [
            BoxShadow(color: Color(0x3316235F), blurRadius: 24, offset: Offset(0, 12)),
          ],
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('CyberNet',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: CyberColors.accent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('شريحة رقمية',
                      style: TextStyle(color: Colors.white, fontSize: 10.5)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // The SIM chip.
            Container(
              width: 46,
              height: 34,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(7),
                gradient: const LinearGradient(
                  colors: [Color(0xFFE8C46A), Color(0xFFC79B3C)],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
              ),
              child: const Icon(Icons.grid_on_rounded, color: Color(0xFF8A6A1E), size: 22),
            ),
            const Spacer(),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text(
                _spacedSim,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 3,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'سايبر نت • CYBERNET SIM',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 11,
                letterSpacing: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _copy(BuildContext context) {
    Clipboard.setData(ClipboardData(text: issue.simNo));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم نسخ ${issue.simNo}'), duration: const Duration(seconds: 2)),
    );
  }
}
