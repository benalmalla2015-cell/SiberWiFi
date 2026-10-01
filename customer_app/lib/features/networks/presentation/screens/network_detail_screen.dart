import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/api/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/connectivity_service.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../chat/presentation/screens/chat_screen.dart';
import '../providers/networks_provider.dart';

class NetworkDetailScreen extends ConsumerWidget {
  final int networkId;
  const NetworkDetailScreen({super.key, required this.networkId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(networkDetailProvider(networkId));

    return Scaffold(
      backgroundColor: Colors.white,
      body: async.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (e, _) => FutureBuilder(
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
                        : 'تعذّر التحميل',
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      color: AppColors.textGray,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () =>
                        ref.invalidate(networkDetailProvider(networkId)),
                    child: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            );
          },
        ),
        data: (net) => _buildContent(context, net, ref),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    Map<String, dynamic> net,
    WidgetRef ref,
  ) {
    final rating = (net['average_rating'] ?? 0.0).toDouble();
    final reviews = net['ratings_count'] ?? 0;
    final imageUrl = net['cover_image_url'] ?? net['logo_url'];

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 200,
          pinned: true,
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: Icon(
                net['is_favorite'] == true
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
              ),
              onPressed: () async {
                final isFavorite = await toggleNetworkFavorite(ref, networkId);
                if (context.mounted)
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        isFavorite
                            ? 'تمت الإضافة إلى المفضلة'
                            : 'تمت الإزالة من المفضلة',
                      ),
                    ),
                  );
              },
            ),
          ],
          flexibleSpace: FlexibleSpaceBar(
            title: Text(
              net['name'] ?? '',
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            background: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.primaryDark,
                    AppColors.primary,
                    Color(0xFF243490),
                  ],
                ),
              ),
              child: imageUrl == null || imageUrl.toString().isEmpty
                  ? const Center(
                      child: Icon(
                        Icons.wifi_rounded,
                        size: 72,
                        color: Colors.white38,
                      ),
                    )
                  : CachedNetworkImage(
                      imageUrl: imageUrl.toString(),
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => const Center(
                        child: Icon(
                          Icons.wifi_rounded,
                          size: 72,
                          color: Colors.white38,
                        ),
                      ),
                    ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.location_on_rounded,
                      color: AppColors.accent,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        net['directorate'] ??
                            net['region'] ??
                            net['location'] ??
                            '',
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 14,
                          color: AppColors.textGray,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    ...List.generate(
                      5,
                      (i) => Icon(
                        i < rating.round()
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        size: 20,
                        color: const Color(0xFFF59E0B),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${rating.toStringAsFixed(1)} ($reviews تقييم)',
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        color: AppColors.textGray,
                      ),
                    ),
                  ],
                ),
                if (net['currency_converted'] == true && net['currency_note'] != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.currency_exchange_rounded, size: 18, color: AppColors.success),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            net['currency_note'].toString(),
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12,
                              color: AppColors.success,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (net['description'] != null &&
                    net['description'].toString().isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.inputBg,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      net['description'],
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 14,
                        color: AppColors.textDark,
                        height: 1.6,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                AppButton(
                  label: 'عرض كروت الشحن',
                  icon: Icons.credit_card_rounded,
                  onPressed: () => GoRouter.of(context).go('/networks/$networkId/cards'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _NetworkActionButton(
                        icon: Icons.chat_bubble_outline_rounded,
                        label: 'تواصل',
                        color: AppColors.primary,
                        onTap: () => _openChat(context, net['name'] ?? ''),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _NetworkActionButton(
                        icon: Icons.star_outline_rounded,
                        label: 'تقييم',
                        color: AppColors.primary,
                        onTap: () => _showRatingSheet(context, ref),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _NetworkActionButton(
                        icon: Icons.report_outlined,
                        label: 'بلاغ',
                        color: AppColors.accent,
                        onTap: () => _showReportSheet(context, ref),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _openChat(BuildContext context, String networkName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ChatScreen(networkId: networkId, networkName: networkName),
      ),
    );
  }

  void _showRatingSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _RatingSheet(networkId: networkId),
    );
  }

  void _showReportSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _ReportSheet(networkId: networkId),
    );
  }
}

/// Icon-over-label action button used for the "تواصل / تقييم / بلاغ" row.
/// Using a fixed-height column (instead of OutlinedButton.icon's internal
/// Row) avoids the label wrapping unpredictably when different icon glyphs
/// have different intrinsic widths.
class _NetworkActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _NetworkActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RatingSheet extends ConsumerStatefulWidget {
  final int networkId;
  const _RatingSheet({required this.networkId});

  @override
  ConsumerState<_RatingSheet> createState() => _RatingSheetState();
}

class _RatingSheetState extends ConsumerState<_RatingSheet> {
  int _rating = 0;
  final _reviewCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _reviewCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('اختر عدد النجوم'),
          backgroundColor: AppColors.accent,
        ),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      await ref
          .read(apiClientProvider)
          .post(
            '/networks/${widget.networkId}/rate',
            data: {'rating': _rating, 'review': _reviewCtrl.text.trim()},
          );
      ref.invalidate(networkDetailProvider(widget.networkId));
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إرسال التقييم بنجاح'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: AppColors.accent),
        );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 20,
        right: 20,
        top: 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'قيّم الشبكة',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              5,
              (i) => IconButton(
                icon: Icon(
                  i < _rating ? Icons.star_rounded : Icons.star_border_rounded,
                  color: const Color(0xFFF59E0B),
                  size: 36,
                ),
                onPressed: () => setState(() => _rating = i + 1),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reviewCtrl,
            textDirection: TextDirection.rtl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'تعليقك (اختياري)',
              labelStyle: TextStyle(fontFamily: 'Cairo'),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _loading ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Text(
                    'إرسال التقييم',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _ReportSheet extends ConsumerStatefulWidget {
  final int networkId;
  const _ReportSheet({required this.networkId});

  @override
  ConsumerState<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<_ReportSheet> {
  final _subjectCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final msg = _messageCtrl.text.trim();
    if (msg.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('أدخل نص البلاغ'),
          backgroundColor: AppColors.accent,
        ),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      await ref
          .read(apiClientProvider)
          .post(
            '/networks/${widget.networkId}/report',
            data: {'subject': _subjectCtrl.text.trim(), 'message': msg},
          );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إرسال البلاغ بنجاح'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: AppColors.accent),
        );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 20,
        right: 20,
        top: 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'إرسال بلاغ',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _subjectCtrl,
            textDirection: TextDirection.rtl,
            decoration: const InputDecoration(
              labelText: 'الموضوع',
              labelStyle: TextStyle(fontFamily: 'Cairo'),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _messageCtrl,
            textDirection: TextDirection.rtl,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'التفاصيل *',
              labelStyle: TextStyle(fontFamily: 'Cairo'),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _loading ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Text(
                    'إرسال البلاغ',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
