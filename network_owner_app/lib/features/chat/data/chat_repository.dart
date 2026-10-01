import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../core/cache/hive_service.dart';
import '../../../core/utils/connectivity_service.dart';

final chatRepositoryProvider = Provider<ChatRepository>(
  (ref) => ChatRepository(ref.read(apiClientProvider)),
);

class ChatRepository {
  final ApiClient _api;

  ChatRepository(this._api);

  Future<List<Map<String, dynamic>>> getConversations() async {
    final online = await ConnectivityService.isConnected();
    if (!online) {
      final cached = HiveService.networksBox.get('conversations');
      if (cached != null) return _castList(cached);
      throw 'لا يوجد اتصال بالإنترنت';
    }
    try {
      final response = await _api.get('/network-owner/conversations');
      final list = List<Map<String, dynamic>>.from(response.data['data'] ?? []);
      await HiveService.networksBox.put('conversations', list);
      return list;
    } on DioException catch (e) {
      final cached = HiveService.networksBox.get('conversations');
      if (cached != null) return _castList(cached);
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout) {
        throw 'لا يوجد اتصال بالإنترنت';
      }
      throw 'تعذر تحميل الرسائل';
    }
  }

  Future<List<Map<String, dynamic>>> getMessages({
    required int networkId,
    required int contactId,
  }) async {
    final online = await ConnectivityService.isConnected();
    if (!online) {
      throw 'لا يوجد اتصال بالإنترنت';
    }
    try {
      final response = await _api.get(
        '/chat/$networkId',
        params: {'contact_id': contactId},
      );
      return List<Map<String, dynamic>>.from(response.data['data'] ?? []);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout) {
        throw 'لا يوجد اتصال بالإنترنت';
      }
      throw 'تعذر تحميل الرسائل';
    }
  }

  Future<void> sendMessage({
    required int networkId,
    required int receiverId,
    required String message,
    String? imagePath,
  }) async {
    final data = imagePath == null
        ? {'receiver_id': receiverId, 'message': message}
        : FormData.fromMap({
            'receiver_id': receiverId,
            'message': message,
            'image': await MultipartFile.fromFile(imagePath),
          });
    await _api.post('/chat/$networkId', data: data);
  }

  List<Map<String, dynamic>> _castList(dynamic cached) {
    if (cached is List) {
      return cached.map((item) {
        if (item is Map<String, dynamic>) return item;
        if (item is Map) return Map<String, dynamic>.from(item);
        return <String, dynamic>{};
      }).toList();
    }
    return [];
  }
}
