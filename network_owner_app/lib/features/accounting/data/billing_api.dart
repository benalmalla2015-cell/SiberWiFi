import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../core/utils/json_helpers.dart';

/// Server-side accounting subscription state returned by
/// GET /network-owner/accounting/billing/entitlements — same shape
/// as the mikrotik entitlements payload, resolved per tenant
/// (network_owner_id) so every agent sees the owner's plan.
class AccEntitlementState {
  const AccEntitlementState({
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

  /// Backend gate switch (acc.enforce setting). While false the app
  /// keeps allow-all behaviour — nothing is paywalled until the
  /// admin flips the setting after verification.
  final bool enforced;
  final int trialDays;
  final String? planName;
  final DateTime? trialEndsAt;
  final DateTime? endsAt;
  final List<String> features;

  static DateTime? _dt(dynamic v) =>
      v == null ? null : DateTime.tryParse(v.toString());

  factory AccEntitlementState.fromJson(Map<String, dynamic> j) {
    final plan = j['plan'];
    return AccEntitlementState(
      status: j['status']?.toString() ?? 'trial',
      trialing: j['trialing'] == true,
      active: j['active'] == true,
      enforced: j['enforce'] == true || j['enforce'] == 1,
      trialDays: (j['trial_days'] as num?)?.toInt() ?? 30,
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

/// A paid accounting plan returned by GET …/billing/plans.
class AccPlan {
  const AccPlan({
    required this.id,
    required this.name,
    required this.price,
    required this.currency,
    required this.durationDays,
    this.description,
    this.features = const [],
  });

  final int id;
  final String name;
  final double price;
  final String currency;
  final int durationDays;
  final String? description;
  final List<String> features;

  factory AccPlan.fromJson(Map<String, dynamic> j) => AccPlan(
        id: (j['id'] as num).toInt(),
        name: j['name']?.toString() ?? '',
        price: (j['price'] as num?)?.toDouble() ?? 0,
        currency: j['currency']?.toString() ?? 'YER',
        durationDays: (j['duration_days'] as num?)?.toInt() ?? 30,
        description: j['description']?.toString(),
        features: (j['features'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
      );
}

/// A manual bank/e-wallet transfer request for an accounting plan —
/// its own pipeline (acc_payment_requests), reviewed independently
/// by admins (Filament, ADM-01).
class AccPaymentRequest {
  const AccPaymentRequest({
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

  factory AccPaymentRequest.fromJson(Map<String, dynamic> j) =>
      AccPaymentRequest(
        id: (j['id'] as num).toInt(),
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
        status: j['status']?.toString() ?? 'pending',
        plan: j['plan']?.toString(),
        senderName: j['sender_name']?.toString(),
        adminNote: j['admin_note']?.toString(),
        createdAt: j['created_at']?.toString(),
      );
}

/// The plans endpoint's extra payload — gate knobs and the optional
/// admin-editable pricing note shown on the packages screen.
class AccPlansPayload {
  const AccPlansPayload({
    required this.plans,
    required this.trialDays,
    required this.enforced,
    this.pricingNote,
    this.freeFeatures = const [],
  });

  final List<AccPlan> plans;
  final int trialDays;
  final bool enforced;
  final String? pricingNote;
  final List<String> freeFeatures;
}

/// Thin client for the ACC-11 billing endpoints
/// (routes/api_accounting.php → /network-owner/accounting/billing/*).
/// Read paths are best-effort-safe: entitlements returns null when
/// the backend is unreachable so the app stays in allow-all mode.
class AccBillingApi {
  AccBillingApi(this._api);

  final ApiClient _api;
  static const _base = '/network-owner/accounting/billing';

  /// Null when the endpoint is unreachable — caller keeps allow-all.
  Future<AccEntitlementState?> entitlements() async {
    try {
      final res = await _api.get('$_base/entitlements');
      final j = res.data is Map ? toMap(res.data) : null;
      if (j?['success'] == true) {
        return AccEntitlementState.fromJson(toMap(j));
      }
    } catch (_) {}
    return null;
  }

  Future<AccPlansPayload> plans() async {
    final res = await _api.get('$_base/plans');
    final j = res.data is Map ? toMap(res.data) : null;
    final list = j?['data'];
    return AccPlansPayload(
      plans: list is List
          ? list
              .whereType<Map>()
              .map((e) => AccPlan.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      trialDays: (j?['trial_days'] as num?)?.toInt() ?? 30,
      enforced: j?['enforce'] == true || j?['enforce'] == 1,
      pricingNote: j?['pricing_note']?.toString(),
      freeFeatures: (j?['free_features'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }

  /// Wallet payment — debits the acting account's wallet server-side
  /// (WalletLog reference_type='acc_subscription'). Throws a
  /// user-facing Arabic message on failure.
  Future<String> subscribe(int planId) async {
    final res = await _api.post('$_base/subscribe', data: {'plan_id': planId});
    final j = res.data is Map ? toMap(res.data) : null;
    if (j?['success'] == true) {
      return j!['message']?.toString() ?? 'تم تفعيل اشتراكك بنجاح';
    }
    throw Exception(j?['message']?.toString() ?? 'تعذر إتمام الاشتراك');
  }

  Future<List<AccPaymentRequest>> paymentRequests() async {
    final res = await _api.get('$_base/payments');
    final j = res.data is Map ? toMap(res.data) : null;
    final list = j?['data'];
    if (list is List) {
      return list
          .whereType<Map>()
          .map((e) =>
              AccPaymentRequest.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    return const [];
  }

  /// Manual transfer request — same sender-name + receipt workflow
  /// as the mikrotik payments pipeline, stored in acc_payment_requests.
  Future<String> submitPaymentRequest({
    required int planId,
    required String senderName,
    int? bankAccountId,
    String? receiptNumber,
    String? receiptImagePath,
  }) async {
    final res = await _api.post(
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
    final j = res.data is Map ? toMap(res.data) : null;
    if (j?['success'] == true) {
      return j!['message']?.toString() ?? 'تم إرسال طلب الدفع';
    }
    throw Exception(j?['message']?.toString() ?? 'تعذر إرسال طلب الدفع');
  }
}
