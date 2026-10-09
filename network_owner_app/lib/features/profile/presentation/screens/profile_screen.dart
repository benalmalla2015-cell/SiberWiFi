import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/cache/hive_service.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../auth/data/auth_repository.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _uploadingAvatar = false;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('حسابي')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _ProfileHeader(
              name: user?.name ?? '',
              phone: user?.phone ?? '',
              networkCode: user?.networkId?.toString(),
              avatarUrl: user?.avatar,
              uploading: _uploadingAvatar,
              onAvatarTap: _pickAvatar,
            ),
            const SizedBox(height: 20),
            _ProfileCard(
              items: [
                _ProfileItem(
                  icon: Icons.edit_outlined,
                  label: 'تعديل بيانات الحساب',
                  value: '',
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: AppColors.textGray,
                  ),
                  onTap: () => _showEditProfileDialog(
                    user?.name ?? '',
                    user?.email ?? '',
                  ),
                ),
                _ProfileItem(
                  icon: Icons.phone_outlined,
                  label: 'رقم الهاتف',
                  value: user?.phone ?? '—',
                ),
                _ProfileItem(
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'بيانات المدفوعات والسحب',
                  value: '',
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: AppColors.textGray,
                  ),
                  onTap: _showPayoutDetailsDialog,
                ),
                _ProfileItem(
                  icon: Icons.account_balance_outlined,
                  label: 'رقم الحساب',
                  value: user?.accountNumber ?? '—',
                ),
              ],
            ),
            const SizedBox(height: 16),
            _ProfileCard(
              title: 'معلومات التطبيق',
              items: [
                _ProfileItem(
                  icon: Icons.info_outline,
                  label: 'من نحن',
                  value: '',
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: AppColors.textGray,
                  ),
                  onTap: () => context.push('/about-us'),
                ),
                _ProfileItem(
                  icon: Icons.article_outlined,
                  label: 'شروط الخدمة',
                  value: '',
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: AppColors.textGray,
                  ),
                  onTap: () => context.push('/terms-of-service'),
                ),
                _ProfileItem(
                  icon: Icons.privacy_tip_outlined,
                  label: 'سياسة الخصوصية',
                  value: '',
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: AppColors.textGray,
                  ),
                  onTap: () => context.push('/privacy-policy'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _ProfileCard(
              title: 'الإعدادات',
              items: [
                _ProfileItem(
                  icon: Icons.lock_outlined,
                  label: 'تغيير كلمة المرور',
                  value: '',
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: AppColors.textGray,
                  ),
                  onTap: () => _showChangePasswordDialog(),
                ),
                _ProfileItem(
                  icon: Icons.notifications_outlined,
                  label: 'رسائل العملاء',
                  value: '',
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: AppColors.textGray,
                  ),
                  onTap: () => context.push('/conversations'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  try {
                    await ref.read(authProvider.notifier).logout();
                  } finally {
                    // The GoRouter auth redirect navigates to /login when the
                    // session state changes; context.go() on a deactivating
                    // context asserts '_dependents.isEmpty'.
                  }
                },
                icon: const Icon(Icons.logout, color: AppColors.error),
                label: const Text(
                  'تسجيل الخروج',
                  style: TextStyle(color: AppColors.error),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.error),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _confirmDeleteAccount(context, ref),
                icon: const Icon(Icons.delete_forever, color: AppColors.error),
                label: const Text(
                  'حذف الحساب',
                  style: TextStyle(color: AppColors.error),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.error),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteAccount(BuildContext context, WidgetRef ref) async {
    final passwordController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text(
          'حذف الحساب',
          style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.error),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('سيتم حذف حسابك نهائياً وإلغاء جميع جلسات الدخول. لا يمكن التراجع عن هذا الإجراء.'),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'كلمة المرور الحالية',
                border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    final password = confirmed == true ? passwordController.text.trim() : '';
    // The dialog's TextField keeps rebuilding during the dismiss animation —
    // dispose after it finishes, otherwise the framework throws
    // "TextEditingController used after being disposed" / '_dependents.isEmpty'.
    Future.delayed(const Duration(milliseconds: 400), passwordController.dispose);

    if (confirmed != true) return;

    if (password.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يرجى إدخال كلمة المرور')),
        );
      }
      return;
    }

    final success = await ref.read(authProvider.notifier).deleteAccount(password: password);
    if (!context.mounted) return;
    if (!success) {
      final error = ref.read(authProvider).error ?? 'تعذر حذف الحساب';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: AppColors.error),
      );
    }
    // On success, the GoRouter auth redirect routes to /login automatically —
    // calling context.go() here asserts '_dependents.isEmpty' on the
    // deactivating context.
  }

  Future<void> _showPayoutDetailsDialog() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => const _PayoutDetailsDialog(),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم حفظ بيانات المدفوعات والسحب'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  Future<void> _pickAvatar() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1024,
    );
    if (image == null || !mounted) return;

    setState(() => _uploadingAvatar = true);
    final success = await ref
        .read(authProvider.notifier)
        .updateAvatar(image.path);
    if (!mounted) return;
    setState(() => _uploadingAvatar = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'تم تحديث الصورة الشخصية'
              : ref.read(authProvider).error ?? 'تعذر تحديث الصورة الشخصية',
        ),
        backgroundColor: success ? AppColors.success : AppColors.error,
      ),
    );
  }

  Future<void> _showEditProfileDialog(String name, String email) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _EditProfileDialog(name: name, email: email),
    );
    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تحديث بيانات الحساب'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  Future<void> _showChangePasswordDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => const _ChangePasswordDialog(),
    );
    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تغيير كلمة المرور'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }
}

