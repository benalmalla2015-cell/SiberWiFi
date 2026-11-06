import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../core/utils/json_helpers.dart';

/// A discount/reward tier (ACC-10, PLAN §2.4) — one bracket over a
/// document's qty or amount that earns a configured reward.
class AccDiscountTier {
  const AccDiscountTier({
    required this.id,
    required this.mode,
    required this.modeLabel,
    required this.basis,
    required this.min,
    required this.rewardValue,
    required this.rewardUnit,
    required this.sortOrder,
    required this.isActive,
    this.max,
  });

  final int id;
  final String mode; // commission|points|profit_balance|direct_percent
  final String modeLabel;
  final String basis; // qty|amount
  final double min;
  final double? max; // null = open-ended bracket
  final double rewardValue;
  final String rewardUnit; // percent|fixed
  final int sortOrder;
  final bool isActive;

  String get basisLabel => basis == 'qty' ? 'الكمية' : 'المبلغ';
  String get rewardLabel => rewardUnit == 'percent'
      ? '$rewardValue%'
      : '$rewardValue ثابت';
  String get bracketLabel =>
      'من $min${max != null ? ' إلى $max' : ' فأكثر'}';

  factory AccDiscountTier.fromJson(Map<String, dynamic> j) =>
      AccDiscountTier(
        id: (j['id'] as num).toInt(),
        mode: j['mode']?.toString() ?? 'direct_percent',
        modeLabel: j['mode_label']?.toString() ?? '',
        basis: j['basis']?.toString() ?? 'qty',
        min: (j['min'] as num?)?.toDouble() ?? 0,
        max: (j['max'] as num?)?.toDouble(),
        rewardValue: (j['reward_value'] as num?)?.toDouble() ?? 0,
        rewardUnit: j['reward_unit']?.toString() ?? 'percent',
        sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
        isActive: j['is_active'] == true,
      );
}

/// One matched tier in the /discount-tiers/match preview.
class AccTierMatch {
  const AccTierMatch({
    required this.tierId,
    required this.mode,
    required this.modeLabel,
    required this.reward,
  });

  final int tierId;
  final String mode;
  final String modeLabel;
  final double reward;

  factory AccTierMatch.fromJson(Map<String, dynamic> j) => AccTierMatch(
        tierId: (j['tier_id'] as num?)?.toInt() ?? 0,
        mode: j['mode']?.toString() ?? '',
        modeLabel: j['mode_label']?.toString() ?? '',
        reward: (j['reward'] as num?)?.toDouble() ?? 0,
      );
}

/// A WhatsApp notification template bound to an accounting event
/// (ACC-10, PLAN §2.5).
class AccWebhookEventRow {
  const AccWebhookEventRow({
    required this.id,
    required this.event,
    required this.eventLabel,
    required this.channel,
    required this.templateBody,
    required this.isActive,
    required this.placeholders,
  });

  final int id;
  final String event;
  final String eventLabel;
  final String channel;
  final String templateBody;
  final bool isActive;
  final List<String> placeholders;

