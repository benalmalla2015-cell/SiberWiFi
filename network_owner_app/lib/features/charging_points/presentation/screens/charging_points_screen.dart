import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/api/api_client.dart';
import '../../../../core/cache/hive_service.dart';
import '../../../../core/utils/connectivity_service.dart';
import '../../../../core/utils/json_helpers.dart';
import '../../../networks/presentation/providers/networks_provider.dart';

final chargingPointsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  // Always hit the live backend first; only fall back to local cache when
  // the device is truly offline or the API call fails.
  try {
    final api  = ref.read(apiClientProvider);
    final res  = await api.get('/network-owner/charging-points');
    final list = toMapList(res.data['data']);
    await HiveService.networksBox.put('charging_points', list);
    return list;
  } catch (_) {
    final online = await ConnectivityService.isConnected();
    if (!online) {
      final c = HiveService.networksBox.get('charging_points');
      if (c != null) return toMapList(c);
    }
    rethrow;
  }
});

class ChargingPointsScreen extends ConsumerWidget {
  const ChargingPointsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cpAsync = ref.watch(chargingPointsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('نقاط الشحن')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddEditSheet(context, ref, null),
        icon: const Icon(Icons.add_location_alt),
        label: const Text('إضافة نقطة'),
        backgroundColor: AppColors.primary,
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(chargingPointsProvider),
        child: cpAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error:   (e, _) => _buildErrorWidget(context, ref, e),
          data: (points) {
            if (points.isEmpty) {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.ev_station, size: 64, color: AppColors.divider),
                    SizedBox(height: 12),
                    Text('لا توجد نقاط شحن', style: TextStyle(color: AppColors.textGray, fontSize: 16)),
                    SizedBox(height: 6),
                    Text('اضغط + لإضافة نقطة شحن جديدة', style: TextStyle(color: AppColors.textGray, fontSize: 12)),
                  ],
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: points.length,
              itemBuilder: (_, i) => _ChargingPointCard(
                point: points[i],
                onEdit: () => _showAddEditSheet(context, ref, points[i]),
                onDelete: () => _confirmDelete(context, ref, points[i]['id']),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildErrorWidget(BuildContext ctx, WidgetRef ref, Object e) {
    return FutureBuilder<bool>(
      future: ConnectivityService.isConnected(),
      builder: (context, snapshot) {
        final isOffline = snapshot.data == false;
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isOffline ? Icons.signal_wifi_off_rounded : Icons.error_outline_rounded,
                  size: 64,
                  color: AppColors.textLight,
                ),
                const SizedBox(height: 16),
                Text(
                  isOffline ? 'لا يوجد اتصال بالإنترنت' : 'تعذّر تحميل نقاط الشحن',
                  style: const TextStyle(color: AppColors.textGray, fontSize: 16),
                ),
                const SizedBox(height: 8),
                if (!isOffline)
                  Text(
                    e.toString(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textGray, fontSize: 12),
                  ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => ref.invalidate(chargingPointsProvider),
                  child: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(BuildContext ctx, WidgetRef ref, int id) async {
    final confirm = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('حذف نقطة الشحن'),
        content: const Text('هل أنت متأكد من حذف هذه النقطة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        final api = ref.read(apiClientProvider);
        await api.delete('/network-owner/charging-points/$id');
        ref.invalidate(chargingPointsProvider);
        if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('تم الحذف'), backgroundColor: AppColors.success));
      } catch (e) {
        if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: AppColors.error));
      }
    }
  }

  void _showAddEditSheet(BuildContext ctx, WidgetRef ref, Map<String, dynamic>? point) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _AddEditChargingPointSheet(ref: ref, point: point),
    );
  }
}

