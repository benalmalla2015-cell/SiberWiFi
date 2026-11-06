import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../mikrotik/presentation/widgets/ui_states.dart';
import '../../data/reports_api.dart';
import '../../providers/reports_providers.dart';

/// ACC-09 — التقارير والمتابعة (PLAN §5: reports_screen).
///
/// Three tabs: executive summary (month figures + today + the
/// 30-day trend chart), the sales book sliced by kind/category/
/// point/distributor with its journal reconciliation, and
/// distributor commissions checked against POS_PROFITS legs.
/// Every money figure is journal-derived server-side.
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('التقارير'),
          bottom: const TabBar(tabs: [
            Tab(text: 'ملخص تنفيذي'),
            Tab(text: 'المبيعات'),
            Tab(text: 'العمولات'),
          ]),
        ),
        body: Container(
          color: AppColors.inputBg,
          child: const TabBarView(children: [
            _SummaryTab(),
            _SalesTab(),
            _CommissionsTab(),
          ]),
        ),
      ),
    );
  }
}

// ── الملخص التنفيذي ────────────────────────────────────────────

class _SummaryTab extends ConsumerWidget {
  const _SummaryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(accSummaryProvider);
    final trendAsync = ref.watch(accTrendProvider(30));

    return summaryAsync.when(
      loading: () => const LoadingState(),
      error: (e, _) => ErrorRetry(
        message: 'تعذّر تحميل الملخص\n$e',
        onRetry: () => ref.invalidate(accSummaryProvider),
      ),
      data: (s) => RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(accSummaryProvider);
          ref.invalidate(accTrendProvider(30));
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _ResultCard(result: s.monthResult, entries: s.monthEntries),
            const SizedBox(height: 14),
            _SectionTitle('هذا الشهر'),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: _MiniStat(
                  label: 'الإيرادات',
                  value: _money(s.monthRevenue),
                  color: AppColors.success,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniStat(
                  label: 'المصروفات + التكلفة',
                  value: _money(s.monthExpenses),
                  color: AppColors.error,
                ),
              ),
            ]),
            const SizedBox(height: 14),
            _SectionTitle('اليوم'),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: _MiniStat(
                  label: 'مبيعات',
                  value: _money(s.todaySales),
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniStat(
                  label: 'تحصيلات',
                  value: _money(s.todayCollections),
                  color: AppColors.lightBlue,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniStat(
                  label: 'مصروفات',
                  value: _money(s.todayExpenses),
                  color: AppColors.warning,
                ),
              ),
            ]),
            const SizedBox(height: 14),
            _SectionTitle('اتجاه 30 يوماً'),
            const SizedBox(height: 8),
            trendAsync.when(
              loading: () => const SizedBox(
                height: 160,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => const SizedBox(
                height: 160,
                child: Center(
                  child: Text('تعذّر تحميل الاتجاه',
                      style: TextStyle(color: AppColors.textGray)),
                ),
              ),
              data: (points) => _TrendCard(points: points),
            ),
            const SizedBox(height: 14),
            _SectionTitle('الأرصدة'),
            const SizedBox(height: 8),
            _BalanceRow(icon: Icons.account_balance_wallet_outlined,
                label: 'الصناديق (بالأساس)', value: _money(s.cashBase)),
            _BalanceRow(icon: Icons.call_received_outlined,
                label: 'ذمم لنا (نقاط+موزعون+عملاء)',
                value: _money(s.receivablesTotal)),
            _BalanceRow(icon: Icons.call_made_outlined,
                label: 'ذمم علينا (موردون+أرباح)',
                value: _money(s.liabilitiesTotal)),
            _BalanceRow(icon: Icons.inventory_2_outlined,
                label: 'قيمة المخزون (${s.stockQty.toStringAsFixed(0)} وحدة)',
                value: _money(s.stockValue)),
            _BalanceRow(icon: Icons.handshake_outlined,
                label: 'ديون مفتوحة (${s.openDebts})',
                value: _money(s.debtsRemaining)),
          ],
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final double result;
  final int entries;
  const _ResultCard({required this.result, required this.entries});

  @override
  Widget build(BuildContext context) {
    final positive = result >= 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: positive
              ? [AppColors.primary, AppColors.lightBlue]
              : [AppColors.accent, const Color(0xFFB91C1C)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            positive ? 'نتيجة التشغيل — ربح' : 'نتيجة التشغيل — خسارة',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Text(
            _money(result),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'من $entries قيداً مرحّلاً هذا الشهر',
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _TrendCard extends StatelessWidget {
  final List<AccTrendPoint> points;
  const _TrendCard({required this.points});

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const EmptyState('لا توجد حركة بعد',
          icon: Icons.show_chart_outlined);
    }
    final maxY = points
            .map((p) => p.sales)
            .fold(0.0, (a, b) => a > b ? a : b) *
        1.25;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
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
      child: SizedBox(
        height: 170,
        child: LineChart(
          LineChartData(
            gridData: FlGridData(
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) =>
                  const FlLine(color: AppColors.divider, strokeWidth: 1),
            ),
            titlesData: FlTitlesData(
              rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false)),
              topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: 5,
                  getTitlesWidget: (val, meta) {
                    final i = val.toInt();
                    if (i < 0 || i >= points.length || i % 5 != 0) {
                      return const SizedBox();
                    }
                    final d = points[i].date;
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        d.length >= 10 ? d.substring(8) : d,
                        style: const TextStyle(
                            fontSize: 9, color: AppColors.textGray),
                      ),
                    );
                  },
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 38,
                  getTitlesWidget: (val, meta) => Text(
                    val >= 1000
                        ? '${(val / 1000).toStringAsFixed(0)}K'
                        : val.toStringAsFixed(0),
                    style: const TextStyle(
                        fontSize: 9, color: AppColors.textGray),
                  ),
                ),
              ),
            ),
            borderData: FlBorderData(show: false),
            minX: 0,
            maxX: (points.length - 1).toDouble(),
            minY: 0,
            maxY: maxY <= 0 ? 1 : maxY,
            lineBarsData: [
              _line(points, (p) => p.sales, AppColors.primary),
              _line(points, (p) => p.collections, AppColors.success),
              _line(points, (p) => p.expenses, AppColors.error),
            ],
          ),
        ),
      ),
    );
  }

  LineChartBarData _line(
    List<AccTrendPoint> pts,
    double Function(AccTrendPoint) v,
    Color color,
  ) {
    return LineChartBarData(
      spots: [
        for (var i = 0; i < pts.length; i++)
          FlSpot(i.toDouble(), v(pts[i])),
      ],
      isCurved: true,
      color: color,
      barWidth: 2.5,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(
        show: color == AppColors.primary,
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.18),
            color.withValues(alpha: 0.0),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
    );
  }
}

