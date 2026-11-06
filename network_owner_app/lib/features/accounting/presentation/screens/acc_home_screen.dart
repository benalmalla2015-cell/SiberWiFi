import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/connectivity_service.dart';
import '../../../mikrotik/data/feature_keys.dart';
import '../../../mikrotik/presentation/widgets/ui_states.dart';
import '../../data/acc_api.dart';
import '../../data/acc_entitlement_service.dart';
import '../../providers/acc_entitlement_provider.dart';
import '../../providers/acc_providers.dart';
import '../../providers/reports_providers.dart';
import '../../providers/sync_providers.dart';
import '../widgets/acc_feature_gate.dart';
import 'acc_subscription_screen.dart';
import 'agents_screen.dart';
import 'audit_log_screen.dart';
import 'backup_screen.dart';
import 'balances_screen.dart';
import 'card_categories_screen.dart';
import 'cash_boxes_screen.dart';
import 'collections_screen.dart';
import 'debts_screen.dart';
import 'discount_tiers_screen.dart';
import 'dist_home_screen.dart';
import 'doc_header_screen.dart';
import 'expenses_screen.dart';
import 'inventory_screen.dart';
import 'journal_screen.dart';
import 'pos_analysis_screen.dart';
import 'pos_home_screen.dart';
import 'pos_management_screen.dart';
import 'pos_orders_screen.dart';
import 'reports_screen.dart';
import 'sync_center_screen.dart';
import 'webhook_events_screen.dart';

/// Accounting home — role-aware launcher (PLAN §1).
///
/// The session resolved by `/accounting/me` picks the surface:
/// - owner/admin → the management grid (sections unlock per sprint);
/// - distributor / pos → their dedicated home surfaces (ACC-06/07).
/// `null` session = the account has no accounting role at all.
class AccHomeScreen extends ConsumerWidget {
  const AccHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionAsync = ref.watch(accSessionProvider);

    // ACC-12 — reconnecting flushes the device's offline queue
    // through /sync/push. Fire-and-forget: the sync center shows
    // whatever stays pending or needs review.
    ref.listen(connectivityProvider, (prev, next) {
      final isOnline = next.valueOrNull == true;
      final wasOffline = prev?.valueOrNull == false;
      if (isOnline && wasOffline) {
        ref.read(accSyncEngineProvider).flush();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('المحاسبة'),
        actions: [
          // acc agents have no owner bottom-nav — this is their only
          // path to profile/logout (router keeps /profile allowed).
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: 'حسابي',
            onPressed: () => context.push('/profile'),
          ),
        ],
      ),
      body: Container(
        width: double.infinity,
        color: AppColors.inputBg,
        child: sessionAsync.when(
          loading: () => const LoadingState(),
          error: (e, _) => ErrorRetry(
            message: 'تعذّر تحميل حساب المحاسبة\n$e',
            onRetry: () => ref.invalidate(accSessionProvider),
          ),
          data: (session) {
            if (session == null) {
              return const _NoAccountState();
            }
            if (session.isDistributor) {
              return const AccFeatureGate(
                feature: AccFeatures.distributor,
                child: DistHomeScreen(),
              );
            }
            if (session.isPos) {
              return const AccFeatureGate(
                feature: AccFeatures.posApp,
                child: PosHomeScreen(),
              );
            }
            return _ManagerHome(session: session);
          },
        ),
      ),
    );
  }
}

