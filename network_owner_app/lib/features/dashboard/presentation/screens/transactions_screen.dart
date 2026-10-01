import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/api/api_client.dart';
import '../../../../core/cache/hive_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/connectivity_service.dart';
import '../../../../core/utils/json_helpers.dart';

class TransactionsState {
  final List<Map<String, dynamic>> items;
  final int currentPage;
  final int lastPage;
  final bool isLoading;
  final String? error;
  final String search;

  const TransactionsState({
    this.items = const [],
    this.currentPage = 0,
    this.lastPage = 1,
    this.isLoading = false,
    this.error,
    this.search = '',
  });

  bool get canLoadMore => currentPage < lastPage;

  bool get isSearchActive => search.trim().isNotEmpty;

  TransactionsState copyWith({
    List<Map<String, dynamic>>? items,
    int? currentPage,
    int? lastPage,
    bool? isLoading,
    String? error,
    String? search,
  }) {
    return TransactionsState(
      items: items ?? this.items,
      currentPage: currentPage ?? this.currentPage,
      lastPage: lastPage ?? this.lastPage,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      search: search ?? this.search,
    );
  }
}

class TransactionsNotifier extends StateNotifier<TransactionsState> {
  final Ref _ref;

  TransactionsNotifier(this._ref) : super(const TransactionsState()) {
    refresh();
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, error: null);
    await _loadPage(1, replace: true);
  }

  Future<void> loadMore() async {
    if (state.isLoading || !state.canLoadMore) return;
    state = state.copyWith(isLoading: true, error: null);
    await _loadPage(state.currentPage + 1);
  }

  Future<void> setSearch(String query) async {
    if (state.search == query) return;
    state = TransactionsState(search: query, isLoading: true);
    await _loadPage(1, replace: true);
  }

  Future<void> _loadPage(int page, {bool replace = false}) async {
    final isOnline = await ConnectivityService.isConnected();
    if (!isOnline) {
      if (page == 1) {
        final cached = HiveService.transactionsBox.get('list');
        var data = cached != null
            ? toMapList(cached)
            : <Map<String, dynamic>>[];
        final query = state.search.trim().toLowerCase();
        if (query.isNotEmpty) {
          data = data.where((item) {
            return item.values.any(
              (value) =>
                  value?.toString().toLowerCase().contains(query) == true,
            );
          }).toList();
        }
        state = TransactionsState(
          items: data,
          currentPage: 1,
          lastPage: 1,
          search: state.search,
        );
        return;
      }
      state = state.copyWith(
        isLoading: false,
        error: 'لا يوجد اتصال بالإنترنت',
      );
      return;
    }

    try {
      final params = <String, dynamic>{'page': page};
      if (state.search.trim().isNotEmpty) {
        params['search'] = state.search.trim();
      }
      final response = await _ref
          .read(apiClientProvider)
          .get('/network-owner/transactions', params: params);
      final data = List<Map<String, dynamic>>.from(response.data['data'] ?? []);
      final meta = Map<String, dynamic>.from(response.data['meta'] ?? {});
      final newItems = replace ? data : [...state.items, ...data];
      if (state.search.trim().isEmpty) {
        await HiveService.transactionsBox.put('list', newItems);
      }
      state = TransactionsState(
        items: newItems,
        currentPage: meta['current_page'] as int? ?? page,
        lastPage: meta['last_page'] as int? ?? page,
        search: state.search,
      );
    } catch (error) {
      if (page == 1 && state.search.trim().isEmpty) {
        final cached = HiveService.transactionsBox.get('list');
        final data = cached != null
            ? toMapList(cached)
            : <Map<String, dynamic>>[];
        state = TransactionsState(
          items: data,
          currentPage: 1,
          lastPage: 1,
          search: state.search,
          error: 'تعذر تحميل المعاملات: ${error.toString()}',
        );
        return;
      }
      state = state.copyWith(isLoading: false, error: error.toString());
    }
  }
}

final transactionsProvider =
    StateNotifierProvider<TransactionsNotifier, TransactionsState>(
      (ref) => TransactionsNotifier(ref),
    );

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _debounceTimer;
  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    _syncTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted && _searchCtrl.text.trim().isEmpty) {
        ref.read(transactionsProvider.notifier).refresh();
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounceTimer?.cancel();
    _syncTimer?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      ref.read(transactionsProvider.notifier).setSearch(query);
    });
  }

  void _clearSearch() {
    _searchCtrl.clear();
    _debounceTimer?.cancel();
    ref.read(transactionsProvider.notifier).setSearch('');
  }

  @override
  Widget build(BuildContext context) {
    final transactions = ref.watch(transactionsProvider);
    final notifier = ref.read(transactionsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('كل المعاملات')),
      body: RefreshIndicator(
        onRefresh: notifier.refresh,
        child: _TransactionsBody(
          transactions: transactions,
          onLoadMore: notifier.loadMore,
          searchCtrl: _searchCtrl,
          onSearchChanged: _onSearchChanged,
          onClearSearch: _clearSearch,
        ),
      ),
    );
  }
}