class _PayoutDetailsDialog extends ConsumerStatefulWidget {
  const _PayoutDetailsDialog();

  @override
  ConsumerState<_PayoutDetailsDialog> createState() =>
      _PayoutDetailsDialogState();
}

class _PayoutDetailsDialogState extends ConsumerState<_PayoutDetailsDialog> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _providerController = TextEditingController();
  final _accountController = TextEditingController();
  bool _loading = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFromCache();
    _loadFromServer();
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _providerController.dispose();
    _accountController.dispose();
    super.dispose();
  }

  void _loadFromCache() {
    try {
      final cached = HiveService.getPayoutDetails();
      if (cached != null) {
        _fullNameController.text = cached['full_name'] ?? '';
        _providerController.text = cached['provider'] ?? '';
        _accountController.text = cached['account_number'] ?? '';
      }
    } catch (_) {}
  }

  Future<void> _loadFromServer() async {
    try {
      final data = await ref.read(authRepositoryProvider).getPayoutDetails();
      if (!mounted) return;
      _fullNameController.text = data['full_name']?.toString() ?? '';
      _providerController.text = data['provider']?.toString() ?? '';
      _accountController.text = data['account_number']?.toString() ?? '';
      HiveService.savePayoutDetails(data);
    } catch (_) {}
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final data = {
        'full_name': _fullNameController.text.trim(),
        'provider': _providerController.text,
        'account_number': _accountController.text,
      };
      await ref.read(authRepositoryProvider).updatePayoutDetails(
        fullName: data['full_name']!,
        provider: data['provider'],
        accountNumber: data['account_number'],
      );
      HiveService.savePayoutDetails(data);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted)
        setState(() {
          _saving = false;
          _error = error.toString();
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('بيانات المدفوعات والسحب'),
      content: _loading
          ? const SizedBox(
              height: 100,
              child: Center(child: CircularProgressIndicator()),
            )
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: _fullNameController,
                      decoration: const InputDecoration(
                        labelText: 'الاسم الرباعي *',
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'أدخل الاسم الرباعي';
                        }
                        final nameCount = value.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
                        if (nameCount < 4) {
                          return 'يجب إدخال الاسم الرباعي على الأقل (4 أسماء)';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _providerController,
                      decoration: const InputDecoration(
                        labelText: 'اسم البنك أو المصرف',
                        hintText: 'حساب كريمي أو محفظة جيب',
                        floatingLabelBehavior: FloatingLabelBehavior.always,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _accountController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'رقم الحساب',
                        hintText: 'اكتب رقم الحساب ريال يمني قديم أو قعيطي',
                        floatingLabelBehavior: FloatingLabelBehavior.always,
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: const TextStyle(
                          color: AppColors.error,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: _loading || _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Text('إرسال'),
        ),
      ],
    );
  }
}

class _EditProfileDialog extends ConsumerStatefulWidget {
  final String name;
  final String email;

  const _EditProfileDialog({required this.name, required this.email});

