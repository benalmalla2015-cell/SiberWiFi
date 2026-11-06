import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../core/utils/json_helpers.dart';
import 'offline_queue.dart';

// ── ACC-06 — the distributor surface (PLAN §5: dist_home) ───────────

/// The acting agent block echoed by /dist/home.
class DistAgentInfo {
  const DistAgentInfo({
    required this.id,
    required this.displayName,
    required this.cashAllowed,
    required this.creditAllowed,
    this.commissionMode,
    this.commissionValue,
  });

  final int id;
  final String displayName;
  final bool cashAllowed;
  final bool creditAllowed;
  final String? commissionMode;
  final double? commissionValue;

  static const modeLabels = {
    'percent': 'نسبة',
    'fixed': 'مبلغ ثابت',
  };
  String? get commissionLabel => commissionMode == null
      ? null
      : '${modeLabels[commissionMode] ?? commissionMode}'
          '${commissionValue != null ? ' ${commissionValue!.toStringAsFixed(commissionMode == 'percent' ? 1 : 0)}${commissionMode == 'percent' ? '٪' : ''}' : ''}';

  factory DistAgentInfo.fromJson(Map<String, dynamic> j) => DistAgentInfo(
        id: (j['id'] as num).toInt(),
        displayName: j['display_name']?.toString() ?? '',
        cashAllowed: j['cash_allowed'] == true,
        creditAllowed: j['credit_allowed'] == true,
        commissionMode: j['commission_mode']?.toString(),
        commissionValue: (j['commission_value'] as num?)?.toDouble(),
      );
}

/// Today's counters for the distributor hero card.
class DistToday {
  const DistToday({
    required this.salesCount,
    required this.salesTotal,
    required this.cashTotal,
    required this.creditTotal,
    required this.collectionsTotal,
  });

  final int salesCount;
  final double salesTotal;
  final double cashTotal;
  final double creditTotal;
  final double collectionsTotal;

  factory DistToday.fromJson(Map<String, dynamic> j) => DistToday(
        salesCount: (j['sales_count'] as num?)?.toInt() ?? 0,
        salesTotal: (j['sales_total'] as num?)?.toDouble() ?? 0,
        cashTotal: (j['cash_total'] as num?)?.toDouble() ?? 0,
        creditTotal: (j['credit_total'] as num?)?.toDouble() ?? 0,
        collectionsTotal:
            (j['collections_total'] as num?)?.toDouble() ?? 0,
      );
}

/// A sellable category with stock + the distributor's daily remaining.
class DistCategory {
  const DistCategory({
    required this.id,
    required this.name,
    required this.unitLabel,
    required this.sellPrice,
    required this.stockQty,
    required this.soldToday,
    this.dailyLimit,
    this.remainingToday,
  });

  final int id;
  final String name;
  final String unitLabel;
  final double sellPrice;
  final double stockQty;
  final double soldToday;

  /// null = no per-category cap for this distributor.
  final double? dailyLimit;
  final double? remainingToday;

  bool get isSoldOut => stockQty <= 0 || (remainingToday != null && remainingToday! <= 0);

  factory DistCategory.fromJson(Map<String, dynamic> j) => DistCategory(
        id: (j['id'] as num).toInt(),
        name: j['name']?.toString() ?? '',
        unitLabel: j['unit_label']?.toString() ?? 'كرت',
        sellPrice: (j['sell_price'] as num?)?.toDouble() ?? 0,
        stockQty: (j['stock_qty'] as num?)?.toDouble() ?? 0,
        soldToday: (j['sold_today'] as num?)?.toDouble() ?? 0,
        dailyLimit: (j['daily_limit'] as num?)?.toDouble(),
        remainingToday: (j['remaining_today'] as num?)?.toDouble(),
      );
}

/// A POS point as the distributor sees it — balances + receivable.
class DistPosPoint {
  const DistPosPoint({
    required this.id,
    required this.name,
    required this.pointsBalance,
    required this.profitBalance,
    required this.creditLimit,
    required this.arBalance,
    this.location,
    this.phone,
  });

