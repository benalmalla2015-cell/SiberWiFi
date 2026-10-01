import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/api/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/connectivity_service.dart';
import '../../../../core/utils/json_helpers.dart';
import '../providers/auth_provider.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _form       = GlobalKey<FormState>();
  final _nameCt     = TextEditingController();
  final _phoneCt    = TextEditingController();
  final _passCt     = TextEditingController();
  final _confCt     = TextEditingController();
  final _referralCt = TextEditingController();
  bool  _obscure  = true;
  bool  _obscure2 = true;
  bool  _loading  = false;

  List<Map<String, dynamic>> _regions      = [];
  List<Map<String, dynamic>> _directorates = [];
  int?   _regionId;
  int?   _directorateId;
  bool   _loadingRegions = false;
  String? _regionsError;

  @override
  void initState() {
    super.initState();
    _loadRegions();
  }

  @override
  void dispose() {
    _nameCt.dispose(); _phoneCt.dispose();
    _passCt.dispose(); _confCt.dispose(); _referralCt.dispose();
    super.dispose();
  }

  Future<void> _loadRegions() async {
    setState(() { _loadingRegions = true; _regionsError = null; });
    try {
      final online = await ConnectivityService.isConnected();
      if (!online) { setState(() { _loadingRegions = false; _regionsError = 'لا يوجد اتصال بالإنترنت'; }); return; }
      final api = ref.read(apiClientProvider);
      final res = await api.get('/regions');
      setState(() {
        _regions = toMapList(res.data['data'] ?? res.data ?? []);
        _loadingRegions = false;
      });
    } catch (e) {
      setState(() { _loadingRegions = false; _regionsError = 'تعذر تحميل المناطق'; });
    }
  }

  Future<void> _loadDirectorates(int regionId) async {
    setState(() { _directorates = []; _directorateId = null; });
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.get('/regions/$regionId/directorates');
      setState(() {
        _directorates = toMapList(res.data['data'] ?? res.data ?? []);
      });
    } catch (_) {}
  }

  String _normalizeReferral(String value) {
    final trimmed = value.trim();
    final match = RegExp(r'[?&]ref=([^&\s]+)').firstMatch(trimmed);
    return match != null ? Uri.decodeComponent(match.group(1)!).trim() : trimmed;
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (_regionId == null || _directorateId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اختر المنطقة والمديرية'), backgroundColor: AppColors.accent));
      return;
    }
    setState(() => _loading = true);
    final err = await ref.read(authProvider.notifier).register(
      name:          _nameCt.text.trim(),
      phone:         _phoneCt.text.trim(),
      password:      _passCt.text,
      regionId:      _regionId,
      directorateId: _directorateId,
      referralCode:  _normalizeReferral(_referralCt.text),
    );
    if (!mounted) return;
    setState(() => _loading = false);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), backgroundColor: AppColors.accent),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildHeader(size),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 24),
                    const Text('إنشاء حساب جديد',
                        style: TextStyle(fontFamily: 'Cairo', fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textDark),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 4),
                    const Text('أدخل بياناتك لإنشاء حسابك',
                        style: TextStyle(fontFamily: 'Cairo', fontSize: 14, color: AppColors.textGray),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _nameCt,
                      decoration: const InputDecoration(labelText: 'الاسم الكامل *', prefixIcon: Icon(Icons.person_outline_rounded)),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'أدخل اسمك الكامل' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phoneCt,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: 'رقم الجوال *', prefixIcon: Icon(Icons.phone_android_rounded)),
                      validator: (v) => (v == null || v.trim().length < 9) ? 'أدخل رقم جوال صحيح' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _passCt,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        labelText: 'كلمة المرور *',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) => (v == null || v.length < 6) ? 'على الأقل 6 أحرف' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _confCt,
                      obscureText: _obscure2,
                      decoration: InputDecoration(
                        labelText: 'إعادة كلمة المرور *',
                        prefixIcon: const Icon(Icons.lock_rounded),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure2 ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                          onPressed: () => setState(() => _obscure2 = !_obscure2),
                        ),
                      ),
                      validator: (v) => v != _passCt.text ? 'كلمتا المرور غير متطابقتين' : null,
                    ),
                    const SizedBox(height: 12),
                    _buildRegionDropdown(),
                    const SizedBox(height: 12),
                    _buildDirectorateDropdown(),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _referralCt,
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.left,
                      decoration: InputDecoration(
                        labelText: 'كود الإحالة (اختياري)',
                        prefixIcon: const Icon(Icons.card_giftcard_outlined),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.paste_outlined),
                          onPressed: () async {
                            final data = await Clipboard.getData(Clipboard.kTextPlain);
                            if (data?.text != null) {
                              _referralCt.text = _normalizeReferral(data!.text!);
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: _loading
                            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                            : const Directionality(
                                textDirection: TextDirection.rtl,
                                child: Text('إنشاء الحساب', style: TextStyle(fontFamily: 'Cairo', fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white)),
                              ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('لديك حساب بالفعل؟', style: TextStyle(fontFamily: 'Cairo', color: AppColors.textGray)),
                        TextButton(
                          onPressed: () => context.go('/login'),
                          child: const Text('تسجيل الدخول', style: TextStyle(fontFamily: 'Cairo', color: AppColors.primary, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRegionDropdown() {
    if (_loadingRegions) return const LinearProgressIndicator(color: AppColors.primary);
    if (_regionsError != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(border: Border.all(color: AppColors.accent), borderRadius: BorderRadius.circular(12), color: const Color(0xFFFEE2E2)),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: AppColors.accent, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(_regionsError!, style: const TextStyle(fontFamily: 'Cairo', color: AppColors.accent, fontSize: 13))),
            TextButton(onPressed: _loadRegions, child: const Text('إعادة', style: TextStyle(fontFamily: 'Cairo', color: AppColors.primary))),
          ],
        ),
      );
    }
    return DropdownButtonFormField<int>(
      value: _regionId,
      decoration: const InputDecoration(labelText: 'المنطقة *', prefixIcon: Icon(Icons.location_city_outlined)),
      items: _regions.map((r) => DropdownMenuItem<int>(
        value: r['id'] as int,
        child: Text(r['name'] ?? '', style: const TextStyle(fontFamily: 'Cairo')),
      )).toList(),
      onChanged: (v) {
        setState(() { _regionId = v; _directorateId = null; _directorates = []; });
        if (v != null) _loadDirectorates(v);
      },
      validator: (v) => v == null ? 'اختر المنطقة' : null,
    );
  }

  Widget _buildDirectorateDropdown() {
    return DropdownButtonFormField<int>(
      value: _directorateId,
      decoration: const InputDecoration(labelText: 'المديرية *', prefixIcon: Icon(Icons.map_outlined)),
      items: _directorates.map((d) => DropdownMenuItem<int>(
        value: d['id'] as int,
        child: Text(d['name'] ?? '', style: const TextStyle(fontFamily: 'Cairo')),
      )).toList(),
      onChanged: (v) => setState(() => _directorateId = v),
      validator: (v) => v == null ? 'اختر المديرية' : null,
    );
  }

  Widget _buildHeader(Size size) {
    return Container(
      width: double.infinity,
      height: size.height * 0.22,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF16235F), Color(0xFF1E2D7D), Color(0xFF243490)],
          stops: [0.0, 0.5, 1.0],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(40),
          bottomRight: Radius.circular(40),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 16, offset: const Offset(0, 6))],
            ),
            padding: const EdgeInsets.all(10),
            child: Image.asset('logoapp/logo.png', fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(Icons.wifi_rounded, color: AppColors.primary, size: 36)),
          ),
          const SizedBox(width: 14),
          const Text('سايبر WiFi',
              style: TextStyle(fontFamily: 'Cairo', fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
        ],
      ),
    );
  }
}
