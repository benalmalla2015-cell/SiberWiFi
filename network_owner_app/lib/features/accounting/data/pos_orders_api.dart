import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../core/utils/json_helpers.dart';
import 'offline_queue.dart';

/// One bundle line of a POS order (ACC-04).
class PosOrderItem {
  const PosOrderItem({
    required this.id,
    required this.qty,
    required this.unitPrice,
    required this.unitCost,
    required this.lineTotal,
    this.categoryId,
    this.categoryName,
  });

  final int id;
  final int? categoryId;
  final String? categoryName;
  final int qty;
  final double unitPrice;
  final double unitCost;
  final double lineTotal;

  factory PosOrderItem.fromJson(Map<String, dynamic> j) => PosOrderItem(
        id: (j['id'] as num?)?.toInt() ?? 0,
        categoryId: (j['category_id'] as num?)?.toInt(),
        categoryName: j['category_name']?.toString(),
        qty: (j['qty'] as num?)?.toInt() ?? 0,
        unitPrice: (j['unit_price'] as num?)?.toDouble() ?? 0,
        unitCost: (j['unit_cost'] as num?)?.toDouble() ?? 0,
        lineTotal: (j['line_total'] as num?)?.toDouble() ?? 0,
      );
}

/// A POS bundle order — pending | approved | rejected.
class PosOrder {
  const PosOrder({
    required this.id,
    required this.orderNo,
    required this.status,
    required this.totalAmount,
    required this.pointsTotal,
    required this.items,
    this.posId,
    this.posName,
    this.posPointsBalance,
    this.distributorId,
    this.distributorName,
    this.note,
    this.rejectReason,
    this.approvedAt,
    this.createdAt,
  });

  final int id;
  final String orderNo;
  final String status;
  final double totalAmount;
  final double pointsTotal;
  final List<PosOrderItem> items;
  final int? posId;
  final String? posName;
  final double? posPointsBalance;
  final int? distributorId;
  final String? distributorName;
  final String? note;
  final String? rejectReason;
  final String? approvedAt;
  final String? createdAt;

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
  int get totalQty => items.fold(0, (s, i) => s + i.qty);

  factory PosOrder.fromJson(Map<String, dynamic> j) => PosOrder(
        id: (j['id'] as num).toInt(),
        orderNo: j['order_no']?.toString() ?? '',
        status: j['status']?.toString() ?? 'pending',
        totalAmount: (j['total_amount'] as num?)?.toDouble() ?? 0,
        pointsTotal: (j['points_total'] as num?)?.toDouble() ?? 0,
        posId: (j['pos_id'] as num?)?.toInt(),
        posName: j['pos_name']?.toString(),
        posPointsBalance: (j['pos_points_balance'] as num?)?.toDouble(),
        distributorId: (j['distributor_id'] as num?)?.toInt(),
        distributorName: j['distributor_name']?.toString(),
        note: j['note']?.toString(),
        rejectReason: j['reject_reason']?.toString(),
        approvedAt: j['approved_at']?.toString(),
        createdAt: j['created_at']?.toString(),
        items: toMapList(j['items']).map(PosOrderItem.fromJson).toList(),
      );
}

/// The POS point summary returned alongside /pos/orders — drives
/// the request surface's balance header.
class PosPointSummary {
  const PosPointSummary({
    required this.id,
    required this.name,
    required this.pointsBalance,
    required this.profitBalance,
  });

  final int id;
  final String name;
  final double pointsBalance;
  final double profitBalance;

  factory PosPointSummary.fromJson(Map<String, dynamic> j) =>
      PosPointSummary(
        id: (j['id'] as num?)?.toInt() ?? 0,
        name: j['name']?.toString() ?? '',
        pointsBalance: (j['points_balance'] as num?)?.toDouble() ?? 0,
        profitBalance: (j['profit_balance'] as num?)?.toDouble() ?? 0,
      );
}

/// Orders + the caller's own point (POS surface result).
class MyPosOrders {
  const MyPosOrders({required this.orders, this.pos});

  final List<PosOrder> orders;
  final PosPointSummary? pos;
}

/// Thin client for the ACC-04 order endpoints — same conventions
/// as AccApi (writes return the Arabic message or throw it).
class PosOrdersApi {
  PosOrdersApi(this._api);

  final ApiClient _api;
  static const _base = '/network-owner/accounting';

  // ── Management surface ───────────────────────────────────────

  Future<List<PosOrder>> orders({String? status, int? posId}) async {
    final res = await _api.get('$_base/pos-orders', params: {
      'status': ?status,
      'pos_id': ?posId,
    });
    return toMapList(res.data?['data']?['data'])
        .map(PosOrder.fromJson)
        .toList();
  }

  Future<String> createOrder(Map<String, dynamic> data) async => _write(
        () => _api.post('$_base/pos-orders', data: data),
        offlineOp: 'pos.order',
        offlinePayload: data,
      );

  Future<String> approve(int orderId) async =>
      _write(() => _api.post('$_base/pos-orders/$orderId/approve'));

  Future<String> reject(int orderId, {String? reason}) async => _write(
        () => _api.post('$_base/pos-orders/$orderId/reject',
            data: {'reason': ?reason}),
      );

  // ── POS surface ──────────────────────────────────────────────

  Future<MyPosOrders> myOrders({String? status}) async {
    final res = await _api.get('$_base/pos/orders', params: {
      'status': ?status,
    });
    final j = res.data is Map ? toMap(res.data) : <String, dynamic>{};
    return MyPosOrders(
      orders: toMapList(j['data']?['data']).map(PosOrder.fromJson).toList(),
      pos: j['pos'] is Map ? PosPointSummary.fromJson(toMap(j['pos'])) : null,
    );
  }

  Future<String> submitOrder(Map<String, dynamic> data) async => _write(
        () => _api.post('$_base/pos/orders', data: data),
        offlineOp: 'pos.order',
        offlinePayload: data,
      );

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
