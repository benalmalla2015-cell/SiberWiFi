import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/api/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/feature_keys.dart';
import '../../data/hotspot_pages_service.dart';
import '../../data/router_model.dart';
import '../../data/router_os_service.dart';
import '../widgets/feature_gate.dart';
import '../widgets/ui_states.dart';

/// Hosted hotspot login-page store: pick a template, customize
/// name/colors/logo, render on the backend, then the router pulls the
/// files via /tool/fetch into its pages directory (no FTP needed).
class HotspotPagesScreen extends ConsumerStatefulWidget {
  final MikrotikRouterConfig router;
  const HotspotPagesScreen({super.key, required this.router});

  @override
  ConsumerState<HotspotPagesScreen> createState() =>
      _HotspotPagesScreenState();
}

class _HotspotPagesScreenState extends ConsumerState<HotspotPagesScreen> {
  // ── data ────────────────────────────────────────────────────────
  List<PageTemplate> _templates = [];
  PageTemplate? _tpl;
  bool _loadingTemplates = true;
  String? _loadError;

  List<Map<String, String>> _profiles = [];
  String? _profileId;

  // ── customization ──────────────────────────────────────────────
  final _nameCtrl = TextEditingController();
  final _msgCtrl = TextEditingController();
  final _waCtrl = TextEditingController();
  final _dirCtrl = TextEditingController(text: 'saiber-pages');
  int _c1 = 0xFF1E2D7D;
  int _c2 = 0xFFE31E24;
  File? _logo;

  // ── apply state ────────────────────────────────────────────────
  RenderedPages? _rendered;
  bool _rendering = false;
  bool _applying = false;
  int _applied = 0, _total = 0;
  List<String> _appliedFiles = [];
  String? _error;

