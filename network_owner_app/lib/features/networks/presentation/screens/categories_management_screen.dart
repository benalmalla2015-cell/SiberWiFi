import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/networks_repository.dart';
import '../providers/networks_provider.dart';

class CategoriesManagementScreen extends ConsumerWidget {
  const CategoriesManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(categoriesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('إدارة فئات الكروت')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showFormSheet(context, ref, null),
        icon: const Icon(Icons.add),
        label: const Text('فئة جديدة'),
        backgroundColor: AppColors.primary,
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('خطأ: $e')),
        data: (categories) {
          if (categories.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.category_outlined, size: 64, color: AppColors.divider),
                  SizedBox(height: 12),
                  Text('لا توجد فئات', style: TextStyle(color: AppColors.textGray, fontSize: 16)),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: categories.length,
            itemBuilder: (_, i) => _CategoryCard(
              category: categories[i],
              onEdit: () => _showFormSheet(context, ref, categories[i]),
            ),
          );
        },
      ),
    );
  }

  void _showFormSheet(BuildContext context, WidgetRef ref, Map<String, dynamic>? category) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _CategoryFormSheet(category: category),
    );
  }
}

class _CategoryCard extends ConsumerWidget {
  final Map<String, dynamic> category;
  final VoidCallback onEdit;
  const _CategoryCard({required this.category, required this.onEdit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = category['name'] ?? 'فئة';
    final speed = category['speed'] ?? '';
    final duration = category['duration'];
    final unit = category['duration_unit'] ?? '';
    final price = (category['price'] ?? 0).toString();
    final value = (category['value'] ?? 0).toString();
    final isActive = category['is_active'] == true;
    final loanEnabled = category['advance_enabled'] == true;
    final loanLimit = category['advance_max_per_customer'];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.category, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    if (speed.isNotEmpty) Text(speed, style: const TextStyle(color: AppColors.textGray, fontSize: 12)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isActive ? AppColors.success.withValues(alpha: 0.1) : AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(isActive ? 'نشطة' : 'معطّلة', style: TextStyle(color: isActive ? AppColors.success : AppColors.error, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _Info(label: 'السعر', value: '$price ر.ي'),
              const SizedBox(width: 16),
              _Info(label: 'القيمة', value: '$value ر.ي'),
              if (duration != null) ...[
                const SizedBox(width: 16),
                _Info(label: 'المدة', value: '$duration $unit'),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (loanEnabled) ...[
                InkWell(
                  onTap: () => _toggleLoan(context, ref),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.account_balance_wallet_outlined, size: 13, color: AppColors.warning.withValues(alpha: 0.9)),
                        const SizedBox(width: 4),
                        Text(
                          'سلفني حتى ${loanLimit ?? '-'} كرت',
                          style: TextStyle(color: AppColors.warning.withValues(alpha: 0.9), fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              OutlinedButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('تعديل', style: TextStyle(fontSize: 13)),
                style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.primary)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _toggleLoan(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(networksRepositoryProvider);
    final loanEnabled = category['advance_enabled'] == true;
    try {
      await repo.updateAdvanceSettings(
        category['id'],
        advanceEnabled: !loanEnabled,
        advanceMaxPerCustomer: category['advance_max_per_customer'] as int?,
      );
      ref.invalidate(categoriesProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(!loanEnabled ? 'تم تفعيل سلفني للفئة' : 'تم إيقاف سلفني للفئة'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }
}

class _Info extends StatelessWidget {
  final String label, value;
  const _Info({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textGray, fontSize: 11)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
      ],
    );
  }
}

class _CategoryFormSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic>? category;
  const _CategoryFormSheet({this.category});

  @override
  ConsumerState<_CategoryFormSheet> createState() => _CategoryFormSheetState();
}

class _CategoryFormSheetState extends ConsumerState<_CategoryFormSheet> {
  final _nameCtrl = TextEditingController();
  final _speedCtrl = TextEditingController();
  final _durationCtrl = TextEditingController();
  final _unitCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _valueCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _loanLimitCtrl = TextEditingController();
  bool _isActive = true;
  bool _loanEnabled = false;
  bool _loading = false;
  int? _selectedNetworkId;

  @override
  void initState() {
    super.initState();
    final c = widget.category;
    if (c != null) {
      _nameCtrl.text = c['name'] ?? '';
      _speedCtrl.text = c['speed'] ?? '';
      _durationCtrl.text = c['duration']?.toString() ?? '';
      _unitCtrl.text = c['duration_unit'] ?? '';
      _priceCtrl.text = c['price']?.toString() ?? '';
      _valueCtrl.text = c['value']?.toString() ?? '';
      _descCtrl.text = c['description'] ?? '';
      _isActive = c['is_active'] == true;
      _loanEnabled = c['advance_enabled'] == true;
      _loanLimitCtrl.text = c['advance_max_per_customer']?.toString() ?? '';
      _selectedNetworkId = c['network_id'] is int ? c['network_id'] : int.tryParse('${c['network_id']}');
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _speedCtrl.dispose(); _durationCtrl.dispose(); _unitCtrl.dispose();
    _priceCtrl.dispose(); _valueCtrl.dispose(); _descCtrl.dispose(); _loanLimitCtrl.dispose();
    super.dispose();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: AppColors.error));
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final price = double.tryParse(_priceCtrl.text.trim());
    final value = double.tryParse(_valueCtrl.text.trim());
    if (name.isEmpty || price == null || value == null) {
      _showError('أكمل الحقول المطلوبة');
      return;
    }

    int? loanLimit;
    if (_loanEnabled) {
      loanLimit = int.tryParse(_loanLimitCtrl.text.trim());
      if (loanLimit == null || loanLimit <= 0) {
        _showError('أدخل حد كروت سلفني صحيح (رقم موجب)');
        return;
      }
    }

    final repo = ref.read(networksRepositoryProvider);
    final data = {
      'name': name,
      'speed': _speedCtrl.text.trim(),
      'duration': int.tryParse(_durationCtrl.text.trim()),
      'duration_unit': _unitCtrl.text.trim(),
      'price': price,
      'value': value,
      'description': _descCtrl.text.trim(),
      'is_active': _isActive ? 1 : 0,
      'advance_enabled': _loanEnabled ? 1 : 0,
      if (_loanEnabled) 'advance_max_per_customer': loanLimit,
    };
    setState(() => _loading = true);
    try {
      if (widget.category == null) {
        final networks = await repo.getNetworks();
        final networkId = _selectedNetworkId ?? networks.firstOrNull?['id'];
        if (networkId == null) {
          _showError('لا توجد شبكة مرتبطة');
          return;
        }
        data['network_id'] = networkId;
        await repo.createCategory(data);
      } else {
        await repo.updateCategory(widget.category!['id'], data);
      }
      ref.invalidate(categoriesProvider);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(widget.category == null ? 'تمت إضافة الفئة' : 'تم تحديث الفئة'),
          backgroundColor: AppColors.success,
        ));
      }
    } catch (e) {
      if (mounted) _showError('خطأ: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.category != null;
    final networksAsync = ref.watch(networksProvider);
    final networks = networksAsync.value ?? [];
    if (!isEdit && _selectedNetworkId == null && networks.isNotEmpty) {
      _selectedNetworkId = networks.first['id'] is int
          ? networks.first['id']
          : int.tryParse('${networks.first['id']}');
    }

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(isEdit ? 'تعديل الفئة' : 'فئة جديدة', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
            const SizedBox(height: 20),
            if (!isEdit && networks.length > 1) ...[
              DropdownButtonFormField<int>(
                value: _selectedNetworkId,
                decoration: const InputDecoration(labelText: 'الشبكة *', prefixIcon: Icon(Icons.wifi)),
                isExpanded: true,
                items: networks.map((n) {
                  final id = n['id'] is int ? n['id'] as int : int.tryParse('${n['id']}') ?? 0;
                  return DropdownMenuItem<int>(value: id, child: Text('${n['name'] ?? ''}', overflow: TextOverflow.ellipsis));
                }).toList(),
                onChanged: (v) => setState(() => _selectedNetworkId = v),
                validator: (v) => v == null ? 'اختر شبكة' : null,
              ),
              const SizedBox(height: 12),
            ],
            TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'اسم الفئة *')),
            const SizedBox(height: 12),
            TextField(controller: _speedCtrl, decoration: const InputDecoration(labelText: 'السرعة (مثال: 2 Mbps)')),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: TextField(controller: _durationCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'المدة'))),
                const SizedBox(width: 12),
                Expanded(child: TextField(controller: _unitCtrl, decoration: const InputDecoration(labelText: 'الوحدة (يوم/أسبوع...)'))),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: TextField(controller: _priceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'سعر البيع *'))),
                const SizedBox(width: 12),
                Expanded(child: TextField(controller: _valueCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'قيمة الكرت *'))),
              ],
            ),
            const SizedBox(height: 12),
            TextField(controller: _descCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'الوصف')),
            const SizedBox(height: 8),
            SwitchListTile(
              value: _isActive,
              onChanged: (v) => setState(() => _isActive = v),
              title: const Text('نشطة'),
              activeColor: AppColors.primary,
            ),
            SwitchListTile(
              value: _loanEnabled,
              onChanged: (v) => setState(() => _loanEnabled = v),
              title: const Text('تفعيل سلفني'),
              subtitle: const Text('السماح للعميل بشراء كروت هذه الفئة بالدين ضمن حد معين', style: TextStyle(fontSize: 12)),
              activeColor: AppColors.primary,
            ),
            if (_loanEnabled) ...[
              const SizedBox(height: 4),
              TextField(
                controller: _loanLimitCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'الحد الأقصى لعدد الكروت المسموح بها سلفني للعميل',
                ),
              ),
            ],
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _loading ? null : _submit,
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              child: _loading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(isEdit ? 'حفظ التعديلات' : 'إضافة الفئة', style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
