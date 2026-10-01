import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/api/api_client.dart';
import '../../../../core/cache/hive_service.dart';
import '../../../../core/utils/connectivity_service.dart';
import '../../../../core/utils/json_helpers.dart';
import '../../../../core/utils/date_utils.dart';

final notificationsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final online = await ConnectivityService.isConnected();
  if (!online) {
    final cached = HiveService.notificationsBox.get('list');
    if (cached != null) return toMapList(cached);
    return [];
  }
  try {
    final api = ref.read(apiClientProvider);
    final res = await api.get('/notifications');
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
    final async = ref.watch(notificationsProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('الإشعارات'),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textDark,
        elevation: 0,
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Container(height: 1, color: AppColors.divider)),
        actions: [
          TextButton(
            onPressed: () async {
              await ref.read(apiClientProvider).post('/notifications/read-all');
              ref.invalidate(notificationsProvider);
            },
            child: const Text('قراءة الكل', style: TextStyle(fontFamily: 'Cairo', color: AppColors.primary)),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
            onPressed: () => ref.invalidate(notificationsProvider),
          ),
        ],
      ),
      body: async.when(
        loading: () => ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: 6,
          itemBuilder: (_, __) => Shimmer.fromColors(
            baseColor: const Color(0xFFE8ECF4),
            highlightColor: const Color(0xFFF5F7FD),
            child: Container(height: 80, margin: const EdgeInsets.only(bottom: 10), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14))),
          ),
        ),
        error: (_, __) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.notifications_off_outlined, size: 56, color: AppColors.textLight),
              const SizedBox(height: 12),
              const Text('تعذّر تحميل الإشعارات', style: TextStyle(fontFamily: 'Cairo', color: AppColors.textGray)),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: () => ref.invalidate(notificationsProvider), child: const Text('إعادة المحاولة')),
            ],
          ),
        ),
        data: (notifs) {
          if (notifs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_none_rounded, size: 64, color: AppColors.textLight),
                  SizedBox(height: 16),
                  Text('لا توجد إشعارات', style: TextStyle(fontFamily: 'Cairo', fontSize: 16, color: AppColors.textGray)),
                ],
              ),
            );
          }
          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () async => ref.invalidate(notificationsProvider),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: notifs.length,
              itemBuilder: (_, i) => _NotifCard(
              notif: notifs[i],
              onRead: () async {
                if (notifs[i]['read_at'] != null) return;
                await ref.read(apiClientProvider).post('/notifications/${notifs[i]['id']}/read');
                ref.invalidate(notificationsProvider);
              },
            ),
            ),
          );
        },
      ),
    );
  }
}

class _NotifCard extends StatelessWidget {
  final Map<String, dynamic> notif;
  final Future<void> Function() onRead;
  const _NotifCard({required this.notif, required this.onRead});

  @override
  Widget build(BuildContext context) {
    final isRead = notif['read_at'] != null;
    final date   = parseUtcToLocal(notif['created_at']);

    return InkWell(
      onTap: onRead,
      borderRadius: BorderRadius.circular(14),
      child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isRead ? Colors.white : AppColors.primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isRead ? AppColors.divider : AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(isRead ? Icons.notifications_outlined : Icons.notifications_active_rounded,
                color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notif['title'] ?? notif['data']?['title'] ?? 'إشعار',
                  style: TextStyle(fontFamily: 'Cairo', fontSize: 14, fontWeight: isRead ? FontWeight.w500 : FontWeight.bold, color: AppColors.textDark),
                ),
                const SizedBox(height: 4),
                Text(
                  notif['body'] ?? notif['data']?['body'] ?? '',
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, color: AppColors.textGray, height: 1.4),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (date != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${date.day}/${date.month}/${date.year}',
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, color: AppColors.textLight),
                  ),
                ],
              ],
            ),
          ),
          if (!isRead)
            Container(
              width: 8, height: 8, margin: const EdgeInsets.only(top: 4),
              decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
            ),
        ],
      ),
    ));
  }
}
