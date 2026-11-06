import '../../../core/api/api_client.dart';
import '../../../core/utils/json_helpers.dart';

// ── ACC-09 — reporting read models (PLAN §4 + §5) ──────────────

/// Executive summary — every money figure aggregates journal legs
/// server-side, so the cards always tie to the posted entries.
class AccSummary {
  const AccSummary({
    required this.todaySales,
    required this.todayCollections,
    required this.todayExpenses,
    required this.monthRevenue,
    required this.monthExpenses,
    required this.monthResult,
    required this.monthEntries,
    required this.cashBase,
    required this.receivablesTotal,
    required this.liabilitiesTotal,
    required this.posReceivable,
    required this.stockQty,
    required this.stockValue,
    required this.openDebts,
    required this.debtsRemaining,
    required this.boxes,
  });

  final double todaySales;
  final double todayCollections;
  final double todayExpenses;
  final double monthRevenue;
  final double monthExpenses;
  final double monthResult;
  final int monthEntries;
  final double cashBase;
  final double receivablesTotal;
  final double liabilitiesTotal;
  final double posReceivable;
  final double stockQty;
  final double stockValue;
  final int openDebts;
  final double debtsRemaining;
  final List<AccBoxBrief> boxes;

  factory AccSummary.fromJson(Map<String, dynamic> j) => AccSummary(
        todaySales: (j['today']?['sales'] as num?)?.toDouble() ?? 0,
        todayCollections:
            (j['today']?['collections'] as num?)?.toDouble() ?? 0,
        todayExpenses: (j['today']?['expenses'] as num?)?.toDouble() ?? 0,
        monthRevenue: (j['month']?['revenue'] as num?)?.toDouble() ?? 0,
        monthExpenses: (j['month']?['expenses'] as num?)?.toDouble() ?? 0,
        monthResult:
            (j['month']?['operating_result'] as num?)?.toDouble() ?? 0,
        monthEntries: (j['month']?['entries'] as num?)?.toInt() ?? 0,
        cashBase: (j['cash']?['base_total'] as num?)?.toDouble() ?? 0,
        receivablesTotal:
            (j['parties']?['receivables_total'] as num?)?.toDouble() ?? 0,
        liabilitiesTotal:
            (j['parties']?['liabilities_total'] as num?)?.toDouble() ?? 0,
        posReceivable:
            (j['parties']?['receivables']?['pos'] as num?)?.toDouble() ??
                0,
        stockQty: (j['stock']?['qty'] as num?)?.toDouble() ?? 0,
        stockValue: (j['stock']?['value'] as num?)?.toDouble() ?? 0,
        openDebts: (j['debts']?['open_count'] as num?)?.toInt() ?? 0,
        debtsRemaining:
            (j['debts']?['remaining_base'] as num?)?.toDouble() ?? 0,
        boxes: toMapList(j['cash']?['boxes'])
            .map(AccBoxBrief.fromJson)
            .toList(),
      );
}

class AccBoxBrief {
  const AccBoxBrief({
    required this.id,
    required this.name,
    required this.currency,
    required this.balance,
    required this.isDefault,
  });

  final int id;
  final String name;
  final String currency;
  final double balance;
  final bool isDefault;

  factory AccBoxBrief.fromJson(Map<String, dynamic> j) => AccBoxBrief(
        id: (j['id'] as num?)?.toInt() ?? 0,
        name: j['name']?.toString() ?? '',
        currency: j['currency']?.toString() ?? 'north',
        balance: (j['balance'] as num?)?.toDouble() ?? 0,
        isDefault: j['is_default'] == true,
      );
}

/// One day of the trend chart (sales/collections/expenses).
class AccTrendPoint {
  const AccTrendPoint({
    required this.date,
    required this.sales,
    required this.collections,
    required this.expenses,
  });

  final String date;
  final double sales;
  final double collections;
  final double expenses;

  factory AccTrendPoint.fromJson(Map<String, dynamic> j) => AccTrendPoint(
        date: j['date']?.toString() ?? '',
        sales: (j['sales'] as num?)?.toDouble() ?? 0,
        collections: (j['collections'] as num?)?.toDouble() ?? 0,
        expenses: (j['expenses'] as num?)?.toDouble() ?? 0,
      );
}

/// A generic report breakdown row (category/pos/distributor/kind).
class AccBreakdownRow {
  const AccBreakdownRow({
    required this.name,
    required this.total,
    this.id,
    this.count = 0,
    this.qty,
    this.commission,
  });

