import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/api/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/json_helpers.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  List<Map<String, dynamic>> _directorates = [];
  int? _directorateId;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authProvider).user;
    _nameController = TextEditingController(text: user?.name ?? '');
    _emailController = TextEditingController(text: user?.email ?? '');
    _directorateId = user?.directorateId;
    if (user?.regionId != null) _loadDirectorates(user!.regionId!);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _loadDirectorates(int regionId) async {
    try {
      final response = await ref.read(apiClientProvider).get('/regions/$regionId/directorates');
      if (!mounted) return;
      setState(() => _directorates = toMapList(response.data['data']));
    } catch (_) {}
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await ref.read(apiClientProvider).put('/profile', data: {
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
        'directorate_id': _directorateId,
      });
      await ref.read(authProvider.notifier).refreshProfile();
      if (mounted) {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/profile');
        }
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر حفظ البيانات'), backgroundColor: AppColors.accent));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    return Scaffold(
      appBar: AppBar(title: const Text('بيانات الحساب')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(controller: _nameController, decoration: const InputDecoration(labelText: 'الاسم الكامل'), validator: (value) {
                final v = value?.trim() ?? '';
                if (v.isEmpty) return 'أدخل الاسم';
                if (v.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length < 4) {
                  return 'يجب إدخال الاسم الرباعي على الأقل';
                }
                return null;
              }),
              const SizedBox(height: 14),
              TextFormField(controller: _emailController, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'البريد الإلكتروني (اختياري)'), validator: (value) => value != null && value.isNotEmpty && !value.contains('@') ? 'أدخل بريداً صحيحاً' : null),
              const SizedBox(height: 14),
              TextFormField(initialValue: user?.phone ?? '', enabled: false, decoration: const InputDecoration(labelText: 'رقم الجوال')),
              const SizedBox(height: 14),
              TextFormField(initialValue: user?.regionName ?? '', enabled: false, decoration: const InputDecoration(labelText: 'المنطقة')),
              const SizedBox(height: 14),
              DropdownButtonFormField<int>(
                value: _directorateId,
                decoration: const InputDecoration(labelText: 'المديرية'),
                items: _directorates.map((directorate) => DropdownMenuItem(value: directorate['id'] as int, child: Text(directorate['name']?.toString() ?? ''))).toList(),
                onChanged: (value) => setState(() => _directorateId = value),
                validator: (value) => value == null ? 'اختر المديرية' : null,
              ),
              const SizedBox(height: 10),
              const Text('يمكنك تغيير المديرية ضمن منطقتك فقط.', style: TextStyle(fontFamily: 'Cairo', color: AppColors.textGray, fontSize: 12)),
              const SizedBox(height: 28),
              ElevatedButton(onPressed: _loading ? null : _save, child: _loading ? const CircularProgressIndicator(color: Colors.white) : const Text('حفظ التغييرات')),
            ],
          ),
        ),
      ),
    );
  }
}
