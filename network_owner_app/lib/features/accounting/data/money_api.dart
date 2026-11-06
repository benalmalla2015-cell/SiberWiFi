import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../core/utils/json_helpers.dart';
import 'offline_queue.dart';

/// A cash drawer (ACC-05).
class AccCashBox {
  const AccCashBox({
    required this.id,
    required this.name,
    required this.currency,
    required this.balance,
    required this.isDefault,
    required this.isActive,
  });

  final int id;
  final String name;
  final String currency;
  final double balance;
  final bool isDefault;
  final bool isActive;

  factory AccCashBox.fromJson(Map<String, dynamic> j) => AccCashBox(
        id: (j['id'] as num).toInt(),
        name: j['name']?.toString() ?? '',
        currency: j['currency']?.toString() ?? 'north',
        balance: (j['balance'] as num?)?.toDouble() ?? 0,
        isDefault: j['is_default'] == true,
        isActive: j['is_active'] == true,
      );
}

/// Money received from a party (ACC-05).
class AccCollection {
  const AccCollection({
    required this.id,
    required this.partyType,
    required this.partyName,
    required this.amount,
    required this.currency,
    required this.baseAmount,
    this.partyId,
    this.phone,
    this.boxName,
    this.debtId,
    this.collectedAt,
    this.note,
  });

  final int id;
  final String partyType;
  final int? partyId;
  final String partyName;
  final String? phone;
  final double amount;
  final String currency;
  final double baseAmount;
  final String? boxName;
  final int? debtId;
  final String? collectedAt;
  final String? note;

  static const partyLabels = {
    'pos': 'نقطة بيع',
    'distributor': 'موزع',
    'customer': 'عميل',
    'person': 'شخص',
  };
  String get partyLabel => partyLabels[partyType] ?? partyType;

  factory AccCollection.fromJson(Map<String, dynamic> j) => AccCollection(
        id: (j['id'] as num).toInt(),
        partyType: j['party_type']?.toString() ?? 'person',
        partyId: (j['party_id'] as num?)?.toInt(),
        partyName: j['party_name']?.toString() ?? '',
        phone: j['phone']?.toString(),
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
        currency: j['currency']?.toString() ?? 'north',
        baseAmount: (j['base_amount'] as num?)?.toDouble() ?? 0,
        boxName: j['box_name']?.toString(),
        debtId: (j['debt_id'] as num?)?.toInt(),
        collectedAt: j['collected_at']?.toString(),
        note: j['note']?.toString(),
      );
}

/// A tracked receivable/payable (ACC-05).
class AccDebt {
  const AccDebt({
    required this.id,
    required this.partyType,
    required this.partyName,
    required this.direction,
    required this.amountDue,
    required this.amountPaid,
    required this.remaining,
    required this.currency,
    required this.status,
    required this.paymentsCount,
    this.partyId,
    this.phone,
    this.dueDate,
    this.note,
  });

  final int id;
  final String partyType;
  final int? partyId;
  final String partyName;
  final String? phone;
  final String direction; // receivable | payable
  final double amountDue;
  final double amountPaid;
  final double remaining;
  final String currency;
  final String status; // open | partial | paid
  final String? dueDate;
  final int paymentsCount;
  final String? note;

  bool get isPayable => direction == 'payable';
  bool get isSettled => status == 'paid';

  factory AccDebt.fromJson(Map<String, dynamic> j) => AccDebt(
        id: (j['id'] as num).toInt(),
        partyType: j['party_type']?.toString() ?? 'person',
        partyId: (j['party_id'] as num?)?.toInt(),
        partyName: j['party_name']?.toString() ?? '',
        phone: j['phone']?.toString(),
        direction: j['direction']?.toString() ?? 'receivable',
        amountDue: (j['amount_due'] as num?)?.toDouble() ?? 0,
        amountPaid: (j['amount_paid'] as num?)?.toDouble() ?? 0,
        remaining: (j['remaining'] as num?)?.toDouble() ?? 0,
        currency: j['currency']?.toString() ?? 'north',
        status: j['status']?.toString() ?? 'open',
        dueDate: j['due_date']?.toString(),
        paymentsCount: (j['payments_count'] as num?)?.toInt() ?? 0,
        note: j['note']?.toString(),
      );
}

/// An inter-box transfer (ACC-05).
class AccTransfer {
  const AccTransfer({
    required this.id,
    required this.amount,
    required this.toAmount,
    this.fromBoxName,
    this.toBoxName,
    this.note,
    this.createdAt,
  });

  final int id;
  final double amount;
  final double toAmount;
  final String? fromBoxName;
  final String? toBoxName;
  final String? note;
  final String? createdAt;

  factory AccTransfer.fromJson(Map<String, dynamic> j) => AccTransfer(
        id: (j['id'] as num).toInt(),
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
        toAmount: (j['to_amount'] as num?)?.toDouble() ?? 0,
        fromBoxName: j['from_box_name']?.toString(),
        toBoxName: j['to_box_name']?.toString(),
        note: j['note']?.toString(),
        createdAt: j['created_at']?.toString(),
      );
}

/// A posted daily expense (ACC-05).
class AccExpense {
  const AccExpense({
    required this.id,
    required this.amount,
    required this.currency,
    required this.baseAmount,
    required this.status,
    this.categoryId,
    this.categoryName,
    this.boxName,
    this.incurredAt,
    this.note,
  });

  final int id;
  final int? categoryId;
  final String? categoryName;
  final double amount;
  final String currency;
  final double baseAmount;
  final String? boxName;
  final String status; // posted | void
  final String? incurredAt;
  final String? note;