class _BalanceRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _BalanceRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(children: [
        Icon(icon, color: AppColors.primary, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textDark)),
        ),
        Text(value,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppColors.primary)),
      ]),
    );
  }
}

// ── المبيعات ───────────────────────────────────────────────────

class _SalesTab extends ConsumerStatefulWidget {
  const _SalesTab();

  @override
  ConsumerState<_SalesTab> createState() => _SalesTabState();
}

class _SalesTabState extends ConsumerState<_SalesTab> {
  ({String? from, String? to}) _period = (from: null, to: null);

  static const _ranges = <String, int>{
    'هذا الشهر': 0,
    '7 أيام': 7,
    '30 يوماً': 30,
    '90 يوماً': 90,
  };
  String _range = 'هذا الشهر';

  void _pick(String label) {
    setState(() {
      _range = label;
      final days = _ranges[label]!;
      if (days == 0) {
        _period = (from: null, to: null);
      } else {
        final from = DateTime.now()
            .subtract(Duration(days: days - 1))
            .toIso8601String()
            .substring(0, 10);
        _period = (from: from, to: null);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final reportAsync = ref.watch(accSalesReportProvider(_period));

    return reportAsync.when(
      loading: () => const LoadingState(),
      error: (e, _) => ErrorRetry(
        message: 'تعذّر تحميل تقرير المبيعات\n$e',
        onRetry: () => ref.invalidate(accSalesReportProvider(_period)),
      ),
      data: (r) => RefreshIndicator(
        onRefresh: () async =>
            ref.invalidate(accSalesReportProvider(_period)),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _ranges.keys.map((label) {
                  final selected = label == _range;
                  return Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: selected,
                      onSelected: (_) => _pick(label),
                      selectedColor:
                          AppColors.primary.withValues(alpha: 0.12),
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: selected
                            ? AppColors.primary
                            : AppColors.textGray,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: _MiniStat(
                  label: 'إجمالي المبيعات',
                  value: _money(r.total),
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniStat(
                  label: 'نقد',
                  value: _money(r.paid),
                  color: AppColors.success,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniStat(
                  label: 'آجل',
                  value: _money(r.credit),
                  color: AppColors.warning,
                ),
              ),
            ]),
            const SizedBox(height: 10),
            _JournalCheck(
              docsTotal: r.total,
              journalTotal: r.journalRevenue,
              count: r.count,
            ),
            const SizedBox(height: 14),
            _SectionTitle('حسب الفئة'),
            const SizedBox(height: 8),
            ...r.byCategory.map((b) => _BreakdownTile(
                name: b.name,
                right: b.qty != null
                    ? '${b.qty!.toStringAsFixed(0)} وحدة'
                    : '${b.count}',
                amount: _money(b.total))),
            if (r.byCategory.isEmpty) const _None(),
            const SizedBox(height: 14),
            _SectionTitle('حسب نقطة البيع'),
            const SizedBox(height: 8),
            ...r.byPos.map((b) => _BreakdownTile(
                name: b.name,
                right: '${b.count} عملية',
                amount: _money(b.total))),
            if (r.byPos.isEmpty) const _None(),
            const SizedBox(height: 14),
            _SectionTitle('حسب الموزع'),
            const SizedBox(height: 8),
            ...r.byDistributor.map((b) => _BreakdownTile(
                name: b.name,
                right: b.commission != null && b.commission! > 0
                    ? 'عمولة ${_money(b.commission!)}'
                    : '${b.count} عملية',
                amount: _money(b.total))),
            if (r.byDistributor.isEmpty) const _None(),
          ],
        ),
      ),
    );
  }
}

/// The match contract surfaced on screen: documents total vs the
/// revenue credited in the journal for the same window.
class _JournalCheck extends StatelessWidget {
  final double docsTotal;
  final double journalTotal;
  final int count;
  const _JournalCheck({
    required this.docsTotal,
    required this.journalTotal,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    final matches = (docsTotal - journalTotal).abs() < 0.01;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: (matches ? AppColors.success : AppColors.warning)
            .withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (matches ? AppColors.success : AppColors.warning)
              .withValues(alpha: 0.3),
        ),
      ),
      child: Row(children: [
        Icon(
          matches ? Icons.verified_outlined : Icons.info_outline,
          size: 18,
          color: matches ? AppColors.success : AppColors.warning,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            matches
                ? 'مطابق للقيود — إيراد مرحّل ${_money(journalTotal)}'
                : 'المستندات ${_money(docsTotal)} · القيود ${_money(journalTotal)} (تشمل طلبات النقاط والتطبيق)',
            style: TextStyle(
              fontSize: 11,
              color:
                  matches ? AppColors.success : AppColors.textDark,
            ),
          ),
        ),
      ]),
    );
  }
}

