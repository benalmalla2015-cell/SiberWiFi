import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/api/api_client.dart';
import '../../../../core/cache/hive_service.dart';
import '../../../../core/utils/connectivity_service.dart';
import '../../../../core/utils/json_helpers.dart';

final reviewsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  // Always hit the live backend first; only fall back to local cache when
  // the device is truly offline or the API call fails.
  try {
    final api  = ref.read(apiClientProvider);
    final res  = await api.get('/network-owner/ratings');
    final list = toMapList(res.data['data']);
    await HiveService.networksBox.put('reviews', list);
    return list;
  } catch (_) {
    final online = await ConnectivityService.isConnected();
    if (!online) {
      final c = HiveService.networksBox.get('reviews');
      if (c != null) return toMapList(c);
    }
    rethrow;
  }
});

class ReviewsScreen extends ConsumerWidget {
  const ReviewsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviewsAsync = ref.watch(reviewsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('التقييمات')),
      body: reviewsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error:   (e, _) => FutureBuilder(
          future: ConnectivityService.isConnected(),
          builder: (context, snapshot) {
            final isOffline = snapshot.data == false;
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isOffline 
                        ? Icons.signal_wifi_statusbar_connected_no_internet_4_rounded
                        : Icons.error_outline_rounded,
                    size: 64,
                    color: AppColors.textLight,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isOffline 
                        ? 'لا يوجد اتصال بالإنترنت'
                        : 'تعذّر تحميل التقييمات',
                    style: const TextStyle(color: AppColors.textGray, fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () => ref.invalidate(reviewsProvider),
                    child: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            );
          },
        ),
        data: (reviews) {
          if (reviews.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.star_border, size: 64, color: AppColors.divider),
                  SizedBox(height: 12),
                  Text('لا توجد تقييمات بعد', style: TextStyle(color: AppColors.textGray, fontSize: 16)),
                ],
              ),
            );
          }

          final avgRating = reviews.fold<double>(0, (s, r) => s + (r['rating'] ?? 0).toDouble()) / reviews.length;

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(reviewsProvider),
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _RatingSummary(avg: avgRating, total: reviews.length)),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => _ReviewCard(key: ValueKey(reviews[i]['id']), review: reviews[i]),
                      childCount: reviews.length,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _RatingSummary extends StatelessWidget {
  final double avg;
  final int total;
  const _RatingSummary({required this.avg, required this.total});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF16235F), Color(0xFF1E2D7D), Color(0xFF2A3A9A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: [0.0, 0.5, 1.0],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Color(0x401E2D7D), blurRadius: 14, offset: const Offset(0, 5))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('متوسط التقييم', style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(avg.toStringAsFixed(1), style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold)),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 6, right: 4),
                      child: Text('/5', style: TextStyle(color: Colors.white60, fontSize: 16)),
                    ),
                  ],
                ),
                _StarRow(rating: avg),
                const SizedBox(height: 4),
                Text('$total تقييم', style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          const Icon(Icons.star, color: Colors.amber, size: 80),
        ],
      ),
    );
  }
}

class _StarRow extends StatelessWidget {
  final double rating;
  const _StarRow({required this.rating});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        if (i < rating.floor()) return const Icon(Icons.star, color: Colors.amber, size: 16);
        if (i < rating) return const Icon(Icons.star_half, color: Colors.amber, size: 16);
        return const Icon(Icons.star_border, color: Colors.white38, size: 16);
      }),
    );
  }
}

class _ReviewCard extends ConsumerWidget {
  final Map<String, dynamic> review;
  const _ReviewCard({super.key, required this.review});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rating     = (review['rating'] ?? 0).toDouble();
    final comment    = review['comment'] ?? review['review'] ?? '';
    final clientName = review['user']?['name'] ?? review['user_name'] ?? review['client_name'] ?? 'عميل';
    final network    = review['network']?['name'] ?? review['network_name'] ?? '';
    final date       = review['created_at']?.toString().substring(0, 10) ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color: AppColors.lightBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.person, color: AppColors.lightBlue, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(clientName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    if (network.isNotEmpty) Text(network, style: const TextStyle(color: AppColors.textGray, fontSize: 11)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(5, (i) => Icon(
                      i < rating ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                      size: 14,
                    )),
                  ),
                  Text(date, style: const TextStyle(color: AppColors.textGray, fontSize: 10)),
                ],
              ),
            ],
          ),
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Divider(height: 1, color: AppColors.divider),
            const SizedBox(height: 10),
            Text(comment, style: const TextStyle(fontSize: 13, color: AppColors.textDark, height: 1.5)),
          ],
          const SizedBox(height: 12),
          if ((review['owner_reply']?.toString().trim() ?? '').isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ردك', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(review['owner_reply'].toString(), style: const TextStyle(fontSize: 13, height: 1.5)),
                ],
              ),
            )
          else
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => _showReplySheet(context, ref),
                icon: const Icon(Icons.reply, size: 18),
                label: const Text('الرد على التقييم'),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showReplySheet(BuildContext context, WidgetRef ref) async {
    final reply = await showDialog<String>(
      context: context,
      builder: (dialogContext) => const _ReplyDialog(),
    );

    if (reply == null || reply.isEmpty) return;

    try {
      final response = await ref.read(apiClientProvider).post(
        '/network-owner/ratings/${review['id']}/reply',
        data: {'reply': reply},
      );

      if (response.data['success'] == true) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم إرسال الرد للعميل'), backgroundColor: AppColors.success),
          );
        }
        // Defer provider invalidation until after the current frame so the
        // reply dialog is fully disposed and the widget tree is stable.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) ref.invalidate(reviewsProvider);
        });
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.data['message'] ?? 'تعذر إرسال الرد'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } on DioException catch (e) {
      String msg = 'تعذر إرسال الرد';
      if (e.response?.data is Map) {
        final data = e.response!.data as Map;
        msg = data['message']?.toString() ??
            (data['errors']?.toString().isNotEmpty == true
                ? data['errors'].toString()
                : msg);
      } else if (e.response?.statusCode != null) {
        msg = 'خطأ من الخادم (${e.response!.statusCode}). تأكد من اتصالك وحاول مجدداً.';
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: AppColors.error),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذر إرسال الرد: حدث خطأ في الاتصال'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
}

class _ReplyDialog extends StatefulWidget {
  const _ReplyDialog();

  @override
  State<_ReplyDialog> createState() => _ReplyDialogState();
}

class _ReplyDialogState extends State<_ReplyDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('الرد على التقييم'),
      scrollable: true,
      content: TextField(
        controller: _controller,
        maxLines: 4,
        minLines: 2,
        decoration: const InputDecoration(labelText: 'اكتب ردك للعميل'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('إرسال'),
        ),
      ],
    );
  }
}
