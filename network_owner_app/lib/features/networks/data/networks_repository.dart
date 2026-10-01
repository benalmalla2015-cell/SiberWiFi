import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../core/cache/hive_service.dart';
import '../../../core/utils/connectivity_service.dart';

final networksRepositoryProvider = Provider<NetworksRepository>(
  (ref) => NetworksRepository(ref.read(apiClientProvider)),
);

List<Map<String, dynamic>> _castCachedList(dynamic cached) {
  if (cached == null) return [];
  if (cached is List) {
    return cached.map((item) {
      if (item is Map<String, dynamic>) return item;
      if (item is Map) return Map<String, dynamic>.from(item);
      return <String, dynamic>{};
    }).toList();
  }
  return [];
}

class NetworksRepository {
  final ApiClient _api;
  NetworksRepository(this._api);

  Future<List<Map<String, dynamic>>> getNetworks() async {
    try {
      final res = await _api.get('/network-owner/networks');
      final list = List<Map<String, dynamic>>.from(res.data['data'] ?? []);
      await HiveService.networksBox.put('list', list);
      return list;
    } catch (e) {
      final cached = HiveService.networksBox.get('list');
      if (cached != null) return _castCachedList(cached);
      return [];
    }
  }

  Future<Map<String, dynamic>> createNetwork(dynamic data) async {
    final res = await _api.post('/network-owner/networks', data: data);
    return res.data;
  }

  Future<Map<String, dynamic>> updateNetwork(int id, dynamic data) async {
    if (data is FormData) {
      data.fields.add(const MapEntry('_method', 'PUT'));
      final res = await _api.post('/network-owner/networks/$id', data: data);
      return res.data;
    }
    final res = await _api.put('/network-owner/networks/$id', data: data);
    return res.data;
  }

  Future<Map<String, dynamic>?> getMyNetwork() async {
    final res = await _api.get('/auth/my-network');
    if (res.data['success'] == true) {
      return Map<String, dynamic>.from(res.data['data']);
    }
    return null;
  }

  Future<Map<String, dynamic>> updateMyNetwork(dynamic data) async {
    final res = await _api.post('/auth/my-network', data: data);
    return res.data;
  }

  Future<List<Map<String, dynamic>>> getCards({
    int? networkId,
    String? status,
  }) async {
    if (networkId == null) {
      // When "الكل" is selected, fetch cards for each network and combine
      try {
        final networks = await getNetworks();
        final List<Map<String, dynamic>> allCards = [];
        for (final network in networks) {
          final nId = network['id'];
          if (nId == null) continue;
          final params = <String, dynamic>{
            'network_id': nId,
            'per_page': 10000,
          };
          try {
            final res = await _api.get('/network-owner/cards', params: params);
            final list = List<Map<String, dynamic>>.from(
              res.data['data'] ?? [],
            );
            allCards.addAll(list);
          } catch (_) {}
        }
        await HiveService.networksBox.put('cards_all_combined', allCards);
        if (status != null) {
          return allCards.where((c) => c['status'] == status).toList();
        }
        return allCards;
      } catch (_) {
        final online = await ConnectivityService.isConnected();
        if (!online) {
          final cached = HiveService.networksBox.get('cards_all_combined');
          if (cached != null) {
            final allCards = _castCachedList(cached);
            if (status != null) {
              return allCards.where((c) => c['status'] == status).toList();
            }
            return allCards;
          }
        }
        return [];
      }
    }

    // Single network selected
    final params = <String, dynamic>{};
    params['network_id'] = networkId;
    if (status != null) params['status'] = status;
    params['per_page'] = 10000;

    try {
      final res = await _api.get('/network-owner/cards', params: params);
      final list = List<Map<String, dynamic>>.from(res.data['data'] ?? []);
      final cacheKey = 'cards_${networkId}_${status ?? 'all'}';
      await HiveService.networksBox.put(cacheKey, list);
      return list;
    } catch (_) {
      final online = await ConnectivityService.isConnected();
      if (!online) {
        final cacheKey = 'cards_${networkId}_${status ?? 'all'}';
        final cached = HiveService.networksBox.get(cacheKey);
        if (cached != null) return _castCachedList(cached);
      }
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getCategories() async {
    try {
      final res = await _api.get('/network-owner/cards/categories');
      final list = List<Map<String, dynamic>>.from(res.data['data'] ?? []);
      await HiveService.networksBox.put('categories', list);
      return list;
    } catch (_) {
      final online = await ConnectivityService.isConnected();
      if (!online) {
        final cached = HiveService.networksBox.get('categories');
        if (cached != null) return _castCachedList(cached);
      }
      return [];
    }
  }

  Future<Map<String, dynamic>> uploadCards(dynamic data) async {
    final res = await _api.post('/network-owner/cards/upload', data: data);
    return res.data;
  }

  Future<Map<String, dynamic>> createCategory(Map<String, dynamic> data) async {
    final res = await _api.post('/network-owner/cards/categories', data: data);
    return res.data;
  }

  Future<Map<String, dynamic>> updateCategory(
    int id,
    Map<String, dynamic> data,
  ) async {
    final res = await _api.put(
      '/network-owner/cards/categories/$id',
      data: data,
    );
    return res.data;
  }

  /// Dedicated endpoint for toggling "سلفني" (advance/lending) on a category
  /// and setting the per-customer card limit.
  Future<Map<String, dynamic>> updateAdvanceSettings(
    int id, {
    required bool advanceEnabled,
    int? advanceMaxPerCustomer,
  }) async {
    final res = await _api.put(
      '/network-owner/cards/categories/$id/advance-settings',
      data: {
        'advance_enabled': advanceEnabled ? 1 : 0,
        if (advanceMaxPerCustomer != null) 'advance_max_per_customer': advanceMaxPerCustomer,
      },
    );
    return res.data;
  }
}
