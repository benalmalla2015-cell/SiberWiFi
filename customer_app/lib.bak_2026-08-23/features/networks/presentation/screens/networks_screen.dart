import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/networks_provider.dart';

class NetworksScreen extends ConsumerWidget {
  const NetworksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(networksProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('الشبكات المتاحة'),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textDark,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(104),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Column(
              children: [
                TextField(
                  onChanged: (value) =>
                      ref.read(networkSearchProvider.notifier).state = value
                          .trim(),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    hintText: 'ابحث باسم الشبكة',
                  ),
                ),
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      FilterChip(
                        label: const Text('الأقرب إليك'),
                        selected: true,
                        onSelected: (_) {},
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: const Text('سلفني'),
                        selected: ref.watch(networkBorrowOnlyProvider),
                        onSelected: (value) =>
                            ref.read(networkBorrowOnlyProvider.notifier).state =
                                value,
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: const Text('الأكثر مبيعاً'),
                        selected: ref.watch(networkSortBySalesProvider),
                        onSelected: (value) =>
                            ref
                                    .read(networkSortBySalesProvider.notifier)
                                    .state =
                                value,
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: const Text('المفضلة'),
                        selected: ref.watch(networkFavoritesOnlyProvider),
                        onSelected: (value) =>
                            ref
                                    .read(networkFavoritesOnlyProvider.notifier)
                                    .state =
                                value,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
            onPressed: () => ref.invalidate(networksProvider),
          ),
        ],
      ),
      body: async.when(
        loading: () => _buildShimmer(),
        error: (e, _) => _buildError(ref),
        data: (nets) => nets.isEmpty
            ? _buildEmpty()
            : RefreshIndicator(
                color: AppColors.primary,
                onRefresh: () async => ref.invalidate(networksProvider),
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: nets.length,
                  itemBuilder: (context, i) => _NetworkCard(network: nets[i]),
                ),
              ),
      ),
    );
  }

  Widget _buildShimmer() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 5,
      itemBuilder: (_, __) => Shimmer.fromColors(
        baseColor: const Color(0xFFE8ECF4),
        highlightColor: const Color(0xFFF5F7FD),
        child: Container(
          height: 100,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_off_rounded, size: 64, color: AppColors.textLight),
          SizedBox(height: 16),
          Text(
            'لا توجد شبكات متاحة',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 16,
              color: AppColors.textGray,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.signal_wifi_statusbar_connected_no_internet_4_rounded,
            size: 64,
            color: AppColors.textLight,
          ),
          const SizedBox(height: 16),
          const Text(
            'تعذّر تحميل الشبكات',
            style: TextStyle(fontFamily: 'Cairo', color: AppColors.textGray),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => ref.invalidate(networksProvider),
            child: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    );
  }
}

class _NetworkCard extends StatelessWidget {
  final Map<String, dynamic> network;
  const _NetworkCard({required this.network});

  @override
  Widget build(BuildContext context) {
    final id = network['id'];
    final rating = (network['average_rating'] ?? 0.0).toDouble();
    final cardCount = network['available_cards_count'] ?? 0;
    final imageUrl = network['logo_url'] ?? network['cover_image_url'];

    return GestureDetector(
      onTap: () => context.go('/networks/$id'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.divider),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.lightBlue],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: imageUrl == null || imageUrl.toString().isEmpty
                  ? const Icon(
                      Icons.wifi_rounded,
                      color: Colors.white,
                      size: 28,
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: CachedNetworkImage(
                        imageUrl: imageUrl.toString(),
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => const Icon(
                          Icons.wifi_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    network['name'] ?? '',
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 13,
                        color: AppColors.textGray,
                      ),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          network['directorate'] ??
                              network['region'] ??
                              network['location'] ??
                              '',
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            color: AppColors.textGray,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.star_rounded,
                        size: 14,
                        color: Color(0xFFF59E0B),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        rating.toStringAsFixed(1),
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          color: AppColors.textGray,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Icon(
                        Icons.credit_card_rounded,
                        size: 13,
                        color: AppColors.textGray,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '$cardCount كرت',
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          color: AppColors.textGray,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 16,
              color: AppColors.textLight,
            ),
          ],
        ),
      ),
    );
  }
}
