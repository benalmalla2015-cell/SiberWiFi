import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api/cyber_api.dart';
import '../../core/models/models.dart';
import '../../core/services/device_service.dart';
import '../../core/services/subscriber_store.dart';
import '../../core/theme/app_theme.dart';
import 'sim_card_screen.dart';

/// First-time enrolment (CYB-03 contract): full 4-part name, governorate
/// + district pickers fed live from the backend, ID documents front/back
/// (or passport single), then POST /cyber/register → the 74XXXXXXX SIM.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _api = CyberApi();
  final _picker = ImagePicker();

  List<Governorate>? _governorates;
  List<District> _districts = const [];
  Governorate? _gov;
  District? _district;
  String _docType = 'national_id';
  File? _front;
  File? _back;
  bool _loading = false;
  bool _govsFailed = false;
  Map<String, String> _fieldErrors = const {};

  int get _nameParts =>
      _nameCtrl.text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

  @override
  void initState() {
    super.initState();
    _loadGovernorates();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadGovernorates() async {
    setState(() => _govsFailed = false);
    try {
      final govs = await _api.governorates();
      if (mounted) setState(() => _governorates = govs);
    } on CyberApiException {
      if (mounted) setState(() => _govsFailed = true);
    }
  }

  Future<void> _loadDistricts(Governorate g) async {
    setState(() {
      _gov = g;
      _district = null;
      _districts = const [];
    });
    try {
      final list = await _api.districts(g.id);
      if (mounted) setState(() => _districts = list);
    } on CyberApiException {
      _toast('تعذر تحميل مديريات ${g.name}');
    }
  }

  Future<void> _pick(bool front) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('الكاميرا'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('المعرض'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
        ]),
      ),
    );
    if (source == null) return;
    final x = await _picker.pickImage(source: source, imageQuality: 85, maxWidth: 2000);
    if (x == null) return;
    setState(() {
      if (front) {
        _front = File(x.path);
      } else {
        _back = File(x.path);
      }
    });
  }

  Future<void> _submit() async {
    final errors = <String, String>{};
    if (_nameParts < 4) {
      errors['full_name'] = 'الاسم يجب أن يكون رباعياً على الأقل';
    }
    if (_gov == null) errors['directorate_id'] = 'اختر المحافظة';
    if (_district == null) errors['sub_directorate_id'] = 'اختر المديرية';
    if (_front == null) errors['id_front_image'] = 'صورة الوثيقة مطلوبة';
    if (_docType == 'national_id' && _back == null) {
      errors['id_back_image'] = 'صورة الوجه الخلفي للبطاقة مطلوبة';
    }
    setState(() => _fieldErrors = errors);
    if (errors.isNotEmpty) return;

    setState(() => _loading = true);
    try {
      final deviceId = await DeviceService.deviceId();
      final issue = await _api.register(
        fullName: _nameCtrl.text.trim(),
        documentType: _docType,
        directorateId: _gov!.id,
        subDirectorateId: _district!.id,
        deviceId: deviceId,
        idFront: _front!,
        idBack: _back,
      );
      await SubscriberStore.saveSubscriber(
        simNo: issue.simNo,
        fullName: issue.fullName,
        deviceId: deviceId,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => SimCardScreen(issue: issue)),
      );
    } on CyberApiException catch (e) {
      setState(() => _fieldErrors = e.fieldErrors);
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              _header(),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _nameField(),
                    const SizedBox(height: 16),
                    _govField(),
                    const SizedBox(height: 16),
                    _districtField(),
                    const SizedBox(height: 20),
                    _docTypeToggle(),
                    const SizedBox(height: 16),
                    _imageField(
                      label: _docType == 'passport' ? 'صورة الجواز' : 'البطاقة — الوجه الأمامي',
                      file: _front,
                      error: _fieldErrors['id_front_image'],
                      onTap: () => _pick(true),
                    ),
                    if (_docType == 'national_id') ...[
                      const SizedBox(height: 14),
                      _imageField(
                        label: 'البطاقة — الوجه الخلفي',
                        file: _back,
                        error: _fieldErrors['id_back_image'],
                        onTap: () => _pick(false),
                      ),
                    ],
                    const SizedBox(height: 28),
                    ElevatedButton(
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: Colors.white,
                              ),
                            )
                          : const Text('إصدار شريحة سايبر'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 36),
      decoration: const BoxDecoration(
        gradient: CyberColors.headerGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.sim_card_outlined, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 12),
            const Text(
              'سايبر نت',
              style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
            ),
          ]),
          const SizedBox(height: 18),
          const Text(
            'احصل على شريحتك الرقمية',
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            'رقم دائم يبدأ بـ 74 + اتصال تلقائي بشبكات CyberNet',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 13.5),
          ),
        ],
      ),
    );
  }

  Widget _nameField() {
    final parts = _nameParts;
    final error = _fieldErrors['full_name'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('الاسم الكامل (رباعي)'),
        TextField(
          controller: _nameCtrl,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'الاسم، الأب، الجد، اللقب',
            errorText: error,
            suffixIcon: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                '$parts/4',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: parts >= 4 ? CyberColors.success : CyberColors.textGray,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _govField() {
    if (_govsFailed) {
      return _retryBox('تعذر تحميل قائمة المحافظات', _loadGovernorates);
    }
    if (_governorates == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('المحافظة'),
        DropdownButtonFormField<Governorate>(
          initialValue: _gov,
          isExpanded: true,
          decoration: InputDecoration(errorText: _fieldErrors['directorate_id']),
          hint: const Text('اختر المحافظة'),
          items: _governorates!
              .map((g) => DropdownMenuItem(value: g, child: Text(g.name)))
              .toList(),
          onChanged: (g) => g == null ? null : _loadDistricts(g),
        ),
      ],
    );
  }

  Widget _districtField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('المديرية'),
        DropdownButtonFormField<District>(
          initialValue: _district,
          isExpanded: true,
          decoration: InputDecoration(errorText: _fieldErrors['sub_directorate_id']),
          hint: Text(_gov == null ? 'اختر المحافظة أولاً' : 'اختر المديرية'),
          items: _districts
              .map((d) => DropdownMenuItem(value: d, child: Text(d.name)))
              .toList(),
          onChanged: _gov == null ? null : (d) => setState(() => _district = d),
        ),
      ],
    );
  }

  Widget _docTypeToggle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('نوع الوثيقة'),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'national_id', label: Text('بطاقة شخصية')),
            ButtonSegment(value: 'passport', label: Text('جواز سفر')),
          ],
          selected: {_docType},
          onSelectionChanged: (s) => setState(() => _docType = s.first),
        ),
      ],
    );
  }

  Widget _imageField({
    required String label,
    required File? file,
    required String? error,
    required VoidCallback onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 140,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: error != null ? CyberColors.accent : CyberColors.divider,
                width: 1.4,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: file != null
                ? Stack(fit: StackFit.expand, children: [
                    Image.file(file, fit: BoxFit.cover),
                    Positioned(
                      left: 10,
                      bottom: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'اضغط للتغيير',
                          style: TextStyle(color: Colors.white, fontSize: 11),
                        ),
                      ),
                    ),
                  ])
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_a_photo_outlined,
                          size: 34, color: CyberColors.primary.withValues(alpha: 0.6)),
                      const SizedBox(height: 8),
                      const Text('اضغط لالتقاط أو اختيار صورة',
                          style: TextStyle(color: CyberColors.textGray, fontSize: 13)),
                    ],
                  ),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 8),
            child: Text(error,
                style: const TextStyle(color: CyberColors.accent, fontSize: 12)),
          ),
      ],
    );
  }

  Widget _retryBox(String msg, VoidCallback onRetry) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: CyberColors.divider),
      ),
      child: Row(children: [
        Expanded(child: Text(msg, style: const TextStyle(fontSize: 13))),
        TextButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
      ]),
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 14,
          color: CyberColors.textDark,
        ),
      ),
    );
  }
}