  final String name;
  final double total;
  final int? id;
  final int count;
  final double? qty;
  final double? commission;

  factory AccBreakdownRow.fromJson(Map<String, dynamic> j) =>
      AccBreakdownRow(
        name: j['category_name']?.toString() ??
            j['pos_name']?.toString() ??
            j['distributor_name']?.toString() ??
            j['kind']?.toString() ??
            '',
        total: (j['total'] as num?)?.toDouble() ??
            (j['amount'] as num?)?.toDouble() ??
            0,
        id: (j['pos_id'] as num?)?.toInt() ??
            (j['distributor_id'] as num?)?.toInt() ??
            (j['category_id'] as num?)?.toInt(),
        count: (j['count'] as num?)?.toInt() ?? 0,
        qty: (j['qty'] as num?)?.toDouble(),
        commission: (j['commission'] as num?)?.toDouble(),
      );
}

/// The sales book + its journal reconciliation block.
class AccSalesReport {
  const AccSalesReport({
    required this.from,
    required this.to,
    required this.count,
    required this.total,
    required this.paid,
    required this.credit,
    required this.commission,
    required this.journalRevenue,
    required this.revenueByDoc,
    required this.byKind,
    required this.byCategory,
    required this.byPos,
    required this.byDistributor,
  });

  final String from;
  final String to;
  final int count;
  final double total;
  final double paid;
  final double credit;
  final double commission;
  final double journalRevenue;
  final List<Map<String, dynamic>> revenueByDoc;
  final List<AccBreakdownRow> byKind;
  final List<AccBreakdownRow> byCategory;
  final List<AccBreakdownRow> byPos;
  final List<AccBreakdownRow> byDistributor;

  static const docLabels = {
    'sale': 'بيع موزع/إدارة',
    'pos_sale': 'طلبات نقاط البيع',
    'card_purchase_platform': 'مبيعات التطبيق',
    'return': 'مرتجعات',
  };

  factory AccSalesReport.fromJson(Map<String, dynamic> j) => AccSalesReport(
        from: j['from']?.toString() ?? '',
        to: j['to']?.toString() ?? '',
        count: (j['totals']?['count'] as num?)?.toInt() ?? 0,
        total: (j['totals']?['total'] as num?)?.toDouble() ?? 0,
        paid: (j['totals']?['paid'] as num?)?.toDouble() ?? 0,
        credit: (j['totals']?['credit'] as num?)?.toDouble() ?? 0,
        commission: (j['totals']?['commission'] as num?)?.toDouble() ?? 0,
        journalRevenue:
            (j['journal']?['revenue_total'] as num?)?.toDouble() ?? 0,
        revenueByDoc: toMapList(j['journal']?['revenue_by_doc']),
        byKind: toMapList(j['by_kind']).map(AccBreakdownRow.fromJson).toList(),
        byCategory:
            toMapList(j['by_category']).map(AccBreakdownRow.fromJson).toList(),
        byPos: toMapList(j['by_pos']).map(AccBreakdownRow.fromJson).toList(),
        byDistributor: toMapList(j['by_distributor'])
            .map(AccBreakdownRow.fromJson)
            .toList(),
      );
}

/// One POS point's strength card.
class AccPosPerf {
  const AccPosPerf({
    required this.posId,
    required this.name,
    required this.status,
    required this.score,
    required this.tier,
    required this.salesTotal,
    required this.salesCount,
    required this.collectionsTotal,
    required this.arBalance,
    required this.pointsBalance,
    required this.profitBalance,
    required this.ordersApproved,
    required this.ordersPending,
    this.location,
    this.lastSaleAt,
  });

  final int posId;
  final String name;
  final String status;
  final int score;
  final String tier;
  final double salesTotal;
  final int salesCount;
  final double collectionsTotal;
  final double arBalance;
  final double pointsBalance;
  final double profitBalance;
  final int ordersApproved;
  final int ordersPending;
  final String? location;
  final String? lastSaleAt;

  static const tierLabels = {
    'strong': 'قوية',
    'medium': 'متوسطة',
    'active': 'نشطة',
    'dormant': 'خاملة',
  };
  String get tierLabel => tierLabels[tier] ?? tier;

