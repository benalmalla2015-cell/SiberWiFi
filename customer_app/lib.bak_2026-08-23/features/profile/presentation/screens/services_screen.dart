import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/api/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/json_helpers.dart';

final chargingPointsProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final response = await ref.read(apiClientProvider).get('/charging-points');
  return toMapList(response.data['data']);
});

final referralProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final response = await ref.read(apiClientProvider).get('/profile/referral');
  return toMap(response.data['data']);
});

class ServicesScreen extends ConsumerWidget {
  const ServicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final referral = ref.watch(referralProvider);
    final points = ref.watch(chargingPointsProvider);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text('خدمات العميل'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'الإحالات'),
              Tab(text: 'نقاط الشحن'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            referral.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => _error(() => ref.invalidate(referralProvider)),
              data: (data) => _referral(context, data),
            ),
            points.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) =>
                  _error(() => ref.invalidate(chargingPointsProvider)),

              data: (items) => items.isEmpty
                  ? const Center(
                      child: Text(
                        'لا توجد نقاط شحن متاحة حالياً',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          color: AppColors.textGray,
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () async =>
                          ref.invalidate(chargingPointsProvider),
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, index) => _point(items[index]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _error(VoidCallback retry) => Center(
    child: ElevatedButton(
      onPressed: retry,
      child: const Text('إعادة المحاولة'),
    ),
  );

  Widget _referral(BuildContext context, Map<String, dynamic> data) {
    final code = data['referral_code']?.toString() ?? '';
    final link = 'https://saiberwifi.net/register?ref=$code';
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.inputBg,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            children: [
              const Icon(
                Icons.card_giftcard_rounded,
                color: AppColors.accent,
                size: 42,
              ),
              const SizedBox(height: 12),
              const Text(
                'ادعُ أصدقاءك واربح عمولة',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'تُحتسب العمولة تلقائياً عند إتمام أول عملية شراء للشخص المدعو.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  color: AppColors.textGray,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _stat(
                'إجمالي الأرباح',
                '${data['total_earnings'] ?? 0} ر.ي',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _stat(
                'الأشخاص المدعوون',
                '${data['referrals_count'] ?? 0}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Text(
          'كود الدعوة الخاص بك',
          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.divider),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: SelectableText(
                  code,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Clipboard.setData(ClipboardData(text: link)),
                icon: const Icon(Icons.copy_rounded, color: AppColors.primary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: link));
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('تم نسخ رابط الدعوة')));
          },
          icon: const Icon(Icons.share_outlined),
          label: const Text('نسخ رابط الدعوة'),
        ),
      ],
    );
  }

  Widget _stat(String label, String value) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.inputBg,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Cairo',
            fontSize: 11,
            color: AppColors.textGray,
          ),
        ),
      ],
    ),
  );

  Widget _point(Map<String, dynamic> point) {
    final region = point['region']?.toString() ?? '';
    final directorate = point['directorate']?.toString() ?? '';
    final regionDirectorate = [region, directorate]
        .where((s) => s.isNotEmpty)
        .join(' - ');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.divider),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircleAvatar(
            backgroundColor: AppColors.inputBg,
            child: Icon(Icons.storefront_rounded, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  point['name']?.toString() ?? '',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (point['network_name']?.toString().isNotEmpty == true)
                  Text(
                    point['network_name'].toString(),
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      color: AppColors.textGray,
                      fontSize: 12,
                    ),
                  ),
                if (regionDirectorate.isNotEmpty)
                  Text(
                    regionDirectorate,
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      color: AppColors.textGray,
                    ),
                  ),
                if (point['location']?.toString().isNotEmpty == true)
                  Text(
                    point['location'].toString(),
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      color: AppColors.textGray,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          if ((point['phone']?.toString() ?? '').isNotEmpty)
            IconButton(
              onPressed: () => Clipboard.setData(
                ClipboardData(text: point['phone'].toString()),
              ),
              icon: const Icon(Icons.phone_outlined, color: AppColors.primary),
            ),
        ],
      ),
    );
  }
}
