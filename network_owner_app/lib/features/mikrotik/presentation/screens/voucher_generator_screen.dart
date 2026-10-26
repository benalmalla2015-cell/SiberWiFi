import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../networks/data/networks_repository.dart';
import '../../../networks/presentation/providers/networks_provider.dart';
import '../../data/card_template.dart';
import '../../data/card_template_store.dart';
import '../../data/router_model.dart';
import '../../data/router_os_service.dart';
import '../../data/voucher_print_service.dart';
import '../providers/mikrotik_provider.dart';
import '../widgets/voucher_card_view.dart';
import 'card_templates_screen.dart';

class VoucherGeneratorScreen extends ConsumerStatefulWidget {
  final MikrotikRouterConfig router;
  const VoucherGeneratorScreen({super.key, required this.router});

  @override
  ConsumerState<VoucherGeneratorScreen> createState() =>
      _VoucherGeneratorScreenState();
}

class _VoucherGeneratorScreenState
    extends ConsumerState<VoucherGeneratorScreen> {
  final _countCtrl = TextEditingController(text: '10');
  final _lengthCtrl = TextEditingController(text: '8');
  final _uptimeCtrl = TextEditingController();
  final _dataCtrl = TextEditingController();
  final _validityCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  String _dataUnit = 'G'; // G or M → limit-bytes-total
  String _uptimeUnit = 'h'; // h or m
  String? _profile;
  int? _networkId;
  int? _categoryId;
  bool _sameAsCode = true;
  bool _running = false;
  int _done = 0;
  int _total = 0;
  List<String> _generated = [];
  String? _error;
  List<CardTemplate> _templates = [];
  CardTemplate? _template;

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    final list = await CardTemplateStore.load(widget.router.id);
    if (mounted) {
      setState(() {
        _templates = list;
        _template ??= list.isNotEmpty ? list.first : null;
      });
    }
  }

  int? get _dataLimitBytes {
    final v = int.tryParse(_dataCtrl.text.trim());
    if (v == null || v <= 0) return null;
    return v * (_dataUnit == 'G' ? 1073741824 : 1048576);
  }

  String? get _limitUptime {
    final v = _uptimeCtrl.text.trim();
    if (v.isEmpty) return null;
    return '$v$_uptimeUnit';
  }

  @override
  void dispose() {
    _countCtrl.dispose();
    _lengthCtrl.dispose();
    _uptimeCtrl.dispose();
    _dataCtrl.dispose();
    _validityCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final count = int.tryParse(_countCtrl.text.trim()) ?? 0;
    final length = int.tryParse(_lengthCtrl.text.trim()) ?? 8;
    if (count < 1 || count > 500) {
      setState(() => _error = 'العدد يجب أن يكون بين 1 و 500');
      return;
    }
    setState(() {
      _running = true;
      _done = 0;
      _total = count;
      _generated = [];
      _error = null;
    });

    final batch = 'saiberwifi-${DateTime.now().millisecondsSinceEpoch}';
    RouterOsService? svc;
    try {
      svc = await RouterOsService.connect(widget.router);
      final codes = <String>[];
      for (var i = 0; i < count; i++) {
        final code = VoucherGenerator.code(length: length.clamp(4, 32));
        await svc.addHotspotUser(
          name: code,
          password: _sameAsCode ? code : null,
          profile: _profile,
          comment: batch,
          limitUptime: _limitUptime,
          limitBytesTotal: _dataLimitBytes,
          validityDays: int.tryParse(_validityCtrl.text.trim()),
          price: int.tryParse(_priceCtrl.text.trim()),
        );
        codes.add(code);
        if (mounted) setState(() => _done = i + 1);
      }
      setState(() => _generated = codes);
      ref.invalidate(routerSessionProvider(widget.router));
    } catch (e) {
      setState(() => _error = 'تعذر الإنشاء: $e');
    } finally {
      svc?.close();
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _uploadToPlatform() async {
    if (_generated.isEmpty) return;
    if (_networkId == null || _categoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اختر الشبكة والفئة أولاً')),
      );
      return;
    }
    try {
      final repo = ref.read(networksRepositoryProvider);
      final res = await repo.uploadCards({
        'network_id': _networkId,
        'category_id': _categoryId,
        'codes': _generated,
        'source': 'mikrotik',
        if (widget.router.remoteId != null)
          'router_id': widget.router.remoteId,
        'meta': {
          'batch': 'batch-${DateTime.now().millisecondsSinceEpoch}',
          if (_template != null) 'template_name': _template!.name,
          if (_limitUptime != null) 'limit_uptime': _limitUptime,
          if (_dataLimitBytes != null)
            'limit_bytes_total': _dataLimitBytes,
          if (int.tryParse(_validityCtrl.text.trim()) != null)
            'validity_days': int.parse(_validityCtrl.text.trim()),
          if (int.tryParse(_priceCtrl.text.trim()) != null)
            'price': int.parse(_priceCtrl.text.trim()),
        },
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.success,
          content: Text(res['message']?.toString() ?? 'تم الرفع بنجاح'),
        ),
      );
      ref.invalidate(cardsProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            backgroundColor: AppColors.accent,
            content: Text('فشل الرفع: $e')),
      );
    }
  }

  Future<void> _copyAll() async {
    await Clipboard.setData(ClipboardData(text: _generated.join('\n')));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم نسخ جميع الأكواد')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final snap = ref.watch(routerSessionProvider(widget.router));
    final networks = ref.watch(networksProvider);
    final categories = ref.watch(categoriesProvider);

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(title: const Text('توليد كروت')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.15)),
            ),
            child: const Row(
              children: [
                Icon(Icons.confirmation_number_outlined,
                    color: AppColors.primary),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'إنشاء دفعة كروت جديدة على الراوتر مباشرة',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _countCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'عدد الكروت',
                    prefixIcon: Icon(Icons.numbers),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _lengthCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'طول الكود',
                    prefixIcon: Icon(Icons.straighten),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          snap.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, _) => const SizedBox.shrink(),
            data: (s) => DropdownButtonFormField<String>(
              initialValue: _profile,
              decoration: const InputDecoration(
                labelText: 'باقة Hotspot',
                prefixIcon: Icon(Icons.speed),
              ),
              items: s.profiles
                  .map((p) => DropdownMenuItem(
                        value: p['name'],
                        child: Text(
                            '${p['name']}${(p['rate-limit'] ?? '').isNotEmpty ? ' — ${p['rate-limit']}' : ''}'),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _profile = v),
            ),
          ),
          const SizedBox(height: 14),
          // ── Consumption limits (قيود الاستهلاك) ──
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.inputBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('قيود الاستهلاك (اختياري)',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: AppColors.primary)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _dataCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'الرصيد'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _dataUnit,
                        decoration:
                            const InputDecoration(labelText: 'وحدة'),
                        items: const [
                          DropdownMenuItem(
                              value: 'G', child: Text('GB')),
                          DropdownMenuItem(
                              value: 'M', child: Text('MB')),
                        ],
                        onChanged: (v) => setState(
                            () => _dataUnit = v ?? 'G'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _uptimeCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'وقت الاستهلاك'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _uptimeUnit,
                        decoration:
                            const InputDecoration(labelText: 'وحدة'),
                        items: const [
                          DropdownMenuItem(
                              value: 'h', child: Text('ساعة')),
                          DropdownMenuItem(
                              value: 'm', child: Text('دقيقة')),
                        ],
                        onChanged: (v) => setState(
                            () => _uptimeUnit = v ?? 'h'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _validityCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'صلاحية الحساب (أيام)'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _priceCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'سعر البيع (ر.ي)'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('كلمة المرور = رقم الكرت',
                style: TextStyle(fontSize: 13)),
            value: _sameAsCode,
            activeThumbColor: AppColors.primary,
            onChanged: (v) => setState(() => _sameAsCode = v),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(_error!,
                  style:
                      const TextStyle(color: AppColors.accent, fontSize: 12)),
            ),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _running ? null : _generate,
              icon: _running
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.bolt),
              label: Text(_running
                  ? 'جارٍ الإنشاء $_done/$_total'
                  : 'توليد على الراوتر'),
            ),
          ),
          if (_running) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: _total > 0 ? _done / _total : null,
                minHeight: 8,
                backgroundColor: AppColors.divider,
                valueColor:
                    const AlwaysStoppedAnimation(AppColors.primary),
              ),
            ),
          ],
          if (_generated.isNotEmpty) ...[
            const SizedBox(height: 24),
            _GeneratedSection(
              codes: _generated,
              router: widget.router,
              networks: networks.value ?? [],
              categories: categories.value ?? [],
              networkId: _networkId,
              categoryId: _categoryId,
              templates: _templates,
              template: _template,
              onTemplateChanged: (t) => setState(() => _template = t),
              onTemplatesUpdated: _loadTemplates,
              onNetworkChanged: (v) => setState(() {
                _networkId = v;
                _categoryId = null;
              }),
              onCategoryChanged: (v) => setState(() => _categoryId = v),
              onUpload: _uploadToPlatform,
              onCopy: _copyAll,
            ),
          ],
        ],
      ),
    );
  }
}

