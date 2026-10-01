import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../wallet/presentation/providers/wallet_provider.dart';
import '../providers/networks_provider.dart';

class NetworksScreen extends ConsumerStatefulWidget {
  const NetworksScreen({super.key});

  @override
  ConsumerState<NetworksScreen> createState() => _NetworksScreenState();
}

class _NetworksScreenState extends ConsumerState<NetworksScreen> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.text = ref.read(networkSearchProvider);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _searchController.clear();
    ref.read(networkSearchProvider.notifier).state = '';
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(networksProvider);
    final user = ref.watch(authProvider).user;
    final wallet = ref.watch(walletBalanceProvider);
    final isEligible = (user?.isEligibleForAdvance ?? false) || (wallet.valueOrNull?.isEligibleForAdvance ?? false);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('الشبكات المتاحة'),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textDark,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
            onPressed: () => ref.invalidate(networksProvider),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  textDirection: TextDirection.rtl,
                  textAlign: TextAlign.right,
                  onChanged: (value) => ref.read(networkSearchProvider.notifier).state = value.trim(),
                  decoration: InputDecoration(
                    prefixIcon: IconButton(
                      icon: const Icon(Icons.tune_rounded, color: AppColors.primary),
                      onPressed: () => showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                      ),
                      builder: (_) => const _GovernorateFilterSheet(),
                    ),
                    ),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close_rounded, color: AppColors.textGray),
                            onPressed: _clearSearch,
                          )
                        : const Icon(Icons.search_rounded, color: AppColors.textGray),
                    hintText: 'ابحث باسم الشبكة أو رقم ID الشبكة...',
                    hintStyle: const TextStyle(fontFamily: 'Cairo', color: AppColors.textLight, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 8),
                _FilterChips(isEligible: isEligible),
              ],
            ),
          ),
          Expanded(
            child: async.when(
              loading: () => _buildShimmer(),
              error: (e, _) => _buildError(ref),
              data: (nets) => nets.isEmpty
                  ? _buildEmpty()
                  : RefreshIndicator(
                      color: AppColors.primary,
                      onRefresh: () async => ref.invalidate(networksProvider),
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: nets.length,
                        itemBuilder: (context, i) => _NetworkCard(network: nets[i]),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShimmer() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 5,
      itemBuilder: (_, __) => Shimmer.fromColors(
        baseColor: const Color(0xFFE8ECF4),
        highlightColor: const Color(0xFFF5F7FD),
        child: Container(
          height: 100,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_off_rounded, size: 64, color: AppColors.textLight),
          SizedBox(height: 16),
          Text(
            'لا توجد شبكات متاحة',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 16,
              color: AppColors.textGray,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.signal_wifi_statusbar_connected_no_internet_4_rounded,
            size: 64,
            color: AppColors.textLight,
          ),
          const SizedBox(height: 16),
          const Text(
            'تعذّر تحميل الشبكات',
            style: TextStyle(fontFamily: 'Cairo', color: AppColors.textGray),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => ref.invalidate(networksProvider),
            child: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    );
  }
}

class _FilterChips extends ConsumerWidget {
  final bool isEligible;
  const _FilterChips({required this.isEligible});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(networkFilterModeProvider);

    final chips = <Widget>[
      _FilterChip(
        label: 'الأقرب إليك',
        selected: mode == NetworkFilterMode.nearest,
        onSelected: (_) => _setMode(
          ref,
          mode == NetworkFilterMode.nearest ? NetworkFilterMode.all : NetworkFilterMode.nearest,
        ),
      ),
      _FilterChip(
        label: 'الكل',
        selected: mode == NetworkFilterMode.all,
        onSelected: (_) => _setMode(ref, NetworkFilterMode.all),
      ),
      _FilterChip(
        label: 'المحافظات',
        selected: mode == NetworkFilterMode.governorates,
        onSelected: (_) => _openFilterSheet(context, ref, NetworkFilterMode.governorates),
      ),
      _FilterChip(
        label: 'المديريات',
        selected: mode == NetworkFilterMode.directorates,
        onSelected: (_) => _openFilterSheet(context, ref, NetworkFilterMode.directorates),
      ),
      _FilterChip(
        label: 'سلفني',
        selected: mode == NetworkFilterMode.loan,
        onSelected: (_) {
          if (!isEligible && mode != NetworkFilterMode.loan) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('قم بشحن رصيدك لأول مرة لتفعيل خاصية سلفني'),
                backgroundColor: AppColors.accent,
              ),
            );
            return;
          }
          _setMode(
            ref,
            mode == NetworkFilterMode.loan ? NetworkFilterMode.all : NetworkFilterMode.loan,
          );
        },
      ),
      _FilterChip(
        label: 'الأكثر مبيعاً',
        selected: mode == NetworkFilterMode.mostSelling,
        onSelected: (_) => _setMode(
          ref,
          mode == NetworkFilterMode.mostSelling ? NetworkFilterMode.all : NetworkFilterMode.mostSelling,
        ),
      ),
      _FilterChip(
        label: 'المفضلة',
        selected: mode == NetworkFilterMode.favorite,
        onSelected: (_) => _setMode(
          ref,
          mode == NetworkFilterMode.favorite ? NetworkFilterMode.all : NetworkFilterMode.favorite,
        ),
      ),
    ];

    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        reverse: false,
        children: _intersperse(chips, const SizedBox(width: 8)),
      ),
    );
  }

  List<Widget> _intersperse(List<Widget> items, Widget separator) {
    if (items.isEmpty) return items;
    final result = <Widget>[items.first];
    for (var i = 1; i < items.length; i++) {
      result.add(separator);
      result.add(items[i]);
    }
    return result;
  }

  void _setMode(WidgetRef ref, NetworkFilterMode mode) {
    ref.read(networkFilterModeProvider.notifier).state = mode;
    if (!mode.isLocation) {
      ref.read(networkRegionIdProvider.notifier).state = null;
      ref.read(networkGovernorateIdProvider.notifier).state = null;
      ref.read(networkDirectorateIdProvider.notifier).state = null;
    }
  }

  void _openFilterSheet(BuildContext context, WidgetRef ref, NetworkFilterMode mode) {
    if (mode == NetworkFilterMode.directorates) {
      final governorateId = ref.read(networkGovernorateIdProvider);
      if (governorateId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('اختر المحافظة أولاً'),
            backgroundColor: AppColors.accent,
          ),
        );
        return;
      }
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (_) => _SubDirectorateFilterSheet(governorateId: governorateId),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _GovernorateFilterSheet(),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final void Function(bool) onSelected;
  const _FilterChip({required this.label, required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontFamily: 'Cairo', fontSize: 12)),
      selected: selected,
      onSelected: onSelected,
      selectedColor: AppColors.primary,
      backgroundColor: const Color(0xFFF1F4F9),
      labelStyle: TextStyle(
        fontFamily: 'Cairo',
        fontSize: 12,
        color: selected ? Colors.white : AppColors.textDark,
        fontWeight: FontWeight.w600,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      side: BorderSide(color: selected ? AppColors.primary : AppColors.divider),
    );
  }
}

