import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../mikrotik/presentation/widgets/ui_states.dart';
import '../../providers/sync_providers.dart';

/// ACC-12 — printed-document header (PLAN §5: settings_screen).
///
/// The texts stamped on top of every printed accounting document,
/// plus an optional logo image (uploaded to private storage and
/// previewed through the auth'd bytes endpoint).
class AccDocHeaderScreen extends ConsumerStatefulWidget {
  const AccDocHeaderScreen({super.key});

  @override
  ConsumerState<AccDocHeaderScreen> createState() =>
      _AccDocHeaderScreenState();
}

class _AccDocHeaderScreenState extends ConsumerState<AccDocHeaderScreen> {
  final _name = TextEditingController();
  final _subtitle = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _footer = TextEditingController();
  bool _showLogo = true;
  bool _hasLogo = false;
  bool _saving = false;
  bool _loaded = false;

  @override
  void dispose() {
    _name.dispose();
    _subtitle.dispose();
    _phone.dispose();
    _address.dispose();
    _footer.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final msg = await ref.read(syncApiProvider).saveDocHeader({
        'business_name': _name.text.trim(),
        'subtitle': _subtitle.text.trim(),
        'phone': _phone.text.trim(),
        'address': _address.text.trim(),
        'footer_text': _footer.text.trim(),
        'show_logo': _showLogo,
      });
      ref.invalidate(accDocHeaderProvider);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickLogo() async {
    final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'webp']);
    final path = picked?.files.single.path;
    if (path == null) return;
    try {
      final msg = await ref.read(syncApiProvider).uploadDocLogo(path);
      ref.invalidate(accDocHeaderProvider);
      setState(() => _hasLogo = true);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _removeLogo() async {
    try {
      final msg = await ref.read(syncApiProvider).removeDocLogo();
      ref.invalidate(accDocHeaderProvider);
      setState(() => _hasLogo = false);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final headerAsync = ref.watch(accDocHeaderProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('رأس المستند')),
      body: Container(
        color: AppColors.inputBg,
        child: headerAsync.when(
          loading: () => const LoadingState(),
          error: (e, _) => ErrorRetry(
            message: 'تعذّر تحميل الإعدادات\n$e',
            onRetry: () => ref.invalidate(accDocHeaderProvider),
          ),
          data: (header) {
            if (!_loaded) {
              _name.text = header.businessName ?? '';
              _subtitle.text = header.subtitle ?? '';
              _phone.text = header.phone ?? '';
              _address.text = header.address ?? '';
              _footer.text = header.footerText ?? '';
              _showLogo = header.showLogo;
              _hasLogo = header.hasLogo;
              _loaded = true;
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _preview(),
                const SizedBox(height: 16),
                _field(_name, 'اسم النشاط', Icons.storefront),
                _field(_subtitle, 'السطر الفرعي', Icons.short_text),
                _field(_phone, 'الهاتف', Icons.phone_outlined,
                    keyboard: TextInputType.phone),
                _field(_address, 'العنوان', Icons.location_on_outlined),
                _field(_footer, 'نص أسفل المستند', Icons.notes),
                const SizedBox(height: 8),
                _logoRow(),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save_outlined,
                            color: Colors.white),
                    label: Text(
                      _saving ? 'جارٍ الحفظ…' : 'حفظ رأس المستند',
                      style: const TextStyle(color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Live preview of how the header sits on a printed document.
  Widget _preview() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          const Text('معاينة',
              style: TextStyle(fontSize: 10, color: AppColors.textGray)),
          const SizedBox(height: 8),
          if (_showLogo && _hasLogo)
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child:
                  Icon(Icons.image, size: 32, color: AppColors.primary),
            ),
          Text(
            _name.text.trim().isEmpty ? 'اسم النشاط' : _name.text.trim(),
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textDark),
          ),
          if (_subtitle.text.trim().isNotEmpty)
            Text(_subtitle.text.trim(),
                style:
                    const TextStyle(fontSize: 12, color: AppColors.textGray)),
          if (_phone.text.trim().isNotEmpty ||
              _address.text.trim().isNotEmpty)
            Text(
              [_phone.text.trim(), _address.text.trim()]
                  .where((s) => s.isNotEmpty)
                  .join(' • '),
              style: const TextStyle(fontSize: 11, color: AppColors.textGray),
            ),
          const Divider(height: 16),
          Text(
            _footer.text.trim().isEmpty
                ? '— نص أسفل المستند —'
                : _footer.text.trim(),
            style: const TextStyle(fontSize: 11, color: AppColors.textGray),
          ),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    TextInputType keyboard = TextInputType.text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: ctrl,
        keyboardType: keyboard,
        onChanged: (_) => setState(() {}), // live preview
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 20),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.divider),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.divider),
          ),
        ),
      ),
    );
  }

  Widget _logoRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Expanded(
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('إظهار الشعار',
                  style: TextStyle(
                      fontSize: 13, color: AppColors.textDark)),
              value: _showLogo,
              onChanged: (v) => setState(() => _showLogo = v),
              activeThumbColor: AppColors.primary,
            ),
          ),
          TextButton.icon(
            onPressed: _pickLogo,
            icon: const Icon(Icons.upload_outlined, size: 18),
            label: Text(_hasLogo ? 'تغيير' : 'رفع شعار',
                style: const TextStyle(fontSize: 12)),
          ),
          if (_hasLogo)
            IconButton(
              tooltip: 'حذف الشعار',
              icon: const Icon(Icons.delete_outline,
                  size: 20, color: AppColors.error),
              onPressed: _removeLogo,
            ),
        ],
      ),
    );
  }
}
