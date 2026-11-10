import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/fiber_topup_models.dart';
import '../providers/fiber_topup_provider.dart';

class FiberTopupScreen extends ConsumerStatefulWidget {
  const FiberTopupScreen({super.key});

  @override
  ConsumerState<FiberTopupScreen> createState() => _FiberTopupScreenState();
}

class _FiberTopupScreenState extends ConsumerState<FiberTopupScreen> {
  final _numCtrl = TextEditingController();
  String _type = 'ftth'; // ftth | adsl | line
  bool _paying = false;

  @override
  void dispose() {
    _numCtrl.dispose();
    super.dispose();
  }

  static const _types = [
    ('ftth', 'فايبر FTTH', Icons.bolt_rounded),
    ('adsl', 'الإنترنت الأرضي ADSL', Icons.router_rounded),
    ('line', 'هاتف أرضي', Icons.phone_rounded),
  ];

  static const _typeHints = {
    'ftth': 'اختر باقة الفايبر المناسبة لسرعة خطك',
    'adsl': 'باقات الإنترنت الأرضي — يمن نت',
    'line': 'سداد مبلغ لرقم الهاتف الثابت',
  };

  String get _num => _numCtrl.text.trim();

  bool get _numValid => RegExp(r'^\d{8}$').hasMatch(_num);

