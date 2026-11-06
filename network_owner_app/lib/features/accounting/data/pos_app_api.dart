import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../core/utils/json_helpers.dart';
import 'money_api.dart' show AccCollection;
import 'offline_queue.dart';

/// The bound POS point as /pos/home returns it (ACC-07).
class PosHomePoint {
  const PosHomePoint({
    required this.id,
    required this.name,
    required this.status,
    required this.pointsBalance,
    required this.profitBalance,
    required this.creditLimit,
    this.location,
    this.phone,
    this.ownerName,
  });

  final int id;
  final String name;
  final String status;
  final double pointsBalance;
  final double profitBalance;
  final double creditLimit;
  final String? location;
  final String? phone;
  final String? ownerName;

  factory PosHomePoint.fromJson(Map<String, dynamic> j) => PosHomePoint(
        id: (j['id'] as num?)?.toInt() ?? 0,
        name: j['name']?.toString() ?? '',
        status: j['status']?.toString() ?? 'active',
        pointsBalance: (j['points_balance'] as num?)?.toDouble() ?? 0,
        profitBalance: (j['profit_balance'] as num?)?.toDouble() ?? 0,
        creditLimit: (j['credit_limit'] as num?)?.toDouble() ?? 0,
        location: j['location']?.toString(),
        phone: j['phone']?.toString(),
        ownerName: j['owner_name']?.toString(),
      );
}

/// A card package the POS can order or redeem points against —
/// points cost is the server-priced sell price.
class PosPackage {
  const PosPackage({
    required this.id,
    required this.name,
    required this.sellPrice,
    required this.pointsCost,
    required this.unitLabel,
    required this.stockQty,
    required this.available,
  });

  final int id;
  final String name;
  final double sellPrice;
  final double pointsCost;
  final String unitLabel;
  final double stockQty;
  final bool available;

  factory PosPackage.fromJson(Map<String, dynamic> j) => PosPackage(
        id: (j['id'] as num?)?.toInt() ?? 0,
        name: j['name']?.toString() ?? '',
        sellPrice: (j['sell_price'] as num?)?.toDouble() ?? 0,
        pointsCost: (j['points_cost'] as num?)?.toDouble() ?? 0,
        unitLabel: j['unit_label']?.toString() ?? 'كرت',
        stockQty: (j['stock_qty'] as num?)?.toDouble() ?? 0,
        available: j['available'] == true,
      );
}

/// Headline counters for the POS home hero card.
class PosHomeStats {
  const PosHomeStats({
    required this.pendingOrders,
    required this.ordersTotal,
    required this.exchangesTotal,
    required this.pendingWithdrawals,
    required this.pendingWithdrawalsAmount,
    required this.collectedTotal,
  });

  final int pendingOrders;
  final int ordersTotal;
  final int exchangesTotal;
  final int pendingWithdrawals;
  final double pendingWithdrawalsAmount;
  final double collectedTotal;

  factory PosHomeStats.fromJson(Map<String, dynamic> j) => PosHomeStats(
        pendingOrders: (j['pending_orders'] as num?)?.toInt() ?? 0,
        ordersTotal: (j['orders_total'] as num?)?.toInt() ?? 0,
        exchangesTotal: (j['exchanges_total'] as num?)?.toInt() ?? 0,
        pendingWithdrawals:
            (j['pending_withdrawals'] as num?)?.toInt() ?? 0,
        pendingWithdrawalsAmount:
            (j['pending_withdrawals_amount'] as num?)?.toDouble() ?? 0,
        collectedTotal: (j['collected_total'] as num?)?.toDouble() ?? 0,
      );
}

/// A compact order row inside the home aggregate.
class PosHomeOrder {
  const PosHomeOrder({
    required this.id,
    required this.orderNo,
    required this.status,
    required this.totalAmount,
    required this.pointsTotal,
    required this.itemsCount,
    this.createdAt,
  });

  final int id;
  final String orderNo;
  final String status;
  final double totalAmount;
  final double pointsTotal;
  final int itemsCount;
  final String? createdAt;

  factory PosHomeOrder.fromJson(Map<String, dynamic> j) => PosHomeOrder(
        id: (j['id'] as num?)?.toInt() ?? 0,
        orderNo: j['order_no']?.toString() ?? '',
        status: j['status']?.toString() ?? 'pending',
        totalAmount: (j['total_amount'] as num?)?.toDouble() ?? 0,
        pointsTotal: (j['points_total'] as num?)?.toDouble() ?? 0,
        itemsCount: (j['items_count'] as num?)?.toInt() ?? 0,
        createdAt: j['created_at']?.toString(),
      );
}

