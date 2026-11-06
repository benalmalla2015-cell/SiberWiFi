import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../mikrotik/presentation/widgets/ui_states.dart';
import '../../data/dist_api.dart';
import '../../providers/dist_providers.dart';

/// ACC-06 — the distributor's own period report + commission ledger.
///
/// Both tabs read backend aggregates scoped to the acting agent
/// (sales scope applies to distributors automatically).
class DistReportScreen extends ConsumerStatefulWidget {
  const DistReportScreen({super.key});

  @override
  ConsumerState<DistReportScreen> createState() =>
      _DistReportScreenState();
}

class _DistReportScreenState extends ConsumerState<DistReportScreen> {
  ({String? from, String? to}) _range = (from: null, to: null);

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('تقريري وعمولاتي'),
          bottom: const TabBar(
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textGray,
            indicatorColor: AppColors.primary,
            tabs: [
              Tab(text: 'التقرير'),
              Tab(text: 'العمولات'),
            ],
          ),
        ),
        body: Container(
          color: AppColors.inputBg,
          child: TabBarView(
            children: [
              _ReportTab(range: _range, onPick: _pickRange),
              const _CommissionsTab(),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange: DateTimeRange(
        start: _range.from != null
            ? DateTime.parse(_range.from!)
            : DateTime(now.year, now.month, 1),
        end: _range.to != null ? DateTime.parse(_range.to!) : now,
      ),
    );
    if (picked != null) {
      setState(() => _range = (
            from: _d(picked.start),
            to: _d(picked.end),
          ));
    }
  }

  static String _d(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class _ReportTab extends ConsumerWidget {
  final ({String? from, String? to}) range;
  final VoidCallback onPick;
  const _ReportTab({required this.range, required this.onPick});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(distReportProvider(range));

    return reportAsync.when(
      loading: () => const LoadingState(),
      error: (e, _) => ErrorRetry(
        message: 'تعذّر تحميل التقرير\n$e',
        onRetry: () => ref.invalidate(distReportProvider(range)),
      ),
      data: (report) => RefreshIndicator(
        onRefresh: () async => ref.invalidate(distReportProvider(range)),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            InkWell(
              onTap: onPick,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.date_range_outlined,
                        size: 18, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${report.from} → ${report.to}',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textDark),
                      ),
                    ),
                    const Icon(Icons.edit_calendar_outlined,
                        size: 16, color: AppColors.textGray),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _TotalsGrid(totals: report.totals),
            const SizedBox(height: 16),
            _section('يوماً بيوم', Icons.calendar_view_day_outlined),
            const SizedBox(height: 8),
            if (report.daily.isEmpty)
              const _Hint('لا توجد مبيعات في الفترة')
            else
              ...report.daily.map((d) => _DayRow(day: d)),
            const SizedBox(height: 16),
            _section('حسب الفئة', Icons.style_outlined),
            const SizedBox(height: 8),
            if (report.categories.isEmpty)
              const _Hint('لا توجد مبيعات في الفترة')
            else
              ...report.categories.map((c) => _CatRow(cat: c)),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, IconData icon) => Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(title,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark)),
        ],
      );
}

class _TotalsGrid extends StatelessWidget {
  final DistReportTotals totals;
  const _TotalsGrid({required this.totals});

  @override
  Widget build(BuildContext context) {
    final cells = [
      ('عدد المبيعات', '${totals.salesCount}', Icons.point_of_sale_outlined,
          AppColors.primary),
      ('إجمالي المبيعات', _n(totals.salesTotal), Icons.receipt_long_outlined,
          AppColors.primary),
      ('نقدي', _n(totals.cashTotal), Icons.payments_outlined,
          AppColors.success),
      ('آجل', _n(totals.creditTotal), Icons.schedule_outlined,
          AppColors.warning),
      ('تحصيلات', _n(totals.collectionsTotal), Icons.south_west,
          AppColors.lightBlue),
      ('ديون مفتوحة', '${totals.openDebtsCount} · ${_n(totals.openDebtsRemaining)}',
          Icons.handshake_outlined, AppColors.error),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.1,
      children: cells
          .map((c) => Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(c.$3, size: 20, color: c.$4),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(c.$2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: c.$4)),
                          Text(c.$1,
                              style: const TextStyle(
                                  fontSize: 10,
                                  color: AppColors.textGray)),
                        ],
                      ),
                    ),
                  ],
                ),
              ))
          .toList(),
    );
  }

  static String _n(double v) => v.toStringAsFixed(0);
}

class _DayRow extends StatelessWidget {
  final DistReportDay day;
  const _DayRow({required this.day});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListTile(
        dense: true,
        title: Text(day.date,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppColors.textDark)),
        subtitle: Text(
          '${day.count} عملية · نقدي ${day.cash.toStringAsFixed(0)} · آجل ${day.credit.toStringAsFixed(0)}',
          style: const TextStyle(fontSize: 11, color: AppColors.textGray),
        ),
        trailing: Text(
          day.total.toStringAsFixed(0),
          style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.primary),
        ),
      ),
    );
  }
}

class _CatRow extends StatelessWidget {
  final DistReportCategory cat;
  const _CatRow({required this.cat});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListTile(
        dense: true,
        title: Text(cat.categoryName,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppColors.textDark)),
        subtitle: Text('كمية ${cat.qty.toStringAsFixed(0)}',
            style: const TextStyle(
                fontSize: 11, color: AppColors.textGray)),
        trailing: Text(
          cat.amount.toStringAsFixed(0),
          style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.primary),
        ),
      ),
    );
  }
}

class _CommissionsTab extends ConsumerWidget {
  const _CommissionsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(distCommissionsProvider(null));

    return listAsync.when(
      loading: () => const LoadingState(),
      error: (e, _) => ErrorRetry(
        message: 'تعذّر تحميل العمولات\n$e',
        onRetry: () => ref.invalidate(distCommissionsProvider(null)),
      ),
      data: (items) => items.isEmpty
          ? const EmptyState('لا توجد عمولات بعد',
              icon: Icons.percent_outlined)
          : RefreshIndicator(
              onRefresh: () async =>
                  ref.invalidate(distCommissionsProvider(null)),
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                itemBuilder: (_, i) => _CommissionCard(item: items[i]),
              ),
            ),
    );
  }
}

class _CommissionCard extends StatelessWidget {
  final DistCommission item;
  const _CommissionCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final color = item.isPaid ? AppColors.success : AppColors.warning;
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
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            item.isPaid
                ? Icons.check_circle_outline
                : Icons.hourglass_bottom_outlined,
            color: color,
            size: 22,
          ),
        ),
        title: Text(
          'عمولة ${item.period}',
          style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: AppColors.textDark),
        ),
        subtitle: Text(
          'مبيعات ${item.salesAmount.toStringAsFixed(0)}'
          '${item.distributorName != null ? ' · ${item.distributorName}' : ''}',
          style: const TextStyle(fontSize: 11, color: AppColors.textGray),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              item.commissionAmount.toStringAsFixed(0),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              item.statusLabel,
              style: const TextStyle(
                  fontSize: 10, color: AppColors.textGray),
            ),
          ],
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  final String text;
  const _Hint(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12, color: AppColors.textGray),
      ),
    );
  }
}
