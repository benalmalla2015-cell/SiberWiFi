import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../data/pos_orders_api.dart';

/// Shared client for the ACC-04 order endpoints.
final posOrdersApiProvider = Provider<PosOrdersApi>(
  (ref) => PosOrdersApi(ref.watch(apiClientProvider)),
);

/// Management list — null filter = all statuses.
final posOrdersProvider =
    FutureProvider.family<List<PosOrder>, String?>(
  (ref, status) => ref.watch(posOrdersApiProvider).orders(status: status),
);

/// The signed-in pos agent's own orders + point summary.
final myPosOrdersProvider = FutureProvider<MyPosOrders>(
  (ref) => ref.watch(posOrdersApiProvider).myOrders(),
);
