import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../data/acc_entitlement_service.dart';
import '../data/billing_api.dart';

/// Shared client for the ACC-11 billing endpoints.
final accBillingApiProvider = Provider<AccBillingApi>(
  (ref) => AccBillingApi(ref.watch(apiClientProvider)),
);

/// Version counter for the tenant's accounting entitlement state.
///
/// On first watch it fetches `/network-owner/accounting/billing/
/// entitlements` once and feeds the result into
/// [AccEntitlementService.applyServerState]. The int bumps each time
/// fresh server state lands, so every `accFeatureAllowedProvider`
/// rebuilds automatically — same contract as the mikrotik
/// entitlementProvider.
///
/// Fail-safe: if the endpoint is unreachable (backend not yet
/// deployed), the service stays in allow-all dev mode.
final accEntitlementProvider =
    NotifierProvider<AccEntitlementNotifier, int>(AccEntitlementNotifier.new);

class AccEntitlementNotifier extends Notifier<int> {
  bool _requested = false;

  @override
  int build() {
    if (!_requested) {
      _requested = true;
      Future.microtask(refresh);
    }
    return 0;
  }

  /// Pull the latest entitlement state and apply it. Safe to call
  /// after a purchase or when returning to the accounting home.
  Future<void> refresh() async {
    final st = await ref.read(accBillingApiProvider).entitlements();
    if (st == null) return; // backend not deployed — keep allow-all
    AccEntitlementService.instance.applyServerState(
      plan: st.planName ?? 'free',
      trialing: st.trialing,
      active: st.active,
      trialEndsAt: st.trialEndsAt,
      allowedFeatures: st.features.toSet(),
      enforced: st.enforced,
    );
    state = state + 1;
  }
}

/// Convenience: `ref.watch(accFeatureAllowedProvider(AccFeatures.inventory))`.
final accFeatureAllowedProvider = Provider.family<bool, String>((ref, key) {
  ref.watch(accEntitlementProvider);
  return AccEntitlementService.instance.isAllowed(key);
});

/// Whether the subscription layer is currently enforcing plans.
final accEntitlementEnforcedProvider = Provider<bool>((ref) {
  ref.watch(accEntitlementProvider);
  return AccEntitlementService.instance.isEnforced;
});

/// Days remaining in the trial — null when no trial is active.
final accTrialDaysLeftProvider = Provider<int?>((ref) {
  ref.watch(accEntitlementProvider);
  return AccEntitlementService.instance.trialDaysLeft;
});

/// True while a paid plan or trial is running (all features open).
final accHasPaidAccessProvider = Provider<bool>((ref) {
  ref.watch(accEntitlementProvider);
  return AccEntitlementService.instance.hasPaidAccess;
});

/// True once the server has answered the entitlements call — keeps
/// subscription UI hidden (not "expired") while the API is down.
final accEntitlementLoadedProvider = Provider<bool>((ref) {
  ref.watch(accEntitlementProvider);
  return AccEntitlementService.instance.serverLoaded;
});
