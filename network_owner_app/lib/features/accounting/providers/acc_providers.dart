import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../auth/presentation/providers/auth_provider.dart';
import '../data/acc_api.dart';

/// Shared API client for the accounting feature.
final accApiProvider = Provider<AccApi>(
  (ref) => AccApi(ref.watch(apiClientProvider)),
);

/// The signed-in account's accounting identity (owner | admin |
/// distributor | pos) — drives which surface acc_home renders.
/// `null` = account has no acc_agents row and isn't an owner.
/// Watching the auth user id re-resolves the session when the
/// account changes, so a previous login's role never leaks into
/// the next account's surface.
final accSessionProvider = FutureProvider<AccSession?>(
  (ref) {
    ref.watch(authProvider.select((s) => s.user?.id));
    return ref.watch(accApiProvider).me();
  },
);

/// All operating sub-accounts of the tenant.
final accAgentsProvider = FutureProvider<List<AccAgent>>(
  (ref) => ref.watch(accApiProvider).agents(),
);

/// Agents eligible to operate a POS point (role = pos).
final accPosAgentsProvider = FutureProvider<List<AccAgent>>(
  (ref) => ref.watch(accApiProvider).agents(role: 'pos'),
);

/// POS outlets of the tenant.
final accPosPointsProvider = FutureProvider<List<AccPosPoint>>(
  (ref) => ref.watch(accApiProvider).posPoints(),
);

// ── ACC-02 — inventory & card categories ──────────────────────────

/// The accounting card catalog with live stock per row.
final accCategoriesProvider = FutureProvider<List<AccCardCategory>>(
  (ref) => ref.watch(accApiProvider).categories(),
);

/// Stock balances + grand totals (router cards auto-synced server-side).
final accStockProvider = FutureProvider<
    ({List<AccStockRow> rows, double totalQty, double totalValue})>(
  (ref) => ref.watch(accApiProvider).stock(),
);

/// Movements for a category — `null` = all categories (latest first).
final accMovementsProvider =
    FutureProvider.family<List<AccStockMovement>, int?>(
  (ref, categoryId) =>
      ref.watch(accApiProvider).stockMovements(categoryId: categoryId),
);
