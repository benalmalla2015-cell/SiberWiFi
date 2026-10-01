import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/vpn_state.dart';

/// "محرك تسريع الشبكة" — network booster screen, ported from the aden_data
/// app's VPN-based bandwidth focus engine.
class NetworkBoosterScreen extends ConsumerWidget {
  const NetworkBoosterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vpn = ref.watch(vpnProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('محرك تسريع الشبكة'),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textDark,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primaryDark, AppColors.primary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Text(
                      'ركّز نطاق شبكتك على التطبيق الذي تحتاجه فعلاً، واحصل على أفضل أداء عند ضعف الإنترنت',
                      style: TextStyle(fontFamily: 'Cairo', fontSize: 13, color: Colors.white, height: 1.6),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text('التطبيق المستهدف', style: TextStyle(fontFamily: 'Cairo', fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textDark)),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => context.push('/booster/apps'),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                decoration: BoxDecoration(
                  color: AppColors.inputBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.chevron_left_rounded, color: AppColors.textGray),
                    Expanded(
                      child: Text(
                        vpn.targetApp?.appName ?? 'اختر التطبيق المستهدف',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 15,
                          fontWeight: vpn.targetApp != null ? FontWeight.bold : FontWeight.normal,
                          color: vpn.targetApp != null ? AppColors.textDark : AppColors.textGray,
                        ),
                      ),
                    ),
                    const Icon(Icons.apps_rounded, color: AppColors.textGray),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),
            const Text('اختر البروفايل المناسب', style: TextStyle(fontFamily: 'Cairo', fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textDark)),
            const SizedBox(height: 12),
            ...VpnProfile.values.map((p) => _ProfileTile(
                  profile: p,
                  selected: vpn.activeProfile == p,
                  onTap: () => ref.read(vpnProvider.notifier).setProfile(p),
                )),
            const SizedBox(height: 28),
            _ToggleButton(vpn: vpn, ref: ref),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  final VpnProfile profile;
  final bool selected;
  final VoidCallback onTap;
  const _ProfileTile({required this.profile, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? AppColors.primary : AppColors.divider, width: selected ? 2 : 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected ? Icons.check_circle_rounded : Icons.circle_outlined,
              color: selected ? AppColors.primary : AppColors.textGray,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(profile.label, style: const TextStyle(fontFamily: 'Cairo', fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textDark)),
                  const SizedBox(height: 4),
                  Text(profile.description, style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, color: AppColors.textGray, height: 1.4)),
                ],
              ),
            ),
            Icon(
              profile == VpnProfile.cellular ? Icons.bar_chart_rounded : Icons.wifi_rounded,
              color: selected ? AppColors.primary : AppColors.textGray,
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleButton extends StatelessWidget {
  final VpnState vpn;
  final WidgetRef ref;
  const _ToggleButton({required this.vpn, required this.ref});

  @override
  Widget build(BuildContext context) {
    final isOn = vpn.isActive;
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: ElevatedButton(
        onPressed: vpn.isLoading
            ? null
            : () async {
                final error = await ref.read(vpnProvider.notifier).toggle();
                if (error != null && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(error), backgroundColor: AppColors.warning),
                  );
                }
              },
        style: ElevatedButton.styleFrom(
          backgroundColor: isOn ? AppColors.accent : AppColors.primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: vpn.isLoading
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(isOn ? Icons.stop_circle_outlined : Icons.bolt_rounded, color: Colors.white),
                  const SizedBox(width: 10),
                  Text(
                    isOn ? 'إيقاف المحرك' : 'اضغط لتشغيل المحرك',
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ],
              ),
      ),
    );
  }
}
