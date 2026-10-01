import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/chat_provider.dart';

class ConversationsScreen extends ConsumerWidget {
  const ConversationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversations = ref.watch(conversationsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('رسائل العملاء')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(conversationsProvider),
        child: conversations.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              const SizedBox(height: 220),
              Center(child: Text('تعذر تحميل الرسائل: $error')),
            ],
          ),
          data: (items) {
            if (items.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 180),
                  Icon(Icons.forum_outlined, size: 64, color: AppColors.divider),
                  SizedBox(height: 12),
                  Center(
                    child: Text(
                      'لا توجد رسائل من العملاء',
                      style: TextStyle(color: AppColors.textGray),
                    ),
                  ),
                ],
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, index) {
                final item = items[index];
                final networkId = item['network_id'] as int? ?? 0;
                final contactId = item['contact_id'] as int? ?? 0;
                final unreadCount = item['unread_count'] as int? ?? 0;
                final timestamp = item['last_message_at']?.toString() ?? '';

                return Material(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: networkId > 0 && contactId > 0
                        ? () => context.push(
                              '/conversations/$networkId/$contactId',
                              extra: {
                                'network_name': item['network_name']?.toString() ?? 'شبكة',
                                'contact_name': item['contact_name']?.toString() ?? 'عميل',
                              },
                            )
                        : null,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.divider),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                            child: const Icon(Icons.person_outline, color: AppColors.primary),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item['contact_name']?.toString() ?? 'عميل',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  item['network_name']?.toString() ?? '',
                                  style: const TextStyle(fontSize: 11, color: AppColors.primary),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  item['last_message']?.toString() ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12, color: AppColors.textGray),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                timestamp.length >= 16 ? timestamp.substring(0, 16) : timestamp,
                                style: const TextStyle(fontSize: 10, color: AppColors.textGray),
                              ),
                              if (unreadCount > 0) ...[
                                const SizedBox(height: 6),
                                CircleAvatar(
                                  radius: 10,
                                  backgroundColor: AppColors.accent,
                                  child: Text(
                                    '$unreadCount',
                                    style: const TextStyle(color: Colors.white, fontSize: 10),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