  factory AccPosPerf.fromJson(Map<String, dynamic> j) => AccPosPerf(
        posId: (j['pos_id'] as num?)?.toInt() ?? 0,
        name: j['name']?.toString() ?? '',
        status: j['status']?.toString() ?? 'active',
        score: (j['score'] as num?)?.toInt() ?? 0,
        tier: j['tier']?.toString() ?? 'dormant',
        salesTotal: (j['sales_total'] as num?)?.toDouble() ?? 0,
        salesCount: (j['sales_count'] as num?)?.toInt() ?? 0,
        collectionsTotal:
            (j['collections_total'] as num?)?.toDouble() ?? 0,
        arBalance: (j['ar_balance'] as num?)?.toDouble() ?? 0,
        pointsBalance: (j['points_balance'] as num?)?.toDouble() ?? 0,
        profitBalance: (j['profit_balance'] as num?)?.toDouble() ?? 0,
        ordersApproved: (j['orders_approved'] as num?)?.toInt() ?? 0,
        ordersPending: (j['orders_pending'] as num?)?.toInt() ?? 0,
        location: j['location']?.toString(),
        lastSaleAt: j['last_sale_at']?.toString(),
      );
}

/// Commission accruals + journal check per distributor.
class AccCommissionsReport {
  const AccCommissionsReport({
    required this.totalSales,
    required this.totalCommission,
    required this.accrued,
    required this.paid,
    required this.byDistributor,
    required this.rows,
  });

  final double totalSales;
  final double totalCommission;
  final double accrued;
  final double paid;
  final List<AccDistributorCommission> byDistributor;
  final List<AccCommissionRow> rows;

  factory AccCommissionsReport.fromJson(Map<String, dynamic> j) =>
      AccCommissionsReport(
        totalSales: (j['totals']?['sales_amount'] as num?)?.toDouble() ?? 0,
        totalCommission:
            (j['totals']?['commission_amount'] as num?)?.toDouble() ?? 0,
        accrued: (j['totals']?['accrued'] as num?)?.toDouble() ?? 0,
        paid: (j['totals']?['paid'] as num?)?.toDouble() ?? 0,
        byDistributor: toMapList(j['by_distributor'])
            .map(AccDistributorCommission.fromJson)
            .toList(),
        rows: toMapList(j['rows']).map(AccCommissionRow.fromJson).toList(),
      );
}

class AccDistributorCommission {
  const AccDistributorCommission({
    required this.id,
    required this.name,
    required this.sales,
    required this.commission,
    required this.journalNet,
  });

  final int id;
  final String name;
  final double sales;
  final double commission;
  final double journalNet;

  factory AccDistributorCommission.fromJson(Map<String, dynamic> j) =>
      AccDistributorCommission(
        id: (j['distributor_id'] as num?)?.toInt() ?? 0,
        name: j['distributor_name']?.toString() ?? '',
        sales: (j['sales_amount'] as num?)?.toDouble() ?? 0,
        commission: (j['commission_amount'] as num?)?.toDouble() ?? 0,
        journalNet: (j['journal_net'] as num?)?.toDouble() ?? 0,
      );
}

class AccCommissionRow {
  const AccCommissionRow({
    required this.period,
    required this.sales,
    required this.commission,
    required this.status,
    this.distributorName,
  });

  final String period;
  final double sales;
  final double commission;
  final String status;
  final String? distributorName;

  factory AccCommissionRow.fromJson(Map<String, dynamic> j) =>
      AccCommissionRow(
        period: j['period']?.toString() ?? '',
        sales: (j['sales_amount'] as num?)?.toDouble() ?? 0,
        commission: (j['commission_amount'] as num?)?.toDouble() ?? 0,
        status: j['status']?.toString() ?? 'accrued',
        distributorName: j['distributor_name']?.toString(),
      );
}

/// One day of the collections register — feeds the PDF statement.
class AccCollectionsDay {
  const AccCollectionsDay({
    required this.date,
    required this.count,
    required this.totalBase,
    required this.journalBase,
    required this.rows,
    required this.byBox,
  });

  final String date;
  final int count;
  final double totalBase;
  final double journalBase;
  final List<AccCollectionRow> rows;
  final List<Map<String, dynamic>> byBox;

