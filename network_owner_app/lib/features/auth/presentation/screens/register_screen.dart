import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/api/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/connectivity_service.dart';
import '../../../../core/widgets/app_button.dart';
import '../providers/auth_provider.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtr = TextEditingController();
  final _phoneCtr = TextEditingController();
  final _passwordCtr = TextEditingController();
  final _confirmPasswordCtr = TextEditingController();
  final _networkNameCtr = TextEditingController();
  final _descriptionCtr = TextEditingController();
  final _urlCtr = TextEditingController();

  final _picker = ImagePicker();
  File? _coverImage;
  File? _backgroundImage;

  List<Map<String, dynamic>> _regions = [];
  List<Map<String, dynamic>> _directorates = [];
  List<Map<String, dynamic>> _subDirectorates = [];
  int? _regionId;
  int? _directorateId;
  int? _subDirectorateId;
  bool _loadingRegions = false;
  bool _loadingDirectorates = false;
  bool _loadingSubDirectorates = false;
  bool _acceptedTerms = false;
  String? _regionsError;
  String? _directoratesError;
  String? _subDirectoratesError;

  @override
  void initState() {
    super.initState();
    _loadRegions();
  }

  @override
  void dispose() {
    _nameCtr.dispose();
    _phoneCtr.dispose();
    _passwordCtr.dispose();
    _confirmPasswordCtr.dispose();
    _networkNameCtr.dispose();
    _descriptionCtr.dispose();
    _urlCtr.dispose();
    super.dispose();
  }

  static const String _offlineTitle = 'انقطع الاتصال بالإنترنت';
  static const String _offlineMessage =
      'تحقق من اتصالك بالإنترنت ثم حاول مرة أخرى.';

  bool _isNetworkError(Object error) {
    if (error is SocketException) return true;
    if (error is DioException) {
      return error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.connectionError ||
          (error.type == DioExceptionType.unknown &&
              error.error is SocketException);
    }
    final message = error.toString().toLowerCase();
    return message.contains('socketexception') ||
        message.contains('failed host lookup') ||
        message.contains('network is unreachable') ||
        message.contains('connection timed out');
  }

  String _friendlyError(Object error, String fallback) {
    if (_isNetworkError(error)) return _offlineMessage;
    final message = error.toString().replaceFirst('Exception: ', '');
    return '$fallback\n$message';
  }

  Future<bool> _ensureOnline() async {
    final isOnline = await ConnectivityService.isConnected();
    if (!isOnline && mounted) _showOfflineSnackBar();
    return isOnline;
  }

  Future<void> _loadRegions() async {
    setState(() {
      _loadingRegions = true;
      _regionsError = null;
    });
    try {
      if (!await _ensureOnline()) {
        throw const SocketException('No internet connection');
      }
      final api = ref.read(apiClientProvider);
      final res = await api.get('/regions');
      final list = List<Map<String, dynamic>>.from(res.data['data'] ?? []);
      if (!mounted) return;
      setState(() {
        _regions = list;
        _loadingRegions = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingRegions = false;
        _regionsError = _friendlyError(e, 'تعذر تحميل المناطق');
      });
      if (_isNetworkError(e)) {
        _showOfflineSnackBar();
      } else {
        _showSnackBar('تعذر تحميل المناطق. حاول مرة أخرى.');
      }
    }
  }

  Future<void> _loadDirectorates(int regionId) async {
    setState(() {
      _loadingDirectorates = true;
      _directoratesError = null;
      _directorateId = null;
      _directorates = [];
    });
    try {
      if (!await _ensureOnline()) {
        throw const SocketException('No internet connection');
      }
      final api = ref.read(apiClientProvider);
      final res = await api.get('/regions/$regionId/directorates');
      final list = List<Map<String, dynamic>>.from(res.data['data'] ?? []);
      if (!mounted) return;
      setState(() {
        _directorates = list;
        _loadingDirectorates = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingDirectorates = false;
        _directoratesError = _friendlyError(e, 'تعذر تحميل المحافظات');
      });
      if (_isNetworkError(e)) {
        _showOfflineSnackBar();
      } else {
        _showSnackBar('تعذر تحميل المحافظات. حاول مرة أخرى.');
      }
    }
  }

  Future<void> _loadSubDirectorates(int directorateId) async {
    setState(() {
      _loadingSubDirectorates = true;
      _subDirectoratesError = null;
      _subDirectorateId = null;
      _subDirectorates = [];
    });
    try {
      if (!await _ensureOnline()) {
        throw const SocketException('No internet connection');
      }
      final api = ref.read(apiClientProvider);
      final res = await api.get(
        '/directorates/$directorateId/sub-directorates',
      );
      final list = List<Map<String, dynamic>>.from(res.data['data'] ?? []);
      if (!mounted) return;
      setState(() {
        _subDirectorates = list;
        _loadingSubDirectorates = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingSubDirectorates = false;
        _subDirectoratesError = _friendlyError(e, 'تعذر تحميل المديريات');
      });
      if (_isNetworkError(e)) {
        _showOfflineSnackBar();
      } else {
        _showSnackBar('تعذر تحميل المديريات. حاول مرة أخرى.');
      }
    }
  }

  Future<void> _pickImage(bool isCover) async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 1200,
      );
      if (picked == null) return;
      setState(() {
        if (isCover) {
          _coverImage = File(picked.path);
        } else {
          _backgroundImage = File(picked.path);
        }
      });
    } catch (e) {
      _showSnackBar('تعذر اختيار الصورة: $e');
    }
  }

  Future<void> _submit() async {
    if (!await _ensureOnline()) return;
    if (!_formKey.currentState!.validate()) return;

    if (!_acceptedTerms) {
      _showSnackBar('يرجى الموافقة على شروط الخدمة وسياسة الخصوصية');
      return;
    }

    if (_regionId == null) {
      _showSnackBar('يرجى اختيار المنطقة');
      return;
    }
    if (_directorateId == null) {
      _showSnackBar('يرجى اختيار المحافظة');
      return;
    }
    if (_subDirectorateId == null) {
      _showSnackBar('يرجى اختيار المديرية');
      return;
    }

    final formData = FormData();
    formData.fields.addAll([
      MapEntry('name', _nameCtr.text.trim()),
      MapEntry('phone', _phoneCtr.text.trim()),
      MapEntry('password', _passwordCtr.text),
      MapEntry('password_confirmation', _confirmPasswordCtr.text),
      MapEntry('network_name', _networkNameCtr.text.trim()),
      MapEntry('region_id', _regionId!.toString()),
      MapEntry('directorate_id', _directorateId!.toString()),
      MapEntry('sub_directorate_id', _subDirectorateId!.toString()),
      MapEntry('description', _descriptionCtr.text.trim()),
      MapEntry('url', _urlCtr.text.trim()),
    ]);

    if (_coverImage != null) {
      formData.files.add(
        MapEntry(
          'cover_image',
          await MultipartFile.fromFile(_coverImage!.path),
        ),
      );
    }
    if (_backgroundImage != null) {
      formData.files.add(
        MapEntry(
          'background_image',
          await MultipartFile.fromFile(_backgroundImage!.path),
        ),
      );
    }

    final ok = await ref
        .read(authProvider.notifier)
        .registerNetworkOwner(formData);
    if (!mounted) return;
    if (ok) {
      context.go('/pending');
    } else {
      final err = ref.read(authProvider).error;
      if (err != null && err.contains('انقطع الاتصال بالإنترنت')) {
        _showOfflineSnackBar();
      } else if (err != null) {
        _showSnackBar(err);
      }
    }
  }

  void _showSnackBar(String msg) {
    _showStyledSnackBar(title: 'تنبيه', message: msg);
  }

  void _showOfflineSnackBar() {
    _showStyledSnackBar(title: _offlineTitle, message: _offlineMessage);
  }

  void _showStyledSnackBar({required String title, required String message}) {
    if (!mounted) return;
    final isOffline = title == _offlineTitle;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          backgroundColor: AppColors.error,
          elevation: 8,
          duration: const Duration(seconds: 4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          content: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isOffline
                      ? Icons.wifi_off_rounded
                      : Icons.error_outline_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      message,
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        color: Colors.white,
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final isOnline = ref.watch(isOnlineProvider);

    return Scaffold(
      backgroundColor: AppColors.primary,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'إنشاء حساب جديد',
          style: TextStyle(fontFamily: 'Cairo', color: Colors.white),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 24),
                    _buildSectionTitle('بيانات صاحب الشبكة'),
                    _buildField(
                      controller: _nameCtr,
                      label: 'الاسم الكامل *',
                      icon: Icons.person_outline,
                      validator: (v) =>
                          v == null ||
                              v
                                      .trim()
                                      .split(RegExp(r'\s+'))
                                      .where((part) => part.isNotEmpty)
                                      .length <
                                  4
                          ? 'يجب إدخال الاسم الرباعي على الأقل'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    _buildField(
                      controller: _phoneCtr,
                      label: 'رقم الهاتف *',
                      icon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                      textDirection: TextDirection.ltr,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(9),
                      ],
                      validator: (v) => v == null || v.length != 9
                          ? 'يجب أن يتكون رقم الهاتف من 9 أرقام'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    _buildField(
                      controller: _passwordCtr,
                      label: 'كلمة المرور *',
                      icon: Icons.lock_outlined,
                      obscure: true,
                      validator: (v) => v == null || v.length < 6
                          ? 'كلمة المرور قصيرة جداً'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    _buildField(
                      controller: _confirmPasswordCtr,
                      label: 'إعادة كلمة المرور *',
                      icon: Icons.lock_outline,
                      obscure: true,
                      validator: (v) {
                        if (v == null || v.isEmpty)
                          return 'أعد إدخال كلمة المرور';
                        if (v != _passwordCtr.text)
                          return 'كلمتا المرور غير متطابقتين';
                        return null;
                      },
                    ),
                    const SizedBox(height: 28),
                    _buildSectionTitle('بيانات الشبكة'),
                    _buildField(
                      controller: _networkNameCtr,
                      label: 'اسم الشبكة *',
                      icon: Icons.wifi,
                      validator: (v) =>
                          v == null || v.isEmpty ? 'أدخل اسم الشبكة' : null,
                    ),
                    const SizedBox(height: 14),
                    _buildRegionDropdown(isOnline),
                    const SizedBox(height: 14),
                    _buildGovernorateDropdown(isOnline),
                    const SizedBox(height: 14),
                    _buildSubDirectorateDropdown(isOnline),
                    const SizedBox(height: 14),
                    _buildField(
                      controller: _descriptionCtr,
                      label: 'الوصف',
                      icon: Icons.description_outlined,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 14),
                    _buildField(
                      controller: _urlCtr,
                      label: 'رابط المشاركة (اختياري)',
                      icon: Icons.link,
                      textDirection: TextDirection.ltr,
                      hint: 'https://saiberwifi.net/network/...',
                    ),
                    const SizedBox(height: 24),
                    _buildImagePicker(
                      title: 'صورة الغلاف',
                      image: _coverImage,
                      onTap: () => _pickImage(true),
                    ),
                    const SizedBox(height: 16),
                    _buildImagePicker(
                      title: 'صورة الخلفية',
                      image: _backgroundImage,
                      onTap: () => _pickImage(false),
                    ),
                    const SizedBox(height: 16),
                    CheckboxListTile(
                      value: _acceptedTerms,
                      onChanged: (value) =>
                          setState(() => _acceptedTerms = value ?? false),
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: AppColors.primary,
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'أوافق على شروط الخدمة وسياسة الخصوصية',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    AppButton(
                      label: 'إنشاء الحساب',
                      height: 52,
                      fontSize: 17,
                      isLoading: auth.isLoading,
                      onPressed: _acceptedTerms ? _submit : null,
                    ),
                    if (auth.error != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFFCA5A5)),
                        ),
                        child: Text(
                          auth.error!,
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            color: AppColors.error,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF16235F), Color(0xFF1E2D7D), Color(0xFF2A3A9A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: [0.0, 0.5, 1.0],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Color(0xFF1E2D7D),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Image.asset(
            'logo/logo.png',
            width: 118,
            height: 88,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) =>
                const Icon(Icons.wifi, color: Colors.white, size: 56),
          ),
          const SizedBox(height: 12),
          const Text(
            'تسجيل حساب صاحب شبكة',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'سيتم مراجعة طلبك من قِبل الإدارة قبل الظهور للعملاء',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Align(
        alignment: Alignment.centerRight,
        child: Text(
          title,
          style: const TextStyle(
            fontFamily: 'Cairo',
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    int maxLines = 1,
    TextInputType? keyboardType,
    TextDirection? textDirection,
    bool obscure = false,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    const border = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
      borderSide: BorderSide(color: AppColors.divider),
    );
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      textDirection: textDirection,
      obscureText: obscure,
      inputFormatters: inputFormatters,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: AppColors.textGray, size: 20),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        border: border,
        enabledBorder: border,
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: AppColors.primary, width: 2),
        ),
      ),
      validator: validator,
    );
  }

  Widget _buildRegionDropdown(bool isOnline) {
    if (_loadingRegions) {
      return const LinearProgressIndicator();
    }
    if (_regionsError != null) {
      return _buildRetryField(
        label: 'تعذر تحميل المناطق',
        error: _regionsError!,
        onRetry: _loadRegions,
      );
    }
    if (!isOnline && _regions.isEmpty) {
      return _buildRetryField(
        label: 'تعذر تحميل المناطق',
        error: _offlineMessage,
        onRetry: _loadRegions,
      );
    }
    return DropdownButtonFormField<int>(
      value: _regionId,
      decoration: InputDecoration(
        labelText: 'المنطقة *',
        prefixIcon: Icon(
          Icons.location_city,
          color: AppColors.textGray,
          size: 20,
        ),
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: AppColors.divider),
        ),
      ),
      items: _regions.map((r) {
        return DropdownMenuItem<int>(
          value: r['id'] as int,
          child: Text(
            r['name'] ?? '',
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
        );
      }).toList(),
      onChanged: (v) {
        setState(() {
          _regionId = v;
        });
        if (v != null) _loadDirectorates(v);
      },
      validator: (v) => v == null ? 'اختر المنطقة' : null,
    );
  }

  Widget _buildGovernorateDropdown(bool isOnline) {
    if (_loadingDirectorates) {
      return const LinearProgressIndicator();
    }
    if (_directoratesError != null) {
      return _buildRetryField(
        label: 'تعذر تحميل المحافظات',
        error: _directoratesError!,
        onRetry: () {
          if (_regionId != null) _loadDirectorates(_regionId!);
        },
      );
    }
    if (!isOnline && _directorates.isEmpty) {
      return _buildRetryField(
        label: 'تعذر تحميل المحافظات',
        error: _offlineMessage,
        onRetry: () {
          if (_regionId != null) {
            _loadDirectorates(_regionId!);
          } else {
            _showOfflineSnackBar();
          }
        },
      );
    }
    return DropdownButtonFormField<int>(
      value: _directorateId,
      decoration: InputDecoration(
        labelText: 'المحافظة *',
        prefixIcon: Icon(
          Icons.map_outlined,
          color: AppColors.textGray,
          size: 20,
        ),
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: AppColors.divider),
        ),
      ),
      items: _directorates.map((d) {
        return DropdownMenuItem<int>(
          value: d['id'] as int,
          child: Text(
            d['name'] ?? '',
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
        );
      }).toList(),
      onChanged: (v) {
        setState(() => _directorateId = v);
        if (v != null) _loadSubDirectorates(v);
      },
      validator: (v) => v == null ? 'اختر المحافظة' : null,
    );
  }

  Widget _buildSubDirectorateDropdown(bool isOnline) {
    if (_loadingSubDirectorates) {
      return const LinearProgressIndicator();
    }
    if (_subDirectoratesError != null) {
      return _buildRetryField(
        label: 'تعذر تحميل المديريات',
        error: _subDirectoratesError!,
        onRetry: () {
          if (_directorateId != null) _loadSubDirectorates(_directorateId!);
        },
      );
    }
    if (!isOnline && _subDirectorates.isEmpty) {
      return _buildRetryField(
        label: 'تعذر تحميل المديريات',
        error: _offlineMessage,
        onRetry: () {
          if (_directorateId != null) {
            _loadSubDirectorates(_directorateId!);
          } else {
            _showOfflineSnackBar();
          }
        },
      );
    }
    return DropdownButtonFormField<int>(
      value: _subDirectorateId,
      decoration: InputDecoration(
        labelText: 'المديرية *',
        prefixIcon: Icon(
          Icons.location_pin,
          color: AppColors.textGray,
          size: 20,
        ),
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: AppColors.divider),
        ),
      ),
      items: _subDirectorates.map((s) {
        return DropdownMenuItem<int>(
          value: s['id'] as int,
          child: Text(
            s['name'] ?? '',
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
        );
      }).toList(),
      onChanged: (v) => setState(() => _subDirectorateId = v),
      validator: (v) => v == null ? 'اختر المديرية' : null,
    );
  }

  Widget _buildRetryField({
    required String label,
    required String error,
    required VoidCallback onRetry,
  }) {
    final isOffline = error == _offlineMessage;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.error.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(14),
        color: const Color(0xFFFFF1F2),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isOffline ? Icons.wifi_off_rounded : Icons.error_outline_rounded,
              color: AppColors.error,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    color: AppColors.error,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  error,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    color: AppColors.error,
                    fontSize: 11.5,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('إعادة المحاولة'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              textStyle: const TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePicker({
    required String title,
    required File? image,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 140,
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: image != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  image,
                  fit: BoxFit.cover,
                  width: double.infinity,
                ),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.add_photo_alternate_outlined,
                    color: AppColors.primary,
                    size: 40,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      color: AppColors.textGray,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
