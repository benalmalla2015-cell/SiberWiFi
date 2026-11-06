import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../mikrotik/presentation/widgets/ui_states.dart';
import '../../data/loyalty_api.dart';
import '../../providers/loyalty_providers.dart';

/// ACC-10 — discount/reward tiers (PLAN §4: discount_tiers_screen).
/// Each tier is a bracket over a document's qty or amount earning a
/// reward (direct discount | bonus points | profit credit | extra
/// distributor commission) applied automatically at posting.
class DiscountTiersScreen extends ConsumerWidget {
  const DiscountTiersScreen({super.key});

  static const modeColors = {
    'direct_percent': AppColors.error,
    'points': AppColors.primary,
    'profit_balance': AppColors.warning,
    'commission': AppColors.success,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tiersAsync = ref.watch(accDiscountTiersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('شرائح الخصم والمكافآت')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context, ref),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label:
            const Text('شريحة', style: TextStyle(color: Colors.white)),
      ),
      body: Container(
        color: AppColors.inputBg,
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(accDiscountTiersProvider),
          child: tiersAsync.when(
            loading: () => const LoadingState(),
            error: (e, _) => ErrorRetry(
              message: 'تعذّر تحميل الشرائح\n$e',
              onRetry: () => ref.invalidate(accDiscountTiersProvider),
            ),
            data: (tiers) => tiers.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 120),
                      EmptyState('لا توجد شرائح — أضف أول شريحة مكافأة',
                          icon: Icons.percent_outlined),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: tiers.length,
                    itemBuilder: (_, i) =>
                        _TierCard(tier: tiers[i]),
                  ),
          ),
        ),
      ),
    );
  }

  Future<void> _openForm(BuildContext context, WidgetRef ref,
      [AccDiscountTier? tier]) async {
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _TierFormSheet(tier: tier),
    );
    if (done == true) ref.invalidate(accDiscountTiersProvider);
  }
}

class _TierCard extends ConsumerWidget {
  final AccDiscountTier tier;
  const _TierCard({required this.tier});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color =
        DiscountTiersScreen.modeColors[tier.mode] ?? AppColors.primary;

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
            color: color.withValues(alpha: tier.isActive ? 0.12 : 0.05),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.percent_outlined,
              color: tier.isActive ? color : AppColors.textLight,
              size: 22),
        ),
        title: Text(
          tier.modeLabel,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color:
                tier.isActive ? AppColors.textDark : AppColors.textGray,
          ),
        ),
        subtitle: Text(
          '${tier.basisLabel}: ${tier.bracketLabel} — المكافأة ${tier.rewardLabel}',
          style:
              const TextStyle(fontSize: 11, color: AppColors.textGray),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'edit') {
              final done = await showModalBottomSheet<bool>(
                context: context,
                isScrollControlled: true,
                shape: const RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(24)),
                ),
                builder: (_) => _TierFormSheet(tier: tier),
              );
              if (done == true) ref.invalidate(accDiscountTiersProvider);
            } else if (v == 'toggle') {
              await ref.read(loyaltyApiProvider).updateTier(
                  tier.id, {'is_active': !tier.isActive});
              ref.invalidate(accDiscountTiersProvider);
            } else if (v == 'delete') {
              final ok = await _confirmDelete(context);
              if (ok == true) {
                await ref.read(loyaltyApiProvider).deleteTier(tier.id);
                ref.invalidate(accDiscountTiersProvider);
              }
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('تعديل')),
            PopupMenuItem(
                value: 'toggle',
                child: Text(tier.isActive ? 'إيقاف' : 'تفعيل')),
            const PopupMenuItem(value: 'delete', child: Text('حذف')),
          ],
        ),
      ),
    );
  }

  Future<bool?> _confirmDelete(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الشريحة'),
        content: const Text(
            'سيتوقف تطبيقها على العمليات الجديدة — السندات المرحَّلة تحتفظ بقيمتها.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف')),
        ],
      ),
    );
  }
}

class _TierFormSheet extends ConsumerStatefulWidget {
  final AccDiscountTier? tier;
  const _TierFormSheet({this.tier});

  @override
  ConsumerState<_TierFormSheet> createState() => _TierFormSheetState();
}