/// One signed movement in the point's points/profit feed.
class PosLedgerRow {
  const PosLedgerRow({
    required this.kind,
    required this.reason,
    required this.delta,
    this.balanceAfter,
    this.note,
    this.createdAt,
  });

  final String kind; // points | profit
  final String reason;
  final double delta;
  final double? balanceAfter;
  final String? note;
  final String? createdAt;

  bool get isPoints => kind == 'points';
  bool get isCredit => delta > 0;

  static const reasonLabels = {
    'order_purchase': 'شراء حزم',
    'conversion': 'استبدال نقاط',
    'adjustment': 'تسوية',
    'bonus': 'مكافأة',
    'sale_commission': 'عمولة بيع',
    'withdrawal': 'سحب أرباح',
  };
  String get reasonLabel => reasonLabels[reason] ?? reason;

  factory PosLedgerRow.fromJson(Map<String, dynamic> j) => PosLedgerRow(
        kind: j['kind']?.toString() ?? 'points',
        reason: j['reason']?.toString() ?? '',
        delta: (j['delta'] as num?)?.toDouble() ?? 0,
        balanceAfter: (j['balance_after'] as num?)?.toDouble(),
        note: j['note']?.toString(),
        createdAt: j['created_at']?.toString(),
      );
}

/// A compact received-collection row inside the home aggregate.
class PosHomeCollection {
  const PosHomeCollection({
    required this.id,
    required this.amount,
    required this.currency,
    required this.baseAmount,
    this.collectedAt,
    this.note,
  });

  final int id;
  final double amount;
  final String currency;
  final double baseAmount;
  final String? collectedAt;
  final String? note;

  factory PosHomeCollection.fromJson(Map<String, dynamic> j) =>
      PosHomeCollection(
        id: (j['id'] as num?)?.toInt() ?? 0,
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
        currency: j['currency']?.toString() ?? 'north',
        baseAmount: (j['base_amount'] as num?)?.toDouble() ?? 0,
        collectedAt: j['collected_at']?.toString(),
        note: j['note']?.toString(),
      );
}

/// The /pos/home aggregate — one round-trip for the whole surface.
class PosHomeData {
  const PosHomeData({
    required this.pos,
    required this.packages,
    required this.stats,
    required this.recentOrders,
    required this.recentLedger,
    required this.recentCollections,
    this.agentName,
  });

  final PosHomePoint pos;
  final List<PosPackage> packages;
  final PosHomeStats stats;
  final List<PosHomeOrder> recentOrders;
  final List<PosLedgerRow> recentLedger;
  final List<PosHomeCollection> recentCollections;
  final String? agentName;

  factory PosHomeData.fromJson(Map<String, dynamic> j) => PosHomeData(
        pos: PosHomePoint.fromJson(toMap(j['pos'])),
        agentName: toMap(j['agent'])['display_name']?.toString(),
        packages:
            toMapList(j['packages']).map(PosPackage.fromJson).toList(),
        stats: PosHomeStats.fromJson(toMap(j['stats'])),
        recentOrders: toMapList(j['recent_orders'])
            .map(PosHomeOrder.fromJson)
            .toList(),
        recentLedger: toMapList(j['recent_ledger'])
            .map(PosLedgerRow.fromJson)
            .toList(),
        recentCollections: toMapList(j['recent_collections'])
            .map(PosHomeCollection.fromJson)
            .toList(),
      );
}

/// A profit withdrawal request in its lifecycle:
/// pending → approved → paid | rejected | cancelled.
class PosWithdrawal {
  const PosWithdrawal({
    required this.id,
    required this.amount,
    required this.status,
    this.receiverName,
    this.receiptNo,
    this.note,
    this.reviewNote,
    this.reviewedAt,
    this.paidAt,
    this.createdAt,
  });

  final int id;
  final double amount;
  final String status;
  final String? receiverName;
  final String? receiptNo;
  final String? note;
  final String? reviewNote;
  final String? reviewedAt;
  final String? paidAt;
  final String? createdAt;

  bool get isPending => status == 'pending';
  bool get isPaid => status == 'paid';
  bool get isRejected => status == 'rejected';
  bool get isCancelled => status == 'cancelled';
  bool get isApproved => status == 'approved';

  static const statusLabels = {
    'pending': 'بانتظار المراجعة',
    'approved': 'معتمد',
    'paid': 'مصروف',
    'rejected': 'مرفوض',
    'cancelled': 'ملغي',
  };
  String get statusLabel => statusLabels[status] ?? status;

