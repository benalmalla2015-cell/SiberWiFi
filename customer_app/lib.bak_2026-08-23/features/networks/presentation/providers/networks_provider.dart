import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/api/api_client.dart';
import '../../../../core/cache/hive_service.dart';
import '../../../../core/utils/connectivity_service.dart';
import '../../../../core/utils/json_helpers.dart';

final networkSearchProvider = StateProvider<String>((ref) => '');
final networkBorrowOnlyProvider = StateProvider<bool>((ref) => false);
final networkSortBySalesProvider = StateProvider<bool>((ref) => false);
final networkFavoritesOnlyProvider = StateProvider<bool>((ref) => false);

final networksProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final search = ref.watch(networkSearchProvider);
  final borrowOnly = ref.watch(networkBorrowOnlyProvider);
  final sortBySales = ref.watch(networkSortBySalesProvider);
  final favoritesOnly = ref.watch(networkFavoritesOnlyProvider);
  final online = await ConnectivityService.isConnected();
  if (!online) {
    final cached = HiveService.networksBox.get('list');
    if (cached != null) return toMapList(cached);
    return [];
  }
  try {
    final api = ref.read(apiClientProvider);
    final res = await api.get(
      favoritesOnly ? '/favorites' : '/networks',
      params: search.isEmpty ? null : {'search': search},
    );
    final list = toMapList(res.data['data'] ?? []);
    final filtered = borrowOnly
        ? list.where((network) => network['supports_credit'] == true).toList()
        : list;
    if (sortBySales)
      filtered.sort(
        (a, b) => ((b['sales_count'] ?? 0) as num).compareTo(
          (a['sales_count'] ?? 0) as num,
        ),
      );
    await HiveService.networksBox.put('list', filtered);
    return filtered;
  } catch (_) {
    final cached = HiveService.networksBox.get('list');
    if (cached != null) return toMapList(cached);
    return [];
  }
});

final favoriteNetworksProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final api = ref.read(apiClientProvider);
  final res = await api.get('/favorites');
  return toMapList(res.data['data'] ?? []);
});

Future<bool> toggleNetworkFavorite(WidgetRef ref, int networkId) async {
  final res = await ref
      .read(apiClientProvider)
      .post('/networks/$networkId/favorite');
  ref.invalidate(networksProvider);
  ref.invalidate(favoriteNetworksProvider);
  ref.invalidate(networkDetailProvider(networkId));
  return res.data['is_favorite'] == true;
}

final networkDetailProvider = FutureProvider.family<Map<String, dynamic>, int>((
  ref,
  id,
) async {
  final online = await ConnectivityService.isConnected();
  if (!online) {
    final cached = HiveService.networksBox.get('detail_$id');
    if (cached != null) return toMap(cached);
    return {};
  }
  try {
    final api = ref.read(apiClientProvider);
    final res = await api.get('/networks/$id');
    final data = toMap(res.data['data'] ?? res.data);
    await HiveService.networksBox.put('detail_$id', data);
    return data;
  } catch (_) {
    final cached = HiveService.networksBox.get('detail_$id');
    if (cached != null) return toMap(cached);
    return {};
  }
});

final networkCardsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, int>((
      ref,
      networkId,
    ) async {
      final online = await ConnectivityService.isConnected();
      if (!online) {
        final cached = HiveService.cardsBox.get('network_$networkId');
        if (cached != null) return toMapList(cached);
        return [];
      }
      try {
        final api = ref.read(apiClientProvider);
        final res = await api.get('/networks/$networkId/categories');
        final list = toMapList(res.data['data'] ?? []);
        await HiveService.cardsBox.put('network_$networkId', list);
        return list;
      } catch (_) {
        final cached = HiveService.cardsBox.get('network_$networkId');
        if (cached != null) return toMapList(cached);
        return [];
      }
    });
