/// Feature-key registry for the MikroTik manager.
///
/// Every gateable section of the feature has a stable key. The mapping
/// below is the *default* plan split; the backend can override any key's
/// free/premium classification at runtime via `/network-owner/mikrotik/
/// entitlements` (admin-editable from Filament — no app update needed).
///
/// Rules for using these keys:
/// - Gate at the section/screen level (`FeatureGate`), never deep inside
///   buttons — one check per user-facing feature keeps reasoning simple.
/// - During development `EntitlementService` allows everything, so new
///   screens must still declare their key but will never be blocked.
class MikroFeatures {
  MikroFeatures._();

  static const connection = 'mikrotik.connection';
  static const monitoring = 'mikrotik.monitoring';
  static const hotspotUsers = 'mikrotik.hotspot_users';
  static const voucherCards = 'mikrotik.voucher_cards';
  static const cardTemplates = 'mikrotik.card_templates';
  static const pppoe = 'mikrotik.pppoe';
  static const userManager = 'mikrotik.user_manager';
  static const profiles = 'mikrotik.profiles';
  static const queues = 'mikrotik.queues';
  static const firewall = 'mikrotik.firewall';
  static const nat = 'mikrotik.nat';
  static const networkTools = 'mikrotik.network_tools';
  static const diagnostics = 'mikrotik.diagnostics';
  static const systemAdmin = 'mikrotik.system_admin';
  static const backup = 'mikrotik.backup';
  static const hotspotPages = 'mikrotik.hotspot_pages';
  static const telegram = 'mikrotik.telegram';
  static const remoteAccess = 'mikrotik.remote_access';

  /// Keys allowed for free / trial-expired accounts.
  /// Everything not listed here is premium by default.
  static const freeKeys = <String>{
    connection,
    monitoring,
    hotspotUsers,
  };

  /// Every known key — used to validate server payloads.
  static const all = <String>{
    connection,
    monitoring,
    hotspotUsers,
    voucherCards,
    cardTemplates,
    pppoe,
    userManager,
    profiles,
    queues,
    firewall,
    nat,
    networkTools,
    diagnostics,
    systemAdmin,
    backup,
    hotspotPages,
    telegram,
    remoteAccess,
  };
}

// ─── Track ACC — accounting feature keys (appended block, ACC-00) ─────
//
// Accounting is a separate subscription domain from MikroTik
// (`acc_plans` / `acc.enforce` — see PLAN.md §6). These keys are
// declared once here so every accounting screen can gate itself from
// day one; the dedicated accounting entitlement service lands in
// ACC-11 and owns their free/premium resolution.
class AccFeatures {
  AccFeatures._();

  static const module = 'acc.module';
  static const dashboard = 'acc.dashboard';
  static const inventory = 'acc.inventory';
  static const categories = 'acc.categories';
  static const sales = 'acc.sales';
  static const posPoints = 'acc.pos_points';
  static const posOrders = 'acc.pos_orders';
  static const agents = 'acc.agents';
  static const networkDevices = 'acc.network_devices';
  static const collections = 'acc.collections';
  static const debts = 'acc.debts';
  static const balances = 'acc.balances';
  static const expenses = 'acc.expenses';
  static const purchases = 'acc.purchases';
  static const returnsKey = 'acc.returns';
  static const damaged = 'acc.damaged';
  static const discountTiers = 'acc.discount_tiers';
  static const cashBoxes = 'acc.cash_boxes';
  static const journal = 'acc.journal';
  static const reports = 'acc.reports';
  static const posAnalysis = 'acc.pos_analysis';
  static const auditLog = 'acc.audit_log';
  static const syncCenter = 'acc.sync_center';
  static const backup = 'acc.backup';
  static const settings = 'acc.settings';
  static const billing = 'acc.billing';
  static const distributor = 'acc.distributor';
  static const posApp = 'acc.pos_app';

  /// Keys allowed for free / trial-expired accounts.
  /// Everything not listed here is premium by default.
  static const freeKeys = <String>{
    module,
    dashboard,
  };

  /// Every known key — used to validate server payloads.
  static const all = <String>{
    module,
    dashboard,
    inventory,
    categories,
    sales,
    posPoints,
    posOrders,
    agents,
    networkDevices,
    collections,
    debts,
    balances,
    expenses,
    purchases,
    returnsKey,
    damaged,
    discountTiers,
    cashBoxes,
    journal,
    reports,
    posAnalysis,
    auditLog,
    syncCenter,
    backup,
    settings,
    billing,
    distributor,
    posApp,
  };
}
