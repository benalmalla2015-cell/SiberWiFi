import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../data/dist_api.dart';

/// Shared client for the ACC-06 distributor endpoints.
final distApiProvider = Provider<DistApi>(
  (ref) => DistApi(ref.watch(apiClientProvider)),
);

/// The distributor home read model — stock, daily remaining, POS
/// balances, and today's counters in one round trip.
final distHomeProvider = FutureProvider<DistHome>(
  (ref) => ref.watch(distApiProvider).home(),
);

/// The sales register — null filter = all payment kinds.
final distSalesProvider =
    FutureProvider.family<List<DistSale>, String?>(
  (ref, paymentKind) =>
      ref.watch(distApiProvider).sales(paymentKind: paymentKind),
);

/// Period report — `(from, to)` as YYYY-MM-DD, nulls = current month.
final distReportProvider = FutureProvider.family<DistReport,
    ({String? from, String? to})>(
  (ref, range) =>
      ref.watch(distApiProvider).report(from: range.from, to: range.to),
);

/// Commission period rows — null = all periods.
final distCommissionsProvider =
    FutureProvider.family<List<DistCommission>, String?>(
  (ref, period) =>
      ref.watch(distApiProvider).commissions(period: period),
);
