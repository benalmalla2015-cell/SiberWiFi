import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../mikrotik/presentation/widgets/ui_states.dart';
import '../../data/acc_api.dart';
import '../../providers/acc_providers.dart';

/// «نقاط البيع» — outlets, their bound pos-role agent, balances and
/// the hardware devices allowed to operate each point (PLAN §2.2).
class PosManagementScreen extends ConsumerWidget {
  const PosManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pointsAsync = ref.watch(accPosPointsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('نقاط البيع')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showForm(context, null),
        icon: const Icon(Icons.add_business_outlined),
        label: const Text('إضافة نقطة'),
        backgroundColor: AppColors.primary,
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(accPosPointsProvider),
        child: pointsAsync.when(
          loading: () => const LoadingState(),
          error: (e, _) => ErrorRetry(
            message: 'تعذّر تحميل نقاط البيع\n$e',
            onRetry: () => ref.invalidate(accPosPointsProvider),
          ),
          data: (points) {
            if (points.isEmpty) {
              return const EmptyState(
                'لا توجد نقاط بيع بعد',
                icon: Icons.storefront_outlined,
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: points.length,
              itemBuilder: (_, i) => _PosCard(
                point: points[i],
                onEdit: () => _showForm(context, points[i]),
                onDevices: () => _showDevices(context, points[i]),
                onDelete: () => _confirmDelete(context, ref, points[i]),
              ),
            );
          },
        ),
      ),
    );
  }

  void _showForm(BuildContext ctx, AccPosPoint? point) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _PosFormSheet(point: point),
    );
  }

  void _showDevices(BuildContext ctx, AccPosPoint point) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _DevicesSheet(point: point),
    );
  }

  Future<void> _confirmDelete(
      BuildContext ctx, WidgetRef ref, AccPosPoint p) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('حذف نقطة البيع'),
        content: Text('حذف «${p.name}» يفك ارتباط أجهزتها. متابعة؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('حذف', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final msg = await ref.read(accApiProvider).deletePosPoint(p.id);
      ref.invalidate(accPosPointsProvider);
      if (ctx.mounted) _toast(ctx, msg, ok: true);
    } catch (e) {
      if (ctx.mounted) _toast(ctx, '$e');
    }
  }

  static void _toast(BuildContext ctx, String msg, {bool ok = false}) {
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: ok ? AppColors.success : AppColors.error,
    ));
  }
}

class _PosCard extends StatelessWidget {
  final AccPosPoint point;
  final VoidCallback onEdit, onDevices, onDelete;
  const _PosCard({
    required this.point,
    required this.onEdit,
    required this.onDevices,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.storefront_outlined,
                      color: AppColors.success, size: 26),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(point.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      if (point.ownerName?.isNotEmpty == true)
                        Text(point.ownerName!,
                            style: const TextStyle(
                                color: AppColors.textGray, fontSize: 12)),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: (point.isActive
                            ? AppColors.success
                            : AppColors.error)
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    point.isActive ? 'نشطة' : 'موقوفة',
                    style: TextStyle(
                        color: point.isActive
                            ? AppColors.success
                            : AppColors.error,
                        fontSize: 11,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (point.location?.isNotEmpty == true ||
                point.phone?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    if (point.location?.isNotEmpty == true)
                      _meta(Icons.location_on_outlined, point.location!),
                    if (point.phone?.isNotEmpty == true)
                      _meta(Icons.phone_outlined, point.phone!),
                  ],
                ),
              ),
            Row(
              children: [
                Expanded(
                    child: _stat('النقاط', point.pointsBalance,
                        Icons.stars_outlined, AppColors.lightBlue)),
                const SizedBox(width: 8),
                Expanded(
                    child: _stat('الأرباح', point.profitBalance,
                        Icons.trending_up, AppColors.success)),
                const SizedBox(width: 8),
                Expanded(
                    child: _stat(
                        'حد الآجل',
                        point.creditLimit,
                        Icons.credit_card_outlined,
                        AppColors.warning)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.point_of_sale_outlined,
                    size: 13, color: AppColors.textGray),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    point.agentName != null
                        ? 'الحساب: ${point.agentName}'
                        : 'بلا حساب نقطة بيع مرتبط',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textGray),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(Icons.devices_outlined,
                    size: 13, color: AppColors.textGray),
                const SizedBox(width: 4),
                Text('${point.devicesCount} جهاز',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textGray)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onDevices,
                    icon: const Icon(Icons.devices_outlined, size: 15),
                    label: const Text('الأجهزة',
                        style: TextStyle(fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 8)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 15),
                    label: const Text('تعديل',
                        style: TextStyle(fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 8)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline,
                        size: 15, color: AppColors.error),
                    label: const Text('حذف',
                        style:
                            TextStyle(fontSize: 13, color: AppColors.error)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      side: const BorderSide(color: AppColors.error),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _meta(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.textGray),
        const SizedBox(width: 4),
        Text(text,
            style: const TextStyle(fontSize: 12, color: AppColors.textGray)),
      ],
    );
  }

