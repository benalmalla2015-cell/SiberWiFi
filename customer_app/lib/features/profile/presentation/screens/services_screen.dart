import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/api/api_client.dart';
import '../../../../core/cache/hive_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/connectivity_service.dart';
import '../../../../core/utils/json_helpers.dart';

/// Kept here so the standalone "نقاط الشحن" screen can still reuse the same
/// provider and cached data, while the services screen itself no longer shows it.
final chargingPointsProvider = FutureProvider<List<Map<String, dynamic>>>(
  (ref) async {
    final online = await ConnectivityService.isConnected();
    if (!online) {
      final cached = HiveService.dashboardBox.get('charging_points');
      if (cached != null) return toMapList(cached);
      return [];
    }
    try {
      final response = await ref.read(apiClientProvider).get('/charging-points');
      final list = toMapList(response.data['data']);
      await HiveService.dashboardBox.put('charging_points', list);
      return list;
    } catch (_) {
      final cached = HiveService.dashboardBox.get('charging_points');
      if (cached != null) return toMapList(cached);
      return [];
    }
  },
);

final referralProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final online = await ConnectivityService.isConnected();
  if (!online) {
    final cached = HiveService.dashboardBox.get('referral');
    if (cached != null) return toMap(cached);
    throw Exception('لا يوجد اتصال بالإنترنت ولا توجد بيانات محفوظة');
  }
  try {
    final response = await ref.read(apiClientProvider).get('/profile/referral');
    final data = toMap(response.data['data']);
    await HiveService.dashboardBox.put('referral', data);
    return data;
  } catch (_) {
    final cached = HiveService.dashboardBox.get('referral');
    if (cached != null) return toMap(cached);
    rethrow;
  }
});

class ServicesScreen extends ConsumerStatefulWidget {
  const ServicesScreen({super.key});

  @override
  ConsumerState<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends ConsumerState<ServicesScreen>
    with WidgetsBindingObserver {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(referralProvider);
    }
  }

  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => ref.invalidate(referralProvider),
    );
  }

  Future<void> _refresh() async {
    ref.invalidate(referralProvider);
    // Wait until the next frame so the provider has a chance to reload.
    await Future.delayed(const Duration(milliseconds: 300));
  }

  @override
  Widget build(BuildContext context) {
    final referral = ref.watch(referralProvider);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('خدمات العميل')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: AppColors.primary,
        child: referral.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => _error(() => ref.invalidate(referralProvider)),
          data: (data) => _referral(context, data),
        ),
      ),
    );
  }

  Widget _error(VoidCallback retry) => FutureBuilder(
    future: ConnectivityService.isConnected(),
    builder: (context, snapshot) {
      final isOffline = snapshot.data == false;
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isOffline
                  ? Icons.signal_wifi_statusbar_connected_no_internet_4_rounded
                  : Icons.error_outline_rounded,
              size: 64,
              color: AppColors.textLight,
            ),
            const SizedBox(height: 16),
            Text(
              isOffline
                  ? 'لا يوجد اتصال بالإنترنت'
                  : 'تعذّر تحميل البيانات',
              style: const TextStyle(
                fontFamily: 'Cairo',
                color: AppColors.textGray,
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: retry,
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );
    },
  );

  Widget _referral(BuildContext context, Map<String, dynamic> data) {
    final code = data['referral_code']?.toString() ?? '';
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.inputBg,
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Column(
            children: [
              Icon(
                Icons.card_giftcard_rounded,
                color: AppColors.accent,
                size: 42,
              ),
              SizedBox(height: 12),
              Text(
                'ادعُ أصدقاءك واربح عمولة',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 8),
              Text(
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
                onPressed: code.isEmpty
                    ? null
                    : () {
                        Clipboard.setData(ClipboardData(text: code));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('تم نسخ كود الدعوة')),
                        );
                      },
                icon: const Icon(Icons.copy_rounded, color: AppColors.primary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: code.isEmpty
              ? null
              : () {
                  Clipboard.setData(ClipboardData(text: code));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم نسخ كود الدعوة')),
                  );
                },
          icon: const Icon(Icons.copy_rounded),
          label: const Text('نسخ كود الدعوة'),
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
}
