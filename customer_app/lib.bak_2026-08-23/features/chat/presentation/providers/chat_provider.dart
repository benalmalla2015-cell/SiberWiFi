import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/api/api_client.dart';
import '../../../../core/cache/hive_service.dart';
import '../../../../core/utils/connectivity_service.dart';
import '../../../../core/utils/json_helpers.dart';

final chatMessagesProvider = FutureProvider.family<List<Map<String, dynamic>>, int>((ref, networkId) async {
  final online = await ConnectivityService.isConnected();
  if (!online) {
    final cached = HiveService.messagesBox.get('network_$networkId');
    if (cached != null) return toMapList(cached);
    return [];
  }
  try {
    final api = ref.read(apiClientProvider);
    final res = await api.get('/chat/$networkId');
    final list = toMapList(res.data['data'] ?? []);
    await HiveService.messagesBox.put('network_$networkId', list);
    return list;
  } catch (_) {
    final cached = HiveService.messagesBox.get('network_$networkId');
    if (cached != null) return toMapList(cached);
    return [];
  }
});