  factory AccWebhookEventRow.fromJson(Map<String, dynamic> j) =>
      AccWebhookEventRow(
        id: (j['id'] as num).toInt(),
        event: j['event']?.toString() ?? '',
        eventLabel: j['event_label']?.toString() ?? '',
        channel: j['channel']?.toString() ?? 'whatsapp',
        templateBody: j['template_body']?.toString() ?? '',
        isActive: j['is_active'] == true,
        placeholders: (j['placeholders'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
      );
}

/// A rendered due-debt reminder (GET /notifications/debt-due).
class AccDebtDueReminder {
  const AccDebtDueReminder({
    required this.debtId,
    required this.partyName,
    required this.remaining,
    required this.body,
    this.currency,
    this.dueDate,
    this.waUrl,
  });

  final int debtId;
  final String partyName;
  final double remaining;
  final String body;
  final String? currency;
  final String? dueDate;
  final String? waUrl;

  factory AccDebtDueReminder.fromJson(Map<String, dynamic> j) =>
      AccDebtDueReminder(
        debtId: (j['debt_id'] as num).toInt(),
        partyName: j['party_name']?.toString() ?? '',
        remaining: (j['remaining'] as num?)?.toDouble() ?? 0,
        body: j['body']?.toString() ?? '',
        currency: j['currency']?.toString(),
        dueDate: j['due_date']?.toString(),
        waUrl: j['wa_url']?.toString(),
      );
}

/// One party row of GET /balances (ACC-10) — journal balance plus
/// the POS wallets when the party is a point.
class AccBalanceRow {
  const AccBalanceRow({
    required this.partyType,
    required this.partyId,
    required this.partyName,
    required this.balance,
    this.pointsBalance,
    this.profitBalance,
  });

  final String partyType;
  final int partyId;
  final String partyName;
  final double balance;
  final double? pointsBalance;
  final double? profitBalance;

  static const partyLabels = {
    'pos': 'نقطة بيع',
    'distributor': 'موزع',
    'customer': 'عميل',
    'box': 'صندوق',
    'supplier': 'مورد',
    'person': 'شخص',
  };
  String get partyLabel => partyLabels[partyType] ?? partyType;

  /// Signed-balance meaning: receivable parties owe us when
  /// positive; a box is an asset we hold when positive.
  bool get isAssetSide => partyType == 'box';

  factory AccBalanceRow.fromJson(Map<String, dynamic> j) =>
      AccBalanceRow(
        partyType: j['party_type']?.toString() ?? '',
        partyId: (j['party_id'] as num?)?.toInt() ?? 0,
        partyName: j['party_name']?.toString() ?? '',
        balance: (j['balance'] as num?)?.toDouble() ?? 0,
        pointsBalance: (j['points_balance'] as num?)?.toDouble(),
        profitBalance: (j['profit_balance'] as num?)?.toDouble(),
      );
}

/// A withdrawal request in the management review queue (ACC-07/10).
class AccWithdrawalRow {
  const AccWithdrawalRow({
    required this.id,
    required this.requesterType,
    required this.requesterName,
    required this.amount,
    required this.status,
    this.receiverName,
    this.receiptNo,
    this.note,
    this.reviewNote,
    this.createdAt,
  });

  final int id;
  final String requesterType; // pos|distributor
  final String requesterName;
  final double amount;
  final String status;
  final String? receiverName;
  final String? receiptNo;
  final String? note;
  final String? reviewNote;
  final String? createdAt;

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isPaid => status == 'paid';

  static const statusLabels = {
    'pending': 'بانتظار المراجعة',
    'approved': 'معتمد',
    'paid': 'مصروف',
    'rejected': 'مرفوض',
    'cancelled': 'ملغي',
  };
  String get statusLabel => statusLabels[status] ?? status;

  factory AccWithdrawalRow.fromJson(Map<String, dynamic> j) =>
      AccWithdrawalRow(
        id: (j['id'] as num).toInt(),
        requesterType: j['requester_type']?.toString() ?? 'pos',
        requesterName: j['requester_name']?.toString() ?? '',
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
        status: j['status']?.toString() ?? 'pending',
        receiverName: j['receiver_name']?.toString(),
        receiptNo: j['receipt_no']?.toString(),
        note: j['note']?.toString(),
        reviewNote: j['review_note']?.toString(),
        createdAt: j['created_at']?.toString(),
      );
}

/// Thin client for the ACC-10 surface — tiers, webhook templates,
/// balances, and the withdrawal review queue. Same conventions as
/// MoneyApi (writes return the Arabic message or throw it).
class LoyaltyApi {
  LoyaltyApi(this._api);

  final ApiClient _api;
  static const _base = '/network-owner/accounting';

  // ── Discount tiers ───────────────────────────────────────────

  Future<List<AccDiscountTier>> tiers() async {
    final res = await _api.get('$_base/discount-tiers');
    return toMapList(res.data?['data'])
        .map(AccDiscountTier.fromJson)
        .toList();
  }

  Future<String> createTier(Map<String, dynamic> data) async =>
      _write(() => _api.post('$_base/discount-tiers', data: data));

  Future<String> updateTier(int id, Map<String, dynamic> data) async =>
      _write(() => _api.put('$_base/discount-tiers/$id', data: data));

  Future<String> deleteTier(int id) async =>
      _write(() => _api.delete('$_base/discount-tiers/$id'));

  /// Preview which tiers a document {qty, amount} would earn.
  Future<List<AccTierMatch>> matchTiers(double qty, double amount) async {
    final res = await _api.post('$_base/discount-tiers/match',
        data: {'qty': qty, 'amount': amount});
    return toMapList(res.data?['data'])
        .map(AccTierMatch.fromJson)
        .toList();
  }

  // ── Webhook event templates ──────────────────────────────────

  Future<List<AccWebhookEventRow>> webhookEvents() async {
    final res = await _api.get('$_base/webhook-events');
    return toMapList(res.data?['data'])
        .map(AccWebhookEventRow.fromJson)
        .toList();
  }

  Future<String> createWebhookEvent(Map<String, dynamic> data) async =>
      _write(() => _api.post('$_base/webhook-events', data: data));

  Future<String> updateWebhookEvent(
          int id, Map<String, dynamic> data) async =>
      _write(() => _api.put('$_base/webhook-events/$id', data: data));

  Future<String> deleteWebhookEvent(int id) async =>
      _write(() => _api.delete('$_base/webhook-events/$id'));

  /// Rendered preview of a template body (server-side render).
  Future<String> previewWebhookEvent(int id) async {
    final res =
        await _api.post('$_base/webhook-events/$id/preview', data: {});
    return toMap(res.data?['data'])['body']?.toString() ?? '';
  }

  /// Due-debt reminders with their rendered WhatsApp messages.
  Future<List<AccDebtDueReminder>> dueDebts() async {
    final res = await _api.get('$_base/notifications/debt-due');
    return toMapList(res.data?['data'])
        .map(AccDebtDueReminder.fromJson)
        .toList();
  }

  // ── Balances ─────────────────────────────────────────────────

  Future<List<AccBalanceRow>> balances({String? party}) async {
    final res = await _api.get('$_base/balances', params: {
      'party': ?party,
    });
    return toMapList(res.data?['data'])
        .map(AccBalanceRow.fromJson)
        .toList();
  }

  // ── Withdrawals review ───────────────────────────────────────

  Future<List<AccWithdrawalRow>> withdrawals({String? status}) async {
    final res = await _api.get('$_base/withdrawals', params: {
      'status': ?status,
    });
    return toMapList(res.data?['data']?['data'])
        .map(AccWithdrawalRow.fromJson)
        .toList();
  }

  Future<String> approveWithdrawal(int id) async =>
      _write(() => _api.post('$_base/withdrawals/$id/approve'));

  Future<String> payWithdrawal(int id, Map<String, dynamic> data) async =>
      _write(() => _api.post('$_base/withdrawals/$id/paid', data: data));

  Future<String> rejectWithdrawal(int id, {String? reason}) async =>
      _write(() => _api.post('$_base/withdrawals/$id/reject',
          data: {'reason': ?reason}));

  /// Unwraps `{success, message}` — the message field is always the
  /// user-facing Arabic copy, whether success or failure.
  Future<String> _write(Future<Response> Function() call) async {
    try {
      final res = await call();
      final j = res.data is Map ? toMap(res.data) : null;
      if (j?['success'] == true) {
        return j!['message']?.toString() ?? 'تمت العملية';
      }
      throw Exception(j?['message']?.toString() ?? 'تعذر تنفيذ العملية');
    } on DioException catch (e) {
      throw Exception(e.message ?? 'تعذر تنفيذ العملية');
    }
  }
}
