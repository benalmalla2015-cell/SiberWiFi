import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/api/api_client.dart';
import '../../../../core/cache/hive_service.dart';
import '../../../../core/utils/connectivity_service.dart';
import '../../../../core/utils/json_helpers.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

final walletBalanceProvider = FutureProvider<double>((ref) async {
  final online = await ConnectivityService.isConnected();
  if (!online) {
    final cached = HiveService.walletBox.get('balance');
    return (cached ?? 0.0).toDouble();
  }
  try {
    final api = ref.read(apiClientProvider);
    final res = await api.get('/wallet/balance');
    final balance = (res.data['data']?['balance'] ?? res.data['balance'] ?? 0).toDouble();
    await HiveService.walletBox.put('balance', balance);
    return balance;
  } catch (_) {
    return (HiveService.walletBox.get('balance') ?? 0.0).toDouble();
  }
});

// Wallet ledger entries (top-ups, debits/credits) — used by the wallet screen
// and the general transactions log.
final walletTransactionsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final online = await ConnectivityService.isConnected();
  if (!online) {
    final cached = HiveService.transactionsBox.get('list');
    if (cached != null) return toMapList(cached);
    return [];
  }
  try {
    final api = ref.read(apiClientProvider);
    final res = await api.get('/wallet/logs');
    final list = toMapList(res.data['data'] ?? []);
    await HiveService.transactionsBox.put('list', list);
    return list;
  } catch (_) {
    final cached = HiveService.transactionsBox.get('list');
    if (cached != null) return toMapList(cached);
    return [];
  }
});

// Bank accounts managed by the admin so the customer knows where to transfer.
final bankAccountsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final online = await ConnectivityService.isConnected();
  if (!online) {
    final cached = HiveService.walletBox.get('bank_accounts');
    if (cached != null) return toMapList(cached);
    return [];
  }
  try {
    final api = ref.read(apiClientProvider);
    final res = await api.get('/bank-accounts');
    final list = toMapList(res.data['data'] ?? []);
    await HiveService.walletBox.put('bank_accounts', list);
    return list;
  } catch (_) {
    final cached = HiveService.walletBox.get('bank_accounts');
    if (cached != null) return toMapList(cached);
    return [];
  }
});

// Purchase (charging card) history — used by the invoices/purchases screen.
final purchaseHistoryProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final online = await ConnectivityService.isConnected();
  if (!online) {
    final cached = HiveService.transactionsBox.get('purchases');
    if (cached != null) return toMapList(cached);
    return [];
  }
  try {
    final api = ref.read(apiClientProvider);
    final res = await api.get('/transactions');
    final list = toMapList(res.data['data'] ?? []);
    await HiveService.transactionsBox.put('purchases', list);
    return list;
  } catch (_) {
    final cached = HiveService.transactionsBox.get('purchases');
    if (cached != null) return toMapList(cached);
    return [];
  }
});

// Full invoice details (including the card code/serial) for a single purchase.
final purchaseDetailProvider = FutureProvider.family<Map<String, dynamic>, int>((ref, id) async {
  final api = ref.read(apiClientProvider);
  final res = await api.get('/transactions/$id');
  return toMap(res.data['data'] ?? res.data);
});

class WalletNotifier extends StateNotifier<AsyncValue<void>> {
  final ApiClient _api;
  final Ref _ref;
  WalletNotifier(this._api, this._ref) : super(const AsyncData(null));

  Future<String?> topup({
    required double amount,
    int? bankAccountId,
    String? transferReceiptNumber,
    String? senderName,
  }) async {
    state = const AsyncLoading();
    try {
      await _api.post('/wallet/topup', data: {
        'amount': amount,
        if (bankAccountId != null) 'bank_account_id': bankAccountId,
        if (transferReceiptNumber != null && transferReceiptNumber.isNotEmpty)
          'transfer_receipt_number': transferReceiptNumber,
        if (senderName != null && senderName.isNotEmpty) 'sender_name': senderName,
      });
      _ref.invalidate(walletBalanceProvider);
      _ref.invalidate(walletTransactionsProvider);
      _ref.read(authProvider.notifier).refreshProfile();
      state = const AsyncData(null);
      return null;
    } catch (e) {
      state = const AsyncData(null);
      return 'فشلت عملية الشحن';
    }
  }

  Future<Map<String, dynamic>> purchaseCategory(int categoryId, int quantity) async {
    try {
      final res = await _api.post('/transactions/purchase', data: {
        'category_id': categoryId,
        'quantity': quantity,
      });
      _ref.invalidate(walletBalanceProvider);
      _ref.invalidate(walletTransactionsProvider);
      _ref.invalidate(purchaseHistoryProvider);
      // Refresh profile without invalidating authProvider to avoid
      // GoRouter redirect (invalidate resets status to unknown -> redirect to login)
      _ref.read(authProvider.notifier).refreshProfile();
      return toMap(res.data['data'] ?? res.data);
    } on DioException catch (e) {
      final serverMsg = e.message ?? '';
      if (serverMsg.isNotEmpty) throw serverMsg;
      if (e.response?.statusCode == 422) {
        throw 'تعذر إتمام الشراء. تأكد من الرصيد والكروت المتاحة.';
      }
      throw 'فشلت عملية الشراء، حاول مجدداً';
    } catch (_) {
      throw 'فشلت عملية الشراء، حاول مجدداً';
    }
  }
}

final walletProvider = StateNotifierProvider<WalletNotifier, AsyncValue<void>>((ref) {
  return WalletNotifier(ref.read(apiClientProvider), ref);
});
