import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../data/money_api.dart' show AccCollection;
import '../data/pos_app_api.dart';

/// Shared client for the ACC-07 POS surface.
final posAppApiProvider = Provider<PosAppApi>(
  (ref) => PosAppApi(ref.watch(apiClientProvider)),
);

/// The /pos/home aggregate — balances, packages, stats, feed.
final posHomeProvider = FutureProvider<PosHomeData>(
  (ref) => ref.watch(posAppApiProvider).home(),
);

/// Points + profit movements of the bound point (latest first).
final posLedgerProvider = FutureProvider<List<PosLedgerRow>>(
  (ref) => ref.watch(posAppApiProvider).ledger(),
);

/// The agent's own withdrawal requests.
final posWithdrawalsProvider = FutureProvider<List<PosWithdrawal>>(
  (ref) => ref.watch(posAppApiProvider).withdrawals(),
);

/// The bound point's exchange history.
final posExchangesProvider = FutureProvider<List<PosExchange>>(
  (ref) => ref.watch(posAppApiProvider).exchanges(),
);

/// Collections recorded against the bound point (ACC-05 endpoint).
final posCollectionsProvider = FutureProvider<List<AccCollection>>(
  (ref) => ref.watch(posAppApiProvider).collectionsReceived(),
);
