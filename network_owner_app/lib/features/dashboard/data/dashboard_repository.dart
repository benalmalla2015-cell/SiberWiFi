import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../core/cache/hive_service.dart';
import '../../../core/utils/connectivity_service.dart';

final dashboardRepositoryProvider = Provider<DashboardRepository>(
  (ref) => DashboardRepository(ref.read(apiClientProvider)),
);

class DashboardRepository {
  final ApiClient _api;
  DashboardRepository(this._api);

  Future<Map<String, dynamic>> getDashboard() async {
    final online = await ConnectivityService.isConnected();
    if (!online) {
      final cached = HiveService.dashboardBox.get('data');
      if (cached != null) return Map<String, dynamic>.from(cached);
      return {};
    }
    try {
      final res = await _api.get('/network-owner/dashboard');
      final data = Map<String, dynamic>.from(res.data['data'] ?? res.data);
      await HiveService.dashboardBox.put('data', data);
      return data;
    } catch (_) {
      final cached = HiveService.dashboardBox.get('data');
      if (cached != null) return Map<String, dynamic>.from(cached);
      return {};
    }
  }

  Future<Map<String, dynamic>> getStats(String period) async {
    final online = await ConnectivityService.isConnected();
    if (!online) {
      final cached = HiveService.dashboardBox.get('stats_$period');
      if (cached != null) return Map<String, dynamic>.from(cached);
      return {};
    }
    try {
      final res = await _api.get('/network-owner/stats', params: {'period': period});
      final data = Map<String, dynamic>.from(res.data['data'] ?? res.data);
      await HiveService.dashboardBox.put('stats_$period', data);
      return data;
    } catch (_) {
      final cached = HiveService.dashboardBox.get('stats_$period');
      if (cached != null) return Map<String, dynamic>.from(cached);
      return {};
    }
  }
}