  final int id;
  final String name;
  final double pointsBalance;
  final double profitBalance;
  final double creditLimit;
  final double arBalance;
  final String? location;
  final String? phone;

  factory DistPosPoint.fromJson(Map<String, dynamic> j) => DistPosPoint(
        id: (j['id'] as num).toInt(),
        name: j['name']?.toString() ?? '',
        pointsBalance: (j['points_balance'] as num?)?.toDouble() ?? 0,
        profitBalance: (j['profit_balance'] as num?)?.toDouble() ?? 0,
        creditLimit: (j['credit_limit'] as num?)?.toDouble() ?? 0,
        arBalance: (j['ar_balance'] as num?)?.toDouble() ?? 0,
        location: j['location']?.toString(),
        phone: j['phone']?.toString(),
      );
}

/// The /dist/home payload — one read model for the whole surface.
class DistHome {
  const DistHome({
    required this.today,
    required this.categories,
    required this.posPoints,
    this.agent,
  });

  final DistToday today;
  final List<DistCategory> categories;
  final List<DistPosPoint> posPoints;
  final DistAgentInfo? agent;

  factory DistHome.fromJson(Map<String, dynamic> j) => DistHome(
        today: DistToday.fromJson(toMap(j['today'])),
        categories: toMapList(j['categories'])
            .map(DistCategory.fromJson)
            .toList(),
        posPoints: toMapList(j['pos_points'])
            .map(DistPosPoint.fromJson)
            .toList(),
        agent: j['agent'] is Map
            ? DistAgentInfo.fromJson(toMap(j['agent']))
            : null,
      );
}

/// One line of a posted sale.
class DistSaleItem {
  const DistSaleItem({
    required this.id,
    required this.categoryName,
    required this.qty,
    required this.unitPrice,
    required this.unitCost,
    required this.lineTotal,
    this.categoryId,
  });

  final int id;
  final int? categoryId;
  final String categoryName;
  final int qty;
  final double unitPrice;
  final double unitCost;
  final double lineTotal;

  factory DistSaleItem.fromJson(Map<String, dynamic> j) => DistSaleItem(
        id: (j['id'] as num?)?.toInt() ?? 0,
        categoryId: (j['category_id'] as num?)?.toInt(),
        categoryName: j['category_name']?.toString() ?? '',
        qty: (j['qty'] as num?)?.toInt() ?? 0,
        unitPrice: (j['unit_price'] as num?)?.toDouble() ?? 0,
        unitCost: (j['unit_cost'] as num?)?.toDouble() ?? 0,
        lineTotal: (j['line_total'] as num?)?.toDouble() ?? 0,
      );
}

/// A posted distributor sale (cash | credit | partial).
class DistSale {
  const DistSale({
    required this.id,
    required this.saleNo,
    required this.posId,
    required this.paymentKind,
    required this.totalAmount,
    required this.paidAmount,
    required this.creditRemaining,
    required this.currency,
    required this.baseTotal,
    required this.commissionAmount,
    required this.status,
    required this.items,
    this.posName,
    this.distributorId,
    this.debtId,
    this.soldAt,
    this.note,
  });

  final int id;
  final String saleNo;
  final int posId;
  final String? posName;
  final int? distributorId;
  final String paymentKind;
  final double totalAmount;
  final double paidAmount;
  final double creditRemaining;
  final String currency;
  final double baseTotal;
  final double commissionAmount;
  final String status;
  final int? debtId;
  final String? soldAt;
  final String? note;
  final List<DistSaleItem> items;

  static const kindLabels = {
    'cash': 'نقدي',
    'credit': 'آجل',
    'partial': 'جزئي',
  };
  String get kindLabel => kindLabels[paymentKind] ?? paymentKind;

