import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../wallet/presentation/providers/wallet_provider.dart';
import '../../../networks/presentation/screens/receipt_share.dart';

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('سجل المعاملات'),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textDark,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textGray,
          indicatorColor: AppColors.primary,
          labelStyle: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(fontFamily: 'Cairo'),
          tabs: const [
            Tab(text: 'حركة المحفظة'),
            Tab(text: 'فواتير الشراء'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
            onPressed: () {
              ref.invalidate(walletTransactionsProvider);
              ref.invalidate(purchaseHistoryProvider);
            },
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _WalletLogsTab(),
          _PurchaseInvoicesTab(),
        ],
      ),
    );
  }
}

class _WalletLogsTab extends ConsumerWidget {
  const _WalletLogsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(walletTransactionsProvider);
    final fmt = NumberFormat('#,##0.00', 'ar');

    return async.when(
      loading: () => ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 8,
        itemBuilder: (_, __) => Shimmer.fromColors(
          baseColor: const Color(0xFFE8ECF4),
          highlightColor: const Color(0xFFF5F7FD),
          child: Container(height: 72, margin: const EdgeInsets.only(bottom: 10), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14))),
        ),
      ),
      error: (e, _) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, size: 56, color: AppColors.textLight),
            const SizedBox(height: 12),
            const Text('تعذّر تحميل المعاملات', style: TextStyle(fontFamily: 'Cairo', color: AppColors.textGray)),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: () => ref.invalidate(walletTransactionsProvider), child: const Text('إعادة المحاولة')),
          ],
        ),
      ),
      data: (txs) {
        if (txs.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.receipt_long_outlined, size: 64, color: AppColors.textLight),
                SizedBox(height: 16),
                Text('لا توجد معاملات بعد', style: TextStyle(fontFamily: 'Cairo', fontSize: 16, color: AppColors.textGray)),
              ],
            ),
          );
        }
        return RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async => ref.invalidate(walletTransactionsProvider),
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: txs.length,
            itemBuilder: (ctx, i) => _TxCard(tx: txs[i], fmt: fmt),
          ),
        );
      },
    );
  }
}

class _PurchaseInvoicesTab extends ConsumerWidget {
  const _PurchaseInvoicesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(purchaseHistoryProvider);
    final fmt = NumberFormat('#,##0.00', 'ar');

    return async.when(
      loading: () => ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 8,
        itemBuilder: (_, __) => Shimmer.fromColors(
          baseColor: const Color(0xFFE8ECF4),
          highlightColor: const Color(0xFFF5F7FD),
          child: Container(height: 72, margin: const EdgeInsets.only(bottom: 10), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14))),
        ),
      ),
      error: (e, _) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, size: 56, color: AppColors.textLight),
            const SizedBox(height: 12),
            const Text('تعذّر تحميل فواتير الشراء', style: TextStyle(fontFamily: 'Cairo', color: AppColors.textGray)),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: () => ref.invalidate(purchaseHistoryProvider), child: const Text('إعادة المحاولة')),
          ],
        ),
      ),
      data: (txs) {
        if (txs.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.credit_card_off_rounded, size: 64, color: AppColors.textLight),
                SizedBox(height: 16),
                Text('لا توجد عمليات شراء بعد', style: TextStyle(fontFamily: 'Cairo', fontSize: 16, color: AppColors.textGray)),
              ],
            ),
          );
        }
        return RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async => ref.invalidate(purchaseHistoryProvider),
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: txs.length,
            itemBuilder: (ctx, i) => _PurchaseCard(tx: txs[i], fmt: fmt),
          ),
        );
      },
    );
  }
}

class _PurchaseCard extends ConsumerWidget {
  final Map<String, dynamic> tx;
  final NumberFormat fmt;
  const _PurchaseCard({required this.tx, required this.fmt});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final price = (tx['price'] ?? 0).toDouble();
    final status = tx['status']?.toString() ?? '';
    final date = parseUtcToLocal(tx['created_at']);
    final networkName = tx['network_name']?.toString() ?? '';
    final categoryName = tx['category_name']?.toString() ?? '';
    final isAdvance = tx['payment_method']?.toString() == 'advance' || tx['is_advance'] == true;
    final isCompleted = status == 'completed' && !isAdvance;

    return GestureDetector(
      onTap: () => _openInvoice(context, ref),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Row(
          children: [
            Container(
              width: 46, height: 46,
              decoration: BoxDecoration(
                color: (isCompleted ? AppColors.success : (isAdvance ? const Color(0xFFEF6C00) : AppColors.accent)).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(
                isAdvance ? Icons.handshake_outlined : Icons.credit_card_rounded,
                color: isCompleted ? AppColors.success : (isAdvance ? const Color(0xFFEF6C00) : AppColors.accent),
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    networkName.isNotEmpty ? networkName : 'شراء كرت',
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textDark),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    softWrap: true,
                  ),
                  if (categoryName.isNotEmpty)
                    Text(categoryName, style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, color: AppColors.textGray), maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (date != null)
                    Text(
                      '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}',
                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, color: AppColors.textLight),
                    ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${fmt.format(price)} ر.ي',
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.accent),
                ),
                Text(
                  isAdvance ? 'سلفة' : _statusLabel(status),
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    color: isAdvance ? const Color(0xFFEF6C00) : (isCompleted ? AppColors.success : AppColors.textGray),
                    fontWeight: isAdvance ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_left_rounded, color: AppColors.textLight),
          ],
        ),
      ),
    );
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'completed': return 'مكتملة';
      case 'pending':   return 'قيد الانتظار';
      case 'failed':    return 'فاشلة';
      case 'refunded':  return 'مسترجعة';
      default:          return s;
    }
  }

  void _openInvoice(BuildContext context, WidgetRef ref) {
    final id = tx['id'] as int?;
    if (id == null) return;
    // A single dialog that fetches (and internally re-fetches on retry) its
    // own data and swaps between loading/error/content states in place.
    // Previously this flow popped a loading dialog and pushed a second one
    // once the network call resolved; if the user pressed back (impatient
    // during a slow request) at the same moment, that pop raced with the
    // system back-navigation's own pop on the same (root) Navigator and
    // could corrupt it — which is what caused the reported frozen/black
    // screen. A single persistent route sidesteps that class of bug
    // entirely since there is only ever one push and one pop.
    showDialog<void>(
      context: context,
      builder: (_) => _InvoiceDialog(id: id),
    );
  }
}