class _ChargingPointCard extends StatelessWidget {
  final Map<String, dynamic> point;
  final VoidCallback onEdit, onDelete;
  const _ChargingPointCard({required this.point, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final name       = point['name'] ?? 'نقطة شحن';
    final address    = point['address'] ?? point['location'] ?? '';
    final phone      = point['phone'] ?? '';
    final isActive   = point['is_active'] == true;
    final isApproved = point['is_approved'] == true;
    final network    = point['network']?['name'] ?? point['network_name'] ?? '';
    final hours      = point['working_hours'] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.lightBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.ev_station, color: AppColors.lightBlue, size: 26),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      if (network.isNotEmpty) Text(network, style: const TextStyle(color: AppColors.lightBlue, fontSize: 11)),
                    ],
                  ),
                ),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isActive ? AppColors.success.withValues(alpha: 0.1) : AppColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      isActive ? 'نشطة' : 'معطّلة',
                      style: TextStyle(color: isActive ? AppColors.success : AppColors.error, fontSize: 11, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
            if (!isApproved) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.lightBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.hourglass_top, size: 12, color: AppColors.lightBlue),
                    SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'بانتظار موافقة المشرف',
                        style: TextStyle(color: AppColors.lightBlue, fontSize: 11, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (address.isNotEmpty || hours.isNotEmpty || phone.isNotEmpty) ...[
              const SizedBox(height: 10),
              if (address.isNotEmpty)
                Row(children: [
                  const Icon(Icons.location_on_outlined, size: 14, color: AppColors.textGray),
                  const SizedBox(width: 4),
                  Expanded(child: Text(address, style: const TextStyle(fontSize: 12, color: AppColors.textGray), maxLines: 2, overflow: TextOverflow.ellipsis)),
                ]),
              if (phone.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.phone_outlined, size: 14, color: AppColors.textGray),
                  const SizedBox(width: 4),
                  Expanded(child: Text(phone, style: const TextStyle(fontSize: 12, color: AppColors.textGray), maxLines: 1, overflow: TextOverflow.ellipsis)),
                ]),
              ],
              if (hours.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.access_time, size: 14, color: AppColors.textGray),
                  const SizedBox(width: 4),
                  Expanded(child: Text(hours, style: const TextStyle(fontSize: 12, color: AppColors.textGray), maxLines: 1, overflow: TextOverflow.ellipsis)),
                ]),
              ],
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 15),
                    label: const Text('تعديل', style: TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis, maxLines: 1),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      side: const BorderSide(color: AppColors.primary),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline, size: 15, color: AppColors.error),
                    label: const Text('حذف', style: TextStyle(fontSize: 13, color: AppColors.error), overflow: TextOverflow.ellipsis, maxLines: 1),
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
}

class _AddEditChargingPointSheet extends ConsumerStatefulWidget {
  final WidgetRef ref;
  final Map<String, dynamic>? point;
  const _AddEditChargingPointSheet({required this.ref, this.point});

  @override
  ConsumerState<_AddEditChargingPointSheet> createState() => _AddEditChargingPointSheetState();
}

class _AddEditChargingPointSheetState extends ConsumerState<_AddEditChargingPointSheet> {
  final _nameCtr    = TextEditingController();
  final _customerPhoneCtr = TextEditingController();
  final _phoneCtr   = TextEditingController();
  final _addressCtr = TextEditingController();
  final _hoursCtr   = TextEditingController();
  bool _loading = false;
  bool _isEdit  = false;
  bool _isActive = true;
  int? _selectedNetworkId;

  @override
  void initState() {
    super.initState();
    final p = widget.point;
    if (p != null) {
      _isEdit = true;
      _nameCtr.text    = p['name']    ?? '';
      _customerPhoneCtr.text = p['customer_phone'] ?? '';
      _phoneCtr.text   = p['phone']   ?? '';
      _addressCtr.text = p['address'] ?? p['location'] ?? '';
      _hoursCtr.text   = p['working_hours'] ?? '';
      _isActive        = p['is_active'] == true;
      _selectedNetworkId = p['network_id'] is int
          ? p['network_id']
          : int.tryParse('${p['network_id']}');
    }
  }

