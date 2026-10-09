import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/json_helpers.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../networks/presentation/providers/networks_provider.dart';
import '../../../notifications/presentation/screens/notifications_screen.dart';
import '../../../wallet/presentation/providers/wallet_provider.dart';
import '../providers/home_provider.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final homeAsync = ref.watch(homeProvider);
    final offersAsync = ref.watch(dailyOffersProvider);
    final netsAsync = ref.watch(networksProvider);
    final walletBalanceAsync = ref.watch(walletBalanceProvider);
    final canTransferBalance =
        ref.watch(chargingPointEligibilityProvider).valueOrNull ?? false;
    final unreadCount = ref
            .watch(notificationsProvider)
            .valueOrNull
            ?.where((n) => n['read_at'] == null)
            .length ??
        0;
    final user = auth.user;
    final fmt = NumberFormat('#,##0', 'ar');

    return Scaffold(
      backgroundColor: Colors.white,
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () async {
          ref.invalidate(homeProvider);
          ref.invalidate(dailyOffersProvider);
          ref.invalidate(networksProvider);
          ref.invalidate(walletBalanceProvider);
          ref.invalidate(chargingPointEligibilityProvider);
          await ref.read(authProvider.notifier).refreshProfile();
        },
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _buildHeader(
                  context, user, walletBalanceAsync, fmt, unreadCount),
            ),
            SliverToBoxAdapter(
              child: homeAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (data) {
                  final sliders = toMapList(data['sliders']);
                  return AnnouncementSlider(
                    items: sliders.isNotEmpty
                        ? sliders
                        : const [
                            {
                              'title': 'اتصال أسرع وتجربة رقمية متكاملة',
                              'subtitle':
                                  'اكتشف الشبكات والخدمات المتاحة بالقرب منك',
                            },
                          ],
                  );
                },
              ),
            ),
            SliverToBoxAdapter(
              child: homeAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (data) =>
                    _buildTopNetworks(context, toMapList(data['top_networks'])),
              ),
            ),
            SliverToBoxAdapter(
              child: _buildQuickActions(context, canTransferBalance),
            ),
            SliverToBoxAdapter(
              child: offersAsync.when(
                loading: () => _buildOffersShimmer(),
                error: (_, __) => const SizedBox.shrink(),
                data: (offers) => _buildOffersSection(context, offers),
              ),
            ),
            SliverToBoxAdapter(
              child: netsAsync.when(
                loading: () => _buildNetworksShimmer(),
                error: (_, __) => const SizedBox.shrink(),
                data: (nets) => _buildNetworksSection(context, nets),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    user,
    AsyncValue<WalletBalanceInfo> walletBalanceAsync,
    NumberFormat fmt,
    int unreadCount,
  ) {
    final liveBalance = walletBalanceAsync.when(
      loading: () => null,
      error: (_, __) => null,
      data: (info) => info.balance,
    );
    final balance = liveBalance ?? user?.balance ?? 0.0;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primaryDark, AppColors.primary, Color(0xFF243490)],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(36),
          bottomRight: Radius.circular(36),
        ),
      ),
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 16,
        left: 20,
        right: 20,
        bottom: 28,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'مرحباً 👋',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        color: Colors.white70,
                      ),
                    ),
                    Text(
                      user?.name ?? 'المستخدم',
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => GoRouter.of(context).go('/notifications'),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Badge(
                    isLabelVisible: unreadCount > 0,
                    backgroundColor: AppColors.accent,
                    label: Text(
                      unreadCount > 99 ? '99+' : '$unreadCount',
                      style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 10,
                          color: Colors.white),
                    ),
                    child: const Icon(
                      Icons.notifications_outlined,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'رصيدي الحالي',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 13,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${fmt.format(balance)} ر.ي',
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => GoRouter.of(context).go('/wallet/topup'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'شحن',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context, bool canTransferBalance) {
    final actions = [
      {
        'icon': Icons.storefront_rounded,
        'label': 'نقاط الشحن',
        'route': '/pos',
        'color': const Color(0xFFFF9F43),
      },
      if (canTransferBalance)
        {
          'icon': Icons.send_rounded,
          'label': 'شحن رصيد',
          'route': '/wallet/transfer',
          'color': const Color(0xFF00A896),
        },
      {
        'icon': Icons.account_balance_wallet_rounded,
        'label': 'محفظتي',
        'route': '/wallet',
        'color': const Color(0xFF2ECC71),
      },
      {
        'icon': Icons.wifi_rounded,
        'label': 'الشبكات',
        'route': '/networks',
        'color': const Color(0xFF4A6CF7),
      },
      {
        'icon': Icons.person_rounded,
        'label': 'حسابي',
        'route': '/profile',
        'color': const Color(0xFF3AB0E2),
      },
      {
        'icon': Icons.receipt_long_rounded,
        'label': 'معاملاتي',
        'route': '/transactions',
        'color': const Color(0xFF8E5AE2),
      },
      {
        'icon': Icons.sell_rounded,
        'label': 'العروض',
        'route': '/offers',
        'color': const Color(0xFFE84C6B),
      },
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'الخدمات السريعة',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 14),
          _buildBoosterCard(context),
          const SizedBox(height: 18),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 14,
            crossAxisSpacing: 12,
            childAspectRatio: 0.88,
            children: actions.map((a) => _quickActionCard(context, a)).toList(),
          ),
          const SizedBox(height: 18),
          _buildBillsBanner(context),
        ],
      ),
    );
  }

  Widget _buildBoosterCard(BuildContext context) {
    return GestureDetector(
      onTap: () => GoRouter.of(context).go('/booster'),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.primaryDark, AppColors.primary],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.chevron_left_rounded,
                        color: Colors.white70,
                        size: 18,
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'محرك تسريع الشبكة',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'حسّن أداء تطبيقك عند ضعف الشبكة أو محدودية البيانات',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11,
                      color: Colors.white70,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.bolt_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBillsBanner(BuildContext context) {
    return GestureDetector(
      onTap: () => GoRouter.of(context).go('/bills'),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.primary, Color(0xFF3A56C4)],
            begin: Alignment.centerRight,
            end: Alignment.centerLeft,
          ),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            const Icon(Icons.chevron_left_rounded, color: Colors.white70),
            Expanded(
              child: Text(
                'خدمة سداد باقات الإنترنت وشركات الإتصالات',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  height: 1.4,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.receipt_long_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickActionCard(BuildContext context, Map a) {
    final color = a['color'] as Color;
    return GestureDetector(
      onTap: () => GoRouter.of(context).go(a['route'] as String),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(a['icon'] as IconData, color: Colors.white, size: 26),
            ),
            const SizedBox(height: 8),
            Text(
              a['label'] as String,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                color: AppColors.textDark,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopNetworks(
    BuildContext context,
    List<Map<String, dynamic>> networks,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'الشبكات الأكثر مبيعاً',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                ),
              ),
              GestureDetector(
                onTap: () => context.go('/networks'),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'عرض الكل',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(width: 2),
                      Icon(
                        Icons.chevron_left_rounded,
                        size: 16,
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (networks.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFF6F7FB),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.divider),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.storefront_outlined,
                    color: AppColors.textLight,
                    size: 22,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'لا تتوفر شبكات مُباعة حالياً في منطقتك',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        color: AppColors.textGray,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            SizedBox(
            height: 108,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: networks.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, index) {
                final network = networks[index];
                final salesCount = (network['sales_count'] ?? 0) as num;
                final imageUrl =
                    network['logo_url'] ?? network['cover_image_url'];
                return InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => context.go('/networks/${network['id']}'),
                  child: Container(
                    width: 184,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.divider),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [AppColors.primary, AppColors.lightBlue],
                            ),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: imageUrl == null || imageUrl.toString().isEmpty
                              ? const Icon(
                                  Icons.wifi_rounded,
                                  color: Colors.white,
                                  size: 24,
                                )
                              : ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: CachedNetworkImage(
                                    imageUrl: imageUrl.toString(),
                                    width: 48,
                                    height: 48,
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) => const Icon(
                                      Icons.wifi_rounded,
                                      color: Colors.white,
                                      size: 24,
                                    ),
                                  ),
                                ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                network['name']?.toString() ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: AppColors.textDark,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE8F5E9),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '$salesCount مبيعة',
                                  style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 10,
                                    color: Color(0xFF2E7D32),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOffersSection(
    BuildContext context,
    List<Map<String, dynamic>> offers,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'العروض اليومية',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                ),
              ),
              GestureDetector(
                onTap: () => context.go('/offers'),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'عرض الكل',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(width: 2),
                      Icon(
                        Icons.chevron_left_rounded,
                        size: 16,
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (offers.isEmpty)
            _buildEmptyOffersCard()
          else if (offers.length == 1)
            _homeOfferCard(context, offers.first)
          else
            _OffersCarousel(offers: offers),
        ],
      ),
    );
  }

  Widget _buildEmptyOffersCard() {
    return GestureDetector(
      onTap: null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
        decoration: BoxDecoration(
          color: const Color(0xFFF6F7FB),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'ترقّب عروضنا',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'لا تتوفر عروض حالياً',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'خصومات وباقات حصرية على شبكاتك المفضلة قريباً — تابعنا!',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      color: AppColors.textGray,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.local_offer_outlined,
                color: AppColors.primary,
                size: 28,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOffersShimmer() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _shimmerBox(120, 18),
          const SizedBox(height: 12),
          _shimmerBox(double.infinity, 130),
        ],
      ),
    );
  }

  Widget _buildNetworksSection(
    BuildContext context,
    List<Map<String, dynamic>> nets,
  ) {
    if (nets.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'الشبكات المتاحة',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                ),
              ),
              GestureDetector(
                onTap: () => GoRouter.of(context).go('/networks'),
                child: const Text(
                  'عرض الكل',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...nets.take(3).map((n) => _networkCard(context, n)),
        ],
      ),
    );
  }

  Widget _networkCard(BuildContext context, Map<String, dynamic> n) {
    final id = n['id'];
    return GestureDetector(
      onTap: () => GoRouter.of(context).go('/networks/$id'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.inputBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.wifi_rounded,
                color: AppColors.primary,
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    n['name'] ?? '',
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    n['directorate'] ?? n['region'] ?? n['location'] ?? '',
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      color: AppColors.textGray,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'كروت',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNetworksShimmer() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _shimmerBox(120, 18),
          const SizedBox(height: 12),
          ...List.generate(
            3,
            (_) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _shimmerBox(double.infinity, 76),
            ),
          ),
        ],
      ),
    );
  }

  Widget _shimmerBox(double w, double h) {
    return Shimmer.fromColors(
      baseColor: const Color(0xFFE8ECF4),
      highlightColor: const Color(0xFFF5F7FD),
      child: Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }
}