/// Owner/admin surface — section grid; each tile gates behind its
/// acc.* feature key, disabled tiles ship with later sprints.
class _ManagerHome extends StatelessWidget {
  final AccSession session;
  const _ManagerHome({required this.session});

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) => RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(accSummaryProvider);
          ref.invalidate(accTrendProvider(30));
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _HeroCard(session: session),
            const SizedBox(height: 16),
            const _ExecutiveSummary(),
            const SizedBox(height: 16),
          _SectionTile(
            title: 'المستخدمون',
            subtitle: 'حسابات الإدارة والموزعين ونقاط البيع',
            icon: Icons.manage_accounts_outlined,
            color: AppColors.primary,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const AccFeatureGate(
                feature: AccFeatures.agents,
                child: AgentsScreen(),
              ),
            )),
          ),
          _SectionTile(
            title: 'نقاط البيع',
            subtitle: 'النقاط، حسابات التشغيل، والأجهزة المرتبطة',
            icon: Icons.storefront_outlined,
            color: AppColors.success,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const AccFeatureGate(
                feature: AccFeatures.posPoints,
                child: PosManagementScreen(),
              ),
            )),
          ),
          _SectionTile(
            title: 'طلبات نقاط البيع',
            subtitle: 'اعتماد ورفض طلبات الحزم الواردة من النقاط',
            icon: Icons.receipt_long_outlined,
            color: AppColors.warning,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const AccFeatureGate(
                feature: AccFeatures.posOrders,
                child: PosOrdersScreen(),
              ),
            )),
          ),
          _SectionTile(
            title: 'فئات الكروت',
            subtitle: 'أسعار البيع والتكلفة ومصدر الكروت',
            icon: Icons.style_outlined,
            color: AppColors.primary,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const AccFeatureGate(
                feature: AccFeatures.categories,
                child: CardCategoriesScreen(),
              ),
            )),
          ),
          _SectionTile(
            title: 'المخزون',
            subtitle: 'الأرصدة والحركات — كروت الراوتر تُرحَّل تلقائياً',
            icon: Icons.inventory_2_outlined,
            color: AppColors.lightBlue,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const AccFeatureGate(
                feature: AccFeatures.inventory,
                child: InventoryScreen(),
              ),
            )),
          ),
          _SectionTile(
            title: 'التحصيلات',
            subtitle: 'تحصيل نقدي من النقاط والموزعين والعملاء',
            icon: Icons.payments_outlined,
            color: AppColors.success,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const AccFeatureGate(
                feature: AccFeatures.collections,
                child: CollectionsScreen(),
              ),
            )),
          ),
          _SectionTile(
            title: 'المديونيات',
            subtitle: 'ديون الأطراف والسداد الجزئي والكامل',
            icon: Icons.handshake_outlined,
            color: AppColors.warning,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const AccFeatureGate(
                feature: AccFeatures.debts,
                child: DebtsScreen(),
              ),
            )),
          ),
          _SectionTile(
            title: 'الصناديق',
            subtitle: 'الأدراج المالية والتحويلات بينها',
            icon: Icons.account_balance_wallet_outlined,
            color: AppColors.primary,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const AccFeatureGate(
                feature: AccFeatures.cashBoxes,
                child: CashBoxesScreen(),
              ),
            )),
          ),
          _SectionTile(
            title: 'المصروفات',
            subtitle: 'المصروفات اليومية وفئاتها',
            icon: Icons.money_off_outlined,
            color: AppColors.error,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const AccFeatureGate(
                feature: AccFeatures.expenses,
                child: ExpensesScreen(),
              ),
            )),
          ),
          _SectionTile(
            title: 'شرائح الخصم',
            subtitle: 'خصومات ومكافآت تلقائية على المبيعات والطلبات',
            icon: Icons.percent_outlined,
            color: AppColors.accent,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const AccFeatureGate(
                feature: AccFeatures.discountTiers,
                child: DiscountTiersScreen(),
              ),
            )),
          ),
          _SectionTile(
            title: 'الأرصدة والسحوبات',
            subtitle: 'أرصدة الأطراف ومراجعة طلبات سحب الأرباح',
            icon: Icons.account_balance_outlined,
            color: AppColors.lightBlue,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const AccFeatureGate(
                feature: AccFeatures.balances,
                child: BalancesScreen(),
              ),
            )),
          ),
          _SectionTile(
            title: 'إشعارات واتساب',
            subtitle: 'قوالب أحداث البيع والتحصيل وتذكير الديون',
            icon: Icons.chat_bubble_outline,
            color: AppColors.success,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const AccFeatureGate(
                feature: AccFeatures.settings,
                child: WebhookEventsScreen(),
              ),
            )),
          ),
          _SectionTile(
            title: 'الاشتراك والباقات',
            subtitle: 'حالة التجربة والباقات والدفع بالمحفظة أو التحويل',
            icon: Icons.workspace_premium_outlined,
            color: AppColors.accent,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const AccFeatureGate(
                feature: AccFeatures.billing,
                child: AccSubscriptionScreen(),
              ),
            )),
          ),
          _SectionTile(
            title: 'مركز المزامنة',
            subtitle: 'طابور عمليات offline والمزامنة مع الخادم',
            icon: Icons.sync_outlined,
            color: AppColors.lightBlue,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const AccFeatureGate(
                feature: AccFeatures.syncCenter,
                child: AccSyncCenterScreen(),
              ),
            )),
          ),
          _SectionTile(
            title: 'النسخ الاحتياطي',
            subtitle: 'تصدير بيانات المحاسبة واستعادتها',
            icon: Icons.backup_outlined,
            color: AppColors.primary,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const AccFeatureGate(
                feature: AccFeatures.backup,
                child: AccBackupScreen(),
              ),
            )),
          ),
          _SectionTile(
            title: 'رأس المستند',
            subtitle: 'اسم النشاط والشعار على المستندات المطبوعة',
            icon: Icons.badge_outlined,
            color: AppColors.warning,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const AccFeatureGate(
                feature: AccFeatures.settings,
                child: AccDocHeaderScreen(),
              ),
            )),
          ),
          _SectionTile(
            title: 'التقارير',
            subtitle: 'الملخص التنفيذي والمبيعات والعمولات',
            icon: Icons.analytics_outlined,
            color: AppColors.primary,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const AccFeatureGate(
                feature: AccFeatures.reports,
                child: ReportsScreen(),
              ),
            )),
          ),
          _SectionTile(
            title: 'تحليل نقاط البيع',
            subtitle: 'قوة كل نقطة — مبيعاتها وتحصيلها وذممها',
            icon: Icons.query_stats_outlined,
            color: AppColors.success,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const AccFeatureGate(
                feature: AccFeatures.posAnalysis,
                child: PosAnalysisScreen(),
              ),
            )),
          ),
          _SectionTile(
            title: 'القيود اليومية',
            subtitle: 'الدورة المستندية — قيود لا تُعدَّل بل تُعكَس',
            icon: Icons.receipt_long_outlined,
            color: AppColors.warning,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const AccFeatureGate(
                feature: AccFeatures.journal,
                child: JournalScreen(),
              ),
            )),
          ),
          _SectionTile(
            title: 'سجل التتبع',
            subtitle: 'كل عملية مالية — الفاعل والوقت والنتيجة',
            icon: Icons.fact_check_outlined,
            color: AppColors.lightBlue,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const AccFeatureGate(
                feature: AccFeatures.auditLog,
                child: AuditLogScreen(),
              ),
            )),
          ),
          ],
        ),
      ),
    );
  }
}