  bool get isVoid => status == 'void';

  factory AccExpense.fromJson(Map<String, dynamic> j) => AccExpense(
        id: (j['id'] as num).toInt(),
        categoryId: (j['category_id'] as num?)?.toInt(),
        categoryName: j['category_name']?.toString(),
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
        currency: j['currency']?.toString() ?? 'north',
        baseAmount: (j['base_amount'] as num?)?.toDouble() ?? 0,
        boxName: j['box_name']?.toString(),
        status: j['status']?.toString() ?? 'posted',
        incurredAt: j['incurred_at']?.toString(),
        note: j['note']?.toString(),
      );
}

/// An expense category row (ACC-05).
class AccExpenseCategory {
  const AccExpenseCategory({
    required this.id,
    required this.name,
    required this.isActive,
  });

  final int id;
  final String name;
  final bool isActive;

  factory AccExpenseCategory.fromJson(Map<String, dynamic> j) =>
      AccExpenseCategory(
        id: (j['id'] as num).toInt(),
        name: j['name']?.toString() ?? '',
        isActive: j['is_active'] == true,
      );
}

/// The platform's two regional currencies + live rate (ACC-05 —
/// read-only over exchange_rate_settings).
class AccCurrencyInfo {
  const AccCurrencyInfo({required this.northToSouth});

  final double northToSouth;

  static const labels = {
    'north': 'ريال يمني قديم (شمال)',
    'south': 'ريال يمني (جنوب)',
  };
  static String label(String code) => labels[code] ?? code;

  factory AccCurrencyInfo.fromJson(Map<String, dynamic> j) =>
      AccCurrencyInfo(
        northToSouth:
            (j['north_to_south'] as num?)?.toDouble() ?? 1,
      );
}

/// Thin client for the ACC-05 money endpoints — same conventions as
/// AccApi (writes return the Arabic message or throw it).
class MoneyApi {
  MoneyApi(this._api);

  final ApiClient _api;
  static const _base = '/network-owner/accounting';

  // ── Lookups ──────────────────────────────────────────────────

  Future<AccCurrencyInfo> currencies() async {
    final res = await _api.get('$_base/currencies');
    final j = res.data is Map ? toMap(res.data) : null;
    return AccCurrencyInfo.fromJson(toMap(j?['data']));
  }

  // ── Collections ──────────────────────────────────────────────

  Future<List<AccCollection>> collections({
    String? partyType,
    String? from,
    String? to,
  }) async {
    final res = await _api.get('$_base/collections', params: {
      'party_type': ?partyType,
      'from': ?from,
      'to': ?to,
    });
    return toMapList(res.data?['data']?['data'])
        .map(AccCollection.fromJson)
        .toList();
  }

  Future<String> collect(Map<String, dynamic> data) async => _write(
        () => _api.post('$_base/collections', data: data),
        offlineOp: 'collection.create',
        offlinePayload: data,
      );

  // ── Debts ────────────────────────────────────────────────────

  Future<List<AccDebt>> debts({String? status, String? partyType}) async {
    final res = await _api.get('$_base/debts', params: {
      'status': ?status,
      'party_type': ?partyType,
    });
    return toMapList(res.data?['data']?['data'])
        .map(AccDebt.fromJson)
        .toList();
  }

  Future<String> createDebt(Map<String, dynamic> data) async => _write(
        () => _api.post('$_base/debts', data: data),
        offlineOp: 'debt.create',
        offlinePayload: data,
      );

  Future<String> payDebt(int debtId, Map<String, dynamic> data) async =>
      _write(
        () => _api.post('$_base/debts/$debtId/pay', data: data),
        offlineOp: 'debt.pay',
        offlinePayload: {...data, 'debt_id': debtId},
      );

  // ── Cash boxes + transfers ───────────────────────────────────

  Future<List<AccCashBox>> cashBoxes() async {
    final res = await _api.get('$_base/cash-boxes');
    return toMapList(res.data?['data'])
        .map(AccCashBox.fromJson)
        .toList();
  }

  Future<String> createBox(Map<String, dynamic> data) async =>
      _write(() => _api.post('$_base/cash-boxes', data: data));

  Future<List<AccTransfer>> transfers() async {
    final res = await _api.get('$_base/cash-boxes/transfers');
    return toMapList(res.data?['data']?['data'])
        .map(AccTransfer.fromJson)
        .toList();
  }

  Future<String> transfer(Map<String, dynamic> data) async => _write(
        () => _api.post('$_base/cash-boxes/transfer', data: data),
        offlineOp: 'transfer.create',
        offlinePayload: data,
      );

  // ── Expenses + categories ────────────────────────────────────

  Future<List<AccExpense>> expenses({int? categoryId}) async {
    final res = await _api.get('$_base/expenses', params: {
      'category_id': ?categoryId,
    });
    return toMapList(res.data?['data']?['data'])
        .map(AccExpense.fromJson)
        .toList();
  }

  Future<String> createExpense(Map<String, dynamic> data) async => _write(
        () => _api.post('$_base/expenses', data: data),
        offlineOp: 'expense.create',
        offlinePayload: data,
      );

  Future<String> voidExpense(int id) async =>
      _write(() => _api.delete('$_base/expenses/$id'));

  Future<List<AccExpenseCategory>> expenseCategories() async {
    final res = await _api.get('$_base/expense-categories');
    return toMapList(res.data?['data'])
        .map(AccExpenseCategory.fromJson)
        .toList();
  }

  Future<String> createExpenseCategory(String name) async =>
      _write(() =>
          _api.post('$_base/expense-categories', data: {'name': name}));

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
