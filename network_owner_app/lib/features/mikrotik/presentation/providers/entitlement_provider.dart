import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_client.dart';
import '../../data/entitlement_service.dart';
import '../../data/subscription_service.dart';

/// Version counter for the owner's MikroTik entitlement state.
///
/// On first watch it fetches `/network-owner/mikrotik/entitlements`
/// once and feeds the result into [EntitlementService.applyServerState].
/// The int bumps each time fresh server state lands, so every
/// `featureAllowedProvider` rebuilds automatically.
///
/// Fail-safe: if the endpoint is unreachable (backend not yet
/// deployed), the service stays in allow-all dev mode.
final entitlementProvider =
    NotifierProvider<EntitlementNotifier, int>(EntitlementNotifier.new);

class EntitlementNotifier extends Notifier<int> {
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
  /// after a purchase or when returning to the router dashboard.
  Future<void> refresh() async {
    final st =
        await SubscriptionService.entitlements(ref.read(apiClientProvider));
    if (st == null) return; // backend not deployed — keep allow-all
    EntitlementService.instance.applyServerState(
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

/// Convenience: `ref.watch(featureAllowedProvider(MikroFeatures.firewall))`.
final featureAllowedProvider = Provider.family<bool, String>((ref, key) {
  ref.watch(entitlementProvider);
  return EntitlementService.instance.isAllowed(key);
});

/// Whether the subscription layer is currently enforcing plans.
final entitlementEnforcedProvider = Provider<bool>((ref) {
  ref.watch(entitlementProvider);
  return EntitlementService.instance.isEnforced;
});

/// Days remaining in the trial — null when no trial is active.
final trialDaysLeftProvider = Provider<int?>((ref) {
  ref.watch(entitlementProvider);
  return EntitlementService.instance.trialDaysLeft;
});

/// True while a paid plan or trial is running (all features open).
final hasPaidAccessProvider = Provider<bool>((ref) {
  ref.watch(entitlementProvider);
  return EntitlementService.instance.hasPaidAccess;
});

/// True once the server has answered the entitlements call — keeps
/// subscription UI hidden (not "expired") while the API is down.
final entitlementLoadedProvider = Provider<bool>((ref) {
  ref.watch(entitlementProvider);
  return EntitlementService.instance.serverLoaded;
});
