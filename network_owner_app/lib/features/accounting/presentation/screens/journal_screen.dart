import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../mikrotik/presentation/widgets/ui_states.dart';
import '../../data/reports_api.dart';
import '../../providers/reports_providers.dart';

/// ACC-09 — القيود اليومية (PLAN §5: journal_screen).
///
/// The immutable document cycle: each row is a posted entry —
/// corrections appear as reversal entries, never edits. The
/// totals strip shows Σمدين = Σدائن for the current filter, and
/// tapping an entry opens its resolved legs.
class JournalScreen extends ConsumerStatefulWidget {
  const JournalScreen({super.key});

  @override
  ConsumerState<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends ConsumerState<JournalScreen> {
  String? _docType;

  static const _filters = <String?, String>{
    null: 'الكل',
    'sale': 'مبيعات',
    'pos_sale': 'بيع نقطة',
    'collection': 'تحصيلات',
    'expense': 'مصروفات',
    'purchase': 'مشتريات',
    'transfer': 'تحويلات',
    'adjustment': 'تسويات',
    'withdrawal': 'سحوبات',
  };

  @override
  Widget build(BuildContext context) {
    final key = (docType: _docType, from: null, to: null);
    final journalAsync = ref.watch(accJournalProvider(key));

    return Scaffold(
      appBar: AppBar(title: const Text('القيود اليومية')),
      body: Container(
        color: AppColors.inputBg,
        child: Column(
          children: [
            Container(
              color: AppColors.white,
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _filters.entries.map((e) {
                    final selected = e.key == _docType;
                    return Padding(
                      padding:
                          const EdgeInsetsDirectional.only(end: 8),
                      child: ChoiceChip(
                        label: Text(e.value),
                        selected: selected,
                        onSelected: (_) =>
                            setState(() => _docType = e.key),
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
            ),
            journalAsync.when(
              loading: () => const Expanded(child: LoadingState()),
              error: (e, _) => Expanded(
                child: ErrorRetry(
                  message: 'تعذّر تحميل القيود\n$e',
                  onRetry: () =>
                      ref.invalidate(accJournalProvider(key)),
                ),
              ),
              data: (j) => Expanded(
                child: Column(
                  children: [
                    _TotalsStrip(debit: j.debit, credit: j.credit),
                    Expanded(
                      child: j.entries.isEmpty
                          ? const EmptyState('لا قيود بعد',
                              icon: Icons.receipt_long_outlined)
                          : RefreshIndicator(
                              onRefresh: () async => ref
                                  .invalidate(accJournalProvider(key)),
                              child: ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: j.entries.length,
                                itemBuilder: (_, i) => _EntryTile(
                                    entry: j.entries[i]),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalsStrip extends StatelessWidget {
  final double debit;
  final double credit;
  const _TotalsStrip({required this.debit, required this.credit});

  @override
  Widget build(BuildContext context) {
    final balanced = (debit - credit).abs() < 0.01;
    return Container(
      color: AppColors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(children: [
        Icon(
          balanced ? Icons.balance_outlined : Icons.warning_amber,
          size: 16,
          color: balanced ? AppColors.success : AppColors.warning,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'مدين ${_fmt(debit)} · دائن ${_fmt(credit)}'
            '${balanced ? ' — متوازن' : ' — غير متوازن'}',
            style: const TextStyle(
                fontSize: 11, color: AppColors.textGray),
          ),
        ),
      ]),
    );
  }
}

class _EntryTile extends ConsumerWidget {
  final AccJournalEntryRow entry;
  const _EntryTile({required this.entry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        onTap: () => _showDetail(context, ref),
        title: Text(entry.entryNo,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.textDark)),
        subtitle: Text(
          '${entry.docLabel} · ${entry.date}'
          '${entry.memo != null ? '\n${entry.memo}' : ''}',
          style: const TextStyle(
              fontSize: 11, color: AppColors.textGray),
          maxLines: 2,
        ),
        trailing: entry.isReversal
            ? const Icon(Icons.replay, size: 16, color: AppColors.warning)
            : const Icon(Icons.chevron_left,
                size: 18, color: AppColors.textGray),
      ),
    );
  }

  void _showDetail(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Consumer(
        builder: (context, ref, _) {
          final detailAsync = ref.watch(accJournalEntryProvider(entry.id));
          return Padding(
            padding: const EdgeInsets.all(20),
            child: detailAsync.when(
              loading: () => const SizedBox(
                height: 160,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => SizedBox(
                height: 160,
                child: Center(child: Text('تعذّر التحميل: $e')),
              ),
              data: (d) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(d.entry.entryNo,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary)),
                  const SizedBox(height: 4),
                  Text(
                    '${d.entry.docLabel} · ${d.entry.date}'
                    '${d.entry.memo != null ? ' · ${d.entry.memo}' : ''}',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textGray),
                  ),
                  const SizedBox(height: 14),
                  ...d.lines.map((l) => Padding(
                        padding:
                            const EdgeInsets.symmetric(vertical: 5),
                        child: Row(children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${l.accountCode} · ${l.accountName}',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.textDark),
                                ),
                                if (l.partyName != null)
                                  Text(l.partyName!,
                                      style: const TextStyle(
                                          fontSize: 10,
                                          color: AppColors.textGray)),
                              ],
                            ),
                          ),
                          if (l.debit > 0)
                            Text('مدين ${_fmt(l.debit)}',
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.success)),
                          if (l.credit > 0)
                            Text('دائن ${_fmt(l.credit)}',
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.error)),
                        ]),
                      )),
                  const SizedBox(height: 10),
                  const Divider(),
                  Row(children: [
                    const Expanded(
                      child: Text('الإجمالي',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textDark)),
                    ),
                    Text(
                      _fmt(d.lines
                          .fold(0.0, (a, l) => a + l.debit)),
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary),
                    ),
                  ]),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

String _fmt(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