class AnnouncementSlider extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  const AnnouncementSlider({super.key, required this.items});

  @override
  State<AnnouncementSlider> createState() => _AnnouncementSliderState();
}

class _AnnouncementSliderState extends State<AnnouncementSlider> {
  final _controller = PageController();
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || widget.items.length < 2) return;
      _index = (_index + 1) % widget.items.length;
      _controller.animateToPage(
        _index,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: SizedBox(
        height: 112,
        child: PageView.builder(
          controller: _controller,
          itemCount: widget.items.length,
          onPageChanged: (value) => setState(() => _index = value),
          itemBuilder: (_, index) {
            final item = widget.items[index];
            final imageUrl = item['image_url']?.toString();
            final title = item['title']?.toString().trim() ?? '';
            final hasTitle = title.isNotEmpty;
            return Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: imageUrl == null || imageUrl.isEmpty
                    ? const LinearGradient(
                        colors: [AppColors.primary, AppColors.lightBlue],
                      )
                    : null,
                image: imageUrl != null && imageUrl.isNotEmpty
                    ? DecorationImage(
                        image: CachedNetworkImageProvider(imageUrl),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: !hasTitle
                  ? const SizedBox.shrink()
                  : Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        gradient: imageUrl != null && imageUrl.isNotEmpty
                            ? LinearGradient(
                                begin: Alignment.centerRight,
                                end: Alignment.centerLeft,
                                colors: [
                                  Colors.black.withValues(alpha: 0.55),
                                  Colors.black.withValues(alpha: 0.15),
                                ],
                              )
                            : null,
                        color: imageUrl == null || imageUrl.isEmpty
                            ? Colors.black.withValues(alpha: 0.12)
                            : null,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Spacer(),
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
            );
          },
        ),
      ),
    );
  }
}
/// Auto-scrolling offer cards shown under "العروض اليومية" when more than one
/// offer exists — cycles every few seconds with a smooth page animation.
class _OffersCarousel extends StatefulWidget {
  final List<Map<String, dynamic>> offers;
  const _OffersCarousel({required this.offers});

