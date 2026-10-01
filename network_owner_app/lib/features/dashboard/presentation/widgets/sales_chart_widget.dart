import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/dashboard_provider.dart';

class SalesChartWidget extends ConsumerWidget {
  const SalesChartWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period    = ref.watch(selectedPeriodProvider);
    final statsAsync = ref.watch(statsDataProvider);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('إحصائيات المبيعات', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                _PeriodSelector(current: period, onChanged: (p) => ref.read(selectedPeriodProvider.notifier).state = p),
              ],
            ),
            const SizedBox(height: 20),
            statsAsync.when(
              loading: () => const SizedBox(height: 180, child: Center(child: CircularProgressIndicator())),
              error:   (e, _) => const SizedBox(height: 180, child: Center(child: Text('تعذّر تحميل البيانات'))),
              data:    (stats) => _buildChart(stats, period),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChart(Map<String, dynamic> stats, String period) {
    final chartData = stats['chart_data'];
    final rawData = chartData is List ? chartData : const [];
    final rawLabels = chartData is Map ? List<dynamic>.from(chartData['labels'] ?? const []) : const <dynamic>[];
    final rawValues = chartData is Map ? List<dynamic>.from(chartData['values'] ?? const []) : const <dynamic>[];
    final totalSales = _asDouble(stats['total_sales'] ?? stats['total_earnings']);
    final totalTxns = stats['total_transactions'] ?? stats['total_cards'] ?? 0;

    final spots = <FlSpot>[];
    final labels = <String>[];

    if (rawValues.isNotEmpty) {
      for (int i = 0; i < rawValues.length; i++) {
        spots.add(FlSpot(i.toDouble(), _asDouble(rawValues[i])));
        labels.add(i < rawLabels.length ? rawLabels[i].toString() : (i + 1).toString());
      }
    } else {
      for (int i = 0; i < rawData.length; i++) {
        final item = rawData[i];
        if (item is! Map) continue;
        spots.add(FlSpot(i.toDouble(), _asDouble(item['total'] ?? item['amount'])));
        labels.add(item['label']?.toString() ?? (i + 1).toString());
      }
    }

    if (spots.isEmpty) {
      return const SizedBox(
        height: 180,
        child: Center(child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [Icon(Icons.bar_chart, size: 48, color: AppColors.divider), SizedBox(height: 8), Text('لا توجد بيانات', style: TextStyle(color: AppColors.textGray))],
        )),
      );
    }

    final highestValue = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final maxY = highestValue > 0 ? highestValue * 1.2 : 1.0;

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _MiniStat(label: 'إجمالي المبيعات', value: '${totalSales.toStringAsFixed(0)} ر', color: AppColors.success)),
            const SizedBox(width: 12),
            Expanded(child: _MiniStat(label: 'عدد المعاملات', value: '$totalTxns', color: AppColors.lightBlue)),
          ],
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 160,
          child: LineChart(
            LineChartData(
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => const FlLine(color: AppColors.divider, strokeWidth: 1),
              ),
              titlesData: FlTitlesData(
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: labels.length > 10 ? 2 : 1,
                    getTitlesWidget: (val, meta) {
                      final i = val.toInt();
                      if (i < 0 || i >= labels.length) return const SizedBox();
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(labels[i], style: const TextStyle(fontSize: 9, color: AppColors.textGray)),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    getTitlesWidget: (val, meta) => Text(
                      val >= 1000 ? '${(val / 1000).toStringAsFixed(0)}K' : val.toStringAsFixed(0),
                      style: const TextStyle(fontSize: 9, color: AppColors.textGray),
                    ),
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              minX: 0,
              maxX: (spots.length - 1).toDouble(),
              minY: 0,
              maxY: maxY,
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  color: AppColors.primary,
                  barWidth: 3,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                      radius: 3,
                      color: AppColors.primary,
                      strokeWidth: 2,
                      strokeColor: Colors.white,
                    ),
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      colors: [AppColors.primary.withValues(alpha: 0.2), AppColors.primary.withValues(alpha: 0.0)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }
}

class _MiniStat extends StatelessWidget {
  final String label, value;
  final Color color;
  const _MiniStat({required this.label, required this.value, required this.color});

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
          Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: AppColors.textGray, fontSize: 11)),
        ],
      ),
    );
  }
}

class _PeriodSelector extends StatelessWidget {
  final String current;
  final ValueChanged<String> onChanged;
  const _PeriodSelector({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.inputBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Tab(label: 'أسبوع', value: 'week',  current: current, onTap: onChanged),
          _Tab(label: 'شهر',   value: 'month', current: current, onTap: onChanged),
          _Tab(label: 'سنة',   value: 'year',  current: current, onTap: onChanged),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final String label, value, current;
  final ValueChanged<String> onTap;
  const _Tab({required this.label, required this.value, required this.current, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final selected = value == current;
    return GestureDetector(
      onTap: () => onTap(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.textGray,
            fontSize: 11,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