  @override
  void dispose() {
    _nameCtr.dispose(); _customerPhoneCtr.dispose(); _phoneCtr.dispose(); _addressCtr.dispose(); _hoursCtr.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_nameCtr.text.trim().isEmpty && (_isEdit || _customerPhoneCtr.text.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل اسم النقطة أو رقم جوال العميل'), backgroundColor: AppColors.error));
      return;
    }
    if (!_isEdit && _customerPhoneCtr.text.isNotEmpty && _customerPhoneCtr.text.length != 9) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يجب أن يتكون رقم جوال العميل من 9 أرقام'), backgroundColor: AppColors.error));
      return;
    }
    setState(() => _loading = true);
    try {
      final api  = ref.read(apiClientProvider);
      final data = {
        'name':          _nameCtr.text.trim(),
        if (!_isEdit && _customerPhoneCtr.text.isNotEmpty) 'customer_phone': _customerPhoneCtr.text.trim(),
        'phone':         _phoneCtr.text.trim(),
        'address':       _addressCtr.text.trim(),
        'working_hours': _hoursCtr.text.trim(),
        if (_selectedNetworkId != null) 'network_id': _selectedNetworkId,
        if (_isEdit) 'is_active': _isActive,
      };
      if (_isEdit) {
        await api.put('/network-owner/charging-points/${widget.point!['id']}', data: data);
      } else {
        await api.post('/network-owner/charging-points', data: data);
      }
      if (mounted) {
        Navigator.pop(context);
        ref.invalidate(chargingPointsProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEdit
                ? 'تم التعديل بنجاح'
                : 'تمت الإضافة بنجاح، بانتظار موافقة المشرف'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final networksAsync = ref.watch(networksProvider);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_isEdit ? 'تعديل نقطة الشحن' : 'إضافة نقطة شحن جديدة', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
            const SizedBox(height: 20),
            networksAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
              data: (networks) {
                if (networks.length <= 1) return const SizedBox.shrink();
                _selectedNetworkId ??= networks.first['id'] is int
                    ? networks.first['id']
                    : int.tryParse('${networks.first['id']}');
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: DropdownButtonFormField<int>(
                    // ignore: deprecated_member_use
                    value: _selectedNetworkId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'الشبكة *', prefixIcon: Icon(Icons.wifi)),
                    items: networks.map((n) {
                      final id = n['id'] is int ? n['id'] as int : int.tryParse('${n['id']}');
                      return DropdownMenuItem<int>(
                        value: id,
                        child: Text(
                          '${n['name'] ?? ''}',
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      );
                    }).toList(),
                    onChanged: (v) => setState(() => _selectedNetworkId = v),
                  ),
                );
              },
            ),
            TextField(controller: _nameCtr, decoration: const InputDecoration(labelText: 'اسم النقطة (اختياري عند إدخال عميل)', prefixIcon: Icon(Icons.ev_station))),
            if (!_isEdit) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _customerPhoneCtr,
                keyboardType: TextInputType.phone,
                maxLength: 9,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(9)],
                decoration: const InputDecoration(labelText: 'رقم جوال العميل في تطبيق العملاء', prefixIcon: Icon(Icons.person_add_alt_1_outlined)),
              ),
            ],
            const SizedBox(height: 12),
            TextField(controller: _phoneCtr, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم هاتف نقطة الشحن', prefixIcon: Icon(Icons.phone_outlined))),
            const SizedBox(height: 12),
            TextField(controller: _addressCtr, decoration: const InputDecoration(labelText: 'العنوان / الموقع', prefixIcon: Icon(Icons.location_on_outlined))),
            const SizedBox(height: 12),
            TextField(controller: _hoursCtr, decoration: const InputDecoration(labelText: 'ساعات العمل', prefixIcon: Icon(Icons.access_time), hintText: 'مثال: 8ص - 10م')),
            if (_isEdit) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('نشطة / متوفرة', style: TextStyle(fontSize: 14)),
                value: _isActive,
                onChanged: (v) => setState(() => _isActive = v),
              ),
            ],
            const SizedBox(height: 12),
            if (!_isEdit)
              const Text(
                'ملاحظة: ستظهر نقطة الشحن للمستخدمين بعد موافقة المشرف عليها.',
                style: TextStyle(fontSize: 12, color: AppColors.textGray),
              ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _loading ? null : _submit,
              icon: _loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.save_outlined),
              label: Text(_isEdit ? 'حفظ التعديلات' : 'إضافة النقطة'),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
