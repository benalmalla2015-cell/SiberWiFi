import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../data/loyalty_api.dart';

/// Shared client for the ACC-10 surface (tiers + notifications +
/// balances + withdrawal review).
final loyaltyApiProvider = Provider<LoyaltyApi>(
  (ref) => LoyaltyApi(ref.watch(apiClientProvider)),
);

/// All configured discount tiers.
final accDiscountTiersProvider = FutureProvider<List<AccDiscountTier>>(
  (ref) => ref.watch(loyaltyApiProvider).tiers(),
);

/// All WhatsApp event templates.
final accWebhookEventsProvider =
    FutureProvider<List<AccWebhookEventRow>>(
  (ref) => ref.watch(loyaltyApiProvider).webhookEvents(),
);

/// Party balances — null filter lists every party type.
final accBalancesProvider =
    FutureProvider.family<List<AccBalanceRow>, String?>(
  (ref, party) => ref.watch(loyaltyApiProvider).balances(party: party),
);

/// The withdrawal review queue — null filter lists every status.
final accWithdrawalsProvider =
    FutureProvider.family<List<AccWithdrawalRow>, String?>(
  (ref, status) =>
      ref.watch(loyaltyApiProvider).withdrawals(status: status),
);

/// Rendered due-debt reminders ready to send over WhatsApp.
final accDebtDueProvider = FutureProvider<List<AccDebtDueReminder>>(
  (ref) => ref.watch(loyaltyApiProvider).dueDebts(),
);
