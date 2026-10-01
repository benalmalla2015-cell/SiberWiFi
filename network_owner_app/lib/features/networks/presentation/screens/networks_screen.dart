import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/networks_repository.dart';
import '../providers/networks_provider.dart';
import 'cards_screen.dart';
import 'add_edit_network_screen.dart';
import 'categories_management_screen.dart';

class NetworksScreen extends ConsumerWidget {
  const NetworksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final networksAsync = ref.watch(networksProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('شبكاتي والكروت'),
          actions: [
            IconButton(
              icon: const Icon(Icons.category_outlined),
              tooltip: 'إدارة الفئات',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const CategoriesManagementScreen(),
                ),
              ),
            ),
          ],
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            indicatorColor: Colors.white,
            tabs: [
              Tab(icon: Icon(Icons.wifi, size: 18), text: 'شبكاتي'),
              Tab(icon: Icon(Icons.credit_card, size: 18), text: 'الكروت'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _NetworksTab(networksAsync: networksAsync, ref: ref),
            const CardsTab(),
          ],
        ),
        floatingActionButton: _NetworksFAB(ref: ref),
      ),
    );
  }
}

class _NetworksFAB extends ConsumerStatefulWidget {
  final WidgetRef ref;
  const _NetworksFAB({required this.ref});
  @override
  ConsumerState<_NetworksFAB> createState() => _NetworksFABState();
}

class _NetworksFABState extends ConsumerState<_NetworksFAB> {
  int _tabIndex = 0;
  TabController? _tabController;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tabController?.removeListener(_onTabChanged);
    _tabController = DefaultTabController.of(context);
    _tabController?.addListener(_onTabChanged);
    _tabIndex = _tabController?.index ?? 0;
  }

  void _onTabChanged() {
    if (mounted && _tabController != null) {
      setState(() => _tabIndex = _tabController!.index);
    }
  }

  @override
  void dispose() {
    _tabController?.removeListener(_onTabChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_tabIndex == 0) {
      return FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddEditNetworkScreen()),
          );
          if (result == true) ref.invalidate(networksProvider);
        },
        icon: const Icon(Icons.add),
        label: const Text('إضافة شبكة'),
        backgroundColor: AppColors.primary,
      );
    }
    return FloatingActionButton.extended(
      onPressed: () => _showUploadCardsSheet(context, ref),
      icon: const Icon(Icons.upload_file),
      label: const Text('رفع كروت'),
      backgroundColor: AppColors.lightBlue,
    );
  }
}

class _NetworksTab extends StatelessWidget {
  final AsyncValue<List<Map<String, dynamic>>> networksAsync;
  final WidgetRef ref;
  const _NetworksTab({required this.networksAsync, required this.ref});

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(networksProvider),
      child: networksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('خطأ: $e')),
        data: (networks) => networks.isEmpty
            ? const _EmptyNetworks()
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: networks.length,
                itemBuilder: (ctx, i) => _NetworkCard(
                  network: networks[i],
                  onEdit: () async {
                    final result = await Navigator.push(
                      ctx,
                      MaterialPageRoute(
                        builder: (_) =>
                            AddEditNetworkScreen(network: networks[i]),
                      ),
                    );
                    if (result == true) ref.invalidate(networksProvider);
                  },
                ),
              ),
      ),
    );
  }
}

