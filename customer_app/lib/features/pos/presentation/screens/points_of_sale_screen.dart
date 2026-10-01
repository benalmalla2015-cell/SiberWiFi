import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../profile/presentation/screens/services_screen.dart' show chargingPointsProvider;

/// نقاط الشحن (Points of Sale) — standalone screen reachable from the home
/// screen quick actions grid. Reuses [chargingPointsProvider] so the data
/// stays in sync with the "خدمات العميل" tab in the profile section.
class PointsOfSaleScreen extends ConsumerWidget {
  const PointsOfSaleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final points = ref.watch(chargingPointsProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('نقاط الشحن'),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textDark,
        elevation: 0,
      ),
      body: points.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (_, __) => Center(
          child: ElevatedButton(
            onPressed: () => ref.invalidate(chargingPointsProvider),
            child: const Text('إعادة المحاولة'),
          ),
        ),
        data: (items) => items.isEmpty
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.storefront_rounded, size: 64, color: AppColors.textLight),
                    SizedBox(height: 16),
                    Text(
                      'لا توجد نقاط شحن متاحة حالياً',
                      style: TextStyle(fontFamily: 'Cairo', color: AppColors.textGray, fontSize: 15),
                    ),
                  ],
                ),
              )
            : RefreshIndicator(
                color: AppColors.primary,
                onRefresh: () async => ref.invalidate(chargingPointsProvider),
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => _PointCard(point: items[i]),
                ),
              ),
      ),
    );
  }
}

class _PointCard extends StatelessWidget {
  final Map<String, dynamic> point;
  const _PointCard({required this.point});

  @override
  Widget build(BuildContext context) {
    final region = point['region']?.toString() ?? '';
    final directorate = point['directorate']?.toString() ?? '';
    final regionDirectorate = [region, directorate].where((s) => s.isNotEmpty).join(' - ');
    final phone = point['phone']?.toString() ?? '';
    final networkName = point['network_name']?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF9F43), Color(0xFFFFC07A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.storefront_rounded, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  point['name']?.toString() ?? '',
                  style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textDark),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (networkName.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.wifi_rounded, size: 12, color: AppColors.primary),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            networkName,
                            style: const TextStyle(fontFamily: 'Cairo', color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (regionDirectorate.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.location_on_outlined, size: 12, color: AppColors.textGray),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            regionDirectorate,
                            style: const TextStyle(fontFamily: 'Cairo', color: AppColors.textGray, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (point['location']?.toString().isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.map_outlined, size: 12, color: AppColors.textGray),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            point['location'].toString(),
                            style: const TextStyle(fontFamily: 'Cairo', color: AppColors.textGray, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (phone.isNotEmpty)
            Column(
              children: [
                IconButton(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: phone));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تم نسخ رقم الهاتف')),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded, color: AppColors.primary, size: 20),
                ),
                IconButton(
                  onPressed: () async {
                    final uri = Uri.parse('tel:$phone');
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri);
                    }
                  },
                  icon: const Icon(Icons.phone_outlined, color: Color(0xFF2ECC71), size: 22),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