  Widget _stat(String label, double value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(height: 2),
          Text(
            _fmt(value),
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.bold, color: color),
          ),
          Text(label,
              style:
                  const TextStyle(fontSize: 10, color: AppColors.textGray)),
        ],
      ),
    );
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}

class _PosFormSheet extends ConsumerStatefulWidget {
  final AccPosPoint? point;
  const _PosFormSheet({this.point});

  @override
  ConsumerState<_PosFormSheet> createState() => _PosFormSheetState();
}

class _PosFormSheetState extends ConsumerState<_PosFormSheet> {
  final _nameCtr = TextEditingController();
  final _ownerCtr = TextEditingController();
  final _phoneCtr = TextEditingController();
  final _locationCtr = TextEditingController();
  final _creditCtr = TextEditingController();
  int? _agentId;
  bool _active = true;
  bool _loading = false;

  bool get _isEdit => widget.point != null;

  @override
  void initState() {
    super.initState();
    final p = widget.point;
    if (p != null) {
      _nameCtr.text = p.name;
      _ownerCtr.text = p.ownerName ?? '';
      _phoneCtr.text = p.phone ?? '';
      _locationCtr.text = p.location ?? '';
      _creditCtr.text =
          p.creditLimit == 0 ? '' : p.creditLimit.toStringAsFixed(0);
      _agentId = p.agentId;
      _active = p.isActive;
    }
  }