  factory AccCollectionsDay.fromJson(Map<String, dynamic> j) =>
      AccCollectionsDay(
        date: j['date']?.toString() ?? '',
        count: (j['totals']?['count'] as num?)?.toInt() ?? 0,
        totalBase: (j['totals']?['total_base'] as num?)?.toDouble() ?? 0,
        journalBase: (j['totals']?['journal_base'] as num?)?.toDouble() ?? 0,
        rows: toMapList(j['rows']).map(AccCollectionRow.fromJson).toList(),
        byBox: toMapList(j['by_box']),
      );
}

class AccCollectionRow {
  const AccCollectionRow({
    required this.id,
    required this.partyType,
    required this.partyName,
    required this.amount,
    required this.currency,
    required this.baseAmount,
    this.boxName,
    this.collector,
    this.collectedAt,
    this.note,
  });

  final int id;
  final String partyType;
  final String partyName;
  final double amount;
  final String currency;
  final double baseAmount;
  final String? boxName;
  final String? collector;
  final String? collectedAt;
  final String? note;

  static const partyLabels = {
    'pos': 'نقطة بيع',
    'distributor': 'موزع',
    'customer': 'عميل',
    'person': 'شخص',
  };
  String get partyLabel => partyLabels[partyType] ?? partyType;

  factory AccCollectionRow.fromJson(Map<String, dynamic> j) =>
      AccCollectionRow(
        id: (j['id'] as num?)?.toInt() ?? 0,
        partyType: j['party_type']?.toString() ?? 'person',
        partyName: j['party_name']?.toString() ?? '',
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
        currency: j['currency']?.toString() ?? 'north',
        baseAmount: (j['base_amount'] as num?)?.toDouble() ?? 0,
        boxName: j['box_name']?.toString(),
        collector: j['collector']?.toString(),
        collectedAt: j['collected_at']?.toString(),
        note: j['note']?.toString(),
      );
}

/// A journal entry row (browser list).
class AccJournalEntryRow {
  const AccJournalEntryRow({
    required this.id,
    required this.entryNo,
    required this.docType,
    required this.date,
    this.docRefId,
    this.memo,
    this.reversalOfId,
  });

  final int id;
  final String entryNo;
  final String docType;
  final String date;
  final int? docRefId;
  final String? memo;
  final int? reversalOfId;

  bool get isReversal => reversalOfId != null;

  static const docLabels = {
    'sale': 'بيع',
    'pos_sale': 'بيع نقطة',
    'collection': 'تحصيل',
    'expense': 'مصروف',
    'purchase': 'شراء',
    'return': 'مرتجع',
    'damaged': 'تالف',
    'withdrawal': 'سحب',
    'adjustment': 'تسوية',
    'transfer': 'تحويل',
    'card_purchase_platform': 'شراء تطبيق',
  };
  String get docLabel => docLabels[docType] ?? docType;

  factory AccJournalEntryRow.fromJson(Map<String, dynamic> j) =>
      AccJournalEntryRow(
        id: (j['id'] as num).toInt(),
        entryNo: j['entry_no']?.toString() ?? '',
        docType: j['doc_type']?.toString() ?? '',
        date: j['date']?.toString() ?? '',
        docRefId: (j['doc_ref_id'] as num?)?.toInt(),
        memo: j['memo']?.toString(),
        reversalOfId: (j['reversal_of_id'] as num?)?.toInt(),
      );
}

/// A resolved journal leg for the detail sheet.
class AccJournalLineModel {
  const AccJournalLineModel({
    required this.accountCode,
    required this.accountName,
    required this.debit,
    required this.credit,
    this.partyName,
  });

  final String accountCode;
  final String accountName;
  final double debit;
  final double credit;
  final String? partyName;

  factory AccJournalLineModel.fromJson(Map<String, dynamic> j) =>
      AccJournalLineModel(
        accountCode: j['account_code']?.toString() ?? '',
        accountName: j['account_name']?.toString() ?? '',
        debit: (j['debit'] as num?)?.toDouble() ?? 0,
        credit: (j['credit'] as num?)?.toDouble() ?? 0,
        partyName: j['party_name']?.toString(),
      );
}

/// An audit trail row.
class AccAuditRow {
  const AccAuditRow({
    required this.id,
    required this.action,
    required this.entity,
    required this.agentName,
    this.entityId,
    this.meta,
    this.createdAt,
  });

  final int id;
  final String action;
  final String entity;
  final String agentName;
  final int? entityId;
  final Map<String, dynamic>? meta;
  final String? createdAt;

  double? get latencyMs => (meta?['latency_ms'] as num?)?.toDouble();

