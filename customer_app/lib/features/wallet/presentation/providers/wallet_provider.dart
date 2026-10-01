import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/api/api_client.dart';
import '../../../../core/cache/hive_service.dart';
import '../../../../core/utils/connectivity_service.dart';
import '../../../../core/utils/json_helpers.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class WalletBalanceInfo {
  final double balance;
  final double advanceBalance;
  final bool isEligibleForAdvance;
  const WalletBalanceInfo({
    this.balance = 0,
    this.advanceBalance = 0,
    this.isEligibleForAdvance = false,
  });
}

final chargingPointEligibilityProvider = FutureProvider<bool>((ref) async {
  try {
    final api = ref.read(apiClientProvider);
    final res = await api.get('/charging-points/me');
    return res.data['success'] == true;
  } catch (_) {
    return false;
  }
});

final walletBalanceProvider = FutureProvider<WalletBalanceInfo>((ref) async {
  final online = await ConnectivityService.isConnected();
  if (!online) {
    final cached = HiveService.walletBox.get('balance');
    return WalletBalanceInfo(balance: (cached ?? 0.0).toDouble());
  }
  try {
    final api = ref.read(apiClientProvider);
    final res = await api.get('/wallet/balance');
    final data = res.data['data'] ?? {};
    final info = WalletBalanceInfo(
      balance: (data['balance'] ?? 0).toDouble(),
      advanceBalance: (data['advance_balance'] ?? 0).toDouble(),
      isEligibleForAdvance: data['is_eligible_for_advance'] == true,
    );
    await HiveService.walletBox.put('balance', info.balance);
    // Keep the cached user profile in sync with the live balance and advance eligibility.
    final user = ref.read(authProvider).user;
    if (user != null) {
      final updated = user.copyWith(
        balance: info.balance,
        advanceBalance: info.advanceBalance,
        isEligibleForAdvance: info.isEligibleForAdvance,
      );
      await HiveService.saveUser(updated);
      // Update auth state directly so any screen reading user.balance refreshes immediately.
      ref.read(authProvider.notifier).updateUser(updated);
    }
    return info;
  } catch (_) {
    final cached = HiveService.walletBox.get('balance');
    return WalletBalanceInfo(balance: (cached ?? 0.0).toDouble());
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
    // Cache each purchase so it is available offline via the detail provider.
    for (final item in list) {
      final id = (item['id'] as num?)?.toInt();
      if (id != null) await HiveService.transactionsBox.put('purchase_$id', item);
    }
    return list;
  } catch (_) {
    final cached = HiveService.transactionsBox.get('purchases');
    if (cached != null) return toMapList(cached);
    return [];
  }
});

// Full invoice details (including the card code/serial) for a single purchase.
final purchaseDetailProvider = FutureProvider.family<Map<String, dynamic>, int>((ref, id) async {
  final online = await ConnectivityService.isConnected();
  final cacheKey = 'purchase_$id';
  Map<String, dynamic>? _fromList() {
    final list = HiveService.transactionsBox.get('purchases');
    if (list == null) return null;
    for (final item in toMapList(list)) {
      if ((item['id'] as num?)?.toInt() == id) return item;
    }
    return null;
  }

  if (!online) {
    final cached = HiveService.transactionsBox.get(cacheKey);
    if (cached != null) return toMap(cached);
    final fromList = _fromList();
    if (fromList != null) return fromList;
    throw 'لا يوجد اتصال بالإنترنت ولا توجد نسخة محفوظة لهذه الفاتورة';
  }
  try {
    final api = ref.read(apiClientProvider);
    final res = await api.get('/transactions/$id');
    final data = toMap(res.data['data'] ?? res.data);
    await HiveService.transactionsBox.put(cacheKey, data);
    return data;
  } catch (_) {
    final cached = HiveService.transactionsBox.get(cacheKey);
    if (cached != null) return toMap(cached);
    final fromList = _fromList();
    if (fromList != null) return fromList;
    throw 'تعذر تحميل تفاصيل الفاتورة';
  }
});

class WalletNotifier extends StateNotifier<AsyncValue<void>> {
  final ApiClient _api;
  final Ref _ref;
  WalletNotifier(this._api, this._ref) : super(const AsyncData(null));

  Future<Map<String, dynamic>> searchCustomer(String phone) async {
    try {
      final res = await _api.get('/wallet/customers/search', params: {'phone': phone});
      return toMap(res.data['data'] ?? {});
    } on DioException catch (e) {
      throw e.message ?? 'تعذر البحث عن العميل';
    }
  }

  Future<String?> transfer({required String phone, required double amount}) async {
    state = const AsyncLoading();
    try {
      await _api.post('/wallet/transfer', data: {'phone': phone, 'amount': amount.toStringAsFixed(2)});
      _ref.invalidate(walletBalanceProvider);
      _ref.invalidate(walletTransactionsProvider);
      _ref.read(authProvider.notifier).refreshProfile();
      state = const AsyncData(null);
      return null;
    } on DioException catch (e) {
      state = const AsyncData(null);
      return e.message ?? 'فشلت عملية شحن الرصيد';
    } catch (_) {
      state = const AsyncData(null);
      return 'فشلت عملية شحن الرصيد';
    }
  }

  Future<String?> topup({
    required double amount,
    int? bankAccountId,
    String? transferReceiptNumber,
    String? senderName,
    File? receiptImage,
  }) async {
    state = const AsyncLoading();
    try {
      final formData = FormData.fromMap({
        'amount': amount.toString(),
        if (bankAccountId != null) 'bank_account_id': bankAccountId.toString(),
        if (transferReceiptNumber != null && transferReceiptNumber.isNotEmpty)
          'transfer_receipt_number': transferReceiptNumber,
        if (senderName != null && senderName.isNotEmpty) 'sender_name': senderName,
        if (receiptImage != null)
          'receipt_image': await MultipartFile.fromFile(
            receiptImage.path,
            filename: receiptImage.path.split('/').last,
          ),
      });
      await _api.post('/wallet/topup', data: formData);
      _ref.invalidate(walletBalanceProvider);
      _ref.invalidate(walletTransactionsProvider);
      _ref.read(authProvider.notifier).refreshProfile();
      state = const AsyncData(null);
      return null;
    } on DioException catch (e) {
      state = const AsyncData(null);
      return e.message ?? 'فشلت عملية الشحن';
    } catch (_) {
      state = const AsyncData(null);
      return 'فشلت عملية الشحن';
    }
  }

  Future<Map<String, dynamic>> purchaseCategory(
    int categoryId,
    int quantity, {
    String paymentMethod = 'wallet',
  }) async {
    try {
      final path = paymentMethod == 'advance'
          ? '/transactions/purchase-advance'
          : '/transactions/purchase';
      final res = await _api.post(path, data: {
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
