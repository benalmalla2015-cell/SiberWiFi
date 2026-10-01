import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/api/api_client.dart';
import '../../../../core/cache/hive_service.dart';
import '../../../../core/utils/connectivity_service.dart';
import '../../../../core/utils/json_helpers.dart';

final homeProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final online = await ConnectivityService.isConnected();
  if (!online) {
    final cached = HiveService.dashboardBox.get('home');
    if (cached != null) return toMap(cached);
    return {};
  }
  try {
    final api = ref.read(apiClientProvider);
    final res = await api.get('/home');
    final data = toMap(res.data['data'] ?? res.data);
    await HiveService.dashboardBox.put('home', data);
    return data;
  } catch (_) {
    final cached = HiveService.dashboardBox.get('home');
    if (cached != null) return toMap(cached);
    return {};
  }
});

final dailyOffersProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final online = await ConnectivityService.isConnected();
  if (!online) {
    final cached = HiveService.dashboardBox.get('daily_offers');
    if (cached != null) return toMapList(cached);
    return [];
  }
  try {
    final api = ref.read(apiClientProvider);
    final response = await api.get('/daily-offers');
    final offers = toMapList(response.data['data'] ?? response.data);
    await HiveService.dashboardBox.put('daily_offers', offers);
    return offers;
  } catch (_) {
    final cached = HiveService.dashboardBox.get('daily_offers');
    if (cached != null) return toMapList(cached);
    return [];
  }
});
