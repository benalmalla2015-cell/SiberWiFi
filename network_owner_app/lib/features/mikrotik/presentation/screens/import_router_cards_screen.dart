import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../networks/data/networks_repository.dart';
import '../../../networks/presentation/providers/networks_provider.dart';
import '../../data/router_model.dart';
import '../providers/mikrotik_provider.dart';

/// Imports existing router hotspot users as platform cards.
/// Backend uses insertOrIgnore so re-importing the same code is a no-op
/// — imported codes never create duplicate revenue.
class ImportRouterCardsScreen extends ConsumerStatefulWidget {
  final MikrotikRouterConfig router;
  const ImportRouterCardsScreen({super.key, required this.router});

  @override
  ConsumerState<ImportRouterCardsScreen> createState() =>
      _ImportRouterCardsScreenState();
}

class _ImportRouterCardsScreenState
    extends ConsumerState<ImportRouterCardsScreen> {
  final Set<String> _selected = {};
  int? _networkId;
  int? _categoryId;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    // networksProvider/categoriesProvider are not autoDispose — a stale
    // empty result (e.g. cached before the owner had a network) must not
    // leave the dropdowns dead. Always refetch when the screen opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.invalidate(networksProvider);
      ref.invalidate(categoriesProvider);
    });
  }

  Future<void> _import(List<Map<String, String>> users) async {
    if (_selected.isEmpty) return;
    if (_networkId == null || _categoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('اختر الشبكة والفئة أولاً'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    setState(() => _importing = true);
    try {
      final repo = ref.read(networksRepositoryProvider);
      final items = users
          .where((u) => _selected.contains(u['name']))
          .map((u) => {
                'code': u['name']!,
                'meta': {
                  'profile': u['profile'] ?? 'default',
                  'imported_from_router': true,
                },
              })
          .toList();
      final res = await repo.uploadCards({
        'network_id': _networkId,
        'category_id': _categoryId,
        'items': items,
        'source': 'mikrotik',
        if (widget.router.remoteId != null)
          'router_id': widget.router.remoteId,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.success,
          content:
              Text(res['message']?.toString() ?? 'تم الاستيراد بنجاح'),
        ),
      );
      ref.invalidate(cardsProvider);
      setState(() => _selected.clear());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            backgroundColor: AppColors.accent,
            content: Text('فشل الاستيراد: $e')),
      );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final snap = ref.watch(routerSessionProvider(widget.router));
    final networks = ref.watch(networksProvider);
    final categories = ref.watch(categoriesProvider);

    // Auto-select when there is exactly one option — keeps the import
    // flow one tap shorter and never leaves the button looking dead.
    final nets = networks.value ?? const [];
    final cats = categories.value ?? const [];
    if (_networkId == null && nets.length == 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _networkId = nets.first['id'] as int?);
      });
    }
    if (_networkId != null && _categoryId == null) {
      final filtered = cats
          .where((c) => c['network_id']?.toString() == _networkId.toString())
          .toList();
      if (filtered.length == 1) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() => _categoryId = filtered.first['id'] as int?);
          }
        });
      }
    }

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(title: const Text('استيراد كروت من الراوتر')),
      body: snap.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('خطأ: $e')),
        data: (s) {
          final users = s.users;
          return Column(
            children: [
              Container(
                width: double.infinity,
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.15)),
                ),
                child: const Text(
                  'حدد مستخدمي الراوتر لإضافتهم ككروت على المنصة. الأكواد المكررة يتم تخطيها تلقائيًا ولا تُحتسب مبيعات مرتين.',
                  style: TextStyle(fontSize: 12, color: AppColors.textDark),
                ),
              ),
              Expanded(
                child: users.isEmpty
                    ? const Center(
                        child: Text('لا يوجد مستخدمون على الراوتر',
                            style: TextStyle(color: AppColors.textGray)))
                    : ListView.builder(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: users.length,
                        itemBuilder: (_, i) {
                          final u = users[i];
                          final name = u['name'] ?? '';
                          final sel = _selected.contains(name);
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: sel
                                  ? AppColors.primary
                                      .withValues(alpha: 0.05)
                                  : AppColors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: sel
                                    ? AppColors.primary
                                    : AppColors.divider,
                              ),
                            ),
                            child: CheckboxListTile(
                              value: sel,
                              activeColor: AppColors.primary,
                              title: Text(name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14)),
                              subtitle: Text(
                                'الباقة: ${u['profile'] ?? 'default'}',
                                style: const TextStyle(
                                    color: AppColors.textGray,
                                    fontSize: 11),
                              ),
                              onChanged: (v) => setState(() {
                                if (v == true) {
                                  _selected.add(name);
                                } else {
                                  _selected.remove(name);
                                }
                              }),
                            ),
                          );
                        },
                      ),
              ),
              _ImportBar(
                networks: networks.value ?? [],
                categories: categories.value ?? [],
                networksLoading: networks.isLoading,
                categoriesLoading: categories.isLoading,
                networkId: _networkId,
                categoryId: _categoryId,
                selectedCount: _selected.length,
                importing: _importing,
                onNetworkChanged: (v) => setState(() {
                  _networkId = v;
                  _categoryId = null;
                }),
                onCategoryChanged: (v) => setState(() => _categoryId = v),
                onImport: () => _import(users),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ImportBar extends StatelessWidget {
  final List<Map<String, dynamic>> networks;
  final List<Map<String, dynamic>> categories;
  final bool networksLoading;
  final bool categoriesLoading;
  final int? networkId;
  final int? categoryId;
  final int selectedCount;
  final bool importing;
  final ValueChanged<int?> onNetworkChanged;
  final ValueChanged<int?> onCategoryChanged;
  final VoidCallback onImport;

  const _ImportBar({
    required this.networks,
    required this.categories,
    required this.networksLoading,
    required this.categoriesLoading,
    required this.networkId,
    required this.categoryId,
    required this.selectedCount,
    required this.importing,
    required this.onNetworkChanged,
    required this.onCategoryChanged,
    required this.onImport,
  });

  @override
  Widget build(BuildContext context) {
    final filtered = networkId == null
        ? categories
        : categories
            .where((c) => c['network_id']?.toString() == networkId.toString())
            .toList();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!networksLoading && networks.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text(
                'لا توجد شبكة لحسابك — أنشئ شبكة من تبويب «شبكاتي» أولاً',
                style: TextStyle(color: AppColors.accent, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: networkId,
                  isDense: true,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'الشبكة'),
                  items: networks
                      .map((n) => DropdownMenuItem(
                            value: n['id'] as int?,
                            child: Text(n['name']?.toString() ?? '',
                                style: const TextStyle(fontSize: 13)),
                          ))
                      .toList(),
                  onChanged: onNetworkChanged,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: categoryId,
                  isDense: true,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'الفئة',
                    hintText: networkId == null ? 'اختر الشبكة أولاً' : null,
                  ),
                  items: filtered
                      .map((c) => DropdownMenuItem(
                            value: c['id'] as int?,
                            child: Text(
                                '${c['name'] ?? ''} — ${c['price'] ?? ''}ر',
                                style: const TextStyle(fontSize: 13)),
                          ))
                      .toList(),
                  onChanged: onCategoryChanged,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed:
                  (selectedCount == 0 || importing) ? null : onImport,
              icon: importing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.download_done),
              label: Text(importing
                  ? 'جارٍ الاستيراد…'
                  : 'استيراد $selectedCount كرت للمنصة'),
            ),
          ),
        ],
      ),
    );
  }
}
