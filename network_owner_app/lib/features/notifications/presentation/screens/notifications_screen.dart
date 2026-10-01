import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/api/api_client.dart';
import '../../../../core/cache/hive_service.dart';
import '../../../../core/utils/connectivity_service.dart';
import '../../../../core/utils/json_helpers.dart';

final notificationsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final online = await ConnectivityService.isConnected();
  if (!online) {
    final cached = HiveService.notificationsBox.get('list');
    if (cached != null) return toMapList(cached);
    return [];
  }
  try {
    final api = ref.read(apiClientProvider);
    final res = await api.get('/network-owner/notifications');
    final list = toMapList(res.data['data'] ?? []);
    await HiveService.notificationsBox.put('list', list);
    return list;
  } catch (_) {
    final cached = HiveService.notificationsBox.get('list');
    if (cached != null) return toMapList(cached);
    return [];
  }
});

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifs = ref.watch(notificationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('الإشعارات'),
        actions: [
          TextButton(
            onPressed: () async {
              try {
                final api = ref.read(apiClientProvider);
                await api.post('/network-owner/notifications/read-all');
                ref.invalidate(notificationsProvider);
              } catch (_) {}
            },
            child: const Text('قراءة الكل', style: TextStyle(color: Colors.white, fontSize: 13)),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(notificationsProvider),
        child: notifs.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error:   (e, _) => Center(child: Text('خطأ: $e')),
          data:    (list) => list.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.notifications_none, size: 64, color: AppColors.textGray),
                      SizedBox(height: 12),
                      Text('لا توجد إشعارات', style: TextStyle(color: AppColors.textGray)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) => _NotificationCard(notif: list[i], onRead: () async {
                    try {
                      final api = ref.read(apiClientProvider);
                      await api.post('/network-owner/notifications/${list[i]['id']}/read');
                      ref.invalidate(notificationsProvider);
                    } catch (_) {}
                  }),
                ),
        ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final Map<String, dynamic> notif;
  final VoidCallback onRead;
  const _NotificationCard({required this.notif, required this.onRead});

  IconData _typeIcon(String? type) {
    switch (type) {
      case 'payout_approved':   return Icons.check_circle_outline;
      case 'payout_paid':       return Icons.payments_outlined;
      case 'payout_rejected':   return Icons.cancel_outlined;
      case 'network_approved':  return Icons.wifi;
      case 'network_rejected':  return Icons.wifi_off;
      default:                  return Icons.notifications_outlined;
    }
  }

  Color _typeColor(String? type) {
    if (type?.contains('rejected') == true) return AppColors.error;
    if (type?.contains('paid') == true)     return AppColors.success;
    if (type?.contains('approved') == true) return AppColors.lightBlue;
    return AppColors.primary;
  }

  @override
  Widget build(BuildContext context) {
    final isRead  = notif['is_read'] == true || notif['read_at'] != null;
    final type    = notif['data']?['type'] as String? ?? notif['type'] as String?;
    final image   = notif['image'] ?? notif['data']?['image'];

    return InkWell(
      onTap: isRead ? null : onRead,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isRead ? Colors.white : AppColors.primary.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isRead ? AppColors.divider : AppColors.primary.withValues(alpha: 0.18),
            width: isRead ? 1.0 : 1.5,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (image != null && image.toString().isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(
                  imageUrl: image.toString(),
                  width: 60,
                  height: 60,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(
                    width: 60,
                    height: 60,
                    color: AppColors.primary.withValues(alpha: 0.10),
                    child: const Icon(Icons.image, color: AppColors.textGray),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    width: 60,
                    height: 60,
                    color: AppColors.primary.withValues(alpha: 0.10),
                    child: Icon(_typeIcon(type), color: _typeColor(type)),
                  ),
                ),
              )
            else
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _typeColor(type).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_typeIcon(type), color: _typeColor(type), size: 22),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(notif['title'] ?? '', style: TextStyle(fontWeight: isRead ? FontWeight.normal : FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(notif['body'] ?? '', style: const TextStyle(color: AppColors.textGray, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(notif['created_at'] ?? '', style: const TextStyle(fontSize: 10, color: AppColors.textGray)),
                ],
              ),
            ),
            if (!isRead)
              Container(width: 8, height: 8, margin: const EdgeInsets.only(top: 4),
                  decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle)),
          ],
        ),
      ),
    );
  }
}