  @override
  ConsumerState<_EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends ConsumerState<_EditProfileDialog> {
  late final _nameController = TextEditingController(text: widget.name);
  late final _emailController = TextEditingController(text: widget.email);
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('تعديل بيانات الحساب'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'الاسم'),
                  validator: (value) {
                    final v = value?.trim() ?? '';
                    if (v.isEmpty) return 'أدخل الاسم';
                    if (v.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length < 4) {
                      return 'يجب إدخال الاسم الرباعي على الأقل';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'البريد الإلكتروني'),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return null;
                    return value.contains('@')
                        ? null
                        : 'البريد الإلكتروني غير صالح';
                  },
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(color: AppColors.error, fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Row(
            textDirection: TextDirection.rtl,
            children: [
              Expanded(
                child: AppButton(
                  label: 'حفظ',
                  height: 44,
                  fontSize: 14,
                  borderRadius: 12,
                  isLoading: _loading,
                  onPressed: _save,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton(
                    onPressed: _loading ? null : () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      side: const BorderSide(color: AppColors.primary, width: 1.5),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                    ),
                    child: const Text(
                      'إلغاء',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final success = await ref
        .read(authProvider.notifier)
        .updateProfile(
          name: _nameController.text.trim(),
          email: _emailController.text.trim(),
        );
    if (!mounted) return;
    if (success) {
      Navigator.pop(context, true);
    } else {
      final err = ref.read(authProvider).error;
      setState(() {
        _loading = false;
        _error = err ?? 'تعذر تحديث البيانات';
      });
    }
  }
}

class _ChangePasswordDialog extends ConsumerStatefulWidget {
  const _ChangePasswordDialog();

  @override
  ConsumerState<_ChangePasswordDialog> createState() =>
      _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends ConsumerState<_ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _currentController.dispose();
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('تغيير كلمة المرور'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _currentController,
                obscureText: true,
              decoration: const InputDecoration(
                labelText: 'كلمة المرور الحالية',
              ),
              validator: (value) => value == null || value.isEmpty
                  ? 'أدخل كلمة المرور الحالية'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'كلمة المرور الجديدة',
              ),
              validator: (value) => value == null || value.length < 6
                  ? 'أدخل 6 أحرف على الأقل'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirmationController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'تأكيد كلمة المرور'),
              validator: (value) => value != _passwordController.text
                  ? 'كلمتا المرور غير متطابقتين'
                  : null,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: AppColors.error, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context, false),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: _loading ? null : _change,
          child: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('تغيير'),
        ),
      ],
    );
  }

  Future<void> _change() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final success = await ref
        .read(authProvider.notifier)
        .changePassword(
          currentPassword: _currentController.text,
          password: _passwordController.text,
          passwordConfirmation: _confirmationController.text,
        );
    if (!mounted) return;
    if (success) {
      Navigator.pop(context, true);
    } else {
      final err = ref.read(authProvider).error;
      setState(() {
        _loading = false;
        _error = err ?? 'تعذر تغيير كلمة المرور';
      });
    }
  }
}

class _ProfileHeader extends StatelessWidget {
  final String name, phone;
  final String? networkCode;
  final String? avatarUrl;
  final bool uploading;
  final VoidCallback onAvatarTap;

  const _ProfileHeader({
    required this.name,
    required this.phone,
    this.networkCode,
    required this.avatarUrl,
    required this.uploading,
    required this.onAvatarTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF16235F), Color(0xFF1E2D7D), Color(0xFF2A3A9A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: [0.0, 0.5, 1.0],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Color(0x331E2D7D),
            blurRadius: 14,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          InkWell(
            onTap: uploading ? null : onAvatarTap,
            borderRadius: BorderRadius.circular(22),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(22),
                    image: avatarUrl == null || avatarUrl!.isEmpty
                        ? null
                        : DecorationImage(
                            image: NetworkImage(avatarUrl!),
                            fit: BoxFit.cover,
                          ),
                  ),
                  child: uploading
                      ? const Center(
                          child: SizedBox(
                            width: 26,
                            height: 26,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          ),
                        )
                      : avatarUrl == null || avatarUrl!.isEmpty
                      ? const Icon(Icons.person, color: Colors.white, size: 38)
                      : null,
                ),
                Positioned(
                  bottom: -5,
                  right: -5,
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: const BoxDecoration(
                      color: AppColors.lightBlue,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.camera_alt_outlined,
                      color: Colors.white,
                      size: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  phone,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 4),
                if (networkCode != null && networkCode!.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: networkCode!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('تم نسخ رقم الشبكة'),
                          backgroundColor: AppColors.success,
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.20),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'ID: $networkCode',
                            textDirection: TextDirection.rtl,
                            style: const TextStyle(
                              fontFamily: 'Roboto',
                              color: Colors.white,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.copy,
                            color: Colors.white,
                            size: 13,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final List<_ProfileItem> items;
  final String? title;
  const _ProfileCard({required this.items, this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Text(
                title!,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: AppColors.primary,
                ),
              ),
            ),
          ...items.asMap().entries.map(
            (e) => Column(
              children: [
                _ProfileTile(item: e.value),
                if (e.key < items.length - 1)
                  const Divider(
                    height: 1,
                    indent: 56,
                    color: AppColors.divider,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileItem {
  final IconData icon;
  final String label, value;
  final Widget? trailing;
  final VoidCallback? onTap;
  const _ProfileItem({
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
    this.onTap,
  });
}

class _ProfileTile extends StatelessWidget {
  final _ProfileItem item;
  const _ProfileTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: item.onTap,
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(item.icon, color: AppColors.primary, size: 18),
      ),
      title: Text(
        item.label,
        style: const TextStyle(fontSize: 13, color: AppColors.textGray),
      ),
      subtitle: item.value.isNotEmpty
          ? Text(
              item.value,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textDark,
                fontWeight: FontWeight.w500,
              ),
            )
          : null,
      trailing: item.trailing,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }
}