  Future<void> _pick(FiberService svc, FiberPackage pkg) async {
    if (!_numValid) {
      _toast('أدخل رقم الهاتف الثابت (8 خانات) أولاً');
      return;
    }
    final ok = await _confirm(svc, pkg);
    if (ok != true || !mounted) return;

    setState(() => _paying = true);
    try {
      final data = await ref
          .read(fiberTopupProvider.notifier)
          .pay(num: _num, package: pkg);
      if (!mounted) return;
      _result(true, data['message']?.toString() ??
          'تم تنفيذ عملية السداد بنجاح');
      ref.invalidate(fiberOrdersProvider);
    } catch (e) {
      if (!mounted) return;
      _result(false, e.toString());
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  /// Confirm sheet — fetches the live server quote so the user sees the
  /// exact wallet charge (incl. cross-gateway currency conversion).
  Future<bool?> _confirm(FiberService svc, FiberPackage pkg) {
    final fmt = NumberFormat('#,##0');
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('تأكيد عملية السداد',
                  textAlign: TextAlign.center,
                  style: Theme.of(ctx)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              _row('الخدمة', svc.nameAr),
              _row('الرقم', _num),
              _row('الباقة', pkg.name),
              const Divider(height: 24),
              ref.watch(fiberQuoteProvider(pkg.code)).when(
                    loading: () => const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (e, _) => Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text('تعذر جلب المعاينة: $e',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.red)),
                    ),
                    data: (q) {
                      final charge =
                          double.tryParse('${q['wallet_charge'] ?? pkg.price}') ??
                              pkg.price;
                      final walletCur =
                          (q['wallet_currency'] ?? '').toString() == 'north'
                              ? 'ر.ش'
                              : 'ر.ج';
                      final converted = q['converted'] == true;
                      return Column(
                        children: [
                          _row('مبلغ الباقة',
                              '${fmt.format(q['amount'] ?? pkg.price)} ${q['provider_currency'] == 'north' ? 'ر.ش' : 'ر.ج'}'),
                          if (converted)
                            _row('سعر التحويل لعملة محفظتك',
                                '${fmt.format(charge)} $walletCur', bold: true)
                          else
                            _row('سيُخصم من رصيدك',
                                '${fmt.format(charge)} $walletCur', bold: true),
                        ],
                      );
                    },
                  ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('تأكيد السداد'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.bold : FontWeight.w500,
      fontSize: 14,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style.copyWith(color: Colors.grey[600])),
          Text(value, style: style),
        ],
      ),
    );
  }

  void _result(bool success, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: Icon(
          success ? Icons.check_circle_rounded : Icons.error_rounded,
          color: success ? Colors.green : Colors.red,
          size: 56,
        ),
        title: Text(success ? 'تمت العملية' : 'لم تكتمل العملية',
            textAlign: TextAlign.center),
        content: Text(message, textAlign: TextAlign.center),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('حسناً'),
          ),
        ],
      ),
    );
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  void _showHistory() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, scroll) => Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('سجل عمليات الشحن',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            Expanded(
              child: ref.watch(fiberOrdersProvider).when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('تعذر التحميل: $e')),
                    data: (orders) {
                      final list = orders
                          .where((o) => o.target.isNotEmpty)
                          .toList();
                      if (list.isEmpty) {
                        return const Center(
                            child: Text('لا توجد عمليات سابقة'));
                      }
                      return ListView.separated(
                        controller: scroll,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: list.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1),
                        itemBuilder: (_, i) => _orderTile(list[i]),
                      );
                    },
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _orderTile(FiberOrder o) {
    final (color, label) = switch (o.status) {
      'done' => (Colors.green, 'ناجحة'),
      'failed' => (Colors.red, 'فاشلة'),
      'banned' => (Colors.orange, 'محظورة'),
      _ => (Colors.blueGrey, 'قيد التنفيذ'),
    };
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: color.withValues(alpha: 0.12),
        child: Icon(Icons.phone_in_talk_rounded, color: color, size: 18),
      ),
      title: Text('رقم ${o.target}',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text(
        '${NumberFormat('#,##0').format(o.totalCharged)} — ${o.resultDesc ?? ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12),
      ),
      trailing: Text(label,
          style: TextStyle(
              color: color, fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }

  Widget _packageTile(FiberService svc, FiberPackage pkg) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _paying ? null : () => _pick(svc, pkg),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(pkg.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14)),
                    if (pkg.specs.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(pkg.specs.join(' · '),
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[600])),
                      ),
                    if (pkg.note.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(pkg.note,
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[600])),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${NumberFormat('#,##0').format(pkg.price)} ريال',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                          fontSize: 14)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text('سداد',
                        style: TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.inputBg,
      appBar: AppBar(
        title: const Text('الانترنت الأرضي'),
        actions: [
          IconButton(
            tooltip: 'سجل العمليات',
            icon: const Icon(Icons.receipt_long_rounded),
            onPressed: _showHistory,
          ),
        ],
      ),
      body: Stack(
        children: [
          ref.watch(fiberServiceProvider).when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('تعذر تحميل الباقات: $e',
                        textAlign: TextAlign.center),
                  ),
                ),
                data: (svc) {
                  final groups = svc.groupedByType(_type);
                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _numField(),
                      const SizedBox(height: 14),
                      _typeSwitcher(),
                      const SizedBox(height: 6),
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(vertical: 8),
                        child: Text(_typeHints[_type] ?? '',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[600])),
                      ),
                      if (groups.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(
                              child: Text(
                                  'لا توجد باقات متاحة لهذا النوع')),
                        )
                      else
                        for (final entry in groups.entries)
                          _groupCard(svc, entry.key, entry.value),
                      const SizedBox(height: 24),
                    ],
                  );
                },
              ),
          if (_paying)
            Container(
              color: Colors.black26,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _numField() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: TextField(
        controller: _numCtrl,
        keyboardType: TextInputType.phone,
        maxLength: 8,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          counterText: '',
          labelText: 'رقم الهاتف الثابت',
          hintText: '01XXXXXX — 8 خانات',
          prefixIcon: Icon(Icons.phone,
              color: _num.isEmpty || _numValid
                  ? Colors.grey
                  : Colors.red),
          suffixIcon: _numValid
              ? const Icon(Icons.check_circle, color: Colors.green)
              : null,
        ),
      ),
    );
  }

  Widget _typeSwitcher() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (final (type, label, icon) in _types)
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _type = type),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: _type == type
                        ? AppColors.primary
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Column(
                    children: [
                      Icon(icon,
                          size: 20,
                          color: _type == type
                              ? Colors.white
                              : Colors.grey[600]),
                      const SizedBox(height: 4),
                      Text(label,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _type == type
                                ? Colors.white
                                : Colors.grey[700],
                          )),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _groupCard(FiberService svc, String title, List<FiberPackage> items) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: ExpansionTile(
        initiallyExpanded: true,
        shape: const Border(),
        title: Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: AppColors.primary)),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              children: [for (final p in items) _packageTile(svc, p)],
            ),
          ),
        ],
      ),
    );
  }
}
