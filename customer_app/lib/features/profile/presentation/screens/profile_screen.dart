import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/api/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _uploadingAvatar = false;

  Future<void> _changeAvatar() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    setState(() => _uploadingAvatar = true);
    try {
      final formData = FormData.fromMap({
        'avatar': await MultipartFile.fromFile(picked.path, filename: picked.name),
      });
      await ref.read(apiClientProvider).post('/profile/avatar', data: formData);
      await ref.read(authProvider.notifier).refreshProfile();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تحديث الصورة الشخصية', style: TextStyle(fontFamily: 'Cairo'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر تحديث الصورة: $e', style: const TextStyle(fontFamily: 'Cairo')), backgroundColor: AppColors.accent),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final user = auth.user;

    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildHeader(context, user)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _sectionCard(
                    children: [
                      _menuItem(
                        icon: Icons.person_outline_rounded,
                        label: 'بيانات الحساب',
                        onTap: () => context.go('/profile/edit'),
                      ),
                      _divider(),
                      _menuItem(
                        icon: Icons.lock_reset_rounded,
                        label: 'تغيير كلمة المرور',
                        onTap: () => context.go('/profile/change-password'),
                      ),
                      _divider(),
                      _menuItem(
                        icon: Icons.notifications_outlined,
                        label: 'الإشعارات',
                        onTap: () => context.go('/notifications'),
                      ),
                      _divider(),
                      _menuItem(
                        icon: Icons.receipt_long_rounded,
                        label: 'سجل معاملاتي',
                        onTap: () => context.go('/transactions'),
                      ),
                      _divider(),
                      _menuItem(
                        icon: Icons.storefront_outlined,
                        label: 'الإحالات والأرباح',
                        onTap: () => context.go('/services'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _sectionCard(
                    children: [
                      _menuItem(
                        icon: Icons.help_outline_rounded,
                        label: 'الدعم الفني',
                        onTap: () => context.go('/support'),
                      ),
                      _divider(),
                      _menuItem(
                        icon: Icons.info_outline_rounded,
                        label: 'عن التطبيق',
                        onTap: () => _showAbout(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _sectionCard(
                    children: [
                      _menuItem(
                        icon: Icons.logout_rounded,
                        label: 'تسجيل الخروج',
                        color: AppColors.accent,
                        onTap: () => _confirmLogout(context, ref),
                      ),
                      _divider(),
                      _menuItem(
                        icon: Icons.delete_forever_rounded,
                        label: 'حذف الحساب',
                        color: AppColors.accent,
                        onTap: () => _confirmDeleteAccount(context, ref),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'سايبر WiFi v1.0.1',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      color: AppColors.textLight,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, user) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primaryDark, AppColors.primary, Color(0xFF243490)],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(36),
          bottomRight: Radius.circular(36),
        ),
      ),
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 20,
        left: 20,
        right: 20,
        bottom: 32,
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: _uploadingAvatar ? null : _changeAvatar,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 82,
                  height: 82,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: _uploadingAvatar
                        ? const Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.primary),
                            ),
                          )
                        : (user?.avatar != null && user!.avatar!.isNotEmpty)
                            ? CachedNetworkImage(
                                imageUrl: user.avatar!,
                                fit: BoxFit.cover,
                                width: 82,
                                height: 82,
                                errorWidget: (_, __, ___) => const Icon(Icons.person_rounded, size: 44, color: AppColors.primary),
                              )
                            : const Icon(Icons.person_rounded, size: 44, color: AppColors.primary),
                  ),
                ),
                Positioned(
                  bottom: -2,
                  left: -2,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(Icons.camera_alt_rounded, size: 14, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            user?.name ?? 'المستخدم',
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            user?.phone ?? '',
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 14,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 4),
          if (user?.email != null && user!.email!.isNotEmpty)
            Text(
              user.email!,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 13,
                color: Colors.white60,
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionCard({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _menuItem({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
    Color? color,
  }) {
    final c = color ?? AppColors.textDark;
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: (color ?? AppColors.primary).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color ?? AppColors.primary, size: 20),
      ),
      title: Text(
        label,
        style: TextStyle(
          fontFamily: 'Cairo',
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: c,
        ),
      ),
      trailing: color == null
          ? const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: AppColors.textLight,
            )
          : null,
      dense: true,
    );
  }

  Widget _divider() => const Divider(
    height: 1,
    indent: 16,
    endIndent: 16,
    color: AppColors.divider,
  );

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'تسجيل الخروج',
          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'هل تريد تسجيل الخروج من حسابك؟',
          style: TextStyle(fontFamily: 'Cairo'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text(
              'إلغاء',
              style: TextStyle(fontFamily: 'Cairo', color: AppColors.textGray),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'خروج',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;

    await ref.read(authProvider.notifier).logout();
    // The GoRouter auth redirect navigates to /login automatically when the
    // session state changes — no context.go() here (it can assert on a
    // deactivating context, see deleteAccount).
  }

  Future<void> _confirmDeleteAccount(BuildContext context, WidgetRef ref) async {
    final passwordController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'حذف الحساب',
          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: AppColors.accent),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'سيتم حذف حسابك نهائياً وإلغاء جميع جلسات الدخول. لا يمكن التراجع عن هذا الإجراء.',
              style: TextStyle(fontFamily: 'Cairo'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'كلمة المرور الحالية',
                border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                labelStyle: TextStyle(fontFamily: 'Cairo'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text(
              'إلغاء',
              style: TextStyle(fontFamily: 'Cairo', color: AppColors.textGray),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text(
              'حذف',
              style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    final password = confirmed == true ? passwordController.text.trim() : '';
    // The dialog's TextField keeps rebuilding during the dismiss animation,
    // so the controller must not be disposed synchronously — defer it until
    // the pop animation has finished to avoid "used after being disposed" /
    // '_dependents.isEmpty' framework assertions.
    Future.delayed(const Duration(milliseconds: 400), passwordController.dispose);

    if (confirmed != true) return;

    if (password.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يرجى إدخال كلمة المرور', style: TextStyle(fontFamily: 'Cairo'))),
        );
      }
      return;
    }

    final error = await ref.read(authProvider.notifier).deleteAccount(password: password);
    if (!context.mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error, style: const TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppColors.accent,
        ),
      );
    }
    // On success, the auth redirect in GoRouter already routes to /login once
    // the session is cleared — calling context.go() here on a deactivating
    // context triggers the '_dependents.isEmpty' framework assertion.
  }

  void _showAbout(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'عن التطبيق',
          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'سايبر WiFi',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'الإصدار 1.0.0\n\nتطبيق اشتراكات الإنترنت - اشترِ كروت الشحن بسهولة.',
              style: TextStyle(
                fontFamily: 'Cairo',
                height: 1.6,
                color: AppColors.textGray,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogCtx),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'حسناً',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