  factory DistSale.fromJson(Map<String, dynamic> j) => DistSale(
        id: (j['id'] as num).toInt(),
        saleNo: j['sale_no']?.toString() ?? '',
        posId: (j['pos_id'] as num?)?.toInt() ?? 0,
        posName: j['pos_name']?.toString(),
        distributorId: (j['distributor_id'] as num?)?.toInt(),
        paymentKind: j['payment_kind']?.toString() ?? 'cash',
        totalAmount: (j['total_amount'] as num?)?.toDouble() ?? 0,
        paidAmount: (j['paid_amount'] as num?)?.toDouble() ?? 0,
        creditRemaining:
            (j['credit_remaining'] as num?)?.toDouble() ?? 0,
        currency: j['currency']?.toString() ?? 'north',
        baseTotal: (j['base_total'] as num?)?.toDouble() ?? 0,
        commissionAmount:
            (j['commission_amount'] as num?)?.toDouble() ?? 0,
        status: j['status']?.toString() ?? 'posted',
        debtId: (j['debt_id'] as num?)?.toInt(),
        soldAt: j['sold_at']?.toString(),
        note: j['note']?.toString(),
        items:
            toMapList(j['items']).map(DistSaleItem.fromJson).toList(),
      );
}

/// The aggregated block of /dist/report.
class DistReportTotals {
  const DistReportTotals({
    required this.salesCount,
    required this.salesTotal,
    required this.cashTotal,
    required this.creditTotal,
    required this.collectionsTotal,
    required this.openDebtsCount,
    required this.openDebtsRemaining,
  });

  final int salesCount;
  final double salesTotal;
  final double cashTotal;
  final double creditTotal;
  final double collectionsTotal;
  final int openDebtsCount;
  final double openDebtsRemaining;

  factory DistReportTotals.fromJson(Map<String, dynamic> j) =>
      DistReportTotals(
        salesCount: (j['sales_count'] as num?)?.toInt() ?? 0,
        salesTotal: (j['sales_total'] as num?)?.toDouble() ?? 0,
        cashTotal: (j['cash_total'] as num?)?.toDouble() ?? 0,
        creditTotal: (j['credit_total'] as num?)?.toDouble() ?? 0,
        collectionsTotal:
            (j['collections_total'] as num?)?.toDouble() ?? 0,
        openDebtsCount: (j['open_debts_count'] as num?)?.toInt() ?? 0,
        openDebtsRemaining:
            (j['open_debts_remaining'] as num?)?.toDouble() ?? 0,
      );
}

/// One row of the report's daily breakdown.
class DistReportDay {
  const DistReportDay({
    required this.date,
    required this.count,
    required this.total,
    required this.cash,
    required this.credit,
  });

  final String date;
  final int count;
  final double total;
  final double cash;
  final double credit;

  factory DistReportDay.fromJson(Map<String, dynamic> j) =>
      DistReportDay(
        date: j['date']?.toString() ?? '',
        count: (j['count'] as num?)?.toInt() ?? 0,
        total: (j['total'] as num?)?.toDouble() ?? 0,
        cash: (j['cash'] as num?)?.toDouble() ?? 0,
        credit: (j['credit'] as num?)?.toDouble() ?? 0,
      );
}

/// One row of the report's per-category breakdown.
class DistReportCategory {
  const DistReportCategory({
    required this.categoryName,
    required this.qty,
    required this.amount,
    this.categoryId,
  });

  final int? categoryId;
  final String categoryName;
  final double qty;
  final double amount;

  factory DistReportCategory.fromJson(Map<String, dynamic> j) =>
      DistReportCategory(
        categoryId: (j['category_id'] as num?)?.toInt(),
        categoryName: j['category_name']?.toString() ?? '',
        qty: (j['qty'] as num?)?.toDouble() ?? 0,
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
      );
}

/// The /dist/report payload.
class DistReport {
  const DistReport({
    required this.from,
    required this.to,
    required this.totals,
    required this.daily,
    required this.categories,
  });