class _HeroCard extends ConsumerWidget {
  final AccSession session;
  const _HeroCard({required this.session});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Subscription indicator — only once the server answered, and a
    // paid/trial state actually exists (ACC-11).
    final loaded = ref.watch(accEntitlementLoadedProvider);
    final paid = ref.watch(accHasPaidAccessProvider);
    final trialing = AccEntitlementService.instance.isTrialing;
    final trialLeft = ref.watch(accTrialDaysLeftProvider);
    final enforced = ref.watch(accEntitlementEnforcedProvider);
    final planName = AccEntitlementService.instance.plan;
    final String? subLabel = !loaded
        ? null
        : trialing
            ? 'فترة تجريبية — بقي ${trialLeft ?? 0} يوم'
            : paid
                ? 'اشتراك نشط${planName != 'free' ? ' — $planName' : ''}'
                : enforced
                    ? 'انتهى الاشتراك — رقِّ حسابك'
                    : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.12),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.lightBlue],
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.account_balance_outlined,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'محاسبة الشبكة',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  session.isOwner
                      ? 'حساب المالك — كل الصلاحيات'
                      : 'حساب إدارة — ${session.agent?.displayName ?? ''}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textGray,
                  ),
                ),
                if (subLabel != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: paid
                          ? AppColors.success
                          : AppColors.accent,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _SectionTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withValues(alpha: enabled ? 0.12 : 0.05),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon,
              color: enabled ? color : AppColors.textLight, size: 24),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: enabled ? AppColors.textDark : AppColors.textGray,
          ),
        ),
        subtitle: Text(
          subtitle,
          style:
              const TextStyle(fontSize: 11, color: AppColors.textGray),
        ),
        trailing: Icon(
          enabled ? Icons.chevron_left : Icons.lock_outline,
          size: 18,
          color: enabled ? AppColors.textGray : AppColors.textLight,
        ),
        onTap: onTap,
      ),
    );
  }
}

