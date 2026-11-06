import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../data/reports_api.dart';

/// Shared client for the ACC-09 reporting endpoints (read-only).
final reportsApiProvider = Provider<ReportsApi>(
  (ref) => ReportsApi(ref.watch(apiClientProvider)),
);

/// Executive summary — the manager-home headline figures.
final accSummaryProvider = FutureProvider<AccSummary>(
  (ref) => ref.watch(reportsApiProvider).summary(),
);

/// Daily sales/collections/expenses series — `days` parameterizes.
final accTrendProvider =
    FutureProvider.family<List<AccTrendPoint>, int>(
  (ref, days) => ref.watch(reportsApiProvider).trend(days: days),
);

/// The sales book + journal reconciliation for a period.
/// `('from','to')` — null strings mean "this month" server-side.
final accSalesReportProvider = FutureProvider.family<AccSalesReport,
    ({String? from, String? to})>(
  (ref, period) => ref.watch(reportsApiProvider)
      .salesReport(from: period.from, to: period.to),
);

/// POS strength analysis over `days`.
final accPosPerfProvider =
    FutureProvider.family<List<AccPosPerf>, int>(
  (ref, days) => ref.watch(reportsApiProvider).posPerformance(days: days),
);

/// Commission accruals + journal check (current period = null).
final accCommissionsProvider = FutureProvider<AccCommissionsReport>(
  (ref) => ref.watch(reportsApiProvider).commissionsReport(),
);

/// One day's collections register — `null` date = today.
final accCollectionsDayProvider =
    FutureProvider.family<AccCollectionsDay, String?>(
  (ref, date) =>
      ref.watch(reportsApiProvider).collectionsDaily(date: date),
);

/// Journal browser — (docType, from, to) filter as the family key.
final accJournalProvider = FutureProvider.family<
    ({List<AccJournalEntryRow> entries, double debit, double credit}),
    ({String? docType, String? from, String? to})>(
  (ref, f) => ref.watch(reportsApiProvider)
      .journal(docType: f.docType, from: f.from, to: f.to),
);

/// One entry's resolved legs for the detail sheet.
final accJournalEntryProvider = FutureProvider.family<
    ({AccJournalEntryRow entry, List<AccJournalLineModel> lines}), int>(
  (ref, id) => ref.watch(reportsApiProvider).journalEntry(id),
);

/// Audit trail — entity filter as the family key.
final accAuditProvider = FutureProvider.family<
    ({List<AccAuditRow> rows, int total}), ({String? entity, int? agentId})>(
  (ref, f) => ref.watch(reportsApiProvider)
      .auditLog(entity: f.entity, agentId: f.agentId),
);
