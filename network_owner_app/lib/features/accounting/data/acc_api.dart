import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../core/utils/json_helpers.dart';
import 'offline_queue.dart';

/// The resolved accounting session — which of the three roles the
/// signed-in account operates as under /network-owner/accounting/me
/// (PLAN §1). `role` is owner|admin|distributor|pos.
class AccSession {
  const AccSession({
    required this.role,
    required this.ownerId,
    required this.permissions,
    this.agent,
  });

  final String role;
  final int ownerId;
  final List<String> permissions;
  final AccAgentRef? agent;

  bool get isOwner => role == 'owner';
  bool get isManager => role == 'owner' || role == 'admin';
  bool get isDistributor => role == 'distributor';
  bool get isPos => role == 'pos';

  factory AccSession.fromJson(Map<String, dynamic> j) => AccSession(
        role: j['role']?.toString() ?? 'owner',
        ownerId: (j['owner_id'] as num?)?.toInt() ?? 0,
        permissions: (j['permissions'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        agent: j['agent'] is Map
            ? AccAgentRef.fromJson(toMap(j['agent']))
            : null,
      );
}

/// The agent row attached to the session (null for the owner).
class AccAgentRef {
  const AccAgentRef({required this.id, required this.role, this.displayName});

  final int id;
  final String role;
  final String? displayName;

  factory AccAgentRef.fromJson(Map<String, dynamic> j) => AccAgentRef(
        id: (j['id'] as num?)?.toInt() ?? 0,
        role: j['role']?.toString() ?? '',
        displayName: j['display_name']?.toString(),
      );
}

/// An operating sub-account (admin | distributor | pos) bound to an
/// existing app user — the "users" screen model.
class AccAgent {
  const AccAgent({
    required this.id,
    required this.userId,
    required this.role,
    required this.displayName,
    required this.status,
    required this.cashAllowed,
    required this.creditAllowed,
    this.userName,
    this.userPhone,
    this.phone,
    this.commissionMode,
    this.commissionValue,
    this.dailyLimits,
  });

  final int id;
  final int userId;
  final String role;
  final String displayName;
  final String status;
  final bool cashAllowed;
  final bool creditAllowed;
  final String? userName;
  final String? userPhone;
  final String? phone;
  final String? commissionMode;
  final double? commissionValue;
  final Map<String, dynamic>? dailyLimits;

  bool get isActive => status == 'active';

  static const roles = {'admin': 'إدارة', 'distributor': 'موزع', 'pos': 'نقطة بيع'};
  String get roleLabel => roles[role] ?? role;

  factory AccAgent.fromJson(Map<String, dynamic> j) => AccAgent(
        id: (j['id'] as num).toInt(),
        userId: (j['user_id'] as num?)?.toInt() ?? 0,
        role: j['role']?.toString() ?? 'pos',
        displayName: j['display_name']?.toString() ?? '',
        status: j['status']?.toString() ?? 'active',
        cashAllowed: j['cash_allowed'] == true,
        creditAllowed: j['credit_allowed'] == true,
        userName: j['user_name']?.toString(),
        userPhone: j['user_phone']?.toString(),
        phone: j['phone']?.toString(),
        commissionMode: j['commission_mode']?.toString(),
        commissionValue: (j['commission_value'] as num?)?.toDouble(),
        dailyLimits: j['daily_limit_per_category'] is Map
            ? Map<String, dynamic>.from(j['daily_limit_per_category'] as Map)
            : null,
      );
}

/// A point-of-sale outlet with its bound agent + device count.
class AccPosPoint {
  const AccPosPoint({
    required this.id,
    required this.name,
    required this.status,
    required this.devicesCount,
    required this.creditLimit,
    required this.pointsBalance,
    required this.profitBalance,
    this.location,
    this.ownerName,
    this.phone,
    this.agentId,
    this.agentName,
  });

  final int id;
  final String name;
  final String status;
  final int devicesCount;
  final double creditLimit;
  final double pointsBalance;
  final double profitBalance;
  final String? location;
  final String? ownerName;
  final String? phone;
  final int? agentId;
  final String? agentName;

  bool get isActive => status == 'active';

  factory AccPosPoint.fromJson(Map<String, dynamic> j) => AccPosPoint(
        id: (j['id'] as num).toInt(),
        name: j['name']?.toString() ?? '',
        status: j['status']?.toString() ?? 'active',
        devicesCount: (j['devices_count'] as num?)?.toInt() ?? 0,
        creditLimit: (j['credit_limit'] as num?)?.toDouble() ?? 0,
        pointsBalance: (j['points_balance'] as num?)?.toDouble() ?? 0,
        profitBalance: (j['profit_balance'] as num?)?.toDouble() ?? 0,
        location: j['location']?.toString(),
        ownerName: j['owner_name']?.toString(),
        phone: j['phone']?.toString(),
        agentId: (j['agent_id'] as num?)?.toInt(),
        agentName: j['agent_name']?.toString(),
      );
}

/// A terminal bound to a POS point.
class AccPosDevice {
  const AccPosDevice({
    required this.id,
    required this.deviceName,
    this.deviceUid,
    this.model,
    this.boundAt,
  });

  final int id;
  final String deviceName;
  final String? deviceUid;
  final String? model;
  final String? boundAt;

  factory AccPosDevice.fromJson(Map<String, dynamic> j) => AccPosDevice(
        id: (j['id'] as num).toInt(),
        deviceName: j['device_name']?.toString() ?? '',
        deviceUid: j['device_uid']?.toString(),
        model: j['model']?.toString(),
        boundAt: j['bound_at']?.toString(),
      );
}

/// Thin client for the accounting API (routes/api_accounting.php).
/// Write methods throw a user-facing Arabic message on failure —
/// same convention as SubscriptionService.
class AccApi {
  AccApi(this._api);

  final ApiClient _api;
  static const _base = '/network-owner/accounting';

  /// Null when the account has no accounting identity (403) or the
  /// backend is unreachable — callers render a friendly empty state.
  Future<AccSession?> me() async {
    try {
      final res = await _api.get('$_base/me');
      final j = res.data is Map ? toMap(res.data) : null;
      if (j?['success'] == true) return AccSession.fromJson(toMap(j?['data']));
    } catch (_) {}
    return null;
  }

  // ── Agents ──────────────────────────────────────────────────

  Future<List<AccAgent>> agents({String? role}) async {
    final res = await _api.get(
      '$_base/agents',
      params: {'role': ?role},
    );
    return toMapList(res.data?['data']?['data'])
        .map(AccAgent.fromJson)
        .toList();
  }

  Future<String> createAgent(Map<String, dynamic> data) async =>
      _write(() => _api.post('$_base/agents', data: data));

  Future<String> updateAgent(int id, Map<String, dynamic> data) async =>
      _write(() => _api.put('$_base/agents/$id', data: data));

  Future<String> deleteAgent(int id) async =>
      _write(() => _api.delete('$_base/agents/$id'));

  // ── POS points + devices ────────────────────────────────────

  Future<List<AccPosPoint>> posPoints() async {
    final res = await _api.get('$_base/pos');
    return toMapList(res.data?['data']?['data'])
        .map(AccPosPoint.fromJson)
        .toList();
  }

  Future<String> createPosPoint(Map<String, dynamic> data) async =>
      _write(() => _api.post('$_base/pos', data: data));

  Future<String> updatePosPoint(int id, Map<String, dynamic> data) async =>
      _write(() => _api.put('$_base/pos/$id', data: data));

  Future<String> deletePosPoint(int id) async =>
      _write(() => _api.delete('$_base/pos/$id'));

  Future<List<AccPosDevice>> posDevices(int posId) async {
    final res = await _api.get('$_base/pos/$posId/devices');
    return toMapList(res.data?['data'])
        .map(AccPosDevice.fromJson)
        .toList();
  }

  Future<String> bindDevice(int posId, Map<String, dynamic> data) async =>
      _write(() => _api.post('$_base/pos/$posId/devices', data: data));

  Future<String> unbindDevice(int posId, int deviceId) async =>
      _write(() => _api.delete('$_base/pos/$posId/devices/$deviceId'));

  /// Unwraps `{success, message}` — the message field is always the
  /// user-facing Arabic copy, whether success or failure. With an
  /// [offlineOp], connectivity failures enqueue for /sync/push
  /// instead of throwing (ACC-12).
  Future<String> _write(
    Future<Response> Function() call, {
    String? offlineOp,
    Map<String, dynamic>? offlinePayload,
  }) =>
      accWriteOrQueue(call,
          offlineOp: offlineOp, offlinePayload: offlinePayload);
}

// ── ACC-02 — inventory & card categories ──────────────────────────

/// An accounting card category with its live stock balance.
class AccCardCategory {
  const AccCardCategory({
    required this.id,
    required this.name,
    required this.sellPrice,
    required this.costPrice,
    required this.unitLabel,
    required this.sourceBinding,
    required this.isActive,
    required this.stockQty,
    required this.avgCost,
    this.cardCategoryId,
    this.sortOrder = 0,
  });

  final int id;
  final String name;
  final double sellPrice;
  final double costPrice;
  final String unitLabel;
  final String sourceBinding;
  final bool isActive;
  final double stockQty;
  final double avgCost;
  final int? cardCategoryId;
  final int sortOrder;

  static const bindings = {
    'any': 'الكل',
    'platform': 'منصة',
    'mikrotik': 'راوتر',
  };
  String get bindingLabel => bindings[sourceBinding] ?? sourceBinding;

  factory AccCardCategory.fromJson(Map<String, dynamic> j) =>
      AccCardCategory(
        id: (j['id'] as num).toInt(),
        name: j['name']?.toString() ?? '',
        sellPrice: (j['sell_price'] as num?)?.toDouble() ?? 0,
        costPrice: (j['cost_price'] as num?)?.toDouble() ?? 0,
        unitLabel: j['unit_label']?.toString() ?? 'كرت',
        sourceBinding: j['source_binding']?.toString() ?? 'any',
        isActive: j['is_active'] == true,
        stockQty: (j['stock_qty'] as num?)?.toDouble() ?? 0,
        avgCost: (j['avg_cost'] as num?)?.toDouble() ?? 0,
        cardCategoryId: (j['card_category_id'] as num?)?.toInt(),
        sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
      );
}

/// One stock row per category — the inventory screen's unit.
class AccStockRow {
  const AccStockRow({
    required this.categoryId,
    required this.categoryName,
    required this.unitLabel,
    required this.sellPrice,
    required this.qty,
    required this.avgCost,
    required this.stockValue,
    required this.isActive,
  });

  final int categoryId;
  final String categoryName;
  final String unitLabel;
  final double sellPrice;
  final double qty;
  final double avgCost;
  final double stockValue;
  final bool isActive;

  factory AccStockRow.fromJson(Map<String, dynamic> j) => AccStockRow(
        categoryId: (j['category_id'] as num).toInt(),
        categoryName: j['category_name']?.toString() ?? '',
        unitLabel: j['unit_label']?.toString() ?? 'كرت',
        sellPrice: (j['sell_price'] as num?)?.toDouble() ?? 0,
        qty: (j['qty'] as num?)?.toDouble() ?? 0,
        avgCost: (j['avg_cost'] as num?)?.toDouble() ?? 0,
        stockValue: (j['stock_value'] as num?)?.toDouble() ?? 0,
        isActive: j['is_active'] == true,
      );
}

/// A signed, immutable stock-ledger row (positive = in).
class AccStockMovement {
  const AccStockMovement({
    required this.id,
    required this.categoryId,
    required this.categoryName,
    required this.type,
    required this.qty,
    required this.unitCost,
    this.note,
    this.createdAt,
  });

  final int id;
  final int categoryId;
  final String categoryName;
  final String type;
  final double qty;
  final double unitCost;
  final String? note;
  final String? createdAt;

  bool get isIn => qty > 0;

  static const typeLabels = {
    'in': 'إدخال',
    'out': 'إخراج',
    'adjust': 'تسوية',
    'sale': 'بيع',
    'return': 'مرتجع',
    'damaged': 'تالف',
    'order_fill': 'تعبئة طلب',
  };
  String get typeLabel => typeLabels[type] ?? type;

  factory AccStockMovement.fromJson(Map<String, dynamic> j) =>
      AccStockMovement(
        id: (j['id'] as num).toInt(),
        categoryId: (j['category_id'] as num?)?.toInt() ?? 0,
        categoryName: j['category_name']?.toString() ?? '',
        type: j['type']?.toString() ?? '',
        qty: (j['qty'] as num?)?.toDouble() ?? 0,
        unitCost: (j['unit_cost'] as num?)?.toDouble() ?? 0,
        note: j['note']?.toString(),
        createdAt: j['created_at']?.toString(),
      );
}

/// ACC-02 inventory endpoints on the same client — an extension so
/// later sprints keep merging cleanly into this shared file.
extension AccInventoryApi on AccApi {
  static const _invBase = '/network-owner/accounting';

  // ── Categories ──────────────────────────────────────────────

  Future<List<AccCardCategory>> categories({bool? active}) async {
    final res = await _api.get('$_invBase/categories',
        params: {if (active != null) 'active': active ? 1 : 0});
    return toMapList(res.data?['data'])
        .map(AccCardCategory.fromJson)
        .toList();
  }

  Future<String> createCategory(Map<String, dynamic> data) async =>
      _write(() => _api.post('$_invBase/categories', data: data));

  Future<String> updateCategory(int id, Map<String, dynamic> data) async =>
      _write(() => _api.put('$_invBase/categories/$id', data: data));

  Future<String> deleteCategory(int id) async =>
      _write(() => _api.delete('$_invBase/categories/$id'));

  // ── Stock ───────────────────────────────────────────────────

  /// Rows + grand totals; the backend auto-syncs router cards first.
  Future<({List<AccStockRow> rows, double totalQty, double totalValue})>
      stock() async {
    final res = await _api.get('$_invBase/stock');
    final j = res.data is Map ? toMap(res.data) : null;
    return (
      rows: toMapList(j?['data']).map(AccStockRow.fromJson).toList(),
      totalQty: (j?['totals']?['qty'] as num?)?.toDouble() ?? 0,
      totalValue: (j?['totals']?['value'] as num?)?.toDouble() ?? 0,
    );
  }

  Future<List<AccStockMovement>> stockMovements({
    int? categoryId,
    String? type,
  }) async {
    final res = await _api.get('$_invBase/stock/movements', params: {
      'category_id': ?categoryId,
      'type': ?type,
    });
    return toMapList(res.data?['data']?['data'])
        .map(AccStockMovement.fromJson)
        .toList();
  }

  Future<String> adjustStock(int categoryId, double qty, String? note) {
    final data = <String, dynamic>{
      'category_id': categoryId,
      'qty': qty,
      if (note != null && note.isNotEmpty) 'note': note,
    };
    return _write(() => _api.post('$_invBase/stock/adjust', data: data),
        offlineOp: 'stock.adjust', offlinePayload: data);
  }

  /// Manually reconcile router (source=mikrotik) cards into stock.
  Future<String> syncRouterCards() async =>
      _write(() => _api.post('$_invBase/stock/sync'));
}