class _NetworkCard extends ConsumerWidget {
  final Map<String, dynamic> network;
  final VoidCallback onEdit;
  const _NetworkCard({required this.network, required this.onEdit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isActive =
        network['is_active'] == true || network['status'] == 'active';
    final statusAppr = network['approval_status'] ?? network['status'] ?? '';
    final name = network['name'] ?? 'شبكة';
    final networkCode = network['code']?.toString() ?? network['id']?.toString() ?? '';
    final location = network['location'] ?? network['address'] ?? '';
    final price =
        (network['price_per_day'] ?? network['subscription_price'] ?? 0)
            .toDouble();
    final speed = network['speed'] ?? '';
    final coverUrl = network['cover_image_url']?.toString();
    final backgroundUrl = network['background_image_url']?.toString();

    Color approvalColor = AppColors.textGray;
    String approvalLabel = '';
    if (statusAppr == 'approved' || statusAppr == 'active') {
      approvalColor = AppColors.success;
      approvalLabel = 'معتمدة';
    } else if (statusAppr == 'pending') {
      approvalColor = AppColors.warning;
      approvalLabel = 'قيد المراجعة';
    } else if (statusAppr == 'rejected') {
      approvalColor = AppColors.error;
      approvalLabel = 'مرفوضة';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if ((backgroundUrl?.isNotEmpty ?? false) ||
                (coverUrl?.isNotEmpty ?? false)) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  height: 120,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        backgroundUrl?.isNotEmpty == true
                            ? backgroundUrl!
                            : coverUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: AppColors.primary.withValues(alpha: 0.08),
                        ),
                      ),
                      Container(color: Colors.black.withValues(alpha: 0.22)),
                      if (coverUrl?.isNotEmpty == true)
                        Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.network(
                                coverUrl!,
                                width: 104,
                                height: 84,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    const SizedBox.shrink(),
                              ),
                            ),
                          ),
                        ),
                      Align(
                        alignment: Alignment.bottomLeft,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            name,
                            style: const TextStyle(
                              color: Colors.white,
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
              const SizedBox(height: 14),
            ],
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.wifi,
                    color: AppColors.primary,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      if (networkCode.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: networkCode));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('تم نسخ رقم الشبكة'),
                                backgroundColor: AppColors.success,
                              ),
                            );
                          },
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'ID: $networkCode',
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.copy,
                                size: 13,
                                color: AppColors.primary,
                              ),
                            ],
                          ),
                        ),
                      if (location.isNotEmpty)
                        Text(
                          location,
                          style: const TextStyle(
                            color: AppColors.textGray,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: isActive
                            ? AppColors.success.withValues(alpha: 0.1)
                            : AppColors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        isActive ? 'نشطة' : 'معطّلة',
                        style: TextStyle(
                          color: isActive ? AppColors.success : AppColors.error,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (approvalLabel.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        approvalLabel,
                        style: TextStyle(color: approvalColor, fontSize: 10),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _InfoPill(
                  icon: Icons.speed,
                  label: speed.isNotEmpty ? speed : '—',
                ),
                const SizedBox(width: 8),
                _InfoPill(
                  icon: Icons.attach_money,
                  label: '${price.toStringAsFixed(0)} ر/يوم',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('تعديل', style: TextStyle(fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      side: const BorderSide(color: AppColors.primary),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      final networkId = network['id'];
                      if (networkId is! int) return;
                      ref.read(selectedNetworkIdProvider.notifier).state =
                          networkId;
                      ref.read(selectedCardStatusProvider.notifier).state =
                          'all';
                      DefaultTabController.of(context).animateTo(1);
                    },
                    icon: const Icon(Icons.credit_card, size: 16),
                    label: const Text('كروتها', style: TextStyle(fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      backgroundColor: AppColors.lightBlue,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.inputBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.textGray),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.textGray),
          ),
        ],
      ),
    );
  }
}

class _EmptyNetworks extends StatelessWidget {
  const _EmptyNetworks();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.wifi_off, size: 64, color: AppColors.divider),
          const SizedBox(height: 16),
          const Text(
            'لا توجد شبكات بعد',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'اضغط + لإضافة شبكتك الأولى',
            style: TextStyle(color: AppColors.textGray),
          ),
        ],
      ),
    );
  }
}

void _showUploadCardsSheet(BuildContext context, WidgetRef ref) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _UploadCardsSheet(ref: ref),
  );
}

class _UploadCardsSheet extends ConsumerStatefulWidget {
  final WidgetRef ref;
  const _UploadCardsSheet({required this.ref});
  @override
  ConsumerState<_UploadCardsSheet> createState() => _UploadCardsSheetState();
}

class _UploadCardsSheetState extends ConsumerState<_UploadCardsSheet> {
  final _codesCtrl = TextEditingController();
  int? _selectedCategoryId;
  int? _selectedNetworkId;
  bool _loading = false;
  PlatformFile? _selectedFile;