/// Self-contained invoice dialog: watches [purchaseDetailProvider] and
/// renders a loading spinner, an error view with retry, or the receipt —
/// all within the same single dialog route.
class _InvoiceDialog extends ConsumerWidget {
  final int id;
  const _InvoiceDialog({required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(purchaseDetailProvider(id));
    return AlertDialog(
      insetPadding: const EdgeInsets.all(16),
      title: const Text(
        'تفاصيل الفاتورة',
        style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
      ),
      content: SizedBox(
        width: 340,
        child: async.when(
          loading: () => const SizedBox(
            height: 160,
            child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
          ),
          error: (e, _) => SizedBox(
            height: 160,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline_rounded, size: 40, color: AppColors.accent),
                  const SizedBox(height: 10),
                  const Text('تعذر تحميل تفاصيل الفاتورة', style: TextStyle(fontFamily: 'Cairo')),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => ref.invalidate(purchaseDetailProvider(id)),
                    child: const Text('إعادة المحاولة', style: TextStyle(fontFamily: 'Cairo')),
                  ),
                ],
              ),
            ),
          ),
          data: (detail) {
            // Multi-card purchases (quantity > 1) come back as a `cards`
            // list; fall back to the single card_code/card_serial fields
            // for older transactions that predate that field.
            final cardsRaw = detail['cards'];
            List<Map<String, dynamic>> cards = cardsRaw is List
                ? cardsRaw
                    .whereType<Map>()
                    .map((c) => Map<String, dynamic>.from(c))
                    .where((c) => (c['code']?.toString() ?? '').isNotEmpty)
                    .toList()
                : const [];
            if (cards.isEmpty) {
              final code = detail['card_code']?.toString();
              if (code != null && code.isNotEmpty) {
                cards = [
                  {'code': code, 'serial': detail['card_serial']?.toString() ?? ''},
                ];
              }
            }
            return ReceiptBody(
              networkName: detail['network_name']?.toString() ?? '',
              cards: cards,
              price: (detail['price'] ?? 0).toDouble(),
              value: (detail['value'] ?? 0).toDouble(),
              transactionNumber: detail['transaction_number']?.toString(),
              isAdvance: detail['payment_method']?.toString() == 'advance',
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إغلاق'),
        ),
      ],
    );
  }
}

class _TxCard extends StatelessWidget {
  final Map<String, dynamic> tx;
  final NumberFormat fmt;
  const _TxCard({required this.tx, required this.fmt});

  @override
  Widget build(BuildContext context) {
    final type     = tx['type'] ?? '';
    final amount   = (tx['amount'] ?? 0).toDouble();
    final isPending = type == 'pending_topup';
    final isCredit = type == 'topup' || type == 'credit';
    final date     = parseUtcToLocal(tx['created_at']);
    final desc     = tx['description'] ?? tx['note'] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          Container(
            width: 46, height: 46,
            decoration: BoxDecoration(
              color: isPending
                  ? AppColors.primary.withValues(alpha: 0.1)
                  : (isCredit ? AppColors.success.withValues(alpha: 0.1) : AppColors.accent.withValues(alpha: 0.1)),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              isPending
                  ? Icons.hourglass_top_rounded
                  : (isCredit ? Icons.south_west_rounded : Icons.north_east_rounded),
              color: isPending ? AppColors.primary : (isCredit ? AppColors.success : AppColors.accent),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_typeLabel(type), style: const TextStyle(fontFamily: 'Cairo', fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textDark)),
                if (desc.toString().isNotEmpty)
                  Text(desc.toString(), style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, color: AppColors.textGray), maxLines: 1, overflow: TextOverflow.ellipsis),
                if (date != null)
                  Text(
                    '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, color: AppColors.textLight),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                isPending ? fmt.format(amount) : '${isCredit ? '+' : '-'} ${fmt.format(amount)}',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: isPending ? AppColors.primary : (isCredit ? AppColors.success : AppColors.accent),
                ),
              ),
              const Text('ر.ي', style: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: AppColors.textGray)),
            ],
          ),
        ],
      ),
    );
  }

  String _typeLabel(String t) {
    switch (t) {
      case 'topup':          return 'شحن رصيد';
      case 'purchase':       return 'شراء كرت';
      case 'credit':         return 'إيداع';
      case 'debit':          return 'خصم';
      case 'pending_topup':  return 'طلب شحن رصيد (بانتظار المراجعة)';
      case 'cashback':       return 'كاشباك';
      case 'referral_commission': return 'عمولة رفلينك';
      case 'refund':         return 'استرجاع';
      default:               return t;
    }
  }
}
