// device_info_plus temporarily unused — will be re-enabled with device lock
// import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/api/api_client.dart';
import '../../../../core/services/device_identity_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/connectivity_service.dart';
import '../../../../core/utils/json_helpers.dart';
import '../../../../core/widgets/app_button.dart';
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
  bool  _formattingReferral = false;

  List<Map<String, dynamic>> _regions         = [];
  List<Map<String, dynamic>> _directorates      = [];
  List<Map<String, dynamic>> _subDirectorates  = [];
  int?   _regionId;
  int?   _directorateId;
  int?   _subDirectorateId;
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
    setState(() {
      _directorates = [];
      _directorateId = null;
      _subDirectorateId = null;
      _subDirectorates = [];
    });
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.get('/regions/$regionId/directorates');
      setState(() {
        _directorates = toMapList(res.data['data'] ?? res.data ?? []);
      });
    } catch (_) {}
  }

  Future<void> _loadSubDirectorates(int directorateId) async {
    setState(() {
      _subDirectorates = [];
      _subDirectorateId = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.get('/directorates/$directorateId/sub-directorates');
      setState(() {
        _subDirectorates = toMapList(res.data['data'] ?? res.data ?? []);
      });
    } catch (_) {}
  }

  String _normalizeReferral(String value) {
    final trimmed = value.trim();
    final match = RegExp(r'[?&]ref=([^&\s]+)').firstMatch(trimmed);
    return match != null ? Uri.decodeComponent(match.group(1)!).trim() : trimmed;
  }

  void _formatReferralAsLink(String value) {
    if (_formattingReferral || value.contains('://')) return;
    final code = value.trim();
    if (!RegExp(r'^[A-Za-z0-9]{6,}$').hasMatch(code)) return;
    final link = 'https://saiberwifi.net/register?ref=$code';
    _formattingReferral = true;
    _referralCt.value = TextEditingValue(
      text: link,
      selection: TextSelection.collapsed(offset: link.length),
    );
    _formattingReferral = false;
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (_regionId == null || _directorateId == null || _subDirectorateId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اختر المنطقة والمحافظة والمديرية'), backgroundColor: AppColors.accent));
      return;
    }
    setState(() => _loading = true);
    String? err;
    try {
      final deviceId = await DeviceIdentityService.getId();
      err = await ref.read(authProvider.notifier).register(
        name:          _nameCt.text.trim(),
        phone:         _phoneCt.text.trim(),
        password:      _passCt.text,
        regionId:         _regionId,
        directorateId:    _directorateId,
        subDirectorateId: _subDirectorateId,
        referralCode:     _normalizeReferral(_referralCt.text),
        deviceId:         deviceId,
      );
    } catch (_) {
      err = 'تعذر التحقق من هوية الجهاز';
    }
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
                      validator: (v) => (v == null || v.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty).length < 4) ? 'يجب إدخال الاسم الرباعي على الأقل' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phoneCt,
                      keyboardType: TextInputType.phone,
                      maxLength: 9,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(9)],
                      decoration: const InputDecoration(labelText: 'رقم الجوال *', prefixIcon: Icon(Icons.phone_android_rounded)),
                      validator: (v) => (v == null || v.trim().length != 9) ? 'يجب أن يتكون رقم الجوال من 9 أرقام' : null,
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
                    _buildSubDirectorateDropdown(),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _referralCt,
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.left,
                      keyboardType: TextInputType.url,
                      onChanged: _formatReferralAsLink,
                      decoration: InputDecoration(
                        labelText: 'كود الإحالة (اختياري)',
                        prefixIcon: const Icon(Icons.card_giftcard_outlined),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.paste_outlined),
                          onPressed: () async {
                            final data = await Clipboard.getData(Clipboard.kTextPlain);
                            if (data?.text != null) {
                              final code = _normalizeReferral(data!.text!);
                              final link = 'https://saiberwifi.net/register?ref=$code';
                              _referralCt.value = TextEditingValue(
                                text: link,
                                selection: TextSelection.collapsed(offset: link.length),
                              );
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    AppButton(
                      label: 'إنشاء الحساب',
                      height: 56,
                      fontSize: 17,
                      isLoading: _loading,
                      onPressed: _submit,
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
        setState(() {
          _regionId = v;
          _directorateId = null;
          _directorates = [];
          _subDirectorateId = null;
          _subDirectorates = [];
        });
        if (v != null) _loadDirectorates(v);
      },
      validator: (v) => v == null ? 'اختر المنطقة' : null,
    );
  }

  Widget _buildDirectorateDropdown() {
    return DropdownButtonFormField<int>(
      value: _directorateId,
      decoration: const InputDecoration(labelText: 'المحافظة *', prefixIcon: Icon(Icons.map_outlined)),
      items: _directorates.map((d) => DropdownMenuItem<int>(
        value: d['id'] as int,
        child: Text(d['name'] ?? '', style: const TextStyle(fontFamily: 'Cairo')),
      )).toList(),
      onChanged: (v) {
        setState(() {
          _directorateId = v;
          _subDirectorateId = null;
          _subDirectorates = [];
        });
        if (v != null) _loadSubDirectorates(v);
      },
      validator: (v) => v == null ? 'اختر المحافظة' : null,
    );
  }

  Widget _buildSubDirectorateDropdown() {
    return DropdownButtonFormField<int>(
      value: _subDirectorateId,
      decoration: const InputDecoration(labelText: 'المديرية *', prefixIcon: Icon(Icons.location_on_outlined)),
      items: _subDirectorates.map((s) => DropdownMenuItem<int>(
        value: s['id'] as int,
        child: Text(s['name'] ?? '', style: const TextStyle(fontFamily: 'Cairo')),
      )).toList(),
      onChanged: (v) => setState(() => _subDirectorateId = v),
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
      child: Center(
        child: Image.asset(
          'logoapp/logo.png',
          width: 142,
          height: 106,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => const Icon(
            Icons.wifi_rounded,
            color: Colors.white,
            size: 68,
          ),
        ),
      ),
    );
  }
}