class _GovernorateFilterSheet extends ConsumerStatefulWidget {
  const _GovernorateFilterSheet();

  @override
  ConsumerState<_GovernorateFilterSheet> createState() => _GovernorateFilterSheetState();
}

class _GovernorateFilterSheetState extends ConsumerState<_GovernorateFilterSheet> {
  int _step = 0;
  List<Map<String, dynamic>> _regions = [];
  List<Map<String, dynamic>> _governorates = [];
  int? _selectedRegionId;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadRegions();
  }

  Future<void> _loadRegions() async {
    setState(() { _loading = true; _error = null; });
    final list = await loadRegions(ref);
    setState(() {
      _regions = list;
      _loading = false;
      _error = list.isEmpty ? 'لا توجد مناطق متاحة' : null;
    });
  }

  Future<void> _loadGovernorates(int regionId) async {
    setState(() { _loading = true; _error = null; });
    final list = await loadGovernoratesByRegion(ref, regionId);
    setState(() {
      _governorates = list;
      _loading = false;
      _error = list.isEmpty ? 'لا توجد محافظات متاحة' : null;
    });
  }

  void _selectRegion(Map<String, dynamic> region) {
    final id = (region['id'] as num).toInt();
    setState(() {
      _selectedRegionId = id;
      _step = 1;
    });
    _loadGovernorates(id);
  }

  void _apply(int governorateId) {
    ref.read(networkFilterModeProvider.notifier).state = NetworkFilterMode.governorates;
    ref.read(networkRegionIdProvider.notifier).state = _selectedRegionId;
    ref.read(networkGovernorateIdProvider.notifier).state = governorateId;
    ref.read(networkDirectorateIdProvider.notifier).state = null;
    ref.invalidate(networksProvider);
    Navigator.pop(context);
  }

  void _applyAll() {
    ref.read(networkFilterModeProvider.notifier).state = NetworkFilterMode.all;
    ref.read(networkRegionIdProvider.notifier).state = null;
    ref.read(networkGovernorateIdProvider.notifier).state = null;
    ref.read(networkDirectorateIdProvider.notifier).state = null;
    ref.invalidate(networksProvider);
    Navigator.pop(context);
  }

  void _backToRegions() {
    setState(() {
      _step = 0;
      _governorates = [];
      _selectedRegionId = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = _step == 0 ? 'اختر المنطقة' : 'اختر المحافظة';
    final items = _step == 0
        ? <Map<String, dynamic>>[{'id': -1, 'name': 'كل المناطق', 'all': true}, ..._regions]
        : <Map<String, dynamic>>[{'id': -1, 'name': 'كل المحافظات', 'all': true}, ..._governorates];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  if (_step == 1)
                    GestureDetector(
                      onTap: _backToRegions,
                      child: const Icon(Icons.arrow_back_ios, color: AppColors.primary, size: 20),
                    ),
                  if (_step == 1) const SizedBox(width: 12),
                  Text(
                    title,
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textDark),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(_error!, style: const TextStyle(fontFamily: 'Cairo', color: AppColors.accent)),
              ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: items.length,
                  itemBuilder: (ctx, i) => _itemBuilder(items[i]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _itemBuilder(Map<String, dynamic> item) {
    final isAll = item['all'] == true;
    return ListTile(
      leading: isAll
          ? const Icon(Icons.public_rounded, color: AppColors.primary)
          : const Icon(Icons.chevron_left_rounded, color: AppColors.textGray),
      title: Text(
        item['name']?.toString() ?? '',
        style: const TextStyle(fontFamily: 'Cairo', fontSize: 15, color: AppColors.textDark),
        textAlign: TextAlign.right,
      ),
      onTap: () {
        if (isAll) {
          _applyAll();
          return;
        }
        if (_step == 0) {
          _selectRegion(item);
        } else {
          _apply((item['id'] as num).toInt());
        }
      },
    );
  }
}

class _SubDirectorateFilterSheet extends ConsumerStatefulWidget {
  final int governorateId;
  const _SubDirectorateFilterSheet({required this.governorateId});

  @override
  ConsumerState<_SubDirectorateFilterSheet> createState() => _SubDirectorateFilterSheetState();
}

class _SubDirectorateFilterSheetState extends ConsumerState<_SubDirectorateFilterSheet> {
  List<Map<String, dynamic>> _subDirectorates = [];
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final list = await loadSubDirectoratesByGovernorate(ref, widget.governorateId);
    setState(() {
      _subDirectorates = list;
      _loading = false;
      _error = list.isEmpty ? 'لا توجد مديريات متاحة' : null;
    });
  }

  void _apply(int subDirectorateId) {
    ref.read(networkFilterModeProvider.notifier).state = NetworkFilterMode.directorates;
    ref.read(networkDirectorateIdProvider.notifier).state = subDirectorateId;
    ref.invalidate(networksProvider);
    Navigator.pop(context);
  }

  void _applyAll() {
    ref.read(networkFilterModeProvider.notifier).state = NetworkFilterMode.governorates;
    ref.read(networkDirectorateIdProvider.notifier).state = null;
    ref.invalidate(networksProvider);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final items = <Map<String, dynamic>>[
      {'id': -1, 'name': 'كل المديريات', 'all': true},
      ..._subDirectorates,
    ];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'اختر المديرية',
                style: TextStyle(fontFamily: 'Cairo', fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textDark),
              ),
            ),
            const SizedBox(height: 12),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(_error!, style: const TextStyle(fontFamily: 'Cairo', color: AppColors.accent)),
              ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: items.length,
                  itemBuilder: (ctx, i) => _itemBuilder(items[i]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _itemBuilder(Map<String, dynamic> item) {
    final isAll = item['all'] == true;
    return ListTile(
      leading: isAll
          ? const Icon(Icons.public_rounded, color: AppColors.primary)
          : const Icon(Icons.chevron_left_rounded, color: AppColors.textGray),
      title: Text(
        item['name']?.toString() ?? '',
        style: const TextStyle(fontFamily: 'Cairo', fontSize: 15, color: AppColors.textDark),
        textAlign: TextAlign.right,
      ),
      onTap: () {
        if (isAll) {
          _applyAll();
          return;
        }
        _apply((item['id'] as num).toInt());
      },
    );
  }
}

class _NetworkCard extends StatelessWidget {
  final Map<String, dynamic> network;
  const _NetworkCard({required this.network});

  @override
  Widget build(BuildContext context) {
    final id = network['id'];
    final rating = (network['average_rating'] ?? 0.0).toDouble();
    final cardCount = network['available_cards_count'] ?? 0;
    final imageUrl = network['logo_url'] ?? network['cover_image_url'];
    final supportsAdvance = network['supports_credit'] == true || network['advance_enabled'] == true;

    return GestureDetector(
      onTap: () => context.go('/networks/$id'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.divider),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.lightBlue],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: imageUrl == null || imageUrl.toString().isEmpty
                  ? const Icon(
                      Icons.wifi_rounded,
                      color: Colors.white,
                      size: 28,
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: CachedNetworkImage(
                        imageUrl: imageUrl.toString(),
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => const Icon(
                          Icons.wifi_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          network['name'] ?? '',
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textDark,
                          ),
                        ),
                      ),
                      if (network['is_cross_region'] == true)
                        Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F5E9),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            network['region_type'] == 'north' ? 'شمال' : 'جنوب',
                            style: const TextStyle(fontFamily: 'Cairo', fontSize: 10, color: Color(0xFF2E7D32), fontWeight: FontWeight.w600),
                          ),
                        ),
                      if (supportsAdvance)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF3E0),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'سلفني',
                            style: TextStyle(fontFamily: 'Cairo', fontSize: 10, color: Color(0xFFEF6C00), fontWeight: FontWeight.w600),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 13,
                        color: AppColors.textGray,
                      ),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          network['directorate'] ?? network['region'] ?? network['location'] ?? '',
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            color: AppColors.textGray,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.star_rounded,
                        size: 14,
                        color: Color(0xFFF59E0B),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        rating.toStringAsFixed(1),
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          color: AppColors.textGray,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Icon(
                        Icons.credit_card_rounded,
                        size: 13,
                        color: AppColors.textGray,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '$cardCount كرت',
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          color: AppColors.textGray,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 16,
              color: AppColors.textLight,
            ),
          ],
        ),
      ),
    );
  }
}
