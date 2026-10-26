import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/card_template.dart';
import '../../data/card_template_store.dart';
import '../../data/feature_keys.dart';
import '../../data/router_model.dart';
import '../providers/entitlement_provider.dart';
import '../widgets/premium_lock_card.dart';
import '../widgets/voucher_card_view.dart';

/// Saved card templates for one router + the visual designer.
/// Manual mode: colors, text, font size, live preview.
/// Image mode: pick a ready design image, code/QR overlayed.
class CardTemplatesScreen extends ConsumerWidget {
  final MikrotikRouterConfig router;
  const CardTemplatesScreen({super.key, required this.router});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allowed =
        ref.watch(featureAllowedProvider(MikroFeatures.cardTemplates));
    if (!allowed) return const PremiumLockCard();
    return _TemplatesBody(router: router);
  }
}

class _TemplatesBody extends ConsumerStatefulWidget {
  final MikrotikRouterConfig router;
  const _TemplatesBody({required this.router});

  @override
  ConsumerState<_TemplatesBody> createState() => _TemplatesBodyState();
}

class _TemplatesBodyState extends ConsumerState<_TemplatesBody> {
  List<CardTemplate> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await CardTemplateStore.load(widget.router.id);
    if (mounted) {
      setState(() {
        _items = list;
        _loading = false;
      });
    }
  }

  Future<void> _save(CardTemplate t) async {
    await CardTemplateStore.upsert(widget.router.id, t);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('تم حفظ القالب'),
          behavior: SnackBarBehavior.floating));
    }
  }

  Future<void> _delete(CardTemplate t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف القالب'),
        content: Text('حذف "${t.name}" نهائياً؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await CardTemplateStore.delete(widget.router.id, t.id);
      await _load();
    }
  }

  void _openDesigner({CardTemplate? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DesignerSheet(
        initial: existing,
        defaultNetworkName: widget.router.name,
        onSave: _save,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(title: const Text('قوالب الكروت')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.style_outlined,
                          size: 56, color: AppColors.divider),
                      const SizedBox(height: 14),
                      const Text('لا توجد قوالب محفوظة لهذه الشبكة',
                          style: TextStyle(color: AppColors.textGray)),
                      const SizedBox(height: 6),
                      const Text('صمّم قالباً يدوياً أو استخدم صورة جاهزة',
                          style: TextStyle(
                              color: AppColors.textLight, fontSize: 12)),
                    ],
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.78,
                  ),
                  itemCount: _items.length,
                  itemBuilder: (_, i) {
                    final t = _items[i];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: VoucherCardView(
                              template: t, code: 'USER-PASS'),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: Text(t.name,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700),
                                  overflow: TextOverflow.ellipsis),
                            ),
                            InkWell(
                              onTap: () => _openDesigner(existing: t),
                              child: const Icon(Icons.edit_outlined,
                                  size: 18, color: AppColors.primary),
                            ),
                            const SizedBox(width: 10),
                            InkWell(
                              onTap: () => _delete(t),
                              child: const Icon(Icons.delete_outline,
                                  size: 18, color: AppColors.accent),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openDesigner(),
        icon: const Icon(Icons.add),
        label: const Text('قالب جديد'),
      ),
    );
  }
}

// ── Designer sheet ─────────────────────────────────────────────

const _palette = <int>[
  0xFF1E2D7D, 0xFFE31E24, 0xFF4B7BEC, 0xFF16235F, 0xFF10B981,
  0xFFF59E0B, 0xFF8B5CF6, 0xFF0EA5E9, 0xFFEC4899, 0xFF14B8A6,
  0xFF64748B, 0xFF0F1729, 0xFF78350F, 0xFF065F46, 0xFF7C3AED,
  0xFFDC2626, 0xFF2563EB, 0xFF059669, 0xFFD97706, 0xFF111827,
];

class _DesignerSheet extends StatefulWidget {
  final CardTemplate? initial;
  final String defaultNetworkName;
  final ValueChanged<CardTemplate> onSave;

  const _DesignerSheet({
    this.initial,
    required this.defaultNetworkName,
    required this.onSave,
  });

  @override
  State<_DesignerSheet> createState() => _DesignerSheetState();
}