class _TierFormSheetState extends ConsumerState<_TierFormSheet> {
  final _minCtrl = TextEditingController();
  final _maxCtrl = TextEditingController();
  final _rewardCtrl = TextEditingController();
  String _mode = 'direct_percent';
  String _basis = 'qty';
  String _rewardUnit = 'percent';
  bool _busy = false;

  static const modeLabels = {
    'direct_percent': 'خصم مباشر على قيمة العملية',
    'points': 'نقاط مكافأة لنقطة البيع',
    'profit_balance': 'رصيد أرباح لنقطة البيع',
    'commission': 'عمولة إضافية للموزع',
  };

  @override
  void initState() {
    super.initState();
    final t = widget.tier;
    if (t != null) {
      _mode = t.mode;
      _basis = t.basis;
      _rewardUnit = t.rewardUnit;
      _minCtrl.text = _num(t.min);
      _maxCtrl.text = t.max != null ? _num(t.max!) : '';
      _rewardCtrl.text = _num(t.rewardValue);
    }
  }

  @override
  void dispose() {
    _minCtrl.dispose();
    _maxCtrl.dispose();
    _rewardCtrl.dispose();
    super.dispose();
  }

  String _num(double v) => v == v.roundToDouble()
      ? v.toStringAsFixed(0)
      : v.toString();

  @override
  Widget build(BuildContext context) {
    final editing = widget.tier != null;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(editing ? 'تعديل الشريحة' : 'شريحة جديدة',
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary)),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _mode,
              decoration: const InputDecoration(
                  labelText: 'نوع المكافأة', border: OutlineInputBorder()),
              items: modeLabels.entries
                  .map((e) => DropdownMenuItem(
                      value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: (v) => setState(() => _mode = v ?? _mode),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _basis,
              decoration: const InputDecoration(
                  labelText: 'أساس الشريحة',
                  border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(
                    value: 'qty', child: Text('كمية المستند')),
                DropdownMenuItem(
                    value: 'amount', child: Text('قيمة المستند')),
              ],
              onChanged: (v) => setState(() => _basis = v ?? _basis),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _minCtrl,
                    decoration: const InputDecoration(
                        labelText: 'من (الحد الأدنى)',
                        border: OutlineInputBorder()),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _maxCtrl,
                    decoration: const InputDecoration(
                        labelText: 'إلى (فارغ = مفتوح)',
                        border: OutlineInputBorder()),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _rewardCtrl,
                    decoration: const InputDecoration(
                        labelText: 'قيمة المكافأة',
                        border: OutlineInputBorder()),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _rewardUnit,
                    decoration: const InputDecoration(
                        labelText: 'الوحدة',
                        border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(
                          value: 'percent', child: Text('%')),
                      DropdownMenuItem(
                          value: 'fixed', child: Text('ثابت')),
                    ],
                    onChanged: (v) =>
                        setState(() => _rewardUnit = v ?? _rewardUnit),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _basis == 'qty'
                  ? 'تُطبَّق عند بلوغ عدد الوحدات في المستند الحد.'
                  : 'تُطبَّق عند بلوغ قيمة المستند الحد. النسبة تُحسب من قيمة المستند.',
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textGray),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(editing ? 'حفظ' : 'إنشاء'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final min = double.tryParse(_minCtrl.text.trim());
    final reward = double.tryParse(_rewardCtrl.text.trim());
    final maxText = _maxCtrl.text.trim();
    final max = maxText.isEmpty ? null : double.tryParse(maxText);

    if (min == null || min < 0) {
      _toast('أدخل حداً أدنى صحيحاً');
      return;
    }
    if (maxText.isNotEmpty && (max == null || max <= min)) {
      _toast('الحد الأعلى يجب أن يكون أكبر من الأدنى');
      return;
    }
    if (reward == null || reward <= 0) {
      _toast('أدخل قيمة مكافأة صحيحة');
      return;
    }

    setState(() => _busy = true);
    try {
      final api = ref.read(loyaltyApiProvider);
      final msg = widget.tier == null
          ? await api.createTier({
              'mode': _mode,
              'basis': _basis,
              'min': min,
              'max': max,
              'reward_value': reward,
              'reward_unit': _rewardUnit,
            })
          : await api.updateTier(widget.tier!.id, {
              'mode': _mode,
              'basis': _basis,
              'min': min,
              'max': max,
              'reward_value': reward,
              'reward_unit': _rewardUnit,
            });
      _toast(msg);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''));
      setState(() => _busy = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }
}