  @override
  void dispose() {
    _nameCtr.dispose();
    _ownerCtr.dispose();
    _phoneCtr.dispose();
    _locationCtr.dispose();
    _creditCtr.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_nameCtr.text.trim().isEmpty) {
      PosManagementScreen._toast(context, 'أدخل اسم نقطة البيع');
      return;
    }
    setState(() => _loading = true);
    try {
      final api = ref.read(accApiProvider);
      final data = <String, dynamic>{
        'name': _nameCtr.text.trim(),
        'owner_name': _ownerCtr.text.trim(),
        'phone': _phoneCtr.text.trim(),
        'location': _locationCtr.text.trim(),
        'agent_id': _agentId,
        'credit_limit': num.tryParse(_creditCtr.text.trim()) ?? 0,
        if (_isEdit) 'status': _active ? 'active' : 'suspended',
      };
      final msg = _isEdit
          ? await api.updatePosPoint(widget.point!.id, data)
          : await api.createPosPoint(data);
      if (mounted) {
        Navigator.pop(context);
        ref.invalidate(accPosPointsProvider);
        PosManagementScreen._toast(context, msg, ok: true);
      }
    } catch (e) {
      if (mounted) PosManagementScreen._toast(context, '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final agentsAsync = ref.watch(accPosAgentsProvider);

    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 20,
          right: 20,
          top: 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_isEdit ? 'تعديل نقطة البيع' : 'إضافة نقطة بيع',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            TextField(
              controller: _nameCtr,
              decoration: const InputDecoration(
                labelText: 'اسم النقطة *',
                prefixIcon: Icon(Icons.storefront_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ownerCtr,
              decoration: const InputDecoration(
                labelText: 'اسم المالك/المشرف',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneCtr,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'الهاتف',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _locationCtr,
              decoration: const InputDecoration(
                labelText: 'الموقع / العنوان',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _creditCtr,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'حد البيع الآجل',
                prefixIcon: Icon(Icons.credit_card_outlined),
              ),
            ),
            const SizedBox(height: 12),
            agentsAsync.when(
              loading: () => const LinearProgressIndicator(minHeight: 2),
              error: (_, _) => const SizedBox.shrink(),
              data: (agents) => DropdownButtonFormField<int?>(
                initialValue: _agentId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'حساب نقطة البيع المرتبط',
                  prefixIcon: Icon(Icons.point_of_sale_outlined),
                ),
                items: [
                  const DropdownMenuItem(
                      value: null, child: Text('بدون ربط')),
                  ...agents.map((a) => DropdownMenuItem(
                        value: a.id,
                        child: Text(a.displayName,
                            overflow: TextOverflow.ellipsis),
                      )),
                ],
                onChanged: (v) => setState(() => _agentId = v),
              ),
            ),
            if (agentsAsync.valueOrNull?.isEmpty == true)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'لا توجد حسابات بدور «نقطة بيع» — أنشئها من شاشة المستخدمين',
                  style: TextStyle(fontSize: 11, color: AppColors.textGray),
                ),
              ),
            if (_isEdit)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title:
                    const Text('نقطة نشطة', style: TextStyle(fontSize: 14)),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(_isEdit ? 'حفظ التعديلات' : 'إنشاء النقطة'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _DevicesSheet extends ConsumerStatefulWidget {
  final AccPosPoint point;
  const _DevicesSheet({required this.point});

  @override
  ConsumerState<_DevicesSheet> createState() => _DevicesSheetState();
}

class _DevicesSheetState extends ConsumerState<_DevicesSheet> {
  final _nameCtr = TextEditingController();
  final _modelCtr = TextEditingController();
  final _uidCtr = TextEditingController();
  List<AccPosDevice>? _devices;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtr.dispose();
    _modelCtr.dispose();
    _uidCtr.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list =
          await ref.read(accApiProvider).posDevices(widget.point.id);
      if (mounted) setState(() => _devices = list);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _bind() async {
    if (_nameCtr.text.trim().isEmpty) {
      PosManagementScreen._toast(context, 'أدخل اسم الجهاز');
      return;
    }
    setState(() => _loading = true);
    try {
      final msg = await ref.read(accApiProvider).bindDevice(
        widget.point.id,
        {
          'device_name': _nameCtr.text.trim(),
          'model': _modelCtr.text.trim(),
          'device_uid': _uidCtr.text.trim(),
        },
      );
      _nameCtr.clear();
      _modelCtr.clear();
      _uidCtr.clear();
      await _load();
      ref.invalidate(accPosPointsProvider);
      if (mounted) PosManagementScreen._toast(context, msg, ok: true);
    } catch (e) {
      if (mounted) PosManagementScreen._toast(context, '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _unbind(AccPosDevice d) async {
    try {
      final msg = await ref
          .read(accApiProvider)
          .unbindDevice(widget.point.id, d.id);
      await _load();
      ref.invalidate(accPosPointsProvider);
      if (mounted) PosManagementScreen._toast(context, msg, ok: true);
    } catch (e) {
      if (mounted) PosManagementScreen._toast(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 20,
          right: 20,
          top: 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('أجهزة «${widget.point.name}»',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!,
                    style: const TextStyle(color: AppColors.error),
                    textAlign: TextAlign.center),
              ),
            if (_devices == null && _error == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if ((_devices ?? []).isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('لا توجد أجهزة مرتبطة',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textGray)),
              )
            else
              ..._devices!.map(
                (d) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.smartphone_outlined,
                      color: AppColors.primary),
                  title: Text(d.deviceName,
                      style: const TextStyle(fontSize: 14)),
                  subtitle: Text(
                    [
                      if (d.model?.isNotEmpty == true) d.model!,
                      if (d.deviceUid?.isNotEmpty == true)
                        'UID: ${d.deviceUid}',
                    ].join(' · '),
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.link_off,
                        color: AppColors.error, size: 20),
                    onPressed: () => _unbind(d),
                  ),
                ),
              ),
            const Divider(height: 24),
            const Text('ربط جهاز جديد',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            TextField(
              controller: _nameCtr,
              decoration: const InputDecoration(
                labelText: 'اسم الجهاز *',
                prefixIcon: Icon(Icons.smartphone_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _modelCtr,
              decoration: const InputDecoration(
                labelText: 'الموديل',
                prefixIcon: Icon(Icons.phone_android_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _uidCtr,
              decoration: const InputDecoration(
                labelText: 'معرّف الجهاز (UID) — يُملأ تلقائياً من التطبيق',
                prefixIcon: Icon(Icons.fingerprint),
              ),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: _loading ? null : _bind,
              icon: const Icon(Icons.add_link),
              label: const Text('ربط الجهاز'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
