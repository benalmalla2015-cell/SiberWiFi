import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/json_helpers.dart';
import '../providers/networks_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
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
      itemBuilder: (_, _) => Shimmer.fromColors(
        baseColor: const Color(0xFFE8ECF4),
        highlightColor: const Color(0xFFF5F7FD),
        child: Container(
          height: 180,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
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
    final convertedPrice = (card['converted_price'] as num?)?.toDouble();
    final baseDisplayPrice = convertedPrice ?? price;
    final offerPrice = (card['offer_price'] as num?)?.toDouble();
    final discountPercent = (card['discount_percent'] as num?)?.toDouble() ?? 0;
    final hasOffer = offerPrice != null && offerPrice < baseDisplayPrice;
    final displayPrice = hasOffer ? offerPrice : baseDisplayPrice;
    final isCrossRegion = card['currency_converted'] == true;
    final networkCurrency = card['network_currency']?.toString();
    final value = (card['value'] ?? 0).toDouble();
    final availableCount = ((card['available_cards_count'] ?? 0) as num)
        .toInt();
    final speed =
        (card['speed'] ?? card['speed_mbps'] ?? card['internet_speed'] ?? 0)
            .toString();
    final duration = (card['duration'] ?? card['duration_days'] ?? 0)
        .toString();
    final unit =
        card['unit']?.toString() ?? card['duration_unit']?.toString() ?? 'يوم';
    final user = ref.watch(authProvider).user;
    final wallet = ref.watch(walletBalanceProvider);
    final isEligible =
        (user?.isEligibleForAdvance ?? false) ||
        (wallet.valueOrNull?.isEligibleForAdvance ?? false);
    final advanceEnabled =
        card['advance_enabled'] == true ||
        card['advance_status']?.toString() == 'approved';
    final advanceMax =
        (card['advance_max_per_customer'] ?? card['advance_max_cards'] ?? 0)
            as num;
    final advanceUsed = (card['advance_used_count'] ?? 0) as num;
    final advanceRemaining = advanceEnabled && advanceMax > 0
        ? (advanceMax - advanceUsed).toInt().clamp(0, availableCount)
        : 0;
    final canAdvance = isEligible && advanceEnabled && advanceRemaining > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primaryDark, AppColors.primary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        card['name']?.toString() ?? 'كرت الشحن',
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${fmt.format(value)} ر.ي',
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (hasOffer)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.accent,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'خصم ${fmt.format(discountPercent)}%',
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          if (hasOffer) const SizedBox(width: 8),
                          if (availableCount > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'متاح: $availableCount',
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 11,
                                  color: Colors.white70,
                                ),
                              ),
                            ),
                          if (isCrossRegion)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                networkCurrency == 'south'
                                    ? 'عملة الجنوب'
                                    : 'عملة الشمال',
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 11,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.wifi_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                _SpecItem(
                  icon: Icons.speed_rounded,
                  label: 'السرعة',
                  value: speed.isNotEmpty && speed != '0'
                      ? '$speed ميجا'
                      : 'غير محدد',
                  color: const Color(0xFF3AB0E2),
                ),
                const SizedBox(width: 10),
                _SpecItem(
                  icon: Icons.timer_outlined,
                  label: 'المدة',
                  value:
                      '$duration ${duration == '1' ? unit : _pluralize(unit)}',
                  color: const Color(0xFF2ECC71),
                ),
                const SizedBox(width: 10),
                _SpecItem(
                  icon: Icons.payments_outlined,
                  label: 'السعر',
                  value: '${fmt.format(displayPrice)} ر.ي',
                  color: hasOffer ? AppColors.accent : const Color(0xFFFF9F43),
                  subtitle: hasOffer
                      ? 'بدلاً من ${fmt.format(baseDisplayPrice)}'
                      : (isCrossRegion
                            ? 'قبل التحويل (${networkCurrency == 'south' ? 'جنوب' : 'شمال'}): ${fmt.format(price)}'
                            : null),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            child: Row(
              children: [
                Expanded(
                  flex: canAdvance ? 1 : 2,
                  child: ElevatedButton(
                    onPressed: () => _confirmPurchase(
                      context,
                      ref,
                      displayPrice,
                      value,
                      availableCount,
                      method: 'wallet',
                      hasOffer: hasOffer,
                      discountPercent: discountPercent,
                      originalPrice: baseDisplayPrice,
                      nativePrice: price,
                      isCrossRegion: isCrossRegion,
                      networkCurrency: networkCurrency,
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.shopping_cart_outlined, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          'شراء ${canAdvance ? '' : '${fmt.format(displayPrice)} ر.ي'}',
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (canAdvance) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _confirmPurchase(
                        context,
                        ref,
                        displayPrice,
                        value,
                        availableCount,
                        method: 'advance',
                        advanceRemaining: advanceRemaining,
                        hasOffer: hasOffer,
                        discountPercent: discountPercent,
                        originalPrice: baseDisplayPrice,
                        nativePrice: price,
                        isCrossRegion: isCrossRegion,
                        networkCurrency: networkCurrency,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEF6C00),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.handshake_outlined, size: 16),
                          const SizedBox(width: 6),
                          const Text(
                            'سلفني',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _pluralize(String unit) {
    if (unit == 'يوم') return 'أيام';
    if (unit == 'أسبوع') return 'أسابيع';
    if (unit == 'شهر') return 'أشهر';
    if (unit == 'ساعة') return 'ساعات';
    return unit;
  }

  Future<void> _confirmPurchase(
    BuildContext context,
    WidgetRef ref,
    double price,
    double value,
    int availableCount, {
    required String method,
    int advanceRemaining = 0,
    bool hasOffer = false,
    double discountPercent = 0,
    double originalPrice = 0,
    double nativePrice = 0,
    bool isCrossRegion = false,
    String? networkCurrency,
  }) async {
    final maxQty = method == 'advance'
        ? advanceRemaining.clamp(1, availableCount)
        : availableCount;
    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      useRootNavigator: false,
      builder: (_) => _PurchaseConfirmationDialog(
        price: price,
        value: value,
        maxQty: maxQty,
        method: method,
        hasOffer: hasOffer,
        discountPercent: discountPercent,
        originalPrice: originalPrice,
        nativePrice: nativePrice,
        isCrossRegion: isCrossRegion,
        networkCurrency: networkCurrency,
      ),
    );
    if (result == null || !context.mounted) return;
    final selectedQuantity = result['quantity'] as int;
    final paymentMethod = result['method'] as String;

    BuildContext? loadingDialogContext;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: false,
      builder: (dialogContext) {
        loadingDialogContext = dialogContext;
        return PopScope(
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
                    'جاري تنفيذ الطلب...',
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
        );
      },
    );
    try {
      final purchaseResult = await ref
          .read(walletProvider.notifier)
          .purchaseCategory(
            card['id'] as int,
            selectedQuantity,
            paymentMethod: paymentMethod,
          );
      if (!context.mounted) return;
      final loadingContext = loadingDialogContext;
      if (loadingContext != null && loadingContext.mounted) {
        Navigator.of(loadingContext).pop();
      }
      final purchasedCards = toMapList(purchaseResult['cards']);
      await showDialog<void>(
        context: context,
        useRootNavigator: false,
        builder: (_) => ReceiptShareDialog(
          networkName: purchaseResult['network_name']?.toString() ?? 'الشبكة',
          cards: purchasedCards,
          price: (purchaseResult['price'] ?? price * selectedQuantity)
              .toDouble(),
          value: (purchaseResult['value'] ?? value).toDouble(),
          transactionNumber: purchaseResult['transaction_number']?.toString(),
          isAdvance: paymentMethod == 'advance',
          discount: (purchaseResult['discount'] as num?)?.toDouble() ?? 0,
          originalPrice:
              (purchaseResult['original_price'] as num?)?.toDouble() ?? 0,
        ),
      );
      ref.invalidate(networkCardsProvider(networkId));
      HapticFeedback.lightImpact();
    } catch (error) {
      if (!context.mounted) return;
      final loadingContext = loadingDialogContext;
      if (loadingContext != null && loadingContext.mounted) {
        Navigator.of(loadingContext).pop();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString()),
          backgroundColor: AppColors.accent,
        ),
      );
    }
  }
}

class _PurchaseConfirmationDialog extends StatefulWidget {
  final double price;
  final double value;
  final int maxQty;
  final String method;
  final bool hasOffer;
  final double discountPercent;
  final double originalPrice;
  final double nativePrice;
  final bool isCrossRegion;
  final String? networkCurrency;

  const _PurchaseConfirmationDialog({
    required this.price,
    required this.value,
    required this.maxQty,
    required this.method,
    required this.hasOffer,
    required this.discountPercent,
    required this.originalPrice,
    required this.nativePrice,
    required this.isCrossRegion,
    required this.networkCurrency,
  });

  @override
  State<_PurchaseConfirmationDialog> createState() =>
      _PurchaseConfirmationDialogState();
}

class _PurchaseConfirmationDialogState
    extends State<_PurchaseConfirmationDialog> {
  final _quantityController = TextEditingController(text: '1');
  final _fmt = NumberFormat('#,##0', 'ar');

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        widget.method == 'advance' ? 'تأكيد السلفة' : 'تأكيد الشراء',
        style: const TextStyle(
          fontFamily: 'Cairo',
          fontWeight: FontWeight.bold,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'فئة بقيمة ${_fmt.format(widget.value)} ر.ي',
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          const SizedBox(height: 4),
          if (widget.isCrossRegion)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'السعر الأساسي (${widget.networkCurrency == 'south' ? 'جنوب' : 'شمال'}): ${_fmt.format(widget.nativePrice)} ر.ي — يُحوَّل بسعر الصرف المعتمد',
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11,
                  color: AppColors.textGray,
                ),
              ),
            ),
          if (widget.hasOffer) ...[
            Row(
              children: [
                Text(
                  'السعر بعد الخصم: ${_fmt.format(widget.price)} ر.ي',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.accent,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _fmt.format(widget.originalPrice),
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    color: AppColors.textGray,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'عرض مفعّل — خصم ${_fmt.format(widget.discountPercent)}% · الكمية القصوى: ${widget.maxQty}',
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11,
                  color: AppColors.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ] else
            Text(
              'السعر: ${_fmt.format(widget.price)} ر.ي · الكمية القصوى: ${widget.maxQty}',
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                color: AppColors.textGray,
              ),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _quantityController,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'الكمية',
              labelStyle: const TextStyle(fontFamily: 'Cairo'),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'الإجمالي: ${_fmt.format(widget.price * (int.tryParse(_quantityController.text) ?? 0))} ر.ي',
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            'إلغاء',
            style: TextStyle(fontFamily: 'Cairo', color: AppColors.textGray),
          ),
        ),
        ElevatedButton(
          onPressed: () {
            final quantity = int.tryParse(_quantityController.text) ?? 0;
            if (quantity < 1 || quantity > widget.maxQty) return;
            Navigator.of(
              context,
            ).pop({'quantity': quantity, 'method': widget.method});
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.method == 'advance'
                ? const Color(0xFFEF6C00)
                : AppColors.primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Text(
            widget.method == 'advance'
                ? 'سلفني ${_fmt.format(widget.price * (int.tryParse(_quantityController.text) ?? 1))} ر.ي'
                : 'شراء بـ ${_fmt.format(widget.price * (int.tryParse(_quantityController.text) ?? 1))} ر.ي',
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}

class _SpecItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final String? subtitle;
  const _SpecItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 10,
                color: AppColors.textGray,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: color,
              ),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null)
              Text(
                subtitle!,
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 9,
                  color: AppColors.textGray,
                  decoration: TextDecoration.lineThrough,
                ),
                textAlign: TextAlign.center,
              ),
          ],
        ),
      ),
    );
  }
}