  factory PosWithdrawal.fromJson(Map<String, dynamic> j) =>
      PosWithdrawal(
        id: (j['id'] as num).toInt(),
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
        status: j['status']?.toString() ?? 'pending',
        receiverName: j['receiver_name']?.toString(),
        receiptNo: j['receipt_no']?.toString(),
        note: j['note']?.toString(),
        reviewNote: j['review_note']?.toString(),
        reviewedAt: j['reviewed_at']?.toString(),
        paidAt: j['paid_at']?.toString(),
        createdAt: j['created_at']?.toString(),
      );
}

/// A completed card-for-points redemption (ACC-07).
class PosExchange {
  const PosExchange({
    required this.id,
    required this.categoryName,
    required this.qty,
    required this.unitPrice,
    required this.pointsSpent,
    required this.status,
    this.categoryId,
    this.note,
    this.createdAt,
  });

  final int id;
  final int? categoryId;
  final String categoryName;
  final int qty;
  final double unitPrice;
  final double pointsSpent;
  final String status;
  final String? note;
  final String? createdAt;

  factory PosExchange.fromJson(Map<String, dynamic> j) => PosExchange(
        id: (j['id'] as num).toInt(),
        categoryId: (j['category_id'] as num?)?.toInt(),
        categoryName: j['category_name']?.toString() ?? '',
        qty: (j['qty'] as num?)?.toInt() ?? 0,
        unitPrice: (j['unit_price'] as num?)?.toDouble() ?? 0,
        pointsSpent: (j['points_spent'] as num?)?.toDouble() ?? 0,
        status: j['status']?.toString() ?? 'completed',
        note: j['note']?.toString(),
        createdAt: j['created_at']?.toString(),
      );
}

/// Thin client for the ACC-07 POS surface (/pos/*) — same
/// conventions as AccApi/PosOrdersApi.
class PosAppApi {
  PosAppApi(this._api);

  final ApiClient _api;
  static const _base = '/network-owner/accounting';

  // ── Home + activity ──────────────────────────────────────────

  Future<PosHomeData> home() async {
    final res = await _api.get('$_base/pos/home');
    final j = res.data is Map ? toMap(res.data) : <String, dynamic>{};
    return PosHomeData.fromJson(toMap(j['data']));
  }

  Future<List<PosLedgerRow>> ledger() async {
    final res = await _api.get('$_base/pos/ledger');
    return toMapList(res.data?['data'])
        .map(PosLedgerRow.fromJson)
        .toList();
  }

  // ── Withdrawals ──────────────────────────────────────────────

  Future<List<PosWithdrawal>> withdrawals() async {
    final res = await _api.get('$_base/pos/withdrawals');
    return toMapList(res.data?['data']?['data'])
        .map(PosWithdrawal.fromJson)
        .toList();
  }

  Future<String> requestWithdrawal(Map<String, dynamic> data) async =>
      _write(
        () => _api.post('$_base/pos/withdrawals', data: data),
        offlineOp: 'pos.withdrawal',
        offlinePayload: data,
      );

  Future<String> cancelWithdrawal(int id) async => _write(
      () => _api.post('$_base/pos/withdrawals/$id/cancel'));

  // ── Exchange ─────────────────────────────────────────────────

  Future<List<PosExchange>> exchanges() async {
    final res = await _api.get('$_base/pos/exchanges');
    return toMapList(res.data?['data']?['data'])
        .map(PosExchange.fromJson)
        .toList();
  }

  Future<String> exchangeCards(Map<String, dynamic> data) async => _write(
        () => _api.post('$_base/pos/exchange-cards', data: data),
        offlineOp: 'pos.exchange',
        offlinePayload: data,
      );

  // ── Collections received (ACC-05 endpoint, POS surface) ────────

  Future<List<AccCollection>> collectionsReceived() async {
    final res = await _api.get('$_base/pos/collections-received');
    return toMapList(res.data?['data']?['data'])
        .map(AccCollection.fromJson)
        .toList();
  }

  /// Unwraps `{success, message}` — connectivity failures can
  /// enqueue for /sync/push instead of throwing (ACC-12).
  Future<String> _write(
    Future<Response> Function() call, {
    String? offlineOp,
    Map<String, dynamic>? offlinePayload,
  }) =>
      accWriteOrQueue(call,
          offlineOp: offlineOp, offlinePayload: offlinePayload);
}
