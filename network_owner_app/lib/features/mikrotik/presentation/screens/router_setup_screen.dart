import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/router_model.dart';
import '../../data/router_os_service.dart';
import '../providers/mikrotik_provider.dart';

class RouterSetupScreen extends ConsumerStatefulWidget {
  final MikrotikRouterConfig? existing;
  const RouterSetupScreen({super.key, this.existing});

  @override
  ConsumerState<RouterSetupScreen> createState() => _RouterSetupScreenState();
}

class _RouterSetupScreenState extends ConsumerState<RouterSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _nameCtrl =
      TextEditingController(text: widget.existing?.name ?? '');
  late final _hostCtrl =
      TextEditingController(text: widget.existing?.host ?? '');
  late final _portCtrl = TextEditingController(
      text: (widget.existing?.port ?? 8728).toString());
  late final _userCtrl =
      TextEditingController(text: widget.existing?.username ?? 'admin');
  late final _passCtrl =
      TextEditingController(text: widget.existing?.password ?? '');
  late bool _useSsl = widget.existing?.useSsl ?? false;
  bool _testing = false;
  String? _testResult;
  bool _testOk = false;
  bool _obscure = true;

  MikrotikRouterConfig get _config => MikrotikRouterConfig(
        id: widget.existing?.id ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        name: _nameCtrl.text.trim(),
        host: _hostCtrl.text.trim(),
        port: int.tryParse(_portCtrl.text.trim()) ?? (_useSsl ? 8729 : 8728),
        username: _userCtrl.text.trim(),
        password: _passCtrl.text,
        useSsl: _useSsl,
        createdAt: widget.existing?.createdAt ?? DateTime.now(),
      );

  @override
  void dispose() {
    _nameCtrl.dispose();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final name = await RouterOsService.testConnection(_config);
      setState(() {
        _testOk = true;
        _testResult = 'تم الاتصال بنجاح — الجهاز: $name';
      });
    } catch (e) {
      setState(() {
        _testOk = false;
        _testResult = 'فشل الاتصال: ${_friendly(e)}';
      });
    } finally {
      setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    await ref.read(routersProvider.notifier).save(_config);
    if (mounted) context.pop();
  }

  String _friendly(Object e) {
    final s = e.toString();
    if (s.contains('timed out') || s.contains('TimeoutException')) {
      return 'انتهت مهلة الاتصال — تأكد من العنوان والمنفذ ووجودك على شبكة الراوتر';
    }
    if (s.contains('refused')) return 'تم رفض الاتصال — فعّل خدمة API في الراوتر';
    return s.length > 120 ? s.substring(0, 120) : s;
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar:
          AppBar(title: Text(isEdit ? 'تعديل الراوتر' : 'إضافة راوتر MikroTik')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _HeaderCard(isEdit: isEdit),
            const SizedBox(height: 20),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'اسم الراوتر (اختياري)',
                prefixIcon: Icon(Icons.label_outline),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _hostCtrl,
              decoration: const InputDecoration(
                labelText: 'عنوان IP أو اسم المضيف',
                hintText: '192.168.88.1',
                prefixIcon: Icon(Icons.dns_outlined),
              ),
              keyboardType: TextInputType.url,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'أدخل عنوان الراوتر' : null,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _portCtrl,
                    decoration: const InputDecoration(
                      labelText: 'المنفذ',
                      prefixIcon: Icon(Icons.settings_ethernet),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (v) =>
                        (int.tryParse(v ?? '') == null) ? 'منفذ غير صالح' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.inputBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('اتصال آمن TLS',
                          style: TextStyle(fontSize: 13)),
                      value: _useSsl,
                      activeThumbColor: AppColors.primary,
                      onChanged: (v) {
                        setState(() {
                          _useSsl = v;
                          _portCtrl.text = v ? '8729' : '8728';
                        });
                      },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _userCtrl,
              decoration: const InputDecoration(
                labelText: 'اسم المستخدم',
                prefixIcon: Icon(Icons.person_outline),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'أدخل اسم المستخدم' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _passCtrl,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'كلمة المرور',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(_obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            if (_testResult != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (_testOk ? AppColors.success : AppColors.accent)
                      .withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: (_testOk ? AppColors.success : AppColors.accent)
                        .withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _testOk ? Icons.check_circle : Icons.error_outline,
                      color: _testOk ? AppColors.success : AppColors.accent,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_testResult!,
                          style: TextStyle(
                              color: _testOk
                                  ? AppColors.success
                                  : AppColors.accent,
                              fontSize: 13)),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _testing ? null : _test,
                    icon: _testing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.wifi_tethering),
                    label: Text(_testing ? 'جارٍ الفحص…' : 'اختبار الاتصال'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(isEdit ? 'حفظ التعديلات' : 'حفظ الراوتر'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const _SecurityNote(),
          ],
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final bool isEdit;
  const _HeaderCard({required this.isEdit});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF16235F), Color(0xFF1E2D7D), Color(0xFF2A3A9A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.router, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isEdit ? 'تحديث بيانات الراوتر' : 'ربط راوتر جديد',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 17)),
                const SizedBox(height: 4),
                const Text('اتصال مباشر عبر RouterOS API',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SecurityNote extends StatelessWidget {
  const _SecurityNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.25)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_outlined, color: AppColors.warning, size: 20),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'بيانات الدخول تُحفظ مشفّرة على جهازك فقط ولا تُرسل لأي خادم. يُنصح بإنشاء مستخدم RouterOS بصلاحيات محدودة مخصص للتطبيق.',
              style: TextStyle(fontSize: 11, color: AppColors.textGray),
            ),
          ),
        ],
      ),
    );
  }
}
