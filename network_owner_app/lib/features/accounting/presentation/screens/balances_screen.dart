import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../mikrotik/presentation/widgets/ui_states.dart';
import '../../data/loyalty_api.dart';
import '../../providers/loyalty_providers.dart';

/// ACC-10 — party balances + the withdrawal review queue
/// (PLAN §4: balances_screen — «أرصدة العملاء/الموزعين + سحب»).
/// Tab 1 lists every party's journal balance (POS rows also carry
/// their points/profit wallets); tab 2 walks pending withdrawal
/// requests through approve → paid | reject.
class BalancesScreen extends ConsumerStatefulWidget {
  const BalancesScreen({super.key});

  @override
  ConsumerState<BalancesScreen> createState() => _BalancesScreenState();
}

class _BalancesScreenState extends ConsumerState<BalancesScreen> {
  String? _partyFilter;

  static const _filters = {
    null: 'الكل',
    'pos': 'نقاط البيع',
    'distributor': 'الموزعون',
    'customer': 'العملاء',
    'box': 'الصناديق',
    'supplier': 'الموردون',
  };

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الأرصدة والسحوبات'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'أرصدة الأطراف'),
              Tab(text: 'طلبات السحب'),
            ],
          ),
        ),
        body: Container(
          color: AppColors.inputBg,
          child: TabBarView(
            children: [
              _BalancesTab(
                filter: _partyFilter,
                filters: _filters,
                onFilter: (v) => setState(() => _partyFilter = v),
              ),
              const _WithdrawalsTab(),
            ],
          ),
        ),
      ),
    );
  }
}

class _BalancesTab extends ConsumerWidget {
  final String? filter;
  final Map<String?, String> filters;
  final ValueChanged<String?> onFilter;
  const _BalancesTab({
    required this.filter,
    required this.filters,
    required this.onFilter,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rowsAsync = ref.watch(accBalancesProvider(filter));

    return RefreshIndicator(
      onRefresh: () async =>
          ref.invalidate(accBalancesProvider(filter)),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: filters.entries
                  .map((e) => Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: ChoiceChip(
                          label: Text(e.value,
                              style: const TextStyle(fontSize: 11)),
                          selected: filter == e.key,
                          onSelected: (_) => onFilter(e.key),
                        ),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 10),
          rowsAsync.when(
            loading: () => const LoadingState(),
            error: (e, _) => ErrorRetry(
              message: 'تعذّر تحميل الأرصدة\n$e',
              onRetry: () =>
                  ref.invalidate(accBalancesProvider(filter)),
            ),
            data: (rows) => rows.isEmpty
                ? const EmptyState('لا توجد أرصدة بعد',
                    icon: Icons.account_balance_outlined)
                : Column(
                    children: rows
                        .map((r) => _BalanceCard(row: r))
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  final AccBalanceRow row;
  const _BalanceCard({required this.row});

  @override
  Widget build(BuildContext context) {
    final positive = row.balance >= 0;
    final color = row.isAssetSide
        ? AppColors.primary
        : positive
            ? AppColors.warning
            : AppColors.success;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
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
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              row.isAssetSide
                  ? Icons.account_balance_wallet_outlined
                  : Icons.person_outline,
              color: color,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.partyName,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: AppColors.textDark)),
                const SizedBox(height: 2),
                Text(row.partyLabel,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textGray)),
                if (row.pointsBalance != null ||
                    row.profitBalance != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'نقاط: ${(row.pointsBalance ?? 0).toStringAsFixed(0)}'
                      ' — أرباح: ${(row.profitBalance ?? 0).toStringAsFixed(0)}',
                      style: const TextStyle(
                          fontSize: 10, color: AppColors.textGray),
                    ),
                  ),
              ],
            ),
          ),
          Text(
            row.balance.toStringAsFixed(0),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _WithdrawalsTab extends ConsumerWidget {
  const _WithdrawalsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rowsAsync = ref.watch(accWithdrawalsProvider(null));

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(accWithdrawalsProvider(null)),
      child: rowsAsync.when(
        loading: () => const LoadingState(),
        error: (e, _) => ErrorRetry(
          message: 'تعذّر تحميل طلبات السحب\n$e',
          onRetry: () => ref.invalidate(accWithdrawalsProvider(null)),
        ),
        data: (rows) => rows.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 120),
                  EmptyState('لا توجد طلبات سحب',
                      icon: Icons.payments_outlined),
                ],
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: rows.length,
                itemBuilder: (_, i) => _WithdrawalCard(row: rows[i]),
              ),
      ),
    );
  }
}

class _WithdrawalCard extends ConsumerWidget {
  final AccWithdrawalRow row;
  const _WithdrawalCard({required this.row});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusColor = row.isPaid
        ? AppColors.success
        : row.isPending
            ? AppColors.warning
            : row.isApproved
                ? AppColors.primary
                : AppColors.textGray;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  row.requesterName.isEmpty
                      ? '${row.requesterType} #${row.id}'
                      : row.requesterName,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: AppColors.textDark),
                ),
              ),
              Text(row.amount.toStringAsFixed(0),
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(row.statusLabel,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: statusColor)),
              ),
              const SizedBox(width: 8),
              if (row.receiverName != null)
                Expanded(
                  child: Text('المستلم: ${row.receiverName}',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textGray)),
                ),
            ],
          ),
          if (row.isPending || row.isApproved) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (row.isPending)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _decide(context, ref, 'approve'),
                      child: const Text('اعتماد'),
                    ),
                  ),
                if (row.isPending) const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: () => _decide(context, ref, 'paid'),
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.success),
                    child: const Text('صرف'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _decide(context, ref, 'reject'),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error),
                    child: const Text('رفض'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _decide(
      BuildContext context, WidgetRef ref, String action) async {
    final api = ref.read(loyaltyApiProvider);
    try {
      final msg = switch (action) {
        'approve' => await api.approveWithdrawal(row.id),
        'paid' => await api.payWithdrawal(row.id, {
            'receiver_name': row.receiverName,
          }),
        _ => await api.rejectWithdrawal(row.id),
      };
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
      ref.invalidate(accWithdrawalsProvider(null));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }
}
