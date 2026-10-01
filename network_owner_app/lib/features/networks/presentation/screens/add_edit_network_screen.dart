import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/api/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/networks_repository.dart';

class AddEditNetworkScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic>? network;
  const AddEditNetworkScreen({super.key, this.network});

  @override
  ConsumerState<AddEditNetworkScreen> createState() =>
      _AddEditNetworkScreenState();
}

class _AddEditNetworkScreenState extends ConsumerState<AddEditNetworkScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtr = TextEditingController();
  final _descCtr = TextEditingController();
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
  String? _regionsError;
  String? _directoratesError;
  String? _subDirectoratesError;

  bool _loading = false;
  bool _isEdit = false;
  bool _isPending = false;

  @override
  void initState() {
    super.initState();
    final n = widget.network;
    if (n != null) {
      _isEdit = true;
      _isPending = n['status'] == 'pending';
      _nameCtr.text = n['name'] ?? '';
      _descCtr.text = n['description'] ?? '';
      _urlCtr.text = n['url'] ?? '';
      _regionId = _toInt(n['region_id']);
      _directorateId = _toInt(n['directorate_id']);
      _subDirectorateId = _toInt(n['sub_directorate_id']);
    }
    _loadRegions();
  }

  @override
  void dispose() {
    _nameCtr.dispose();
    _descCtr.dispose();
    _urlCtr.dispose();
    super.dispose();
  }

  int? _toInt(dynamic value) =>
      value is int ? value : int.tryParse(value?.toString() ?? '');

  Future<void> _loadRegions() async {
    setState(() {
      _loadingRegions = true;
      _regionsError = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.get('/regions');
      final list = List<Map<String, dynamic>>.from(res.data['data'] ?? []);
      setState(() {
        _regions = list;
        _loadingRegions = false;
      });
      if (_regionId != null) {
        await _loadDirectorates(_regionId!, preserveSelection: true);
        if (_directorateId != null) {
          await _loadSubDirectorates(_directorateId!, preserveSelection: true);
        }
      }
    } catch (e) {
      setState(() {
        _loadingRegions = false;
        _regionsError = e.toString();
      });
      _showSnackBar('تعذر تحميل المناطق: $e');
    }
  }

  Future<void> _loadDirectorates(
    int regionId, {
    bool preserveSelection = false,
  }) async {
    setState(() {
      _loadingDirectorates = true;
      _directoratesError = null;
      if (!preserveSelection) _directorateId = null;
      _directorates = [];
    });
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.get('/regions/$regionId/directorates');
      final list = List<Map<String, dynamic>>.from(res.data['data'] ?? []);
      setState(() {
        _directorates = list;
        _loadingDirectorates = false;
      });
    } catch (e) {
      setState(() {
        _loadingDirectorates = false;
        _directoratesError = e.toString();
      });
      _showSnackBar('تعذر تحميل المحافظات: $e');
    }
  }

  Future<void> _loadSubDirectorates(
    int directorateId, {
    bool preserveSelection = false,
  }) async {
    setState(() {
      _loadingSubDirectorates = true;
      _subDirectoratesError = null;
      if (!preserveSelection) _subDirectorateId = null;
      _subDirectorates = [];
    });
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.get('/directorates/$directorateId/sub-directorates');
      final list = List<Map<String, dynamic>>.from(res.data['data'] ?? []);
      setState(() {
        _subDirectorates = list;
        _loadingSubDirectorates = false;
      });
    } catch (e) {
      setState(() {
        _loadingSubDirectorates = false;
        _subDirectoratesError = e.toString();
      });
      _showSnackBar('تعذر تحميل المديريات: $e');
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
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final repo = ref.read(networksRepositoryProvider);
      final formData = FormData();
      formData.fields.addAll([
        MapEntry('name', _nameCtr.text.trim()),
        MapEntry('description', _descCtr.text.trim()),
        MapEntry('url', _urlCtr.text.trim()),
      ]);

      if (_isEdit) {
        // Only send region/directorate/sub-directorate if they changed
        if (_regionId != null) {
          formData.fields.add(MapEntry('region_id', _regionId.toString()));
        }
        if (_directorateId != null) {
          formData.fields.add(
            MapEntry('directorate_id', _directorateId.toString()),
          );
        }
        if (_subDirectorateId != null) {
          formData.fields.add(
            MapEntry('sub_directorate_id', _subDirectorateId.toString()),
          );
        }
      } else {
        formData.fields.addAll([
          MapEntry('region_id', _regionId.toString()),
          MapEntry('directorate_id', _directorateId.toString()),
          MapEntry('sub_directorate_id', _subDirectorateId.toString()),
        ]);
      }

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

      if (_isEdit) {
        if (_isPending) {
          await repo.updateMyNetwork(formData);
        } else {
          await repo.updateNetwork(widget.network!['id'], formData);
        }
      } else {
        await repo.createNetwork(formData);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showSnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'تعديل الشبكة' : 'إضافة شبكة جديدة'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              const SizedBox(height: 24),
              _buildField(
                controller: _nameCtr,
                label: 'اسم الشبكة *',
                icon: Icons.wifi,
                validator: (v) =>
                    v == null || v.isEmpty ? 'أدخل اسم الشبكة' : null,
              ),
              const SizedBox(height: 14),
              _buildRegionDropdown(),
              const SizedBox(height: 14),
              _buildGovernorateDropdown(),
              const SizedBox(height: 14),
              _buildSubDirectorateDropdown(),
              const SizedBox(height: 14),
              _buildField(
                controller: _descCtr,
                label: 'الوصف',
                icon: Icons.description_outlined,
                maxLines: 3,
              ),
              const SizedBox(height: 14),
              _buildField(
                controller: _urlCtr,
                label: 'رابط المشاركة',
                icon: Icons.link,
                textDirection: TextDirection.ltr,
                hint: 'https://saiberwifi.net/network/...',
              ),
              const SizedBox(height: 24),
              _buildImagePicker(
                title: 'صورة الغلاف',
                existingUrl: widget.network?['cover_image_url'],
                image: _coverImage,
                onTap: () => _pickImage(true),
              ),
              const SizedBox(height: 16),
              _buildImagePicker(
                title: 'صورة الخلفية',
                existingUrl: widget.network?['background_image_url'],
                image: _backgroundImage,
                onTap: () => _pickImage(false),
              ),
              const SizedBox(height: 32),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          _isEdit ? 'حفظ التعديلات' : 'إضافة الشبكة',
                          textDirection: TextDirection.rtl,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: 'Roboto',
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
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
            color: Color(0x331E2D7D),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(
            _isEdit ? Icons.edit_note : Icons.wifi_tethering,
            color: Colors.white,
            size: 40,
          ),
          const SizedBox(height: 8),
          Text(
            _isEdit ? 'تعديل بيانات الشبكة' : 'إضافة شبكة جديدة',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _isEdit
                ? 'قم بتحديث معلومات شبكتك'
                : 'ستتم مراجعة الشبكة من قِبل الإدارة',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
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
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: AppColors.textGray, size: 20),
        filled: true,
        fillColor: AppColors.inputBg,
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

  Widget _buildRegionDropdown() {
    if (_loadingRegions) {
      return const LinearProgressIndicator();
    }
    if (_regionsError != null) {
      return _buildRetryField(
        label: 'تعذر تحميل المناطق',
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
          _directorateId = null;
        });
        if (v != null) _loadDirectorates(v);
      },
      validator: (v) => v == null ? 'اختر المنطقة' : null,
    );
  }

  Widget _buildGovernorateDropdown() {
    if (_loadingDirectorates) {
      return const LinearProgressIndicator();
    }
    if (_directoratesError != null) {
      return _buildRetryField(
        label: 'تعذر تحميل المحافظات',
        onRetry: () {
          if (_regionId != null) _loadDirectorates(_regionId!);
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

  Widget _buildSubDirectorateDropdown() {
    if (_loadingSubDirectorates) {
      return const LinearProgressIndicator();
    }
    if (_subDirectoratesError != null) {
      return _buildRetryField(
        label: 'تعذر تحميل المديريات',
        onRetry: () {
          if (_directorateId != null) _loadSubDirectorates(_directorateId!);
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
    required VoidCallback onRetry,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.error),
        borderRadius: BorderRadius.circular(12),
        color: const Color(0xFFFEE2E2),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: 'Cairo',
                color: AppColors.error,
                fontSize: 13,
              ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: const Text(
              'إعادة المحاولة',
              style: TextStyle(
                fontFamily: 'Cairo',
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePicker({
    required String title,
    required String? existingUrl,
    required File? image,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 160,
        decoration: BoxDecoration(
          color: AppColors.inputBg,
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
            : existingUrl != null && existingUrl.isNotEmpty
            ? ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  existingUrl,
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