  @override
  State<_OffersCarousel> createState() => _OffersCarouselState();
}

class _OffersCarouselState extends State<_OffersCarousel> {
  late final PageController _controller;
  Timer? _timer;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _nextPage());
  }

  void _nextPage() {
    if (!mounted || !_controller.hasClients || widget.offers.length < 2) return;
    final next = (_page + 1) % widget.offers.length;
    _controller.animateToPage(
      next,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 188,
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.offers.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: _homeOfferCard(context, widget.offers[i]),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(widget.offers.length, (i) {
            final active = i == _page;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: active ? 18 : 7,
              height: 7,
              decoration: BoxDecoration(
                color: active
                    ? AppColors.primary
                    : AppColors.textLight.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(4),
              ),
            );
          }),
        ),
      ],
    );
  }
}

/// Single daily-offer card used on the home screen — static for one offer and
/// as a page inside [_OffersCarousel] when several offers exist. Upcoming
/// (scheduled) offers are announced with a "قريباً" badge and muted colors.
Widget _homeOfferCard(BuildContext context, Map<String, dynamic> offer) {
  final isUpcoming = offer['is_upcoming'] == true;
  final discount = (offer['discount_percent'] ?? 0) as num;
  final offerTitle = offer['title']?.toString() ?? 'عرض خاص';
  final networkName =
      offer['network_name']?.toString() ?? offer['network']?.toString() ?? '';
  return GestureDetector(
    onTap: () => context.go('/offers'),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isUpcoming
              ? const [Color(0xFF4A5568), Color(0xFF6B7A94)]
              : const [Color(0xFF6C63E0), Color(0xFF8E5AE2)],
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6C63E0).withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isUpcoming ? 'قريباً — خصم $discount%' : 'خصم $discount%',
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  offerTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.wifi_rounded,
                      size: 14,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        networkName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 13,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.local_offer_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
        ],
      ),
    ),
  );
}
