import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/json_helpers.dart';
import '../providers/networks_provider.dart';
import '../../../wallet/presentation/providers/wallet_provider.dart';
import 'receipt_share.dart';

class CardsScreen extends ConsumerWidget {
  final int networkId;
  const CardsScreen({super.key, required this.networkId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(networkCardsProvider(networkId));
    final fmt = NumberFormat('#,##0', 'ar');

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('كروت الشحن'),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textDark,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.divider),
        ),
      ),
      body: async.when(
        loading: () => _buildShimmer(),
        error: (e, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'تعذّر تحميل الكروت',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  color: AppColors.textGray,
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () =>
                    ref.invalidate(networkCardsProvider(networkId)),
                child: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
        data: (cards) {
          final available = cards
              .where((c) => ((c['available_cards_count'] ?? 0) as num) > 0)
              .toList();
          if (available.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.credit_card_off_rounded,
                    size: 64,
                    color: AppColors.textLight,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'لا توجد كروت متاحة حالياً',
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
          final grouped = <String, List<Map<String, dynamic>>>{};
          for (final c in available) {
            final cat = c['name']?.toString() ?? 'عام';
            grouped.putIfAbsent(cat, () => []).add(c);
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: grouped.entries.map((entry) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        Container(
                          width: 4,
                          height: 18,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          entry.key,
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...entry.value.map(
                    (card) =>
                        _CardItem(card: card, fmt: fmt, networkId: networkId),
                  ),
                ],
              );
            }).toList(),
          );
        },
      ),
    );
  }

  Widget _buildShimmer() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 6,
      itemBuilder: (_, __) => Shimmer.fromColors(
        baseColor: const Color(0xFFE8ECF4),
        highlightColor: const Color(0xFFF5F7FD),
        child: Container(
          height: 90,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

class _CardItem extends ConsumerWidget {
  final Map<String, dynamic> card;
  final NumberFormat fmt;
  final int networkId;
  const _CardItem({
    required this.card,
    required this.fmt,
    required this.networkId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final price = (card['price'] ?? 0).toDouble();
    final value = (card['value'] ?? 0).toDouble();
    final availableCount = ((card['available_cards_count'] ?? 0) as num)
        .toInt();

    return Container(
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
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.inputBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  fmt.format(value),
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                const Text(
                  'ر.ي',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 9,
                    color: AppColors.textGray,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'كرت ${fmt.format(value)} ريال',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'السعر: ${fmt.format(price)} ر.ي · متاح: $availableCount',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    color: AppColors.textGray,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () =>
                _confirmPurchase(context, ref, price, value, availableCount),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'شراء',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmPurchase(
    BuildContext context,
    WidgetRef ref,
    double price,
    double value,
    int availableCount,
  ) async {
    final quantityController = TextEditingController(text: '1');
    final fmt2 = NumberFormat('#,##0', 'ar');
    final quantity = await showDialog<int>(
      context: context,
      useRootNavigator: false,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'تأكيد الشراء',
          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'فئة بقيمة ${fmt2.format(value)} ر.ي',
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: quantityController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'الكمية (المتاح: $availableCount)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text(
              'إلغاء',
              style: TextStyle(fontFamily: 'Cairo', color: AppColors.textGray),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              final quantity = int.tryParse(quantityController.text) ?? 0;
              if (quantity < 1 || quantity > availableCount) return;
              Navigator.of(dialogCtx).pop(quantity);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              'شراء بـ ${fmt2.format(price)} ر.ي',
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
    quantityController.dispose();
    if (quantity == null || !context.mounted) return;
    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: false,
      builder: (_) => PopScope(
        canPop: false,
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: AppColors.primary),
                SizedBox(height: 16),
                Text(
                  'جاري تنفيذ الشراء...',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 14,
                    color: AppColors.textDark,
                    decoration: TextDecoration.none,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    try {
      final result = await ref
          .read(walletProvider.notifier)
          .purchaseCategory(card['id'] as int, quantity);
      if (!context.mounted) return;
      Navigator.of(context).pop();
      ref.invalidate(networkCardsProvider(networkId));
      final purchasedCards = toMapList(result['cards']);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        useRootNavigator: false,
        builder: (_) => ReceiptShareDialog(
          networkName: result['network_name']?.toString() ?? 'الشبكة',
          cards: purchasedCards,
          price: (result['price'] ?? price * quantity).toDouble(),
          value: (result['value'] ?? value).toDouble(),
          transactionNumber: result['transaction_number']?.toString(),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString()),
          backgroundColor: AppColors.accent,
        ),
      );
    }
  }
}
