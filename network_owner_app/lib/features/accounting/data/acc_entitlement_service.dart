import '../../mikrotik/data/feature_keys.dart';

/// Decides whether an accounting feature is usable for the current
/// tenant (ACC-11) — the dedicated service the AccFeatures block in
/// feature_keys.dart announced. Mirrors EntitlementService exactly:
///
/// - **allow everything** until `acc.enforce` flips to '1' server-side;
/// - UI never reads plan/trial state directly — it calls [isAllowed]
///   or uses the `AccFeatureGate` widget;
/// - server truth wins when present: `allowedFeatures` overrides the
///   local default split, `active`/`trialing` unlock everything paid.
class AccEntitlementService {
  AccEntitlementService._();
  static final AccEntitlementService instance = AccEntitlementService._();

  /// Enforcement switch — driven by acc.enforce server-side.
  /// While false, [isAllowed] always returns true.
  bool _enforced = false;

  /// Server-reported state (populated once /billing/entitlements
  /// answers).
  String _plan = 'free';
  bool _trialing = false;
  bool _active = false;
  DateTime? _trialEndsAt;
  Set<String>? _serverAllowed;

  /// True after the first successful server response — lets UI hide
  /// subscription indicators while the backend is unreachable instead
  /// of showing a misleading "expired" state.
  bool _loaded = false;

  /// Trial length used for display/banners. Server value wins; this
  /// is the agreed default (acc.trial_days, admin-editable).
  static const defaultTrialDays = 30;

  bool get isEnforced => _enforced;
  bool get serverLoaded => _loaded;
  String get plan => _plan;
  DateTime? get trialEndsAt => _trialEndsAt;

  bool get hasPaidAccess => _active || _trialing;
  bool get isActiveSub => _active;
  bool get isTrialing => _trialing;

  int? get trialDaysLeft {
    final end = _trialEndsAt;
    if (end == null) return null;
    final d = end.difference(DateTime.now()).inDays;
    return d < 0 ? 0 : d;
  }

  /// The single decision point every accounting screen uses.
  bool isAllowed(String featureKey) {
    if (!_enforced) return true;
    if (!AccFeatures.all.contains(featureKey)) return false;
    if (hasPaidAccess) return true;
    final allowed = _serverAllowed ?? AccFeatures.freeKeys;
    return allowed.contains(featureKey);
  }

  /// Fed by GET /billing/entitlements. Unknown keys are dropped
  /// defensively against the local registry.
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
    _loaded = true;
    _serverAllowed = allowedFeatures
        ?.where(AccFeatures.all.contains)
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
    _loaded = false;
  }
}