class _BreakdownTile extends StatelessWidget {
  final String name;
  final String right;
  final String amount;
  const _BreakdownTile(
      {required this.name, required this.right, required this.amount});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        dense: true,
        title: Text(name,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppColors.textDark)),
        subtitle: Text(right,
            style: const TextStyle(
                fontSize: 11, color: AppColors.textGray)),
        trailing: Text(amount,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppColors.primary)),
      ),
    );
  }
}

class _None extends StatelessWidget {
  const _None();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Text('لا بيانات لهذه الفترة',
          style: TextStyle(fontSize: 12, color: AppColors.textGray)),
    );
  }
}

// ── العمولات ───────────────────────────────────────────────────

class _CommissionsTab extends ConsumerWidget {
  const _CommissionsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(accCommissionsProvider);

    return reportAsync.when(
      loading: () => const LoadingState(),
      error: (e, _) => ErrorRetry(
        message: 'تعذّر تحميل العمولات\n$e',
        onRetry: () => ref.invalidate(accCommissionsProvider),
      ),
      data: (r) => RefreshIndicator(
        onRefresh: () async => ref.invalidate(accCommissionsProvider),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(children: [
              Expanded(
                child: _MiniStat(
                  label: 'مبيعات الموزعين',
                  value: _money(r.totalSales),
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniStat(
                  label: 'عمولات مستحقة',
                  value: _money(r.accrued),
                  color: AppColors.warning,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniStat(
                  label: 'عمولات مدفوعة',
                  value: _money(r.paid),
                  color: AppColors.success,
                ),
              ),
            ]),
            const SizedBox(height: 14),
            _SectionTitle('حسب الموزع'),
            const SizedBox(height: 8),
            ...r.byDistributor.map((d) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor:
                          AppColors.primary.withValues(alpha: 0.1),
                      child: Text(
                        d.name.isEmpty ? '؟' : d.name.substring(0, 1),
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.primary),
                      ),
                    ),
                    title: Text(d.name,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textDark)),
                    subtitle: Text(
                      'مبيعات ${_money(d.sales)}'
                      '${(d.commission - d.journalNet).abs() < 0.01 ? ' · مطابق للقيود' : ''}',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textGray),
                    ),
                    trailing: Text(_money(d.commission),
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary)),
                  ),
                )),
            if (r.byDistributor.isEmpty)
              const EmptyState('لا عمولات بعد',
                  icon: Icons.percent_outlined),
            const SizedBox(height: 14),
            if (r.rows.isNotEmpty) _SectionTitle('الفترات'),
            const SizedBox(height: 8),
            ...r.rows.map((c) => _BreakdownTile(
                  name: c.distributorName ?? 'موزع',
                  right:
                      '${c.period} · ${c.status == 'paid' ? 'مدفوعة' : 'مستحقة'}',
                  amount: _money(c.commission),
                )),
          ],
        ),
      ),
    );
  }
}

// ── Shared bits ────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: AppColors.textDark));
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _MiniStat(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
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
                  fontSize: 15)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  color: AppColors.textGray, fontSize: 10)),
        ],
      ),
    );
  }
}

String _money(double v) {
  return v == v.roundToDouble()
      ? v.toStringAsFixed(0)
      : v.toStringAsFixed(2);
}