class _GeneratedSection extends StatelessWidget {
  final List<String> codes;
  final MikrotikRouterConfig router;
  final List<Map<String, dynamic>> networks;
  final List<Map<String, dynamic>> categories;
  final int? networkId;
  final int? categoryId;
  final List<CardTemplate> templates;
  final CardTemplate? template;
  final ValueChanged<CardTemplate?> onTemplateChanged;
  final VoidCallback onTemplatesUpdated;
  final ValueChanged<int?> onNetworkChanged;
  final ValueChanged<int?> onCategoryChanged;
  final VoidCallback onUpload;
  final VoidCallback onCopy;

  const _GeneratedSection({
    required this.codes,
    required this.router,
    required this.networks,
    required this.categories,
    required this.networkId,
    required this.categoryId,
    required this.templates,
    required this.template,
    required this.onTemplateChanged,
    required this.onTemplatesUpdated,
    required this.onNetworkChanged,
    required this.onCategoryChanged,
    required this.onUpload,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final filtered = networkId == null
        ? categories
        : categories
            .where((c) => c['network_id'] == networkId)
            .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('تم إنشاء ${codes.length} كرت',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 15)),
            const Spacer(),
            TextButton.icon(
              onPressed: onCopy,
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('نسخ الكل'),
            ),
          ],
        ),
        Container(
          constraints: const BoxConstraints(maxHeight: 200),
          decoration: BoxDecoration(
            color: AppColors.inputBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.divider),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.all(12),
            itemCount: codes.length,
            separatorBuilder: (_, _) =>
                const Divider(height: 12, color: AppColors.divider),
            itemBuilder: (_, i) => Text(
              codes[i],
              style: const TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 8),
        // ── Print / export with templates ──
        Row(
          children: [
            const Text('الطباعة والتصدير',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14)),
            const Spacer(),
            TextButton.icon(
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) =>
                      CardTemplatesScreen(router: router),
                ));
                onTemplatesUpdated();
              },
              icon: const Icon(Icons.style_outlined, size: 16),
              label: const Text('إدارة القوالب'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (templates.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.3)),
            ),
            child: const Text(
              'لا توجد قوالب — صمّم قالباً أولاً من «إدارة القوالب» لتتمكن من طباعة الكروت أو تصديرها',
              style:
                  TextStyle(fontSize: 12, color: AppColors.textGray),
            ),
          )
        else ...[
          DropdownButtonFormField<String>(
            initialValue: template?.id,
            decoration: const InputDecoration(
              labelText: 'قالب الطباعة',
              prefixIcon: Icon(Icons.style_outlined),
            ),
            items: templates
                .map((t) => DropdownMenuItem(
                    value: t.id, child: Text(t.name)))
                .toList(),
            onChanged: (id) => onTemplateChanged(
                templates.where((t) => t.id == id).firstOrNull),
          ),
          if (template != null) ...[
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.55,
              ),
              itemCount: codes.length > 6 ? 6 : codes.length,
              itemBuilder: (_, i) => VoucherCardView(
                  template: template!, code: codes[i], qrSize: 46),
            ),
            if (codes.length > 6)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('+${codes.length - 6} كرت آخر — كلها في الملف',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textGray)),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () =>
                        VoucherPrintService.print(codes, template!),
                    icon: const Icon(Icons.print_outlined),
                    label: const Text('طباعة'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        VoucherPrintService.sharePdf(codes, template!),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('مشاركة PDF'),
                  ),
                ),
              ],
            ),
          ],
        ],
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 8),
        const Text('رفع الكروت للمنصة (اختياري)',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 6),
        const Text(
          'لعرضها للبيع في تطبيق العملاء، اختر الشبكة والفئة',
          style: TextStyle(color: AppColors.textGray, fontSize: 12),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: networkId,
          decoration: const InputDecoration(
            labelText: 'الشبكة',
            prefixIcon: Icon(Icons.wifi),
          ),
          items: networks
              .map((n) => DropdownMenuItem(
                    value: n['id'] as int?,
                    child: Text(n['name']?.toString() ?? ''),
                  ))
              .toList(),
          onChanged: onNetworkChanged,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: categoryId,
          decoration: const InputDecoration(
            labelText: 'الفئة',
            prefixIcon: Icon(Icons.category_outlined),
          ),
          items: filtered
              .map((c) => DropdownMenuItem(
                    value: c['id'] as int?,
                    child: Text(
                        '${c['name'] ?? ''} — ${c['price'] ?? ''} ر'),
                  ))
              .toList(),
          onChanged: onCategoryChanged,
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent),
            onPressed: onUpload,
            icon: const Icon(Icons.cloud_upload_outlined),
            label: const Text('رفع الكروت للمنصة'),
          ),
        ),
      ],
    );
  }
}
