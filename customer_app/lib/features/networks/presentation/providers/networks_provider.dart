import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/api/api_client.dart';
import '../../../../core/cache/hive_service.dart';
import '../../../../core/models/user_model.dart';
import '../../../../core/utils/connectivity_service.dart';
import '../../../../core/utils/json_helpers.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

enum NetworkFilterMode {
  all,
  governorates,
  directorates,
  nearest,
  mostSelling,
  loan,
  favorite,
}

extension NetworkFilterModeX on NetworkFilterMode {
  bool get isLocation => this == NetworkFilterMode.governorates || this == NetworkFilterMode.directorates;
}

final networkSearchProvider = StateProvider<String>((ref) => '');
final networkFilterModeProvider = StateProvider<NetworkFilterMode>((ref) => NetworkFilterMode.all);
final networkRegionIdProvider = StateProvider<int?>((ref) => null);
final networkGovernorateIdProvider = StateProvider<int?>((ref) => null);
final networkDirectorateIdProvider = StateProvider<int?>((ref) => null);

final networksProvider = FutureProvider<List<Map<String, dynamic>>>(
  (ref) async {
    final search = ref.watch(networkSearchProvider);
    final mode = ref.watch(networkFilterModeProvider);
    final regionId = ref.watch(networkRegionIdProvider);
    final governorateId = ref.watch(networkGovernorateIdProvider);
    final directorateId = ref.watch(networkDirectorateIdProvider);
    final user = ref.watch(authProvider).user;

    final online = await ConnectivityService.isConnected();
    final cached = HiveService.networksBox.get('list');
    List<Map<String, dynamic>> list;

    if (online) {
      try {
        final api = ref.read(apiClientProvider);
        final res = await api.get('/networks', params: {'all': 1, 'scope': 'all'});
        list = toMapList(res.data['data'] ?? []);
        await HiveService.networksBox.put('list', list);
      } catch (_) {
        list = cached != null ? toMapList(cached) : [];
      }
    } else {
      list = cached != null ? toMapList(cached) : [];
    }

    return _applyClientFilters(
      list,
      mode,
      search,
      regionId: regionId,
      governorateId: governorateId,
      directorateId: directorateId,
      user: user,
    );
  },
);

List<Map<String, dynamic>> _applyClientFilters(
  List<Map<String, dynamic>> list,
  NetworkFilterMode mode,
  String search, {
  int? regionId,
  int? governorateId,
  int? directorateId,
  UserModel? user,
}) {
  var result = list;

  if (search.trim().isNotEmpty) {
    final s = search.trim().toLowerCase();
    result = result.where((n) => n['name'].toString().toLowerCase().contains(s) || n['code'].toString().toLowerCase().contains(s)).toList();
  }

  switch (mode) {
    case NetworkFilterMode.governorates:
      if (governorateId != null) {
        result = result.where((n) => (n['directorate_id'] as num?)?.toInt() == governorateId).toList();
      }
      break;
    case NetworkFilterMode.directorates:
      if (directorateId != null) {
        result = result.where((n) => (n['sub_directorate_id'] as num?)?.toInt() == directorateId).toList();
      }
      break;
    case NetworkFilterMode.nearest:
      if (user != null) {
        final candidates = <Map<String, dynamic>>[];
        if (user.subDirectorateId != null) {
          candidates.addAll(result.where((n) => (n['sub_directorate_id'] as num?)?.toInt() == user.subDirectorateId));
        }
        if (candidates.isEmpty && user.directorateId != null) {
          candidates.addAll(result.where((n) => (n['directorate_id'] as num?)?.toInt() == user.directorateId));
        }
        if (candidates.isEmpty && user.regionId != null) {
          candidates.addAll(result.where((n) => (n['region_id'] as num?)?.toInt() == user.regionId));
        }
        result = candidates;
      }
      break;
    case NetworkFilterMode.loan:
      result = result.where((n) => n['supports_credit'] == true).toList();
      break;
    case NetworkFilterMode.favorite:
      result = result.where((n) => n['is_favorite'] == true).toList();
      break;
    case NetworkFilterMode.mostSelling:
      result = result
          .where((n) => ((n['sales_count'] ?? 0) as num) > 0)
          .toList()
        ..sort(
          (a, b) => ((b['sales_count'] ?? 0) as num).compareTo((a['sales_count'] ?? 0) as num),
        );
      break;
    case NetworkFilterMode.all:
      break;
  }

  return result;
}

final networkDetailProvider = FutureProvider.family<Map<String, dynamic>, int>((
  ref,
  networkId,
) async {
  final cacheKey = 'network_detail_$networkId';
  try {
    final api = ref.read(apiClientProvider);
    final res = await api.get('/networks/$networkId');
    final data = res.data['data'];
    if (data is! Map<String, dynamic>) return toMap(data);
    await HiveService.networksBox.put(cacheKey, data);
    return data;
  } catch (_) {
    final online = await ConnectivityService.isConnected();
    if (!online) {
      final cached = HiveService.networksBox.get(cacheKey);
      if (cached != null) {
        if (cached is Map<String, dynamic>) return cached;
        return toMap(cached);
      }
    }
    rethrow;
  }
});

final networkCardsProvider = FutureProvider.family<List<Map<String, dynamic>>, int>((
  ref,
  networkId,
) async {
  final api = ref.read(apiClientProvider);
  final res = await api.get('/networks/$networkId/categories');
  return toMapList(res.data['data'] ?? []);
});

final favoriteNetworksProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final api = ref.read(apiClientProvider);
  final res = await api.get('/favorites');
  return toMapList(res.data['data'] ?? []);
});

Future<bool> toggleNetworkFavorite(WidgetRef ref, int networkId) async {
  final res = await ref.read(apiClientProvider).post('/networks/$networkId/favorite');
  ref.invalidate(networksProvider);
  ref.invalidate(favoriteNetworksProvider);
  return res.data['success'] == true;
}

Future<List<Map<String, dynamic>>> loadRegions(WidgetRef ref) async {
  final cached = HiveService.networksBox.get('regions');
  try {
    final res = await ref.read(apiClientProvider).get('/regions');
    final list = toMapList(res.data['data'] ?? []);
    await HiveService.networksBox.put('regions', list);
    return list;
  } catch (_) {
    if (cached != null) return toMapList(cached);
    return [];
  }
}

Future<List<Map<String, dynamic>>> loadGovernoratesByRegion(WidgetRef ref, int regionId) async {
  final cacheKey = 'governorates_$regionId';
  final cached = HiveService.networksBox.get(cacheKey);
  try {
    final res = await ref.read(apiClientProvider).get('/regions/$regionId/directorates');
    final list = toMapList(res.data['data'] ?? []);
    await HiveService.networksBox.put(cacheKey, list);
    return list;
  } catch (_) {
    if (cached != null) return toMapList(cached);
    return [];
  }
}

Future<List<Map<String, dynamic>>> loadSubDirectoratesByGovernorate(WidgetRef ref, int governorateId) async {
  final cacheKey = 'sub_directorates_$governorateId';
  final cached = HiveService.networksBox.get(cacheKey);
  try {
    final res = await ref.read(apiClientProvider).get('/directorates/$governorateId/sub-directorates');
    final list = toMapList(res.data['data'] ?? []);
    await HiveService.networksBox.put(cacheKey, list);
    return list;
  } catch (_) {
    if (cached != null) return toMapList(cached);
    return [];
  }
}
