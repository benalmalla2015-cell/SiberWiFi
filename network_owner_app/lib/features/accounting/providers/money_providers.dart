import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../data/money_api.dart';

/// Shared client for the ACC-05 money endpoints.
final moneyApiProvider = Provider<MoneyApi>(
  (ref) => MoneyApi(ref.watch(apiClientProvider)),
);

/// The platform's currency pair + live rate (read-only).
final accCurrenciesProvider = FutureProvider<AccCurrencyInfo>(
  (ref) => ref.watch(moneyApiProvider).currencies(),
);

/// Collections list — null filter = all party types.
final accCollectionsProvider =
    FutureProvider.family<List<AccCollection>, String?>(
  (ref, partyType) =>
      ref.watch(moneyApiProvider).collections(partyType: partyType),
);

/// Debts list — null filter = all statuses.
final accDebtsProvider = FutureProvider.family<List<AccDebt>, String?>(
  (ref, status) => ref.watch(moneyApiProvider).debts(status: status),
);

/// Cash boxes of the tenant.
final accCashBoxesProvider = FutureProvider<List<AccCashBox>>(
  (ref) => ref.watch(moneyApiProvider).cashBoxes(),
);

/// Inter-box transfer history.
final accTransfersProvider = FutureProvider<List<AccTransfer>>(
  (ref) => ref.watch(moneyApiProvider).transfers(),
);

/// Posted expenses — null filter = all categories.
final accExpensesProvider =
    FutureProvider.family<List<AccExpense>, int?>(
  (ref, categoryId) =>
      ref.watch(moneyApiProvider).expenses(categoryId: categoryId),
);

/// Expense categories (auto-seeded server-side on first read).
final accExpenseCategoriesProvider =
    FutureProvider<List<AccExpenseCategory>>(
  (ref) => ref.watch(moneyApiProvider).expenseCategories(),
);