  final String from;
  final String to;
  final DistReportTotals totals;
  final List<DistReportDay> daily;
  final List<DistReportCategory> categories;

  factory DistReport.fromJson(Map<String, dynamic> j) => DistReport(
        from: j['from']?.toString() ?? '',
        to: j['to']?.toString() ?? '',
        totals: DistReportTotals.fromJson(toMap(j['totals'])),
        daily:
            toMapList(j['daily']).map(DistReportDay.fromJson).toList(),
        categories: toMapList(j['categories'])
            .map(DistReportCategory.fromJson)
            .toList(),
      );
}

/// A monthly commission row (acc_commissions).
class DistCommission {
  const DistCommission({
    required this.id,
    required this.period,
    required this.salesAmount,
    required this.commissionAmount,
    required this.status,
    this.distributorId,
    this.distributorName,
    this.paidAt,
  });

  final int id;
  final int? distributorId;
  final String? distributorName;
  final String period;
  final double salesAmount;
  final double commissionAmount;
  final String status;
  final String? paidAt;

  static const statusLabels = {
    'open': 'مفتوحة',
    'accrued': 'مستحقة',
    'paid': 'مدفوعة',
    'settled': 'مسواة',
  };
  String get statusLabel => statusLabels[status] ?? status;
  bool get isPaid => status == 'paid' || status == 'settled';

  factory DistCommission.fromJson(Map<String, dynamic> j) =>
      DistCommission(
        id: (j['id'] as num).toInt(),
        distributorId: (j['distributor_id'] as num?)?.toInt(),
        distributorName: j['distributor_name']?.toString(),
        period: j['period']?.toString() ?? '',
        salesAmount: (j['sales_amount'] as num?)?.toDouble() ?? 0,
        commissionAmount:
            (j['commission_amount'] as num?)?.toDouble() ?? 0,
        status: j['status']?.toString() ?? 'open',
        paidAt: j['paid_at']?.toString(),
      );
}

/// Thin client for the ACC-06 distributor endpoints — same
/// conventions as AccApi/MoneyApi (writes return the Arabic message
/// or throw it).
class DistApi {
  DistApi(this._api);

  final ApiClient _api;
  static const _base = '/network-owner/accounting/dist';

  /// Sellable stock + daily remaining + POS balances + today's totals.
  Future<DistHome> home() async {
    final res = await _api.get('$_base/home');
    final j = res.data is Map ? toMap(res.data) : null;
    return DistHome.fromJson(toMap(j?['data']));
  }

  /// The acting distributor's sales register (managers see all).
  Future<List<DistSale>> sales({int? posId, String? paymentKind}) async {
    final res = await _api.get('$_base/sales', params: {
      'pos_id': ?posId,
      'payment_kind': ?paymentKind,
    });
    return toMapList(res.data?['data']?['data'])
        .map(DistSale.fromJson)
        .toList();
  }

  /// One atomic sale posting — returns the user-facing message.
  /// Offline the sale queues in the sync center and replays as
  /// `dist.sale` (ACC-12).
  Future<String> sale(Map<String, dynamic> data) async => _write(
        () => _api.post('$_base/sale', data: data),
        offlineOp: 'dist.sale',
        offlinePayload: data,
      );

  /// Period report — `from`/`to` as YYYY-MM-DD (null = current month).
  Future<DistReport> report({String? from, String? to}) async {
    final res = await _api.get('$_base/report', params: {
      'from': ?from,
      'to': ?to,
    });
    final j = res.data is Map ? toMap(res.data) : null;
    return DistReport.fromJson(toMap(j?['data']));
  }

  /// Commission periods — own rows for a distributor.
  Future<List<DistCommission>> commissions({String? period}) async {
    final res =
        await _api.get('$_base/commissions', params: {'period': ?period});
    return toMapList(res.data?['data'])
        .map(DistCommission.fromJson)
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