  static const _palette = <int>[
    0xFF1E2D7D, 0xFFE31E24, 0xFF4B7BEC, 0xFF16235F, 0xFF10B981,
    0xFFF59E0B, 0xFF8B5CF6, 0xFF0EA5E9, 0xFFEC4899, 0xFF14B8A6,
    0xFF64748B, 0xFF0F1729, 0xFF78350F, 0xFF065F46, 0xFF7C3AED,
    0xFFDC2626, 0xFF2563EB, 0xFF059669, 0xFFD97706, 0xFF111827,
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _msgCtrl.dispose();
    _waCtrl.dispose();
    _dirCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loadingTemplates = true;
      _loadError = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final tpls = await HotspotPagesService.templates(api);
      RouterOsService? svc;
      try {
        svc = await RouterOsService.connect(widget.router);
        _profiles = await svc.hotspotServerProfiles();
        _profileId ??= _profiles.isNotEmpty
            ? _profiles.first['.id'] ?? _profiles.first['name']
            : null;
      } catch (_) {
        _profiles = [];
      } finally {
        svc?.close();
      }
      if (!mounted) return;
      setState(() {
        _templates = tpls;
        _tpl ??= tpls.isNotEmpty ? tpls.first : null;
        if (_tpl != null && _nameCtrl.text.isEmpty) {
          _c1 = _hex(_tpl!.colorPrimary);
          _c2 = _hex(_tpl!.colorAccent);
          _msgCtrl.text = _tpl!.welcomeMsg;
        }
        _loadingTemplates = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = 'تعذر تحميل القوالب: $e';
        _loadingTemplates = false;
      });
    }
  }

  int _hex(String v) {
    final s = v.replaceAll('#', '');
    return int.tryParse('FF$s', radix: 16) ?? 0xFF1E2D7D;
  }

  String _css(int c) =>
      '#${c.toRadixString(16).padLeft(8, '0').substring(2)}';

  Future<void> _pickLogo() async {
    final x = await ImagePicker()
        .pickImage(source: ImageSource.gallery, maxWidth: 512);
    if (x != null) setState(() => _logo = File(x.path));
  }

  Future<void> _render({required bool preview}) async {
    if (_tpl == null) return;
    setState(() {
      _rendering = true;
      _error = null;
    });
    try {
      final r = await HotspotPagesService.render(
        ref.read(apiClientProvider),
        templateId: _tpl!.id,
        networkName: _nameCtrl.text.trim(),
        welcomeMsg: _msgCtrl.text.trim(),
        whatsapp: _waCtrl.text.trim(),
        colorPrimary: _css(_c1),
        colorAccent: _css(_c2),
        logoPath: _logo?.path,
      );
      if (!mounted) return;
      setState(() => _rendered = r);
      if (preview && r.previewUrl.isNotEmpty) {
        await launchUrl(Uri.parse(r.previewUrl),
            mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'تعذر تجهيز القالب: $e');
    } finally {
      if (mounted) setState(() => _rendering = false);
    }
  }

  Future<void> _apply() async {
    if (_rendered == null) {
      await _render(preview: false);
      if (_rendered == null) return;
    }
    final dir = _dirCtrl.text.trim().isEmpty
        ? 'saiber-pages'
        : _dirCtrl.text.trim();
    setState(() {
      _applying = true;
      _applied = 0;
      _appliedFiles = [];
      _error = null;
      _total = _rendered!.files.length + 1; // files + profile set
    });

    RouterOsService? svc;
    try {
      svc = await RouterOsService.connect(widget.router);
      for (final entry in _rendered!.files.entries) {
        await svc.fetchToFile(entry.value, '$dir/${entry.key}');
        if (mounted) {
          setState(() {
            _applied++;
            _appliedFiles.add(entry.key);
          });
        }
      }
      if (_profileId != null) {
        await svc.setHotspotServerProfile(
            _profileId!, {'html-directory': dir});
      }
      if (mounted) setState(() => _applied = _total);
    } catch (e) {
      if (mounted) setState(() => _error = 'فشل التطبيق: $e');
    } finally {
      svc?.close();
      if (mounted) setState(() => _applying = false);
    }
  }

  // ── UI ──────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(title: const Text('صفحات الدخول')),
      body: FeatureGate(
        feature: MikroFeatures.hotspotPages,
        child: _loadingTemplates
            ? const LoadingState()
            : _loadError != null
                ? ErrorRetry(message: _loadError!, onRetry: _load)
                : _templates.isEmpty
                    ? const EmptyState('لا توجد قوالب متاحة حالياً',
                        icon: Icons.web_asset_off_outlined)
                    : _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.15)),
          ),
          child: const Text(
            'اختر قالب صفحة الدخول، خصّصه باسم شبكتك وألوانك وشعارك، '
            'ثم طبّقه — الراوتر يسحب الملفات تلقائياً (يتطلب اتصال '
            'الراوتر بالإنترنت)',
            style: TextStyle(fontSize: 12.5, height: 1.6),
          ),
        ),
        const SizedBox(height: 16),
        _stepHeader(1, 'اختر القالب'),
        const SizedBox(height: 10),
        ..._templates.map(_templateCard),
        const SizedBox(height: 18),
        if (_tpl != null) ...[
          _stepHeader(2, 'خصّص صفحتك'),
          const SizedBox(height: 10),
          _sectionCard([
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'اسم الشبكة',
                prefixIcon: Icon(Icons.wifi),
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _msgCtrl,
              decoration: const InputDecoration(
                labelText: 'رسالة الترحيب',
                prefixIcon: Icon(Icons.waving_hand_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _waCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'رقم الدعم / واتساب (اختياري)',
                prefixIcon: Icon(Icons.support_agent),
              ),
            ),
            const SizedBox(height: 14),
            _colorRow('اللون الرئيسي', _c1, (c) => setState(() => _c1 = c)),
            const SizedBox(height: 10),
            _colorRow('لون الأزرار', _c2, (c) => setState(() => _c2 = c)),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickLogo,
                    icon: const Icon(Icons.image_outlined, size: 18),
                    label: Text(
                        _logo == null ? 'شعار (اختياري)' : 'تغيير الشعار'),
                  ),
                ),
                if (_logo != null) ...[
                  const SizedBox(width: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(_logo!,
                        width: 44, height: 44, fit: BoxFit.cover),
                  ),
                  IconButton(
                    onPressed: () => setState(() => _logo = null),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ],
            ),
          ]),
          const SizedBox(height: 18),
          _stepHeader(3, 'طبّق على الراوتر'),
          const SizedBox(height: 10),
          _sectionCard([
            TextFormField(
              controller: _dirCtrl,
              decoration: const InputDecoration(
                labelText: 'مجلد الصفحات على الراوتر',
                helperText:
                    'مجلد جديد يحفظ القالب دون المساس بالأصل',
                prefixIcon: Icon(Icons.folder_outlined),
              ),
            ),
            const SizedBox(height: 10),
            if (_profiles.isNotEmpty)
              DropdownButtonFormField<String>(
                initialValue: _profileId,
                decoration: const InputDecoration(
                  labelText: 'بروفايل سيرفر الهوتسبوت',
                  prefixIcon: Icon(Icons.dns_outlined),
                ),
                items: _profiles
                    .map((p) => DropdownMenuItem(
                          value: p['.id'] ?? p['name'],
                          child: Text(
                              '${p['name'] ?? ''}  —  ${p['html-directory'] ?? 'hotspot'}'),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _profileId = v),
              )
            else
              const Text(
                'تعذر قراءة بروفايلات السيرفر — سيتم رفع الملفات فقط دون تغيير html-directory',
                style: TextStyle(fontSize: 12, color: AppColors.textGray),
              ),
          ]),
          const SizedBox(height: 18),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_error!,
                  style: const TextStyle(
                      color: AppColors.accent, fontSize: 12)),
            ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      _rendering ? null : () => _render(preview: true),
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('معاينة'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: (_applying || _rendering) ? null : _apply,
                  icon: _applying
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.rocket_launch_outlined),
                  label: Text(_applying
                      ? 'جارٍ التطبيق $_applied/$_total'
                      : 'تطبيق على الراوتر'),
                ),
              ),
            ],
          ),
          if (_applying) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: _total > 0 ? _applied / _total : null,
                minHeight: 8,
                backgroundColor: AppColors.divider,
                valueColor:
                    const AlwaysStoppedAnimation(AppColors.primary),
              ),
            ),
          ],
          if (_appliedFiles.isNotEmpty) ...[
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppColors.success.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('الملفات المرفوعة',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  for (final f in _appliedFiles)
                    Text('• ${_dirCtrl.text.trim()}/$f',
                        style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            color: AppColors.textGray)),
                  const SizedBox(height: 6),
                  const Text(
                      'جرّب الصفحة بفتح أي موقع من جهاز متصل بالهوتسبوت',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textGray)),
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _templateCard(PageTemplate t) {
    final sel = _tpl?.id == t.id;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: sel ? AppColors.primary : AppColors.divider,
          width: sel ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() {
          _tpl = t;
          _c1 = _hex(t.colorPrimary);
          _c2 = _hex(t.colorAccent);
          if (_msgCtrl.text.isEmpty) _msgCtrl.text = t.welcomeMsg;
        }),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: [
                      Color(_hex(t.colorPrimary)),
                      Color(_hex(t.colorAccent)),
                    ],
                  ),
                ),
                child: const Icon(Icons.web, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 3),
                    Text(t.description,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textGray)),
                  ],
                ),
              ),
              if (sel)
                const Icon(Icons.check_circle,
                    color: AppColors.primary, size: 22),
            ],
          ),
        ),
      ),
    );
  }

  /// Numbered step header — gives the long form a clear 1-2-3 flow.
  Widget _stepHeader(int n, String title) {
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: const BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text('$n',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 8),
        Text(title,
            style:
                const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      ],
    );
  }

  /// Groups a step's controls inside one bordered card so sections read
  /// as distinct blocks instead of floating fields on the page.
  Widget _sectionCard(List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _colorRow(String label, int selected, ValueChanged<int> onPick) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style:
                const TextStyle(fontSize: 12, color: AppColors.textGray)),
        const SizedBox(height: 6),
        SizedBox(
          height: 34,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _palette.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final c = _palette[i];
              final sel = c == selected;
              return GestureDetector(
                onTap: () => onPick(c),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Color(c),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: sel ? AppColors.textDark : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                  child: sel
                      ? const Icon(Icons.check,
                          color: Colors.white, size: 16)
                      : null,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