  @override
  Widget build(BuildContext context) {
    final allCategories = ref.watch(categoriesProvider).value ?? [];
    final networks = ref.watch(networksProvider).value ?? [];
    final cats = _selectedNetworkId == null
        ? <Map<String, dynamic>>[]
        : allCategories
              .where(
                (category) =>
                    category['network_id']?.toString() ==
                    _selectedNetworkId.toString(),
              )
              .toList();

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 20,
        right: 20,
        top: 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'رفع كروت جديدة',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            const Text(
              'أدخل الأكواد أو ارفع ملف كروت',
              style: TextStyle(color: AppColors.textGray, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<int>(
              // ignore: deprecated_member_use
              value: _selectedNetworkId,
              decoration: const InputDecoration(
                labelText: 'اختر الشبكة',
                prefixIcon: Icon(Icons.wifi),
              ),
              isExpanded: true,
              items: networks
                  .map(
                    (n) => DropdownMenuItem<int>(
                      value: n['id'] as int?,
                      child: Text(
                        n['name'] ?? '',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() {
                _selectedNetworkId = v;
                _selectedCategoryId = null;
              }),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              // ignore: deprecated_member_use
              value: _selectedCategoryId,
              decoration: const InputDecoration(
                labelText: 'اختر الفئة',
                prefixIcon: Icon(Icons.category),
              ),
              isExpanded: true,
              items: cats
                  .map(
                    (c) => DropdownMenuItem<int>(
                      value: c['id'] as int?,
                      child: Text(
                        '${c['name']} - ${c['price']} ر',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _selectedCategoryId = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _codesCtrl,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'أكواد الكروت (اختياري عند رفع ملف)',
                alignLabelWithHint: true,
                prefixIcon: Padding(
                  padding: EdgeInsets.only(bottom: 80),
                  child: Icon(Icons.list),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _FilePickerSection(
              file: _selectedFile,
              onPick: _pickFile,
              onClear: () => setState(() => _selectedFile = null),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _loading ? null : _upload,
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.upload),
              label: const Text('رفع الكروت'),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _upload() async {
    final codes = _codesCtrl.text
        .split(RegExp(r'\r?\n'))
        .map((code) => code.trim())
        .where((code) => code.isNotEmpty)
        .toSet()
        .toList();

    if (_selectedCategoryId == null || _selectedNetworkId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('اختر الشبكة والفئة أولاً'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (codes.isEmpty && _selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('أدخل أكواد الكروت أو اختر ملفاً'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final repo = ref.read(networksRepositoryProvider);
      late final Map<String, dynamic> res;

      if (_selectedFile != null) {
        final formData = FormData.fromMap({
          'network_id': _selectedNetworkId.toString(),
          'category_id': _selectedCategoryId.toString(),
          if (codes.isNotEmpty) 'codes': codes,
          'cards_file': await MultipartFile.fromFile(
            _selectedFile!.path!,
            filename: _selectedFile!.name,
          ),
        }, ListFormat.multiCompatible);
        res = await repo.uploadCards(formData);
      } else {
        res = await repo.uploadCards({
          'network_id': _selectedNetworkId,
          'category_id': _selectedCategoryId,
          'codes': codes,
        });
      }

      if (mounted) {
        Navigator.pop(context);
        ref.invalidate(cardsProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              res['message']?.toString() ??
                  'تم رفع ${res['uploaded_count'] ?? codes.length} كرت بنجاح',
            ),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } on DioException catch (e) {
      if (mounted) {
        final data = e.response?.data;
        final message = data is Map
            ? data['message']?.toString() ??
                  (data['errors'] is Map
                      ? (data['errors'] as Map).values.expand((value) => value is List ? value : [value]).join('\n')
                      : null) ??
                  'تعذر رفع الكروت'
            : 'تعذر رفع الكروت';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: AppColors.error),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ غير متوقع: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'xls', 'xlsx', 'xml', 'txt'],
        allowMultiple: false,
        withData: false,
        withReadStream: false,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.path == null || file.path!.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تعذر الوصول إلى مسار الملف'),
              backgroundColor: AppColors.error,
            ),
          );
        }
        return;
      }

      setState(() => _selectedFile = file);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في اختيار الملف: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }
}

class _FilePickerSection extends StatelessWidget {
  final PlatformFile? file;
  final VoidCallback onPick;
  final VoidCallback onClear;

  const _FilePickerSection({
    required this.file,
    required this.onPick,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          children: [
            Expanded(child: Divider()),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('أو', style: TextStyle(color: AppColors.textGray, fontSize: 12)),
            ),
            Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onPick,
          icon: const Icon(Icons.upload_file),
          label: const Text('رفع ملف كروت'),
        ),
        const SizedBox(height: 4),
        const Text(
          'الصيغ المدعومة: CSV, XLS, XLSX, XML',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textGray, fontSize: 11),
        ),
        if (file != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.inputBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.divider),
            ),
            child: Row(
              children: [
                const Icon(Icons.insert_drive_file, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    file!.name,
                    style: const TextStyle(fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                GestureDetector(
                  onTap: onClear,
                  child: const Icon(Icons.close, color: AppColors.error, size: 20),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