class _DesignerSheetState extends State<_DesignerSheet> {
  late CardTemplate _t;
  late final TextEditingController _name;
  late final TextEditingController _network;
  late final TextEditingController _contact;
  late final TextEditingController _package;
  late final TextEditingController _price;
  late final TextEditingController _loginUrl;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _t = i ??
        CardTemplate(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: '',
          networkName: widget.defaultNetworkName,
        );
    _name = TextEditingController(text: _t.name);
    _network = TextEditingController(text: _t.networkName);
    _contact = TextEditingController(text: _t.contact);
    _package = TextEditingController(text: _t.packageLabel);
    _price = TextEditingController(
        text: _t.price == 0 ? '' : '${_t.price}');
    _loginUrl = TextEditingController(text: _t.loginUrl ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _network.dispose();
    _contact.dispose();
    _package.dispose();
    _price.dispose();
    _loginUrl.dispose();
    super.dispose();
  }

  void _mut(VoidCallback fn) => setState(fn);

  Future<void> _pickImage() async {
    final x = await ImagePicker()
        .pickImage(source: ImageSource.gallery, maxWidth: 1600);
    if (x != null) {
      _mut(() => _t = _t.copyWith(isImage: true, imagePath: x.path));
    }
  }

  void _save() {
    if (_name.text.trim().isEmpty) return;
    final t = _t.copyWith(
      name: _name.text.trim(),
      networkName: _network.text.trim(),
      contact: _contact.text.trim(),
      packageLabel: _package.text.trim(),
      price: int.tryParse(_price.text.trim()) ?? 0,
      loginUrl: _loginUrl.text.trim().isEmpty
          ? null
          : _loginUrl.text.trim(),
    );
    widget.onSave(t);
    Navigator.pop(context);
  }

  Widget _colorRow(String label, int selected,
      ValueChanged<int> onPick) {
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
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final c = _palette[i];
              final sel = c == selected;
              return InkWell(
                onTap: () => onPick(c),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: 30,
                  height: 30,
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

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(16, 14, 16, 16 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 14),
            // ── Mode toggle ──
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: const Text('تصميم يدوي'),
                    selected: !_t.isImage,
                    onSelected: (_) =>
                        _mut(() => _t = _t.copyWith(isImage: false)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ChoiceChip(
                    label: const Text('قالب صوري'),
                    selected: _t.isImage,
                    onSelected: (_) =>
                        _mut(() => _t = _t.copyWith(isImage: true)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // ── Live preview ──
            Center(
              child: SizedBox(
                width: 240,
                child: AspectRatio(
                  aspectRatio: 1.55,
                  child: VoucherCardView(
                      template: _t, code: 'USER-PASS'),
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                  labelText: 'اسم القالب المرجعي'),
            ),
            const SizedBox(height: 10),
            if (_t.isImage) ...[
              OutlinedButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.image_outlined),
                label: Text(_t.imagePath == null
                    ? 'اختيار صورة التصميم'
                    : 'تغيير الصورة'),
              ),
              const SizedBox(height: 10),
            ],
            if (!_t.isImage) ...[
              TextField(
                controller: _network,
                decoration:
                    const InputDecoration(labelText: 'اسم الشبكة'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _contact,
                decoration:
                    const InputDecoration(labelText: 'رقم التواصل'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _package,
                decoration: const InputDecoration(
                    labelText: 'اسم الباقة على الكرت'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _price,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'السعر على الكرت (ر.ي)'),
              ),
              const SizedBox(height: 12),
              _colorRow('اللون 1', _t.color1,
                  (c) => _mut(() => _t = _t.copyWith(color1: c))),
              const SizedBox(height: 8),
              _colorRow('اللون 2', _t.color2,
                  (c) => _mut(() => _t = _t.copyWith(color2: c))),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('حجم الخط',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textGray)),
                  Expanded(
                    child: Slider(
                      value: _t.fontSize.clamp(12, 30),
                      min: 12,
                      max: 30,
                      divisions: 18,
                      onChanged: (v) =>
                          _mut(() => _t = _t.copyWith(fontSize: v)),
                    ),
                  ),
                  Text(_t.fontSize.toStringAsFixed(0),
                      style: const TextStyle(fontSize: 12)),
                ],
              ),
            ],
            TextField(
              controller: _loginUrl,
              decoration: const InputDecoration(
                labelText: 'رابط QR (اختياري)',
                helperText:
                    'مثال: http://wifi.net/login?user={code} — {code} يُستبدل برقم الكرت',
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _name.text.trim().isEmpty ? null : _save,
                icon: const Icon(Icons.check),
                label: const Text('حفظ القالب النهائي'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
