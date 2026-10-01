import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/networks_provider.dart';

class CardsTab extends ConsumerWidget {
  const CardsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardsAsync      = ref.watch(cardsProvider);
    final selectedNetwork = ref.watch(selectedNetworkIdProvider);
    final selectedStatus  = ref.watch(selectedCardStatusProvider);
    final networksAsync   = ref.watch(networksProvider);

    return Column(
      children: [
        Container(
          color: AppColors.white,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            children: [
              _NetworkFilterRow(
                networks: networksAsync.value ?? [],
                selectedId: selectedNetwork,
                onChanged: (id) => ref.read(selectedNetworkIdProvider.notifier).state = id,
              ),
              const SizedBox(height: 8),
              _StatusFilterRow(
                current: selectedStatus,
                onChanged: (s) => ref.read(selectedCardStatusProvider.notifier).state = s,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => ref.invalidate(cardsProvider),
            child: cardsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error:   (e, _) => Center(child: Text('خطأ: $e')),
              data: (cards) {
                if (cards.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.credit_card_off, size: 56, color: AppColors.divider),
                        SizedBox(height: 12),
                        Text('لا توجد كروت', style: TextStyle(color: AppColors.textGray, fontSize: 16)),
                        SizedBox(height: 6),
                        Text('اضغط "رفع كروت" لإضافة كروت جديدة', style: TextStyle(color: AppColors.textGray, fontSize: 12)),
                      ],
                    ),
                  );
                }
                return Column(
                  children: [
                    _CardsSummaryBar(cards: cards),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: cards.length,
                        itemBuilder: (_, i) => _CardTile(card: cards[i]),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _NetworkFilterRow extends StatelessWidget {
  final List<Map<String, dynamic>> networks;
  final int? selectedId;
  final ValueChanged<int?> onChanged;
  const _NetworkFilterRow({required this.networks, required this.selectedId, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _FilterChip(
            label: 'الكل',
            selected: selectedId == null,
            onTap: () => onChanged(null),
          ),
          ...networks.map((n) => Padding(
            padding: const EdgeInsets.only(right: 6),
            child: _FilterChip(
              label: n['name'] ?? '',
              selected: selectedId == n['id'],
              onTap: () => onChanged(n['id'] as int?),
            ),
          )),
        ],
      ),
    );
  }
}

class _StatusFilterRow extends StatelessWidget {
  final String current;
  final ValueChanged<String> onChanged;
  const _StatusFilterRow({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const statuses = {'all': 'الكل', 'available': 'متاحة', 'sold': 'مباعة', 'reserved': 'محجوزة'};
    return SizedBox(
      height: 32,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: statuses.entries.map((e) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: _FilterChip(label: e.value, selected: current == e.key, onTap: () => onChanged(e.key)),
        )).toList(),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.inputBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? AppColors.primary : AppColors.divider),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.textGray,
            fontSize: 12,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _CardsSummaryBar extends StatelessWidget {
  final List<Map<String, dynamic>> cards;
  const _CardsSummaryBar({required this.cards});

  @override
  Widget build(BuildContext context) {
    final available = cards.where((c) => c['status'] == 'available').length;
    final sold      = cards.where((c) => c['status'] == 'sold').length;
    final total     = cards.length;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _SummaryItem(label: 'إجمالي', value: '$total', color: AppColors.primary),
          _Divider(),
          _SummaryItem(label: 'متاحة', value: '$available', color: AppColors.success),
          _Divider(),
          _SummaryItem(label: 'مباعة', value: '$sold', color: AppColors.accent),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 24, color: AppColors.divider);
}

class _SummaryItem extends StatelessWidget {
  final String label, value;
  final Color color;
  const _SummaryItem({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 18)),
        Text(label, style: const TextStyle(color: AppColors.textGray, fontSize: 11)),
      ],
    );
  }
}

class _CardTile extends StatelessWidget {
  final Map<String, dynamic> card;
  const _CardTile({required this.card});

  Color _statusColor(String s) {
    switch (s) {
      case 'available': return AppColors.success;
      case 'sold':      return AppColors.accent;
      case 'reserved':  return AppColors.warning;
      default:          return AppColors.textGray;
    }
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'available': return 'متاح';
      case 'sold':      return 'مباع';
      case 'reserved':  return 'محجوز';
      default:          return s;
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = card['status']?.toString() ?? 'available';
    final category = card['category'];
    final legacyCategory = card['card_category'];
    final catName = category is Map
        ? category['name']?.toString() ?? 'بطاقة'
        : legacyCategory is Map
            ? legacyCategory['name']?.toString() ?? 'بطاقة'
            : category?.toString() ?? 'بطاقة';
    final catPrice = _asDouble(
      category is Map
          ? category['price']
          : legacyCategory is Map
              ? legacyCategory['price']
              : card['price'],
    );
    final code = card['code']?.toString() ?? card['card_number']?.toString() ?? '—';
    final color = _statusColor(status);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.credit_card, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(catName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                Text(
                  status == 'sold' ? '••••••••' : code,
                  style: TextStyle(
                    color: AppColors.textGray,
                    fontSize: 12,
                    letterSpacing: status == 'sold' ? 2 : 0,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_statusLabel(status), style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 4),
              Text('${catPrice.toStringAsFixed(0)} ر', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.primary)),
            ],
          ),
        ],
      ),
    );
  }
}

double _asDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}