  factory AccAuditRow.fromJson(Map<String, dynamic> j) => AccAuditRow(
        id: (j['id'] as num?)?.toInt() ?? 0,
        action: j['action']?.toString() ?? '',
        entity: j['entity']?.toString() ?? '',
        agentName: j['agent_name']?.toString() ?? '',
        entityId: (j['entity_id'] as num?)?.toInt(),
        meta: j['meta'] is Map ? toMap(j['meta']) : null,
        createdAt: j['created_at']?.toString(),
      );
}

/// Thin client for the ACC-09 reporting endpoints — read-only.
class ReportsApi {
  ReportsApi(this._api);

  final ApiClient _api;
  static const _base = '/network-owner/accounting';

  Future<AccSummary> summary() async {
    final res = await _api.get('$_base/summary');
    return AccSummary.fromJson(toMap(res.data?['data']));
  }

  Future<List<AccTrendPoint>> trend({int days = 30}) async {
    final res = await _api
        .get('$_base/dashboard/trend', params: {'days': days});
    return toMapList(res.data?['data']?['points'])
        .map(AccTrendPoint.fromJson)
        .toList();
  }

  Future<AccSalesReport> salesReport({String? from, String? to}) async {
    final res = await _api.get('$_base/reports/sales',
        params: {'from': ?from, 'to': ?to});
    return AccSalesReport.fromJson(toMap(res.data?['data']));
  }

  Future<List<AccPosPerf>> posPerformance({int days = 30}) async {
    final res = await _api.get('$_base/reports/pos-performance',
        params: {'days': days});
    return toMapList(res.data?['data']?['points'])
        .map(AccPosPerf.fromJson)
        .toList();
  }

  Future<AccCommissionsReport> commissionsReport({String? period}) async {
    final res = await _api.get('$_base/reports/distributor-commissions',
        params: {'period': ?period});
    return AccCommissionsReport.fromJson(toMap(res.data?['data']));
  }

  Future<AccCollectionsDay> collectionsDaily({String? date}) async {
    final res = await _api.get('$_base/reports/collections-daily',
        params: {'date': ?date});
    return AccCollectionsDay.fromJson(toMap(res.data?['data']));
  }

  /// Journal browser — returns (entries, debitTotal, creditTotal).
  Future<
      ({
        List<AccJournalEntryRow> entries,
        double debit,
        double credit
      })> journal({
    String? docType,
    String? from,
    String? to,
    int page = 1,
  }) async {
    final res = await _api.get('$_base/journal', params: {
      'doc_type': ?docType,
      'from': ?from,
      'to': ?to,
      'page': page,
    });
    final j = res.data is Map ? toMap(res.data) : null;
    return (
      entries: toMapList(j?['data']?['entries']?['data'])
          .map(AccJournalEntryRow.fromJson)
          .toList(),
      debit: (j?['data']?['totals']?['debit'] as num?)?.toDouble() ?? 0,
      credit: (j?['data']?['totals']?['credit'] as num?)?.toDouble() ?? 0,
    );
  }

  /// One entry's resolved legs — (entry info, lines).
  Future<({AccJournalEntryRow entry, List<AccJournalLineModel> lines})>
      journalEntry(int id) async {
    final res = await _api.get('$_base/journal/$id');
    final j = toMap(res.data?['data']);
    return (
      entry: AccJournalEntryRow.fromJson({
        ...j,
        'doc_ref_id': j['doc_ref_id'],
        'reversal_of_id': j['reversal_of_id'],
      }),
      lines: toMapList(j['lines'])
          .map(AccJournalLineModel.fromJson)
          .toList(),
    );
  }

  /// Audit trail — (rows, total count for "showing N of M").
  Future<({List<AccAuditRow> rows, int total})> auditLog({
    String? action,
    String? entity,
    int? agentId,
    String? from,
    String? to,
    int page = 1,
  }) async {
    final res = await _api.get('$_base/audit-log', params: {
      'action': ?action,
      'entity': ?entity,
      'agent_id': ?agentId,
      'from': ?from,
      'to': ?to,
      'page': page,
    });
    final j = res.data is Map ? toMap(res.data) : null;
    return (
      rows: toMapList(j?['data']?['data'])
          .map(AccAuditRow.fromJson)
          .toList(),
      total: (j?['data']?['total'] as num?)?.toInt() ?? 0,
    );
  }
}
