import 'feature_keys.dart';

/// Decides whether a MikroTik feature is usable for the current owner.
///
/// Sprint-0 behaviour: **allow everything**. The subscription backend
/// (plans, trials, per-feature free/premium flags) lands in Sprint 9 —
/// at that point [applyServerState] starts receiving real data and the
/// same call sites enforce paid plans automatically without touching
/// any feature screen again.
///
/// Design contract:
/// - UI never reads plan/trial state directly; it calls [isAllowed] or
///   uses the `FeatureGate` widget.
/// - Server truth wins when present: `allowedFeatures` overrides the
///   local default split, `active`/`trialing` unlock everything paid.
class EntitlementService {
  EntitlementService._();
  static final EntitlementService instance = EntitlementService._();

  /// Enforcement switch — stays OFF until the subscription backend is
  /// live (Sprint 9). While false, [isAllowed] always returns true.
  bool _enforced = false;

  /// Server-reported state (populated once the API exists).
  String _plan = 'free';
  bool _trialing = false;
  bool _active = false;
  DateTime? _trialEndsAt;
  Set<String>? _serverAllowed;

  /// Trial length used for display/banners once the API is live.
  /// Server value wins; this is the agreed default (admin-editable).
  static const defaultTrialDays = 14;

  bool get isEnforced => _enforced;
  String get plan => _plan;
  DateTime? get trialEndsAt => _trialEndsAt;

  bool get hasPaidAccess => _active || _trialing;

  int? get trialDaysLeft {
    final end = _trialEndsAt;
    if (end == null) return null;
    final d = end.difference(DateTime.now()).inDays;
    return d < 0 ? 0 : d;
  }

  /// The single decision point every screen uses.
  bool isAllowed(String featureKey) {
    if (!_enforced) return true;
    if (!MikroFeatures.all.contains(featureKey)) return false;
    if (hasPaidAccess) return true;
    final allowed = _serverAllowed ?? MikroFeatures.freeKeys;
    return allowed.contains(featureKey);
  }

  /// Called once the entitlements endpoint exists (Sprint 9).
  /// Unknown keys are dropped defensively.
  void applyServerState({
    required String plan,
    required bool trialing,
    required bool active,
    DateTime? trialEndsAt,
    Set<String>? allowedFeatures,
    bool enforced = true,
  }) {
    _enforced = enforced;
    _plan = plan;
    _trialing = trialing;
    _active = active;
    _trialEndsAt = trialEndsAt;
    _serverAllowed = allowedFeatures
        ?.where(MikroFeatures.all.contains)
        .toSet();
  }

  /// Test/dev hook — returns to allow-all.
  void reset() {
    _enforced = false;
    _plan = 'free';
    _trialing = false;
    _active = false;
    _trialEndsAt = null;
    _serverAllowed = null;
  }
}