class _NoAccountState extends StatelessWidget {
  const _NoAccountState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.no_accounts_outlined,
                size: 56, color: AppColors.textLight),
            SizedBox(height: 16),
            Text(
              'لا يوجد حساب محاسبة',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark),
            ),
            SizedBox(height: 8),
            Text(
              'هذا الحساب غير مرتبط بأي شبكة كوكيل.\nاطلب من مالك الشبكة إضافتك من شاشة «المستخدمون».',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13, height: 1.7, color: AppColors.textGray),
            ),
          ],
        ),
      ),
    );
  }
}

/// ACC-09 — executive summary strip on the manager home: today's
/// money in/out beside the month result, over a compact 30-day
/// trend. Every figure is journal-derived via /accounting/summary.
class _ExecutiveSummary extends ConsumerWidget {
  const _ExecutiveSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(accSummaryProvider);
    final trendAsync = ref.watch(accTrendProvider(30));

    return summaryAsync.when(
      loading: () => const SizedBox(height: 8),
      error: (e, _) => const SizedBox(height: 8),
      data: (s) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Expanded(
                child: Text('الملخص التنفيذي',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark)),
              ),
              GestureDetector(
                onTap: () =>
                    Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const AccFeatureGate(
                    feature: AccFeatures.reports,
                    child: ReportsScreen(),
                  ),
                )),
                child: const Text('التفاصيل',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary)),
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: _HomeStat(
                  label: 'مبيعات اليوم',
                  value: _homeMoney(s.todaySales),
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HomeStat(
                  label: 'تحصيل اليوم',
                  value: _homeMoney(s.todayCollections),
                  color: AppColors.success,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HomeStat(
                  label: 'نتيجة الشهر',
                  value: _homeMoney(s.monthResult),
                  color: s.monthResult >= 0
                      ? AppColors.lightBlue
                      : AppColors.error,
                ),
              ),
            ]),
            const SizedBox(height: 12),
            trendAsync.maybeWhen(
              data: (points) => points.isEmpty
                  ? const SizedBox()
                  : SizedBox(
                      height: 70,
                      child: LineChart(
                        LineChartData(
                          gridData: const FlGridData(show: false),
                          titlesData:
                              const FlTitlesData(show: false),
                          borderData: FlBorderData(show: false),
                          minX: 0,
                          maxX: (points.length - 1).toDouble(),
                          lineBarsData: [
                            LineChartBarData(
                              spots: [
                                for (var i = 0;
                                    i < points.length;
                                    i++)
                                  FlSpot(i.toDouble(),
                                      points[i].sales),
                              ],
                              isCurved: true,
                              color: AppColors.primary,
                              barWidth: 2,
                              dotData:
                                  const FlDotData(show: false),
                              belowBarData: BarAreaData(
                                show: true,
                                gradient: LinearGradient(
                                  colors: [
                                    AppColors.primary.withValues(
                                        alpha: 0.15),
                                    AppColors.primary.withValues(
                                        alpha: 0.0),
                                  ],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
              orElse: () => const SizedBox(),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _HomeStat(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 14)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  color: AppColors.textGray, fontSize: 10)),
        ],
      ),
    );
  }
}

String _homeMoney(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