class _TransactionsBody extends StatelessWidget {
  final TransactionsState transactions;
  final Future<void> Function() onLoadMore;
  final TextEditingController searchCtrl;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;

  const _TransactionsBody({
    required this.transactions,
    required this.onLoadMore,
    required this.searchCtrl,
    required this.onSearchChanged,
    required this.onClearSearch,
  });

  @override
  Widget build(BuildContext context) {
    if (transactions.isLoading && transactions.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (transactions.error != null && transactions.items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _SearchHeader(
            searchCtrl: searchCtrl,
            onSearchChanged: onSearchChanged,
            onClearSearch: onClearSearch,
          ),
          const SizedBox(height: 180),
          Center(child: Text('تعذر تحميل المعاملات: ${transactions.error}')),
        ],
      );
    }

    if (transactions.items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _SearchHeader(
            searchCtrl: searchCtrl,
            onSearchChanged: onSearchChanged,
            onClearSearch: onClearSearch,
          ),
          const SizedBox(height: 160),
          const Icon(
            Icons.receipt_long_outlined,
            size: 64,
            color: AppColors.divider,
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              transactions.isSearchActive
                  ? 'لا توجد نتائج مطابقة'
                  : 'لا توجد معاملات حتى الآن',
              style: const TextStyle(color: AppColors.textGray),
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount:
          transactions.items.length +
          (transactions.canLoadMore || transactions.isLoading ? 1 : 0) +
          1,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, index) {
        if (index == 0) {
          return _SearchHeader(
            searchCtrl: searchCtrl,
            onSearchChanged: onSearchChanged,
            onClearSearch: onClearSearch,
          );
        }
        final itemIndex = index - 1;
        if (itemIndex < transactions.items.length) {
          return _TransactionCard(transaction: transactions.items[itemIndex]);
        }
        return Center(
          child: transactions.isLoading
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                )
              : OutlinedButton(
                  onPressed: onLoadMore,
                  child: const Text('تحميل المزيد'),
                ),
        );
      },
    );
  }
}

class _SearchHeader extends StatelessWidget {
  final TextEditingController searchCtrl;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;

  const _SearchHeader({
    required this.searchCtrl,
    required this.onSearchChanged,
    required this.onClearSearch,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: TextField(
        controller: searchCtrl,
        onChanged: onSearchChanged,
        textAlignVertical: TextAlignVertical.center,
        decoration: InputDecoration(
          filled: true,
          fillColor: AppColors.inputBg,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          hintText: 'ابحث برقم العملية أو اسم العميل',
          hintStyle: const TextStyle(color: AppColors.textLight, fontSize: 13),
          prefixIcon: const Icon(
            Icons.search,
            color: AppColors.textGray,
            size: 22,
          ),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: searchCtrl,
            builder: (context, value, _) {
              if (value.text.isEmpty) return const SizedBox.shrink();
              return IconButton(
                onPressed: onClearSearch,
                icon: const Icon(
                  Icons.clear,
                  color: AppColors.textGray,
                  size: 18,
                ),
                splashRadius: 18,
              );
            },
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: const BorderSide(color: AppColors.divider),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: const BorderSide(color: AppColors.divider, width: 1.2),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
          ),
        ),
      ),
    );
  }
}

class _TransactionCard extends StatelessWidget {
  final Map<String, dynamic> transaction;

  const _TransactionCard({required this.transaction});

  @override
  Widget build(BuildContext context) {
    final ownerAmount = _asDouble(transaction['owner_amount']);
    final price = _asDouble(transaction['price']);
    final commission = _asDouble(transaction['commission_amount']);
    final timestamp = transaction['created_at']?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.credit_card, color: AppColors.success),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      transaction['category_name']?.toString() ?? 'بطاقة',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      transaction['network_name']?.toString() ?? '',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.primary,
                      ),
                    ),
                    Text(
                      'العميل: ${transaction['client_name']?.toString() ?? '—'}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textGray,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '+${ownerAmount.toStringAsFixed(0)} ر',
                    style: const TextStyle(
                      color: AppColors.success,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    timestamp.length >= 16
                        ? timestamp.substring(0, 16)
                        : timestamp,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textGray,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: AppColors.divider),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _CopyableDetail(
                label: 'رقم العملية',
                value: transaction['transaction_number']?.toString() ?? '—',
              ),
              _Detail(
                label: 'سعر البيع',
                value: '${price.toStringAsFixed(0)} ر',
              ),
              _Detail(
                label: 'العمولة',
                value: '${commission.toStringAsFixed(0)} ر',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  final String label;
  final String value;

  const _Detail({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: AppColors.textGray),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _CopyableDetail extends StatelessWidget {
  final String label;
  final String value;

  const _CopyableDetail({required this.label, required this.value});

  Future<void> _copy(BuildContext context) async {
    if (value == '—') return;
    await Clipboard.setData(ClipboardData(text: value));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم نسخ رقم العملية'),
          duration: Duration(seconds: 2),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: AppColors.textGray),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () => _copy(context),
              child: const Icon(
                Icons.copy,
                size: 14,
                color: AppColors.textGray,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

double _asDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}
