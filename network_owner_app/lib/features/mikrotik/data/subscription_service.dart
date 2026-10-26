import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';

/// Server-side MikroTik subscription state returned by
/// GET /network-owner/mikrotik/entitlements.
class MikrotikEntitlementState {
  const MikrotikEntitlementState({
    required this.status,
    required this.trialing,
    required this.active,
    required this.enforced,
    required this.trialDays,
    this.planName,
    this.trialEndsAt,
    this.endsAt,
    this.features = const [],
  });

  final String status;
  final bool trialing;
  final bool active;

  /// Backend gate switch (mikrotik.enforce setting). While false the
  /// app keeps Sprint-0 allow-all behaviour — nothing is paywalled
  /// until the admin flips the setting after verification.
  final bool enforced;
  final int trialDays;
  final String? planName;
  final DateTime? trialEndsAt;
  final DateTime? endsAt;
  final List<String> features;

  static DateTime? _dt(dynamic v) =>
      v == null ? null : DateTime.tryParse(v.toString());

  factory MikrotikEntitlementState.fromJson(Map<String, dynamic> j) {
    final plan = j['plan'];
    return MikrotikEntitlementState(
      status: j['status']?.toString() ?? 'trial',
      trialing: j['trialing'] == true,
      active: j['active'] == true,
      enforced: j['enforce'] == true || j['enforce'] == 1,
      trialDays: (j['trial_days'] as num?)?.toInt() ?? 14,
      planName: plan is Map ? plan['name']?.toString() : null,
      trialEndsAt: _dt(j['trial_ends_at']),
      endsAt: _dt(j['ends_at']),
      features: (j['features'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }
}

/// A paid plan returned by GET /network-owner/mikrotik/plans.
class MikrotikPlan {
  const MikrotikPlan({
    required this.id,
    required this.name,
    required this.price,
    required this.currency,
    required this.durationDays,
    this.description,
  });

  final int id;
  final String name;
  final double price;
  final String currency;
  final int durationDays;
  final String? description;

  factory MikrotikPlan.fromJson(Map<String, dynamic> j) => MikrotikPlan(
        id: (j['id'] as num).toInt(),
        name: j['name']?.toString() ?? '',
        price: (j['price'] as num?)?.toDouble() ?? 0,
        currency: j['currency']?.toString() ?? 'YER',
        durationDays: (j['duration_days'] as num?)?.toInt() ?? 30,
        description: j['description']?.toString(),
      );
}

/// A manual bank/e-wallet transfer request — separate pipeline from
/// wallet top-ups, reviewed independently by admins.
class MikrotikPaymentRequest {
  const MikrotikPaymentRequest({
    required this.id,
    required this.amount,
    required this.status,
    this.plan,
    this.senderName,
    this.adminNote,
    this.createdAt,
  });

  final int id;
  final double amount;
  final String status;
  final String? plan;
  final String? senderName;
  final String? adminNote;
  final String? createdAt;

  factory MikrotikPaymentRequest.fromJson(Map<String, dynamic> j) =>
      MikrotikPaymentRequest(
        id: (j['id'] as num).toInt(),
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
        status: j['status']?.toString() ?? 'pending',
        plan: j['plan']?.toString(),
        senderName: j['sender_name']?.toString(),
        adminNote: j['admin_note']?.toString(),
        createdAt: j['created_at']?.toString(),
      );
}

/// Bank/e-wallet account shown in the transfer form — reuses the
/// shared /bank-accounts endpoint (same as wallet top-up).
class BankAccountOption {
  const BankAccountOption({
    required this.id,
    required this.bankName,
    required this.ownerName,
    required this.accountNumber,
  });

  final int id;
  final String bankName;
  final String ownerName;
  final String accountNumber;

  factory BankAccountOption.fromJson(Map<String, dynamic> j) =>
      BankAccountOption(
        id: (j['id'] as num).toInt(),
        bankName: j['bank_name']?.toString() ?? '',
        ownerName: j['owner_name']?.toString() ?? '',
        accountNumber: j['account_number']?.toString() ?? '',
      );
}

/// Thin client for the MikroTik subscription endpoints added in
/// Sprint 9. Every method is best-effort-safe at the call site:
/// read paths return null/empty on failure so a missing backend
/// leaves the app in allow-all dev mode.
class SubscriptionService {
  SubscriptionService._();

  static const _base = '/network-owner/mikrotik';

  static Map<String, dynamic>? _data(Response res) =>
      res.data is Map ? Map<String, dynamic>.from(res.data as Map) : null;

  /// Null when the endpoint is unreachable — caller keeps allow-all.
  static Future<MikrotikEntitlementState?> entitlements(ApiClient api) async {
    try {
      final res = await api.get('$_base/entitlements');
      final j = _data(res);
      if (j?['success'] == true) return MikrotikEntitlementState.fromJson(j!);
    } catch (_) {}
    return null;
  }

  static Future<List<MikrotikPlan>> plans(ApiClient api) async {
    final res = await api.get('$_base/plans');
    final j = _data(res);
    final list = j?['data'];
    if (list is List) {
      return list
          .whereType<Map>()
          .map((e) => MikrotikPlan.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    return const [];
  }

  /// Wallet payment — debits the existing owner wallet server-side.
  /// Throws a user-facing message on failure (e.g. insufficient balance).
  static Future<String> subscribe(ApiClient api, int planId) async {
    final res =
        await api.post('$_base/subscribe', data: {'plan_id': planId});
    final j = _data(res);
    if (j?['success'] == true) {
      return j!['message']?.toString() ?? 'تم تفعيل اشتراكك بنجاح';
    }
    throw Exception(j?['message']?.toString() ?? 'تعذر إتمام الاشتراك');
  }

  static Future<List<MikrotikPaymentRequest>> paymentRequests(
      ApiClient api) async {
    final res = await api.get('$_base/payments');
    final j = _data(res);
    final list = j?['data'];
    if (list is List) {
      return list
          .whereType<Map>()
          .map((e) =>
              MikrotikPaymentRequest.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    return const [];
  }

  /// Manual transfer request — same sender-name + receipt workflow as
  /// wallet top-up, stored in its own table/endpoint.
  static Future<String> submitPaymentRequest(
    ApiClient api, {
    required int planId,
    required String senderName,
    int? bankAccountId,
    String? receiptNumber,
    String? receiptImagePath,
  }) async {
    final res = await api.post(
      '$_base/payments',
      data: {
        'plan_id': planId,
        'sender_name': senderName,
        'bank_account_id': ?bankAccountId,
        'transfer_receipt_number': ?receiptNumber,
        if (receiptImagePath != null)
          'receipt_image': await MultipartFile.fromFile(receiptImagePath),
      },
    );
    final j = _data(res);
    if (j?['success'] == true) {
      return j!['message']?.toString() ?? 'تم إرسال طلب الدفع';
    }
    throw Exception(j?['message']?.toString() ?? 'تعذر إرسال طلب الدفع');
  }

  static Future<List<BankAccountOption>> bankAccounts(ApiClient api) async {
    final res = await api.get('/bank-accounts');
    final j = _data(res);
    final list = j?['data'];
    if (list is List) {
      return list
          .whereType<Map>()
          .map((e) => BankAccountOption.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    return const [];
  }

  /// Current wallet balance for the "pay from wallet" confirmation.
  static Future<double?> walletBalance(ApiClient api) async {
    try {
      final res = await api.get('/wallet/balance');
      final j = _data(res);
      final data = j?['data'];
      if (data is Map) {
        return (data['available_balance'] as num?)?.toDouble() ??
            (data['balance'] as num?)?.toDouble();
      }
    } catch (_) {}
    return null;
  }
}
