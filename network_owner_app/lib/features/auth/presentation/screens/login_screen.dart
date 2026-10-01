// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../providers/auth_provider.dart';

/// Login screen for the network owner app.
///
/// Rebuilt with the simplest possible widget tree on purpose: no Material
/// elevation, no ClipRRect, no BoxShadow, no ColoredBox, no AnnotatedRegion.
/// Every surface color is set explicitly and opaquely so no OS-level
/// rendering path (Force Dark, Impeller shadow layers, autofill overlays)
/// can turn any part of this screen gray.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneCtr = TextEditingController();
  final _passwordCtr = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _phoneCtr.dispose();
    _passwordCtr.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final ok = await ref
        .read(authProvider.notifier)
        .login(_phoneCtr.text.trim(), _passwordCtr.text);
    if (ok && mounted) {
      context.go('/');
    }
  }

  InputDecoration _decoration({
    required String label,
    required IconData icon,
    Widget? suffix,
  }) {
    const border = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
      borderSide: BorderSide(color: AppColors.divider),
    );
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontFamily: 'Cairo', color: AppColors.textGray, fontSize: 14),
      floatingLabelStyle: const TextStyle(fontFamily: 'Cairo', color: AppColors.primary, fontSize: 13),
      prefixIcon: Icon(icon, color: AppColors.textGray, size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: AppColors.inputBg,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: border,
      enabledBorder: border,
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: AppColors.primary, width: 2),
      ),
      errorBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: AppColors.error),
      ),
      focusedErrorBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: AppColors.error, width: 2),
      ),
      errorStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final top = MediaQuery.of(context).padding.top;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: AppColors.primary,
      body: Column(
        children: [
          // ── Header: navy background with logo ──────────────────────
          SizedBox(
            height: top + 170,
            child: Center(
              child: Image.asset(
                'logo/logo.png',
                width: 148,
                height: 112,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.wifi,
                  color: Colors.white,
                  size: 72,
                ),
              ),
            ),
          ),

          // ── Body: opaque white area with the form ───────────────────
          Expanded(
            child: Container(
              width: double.infinity,
              color: Colors.white,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
                children: [
                  const Text(
                    'تسجيل الدخول',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'تطبيق صاحب الشبكة',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: 'Cairo', fontSize: 13, color: AppColors.textGray),
                  ),
                  const SizedBox(height: 28),
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _phoneCtr,
                          keyboardType: TextInputType.phone,
                          textDirection: TextDirection.ltr,
                          style: const TextStyle(fontFamily: 'Cairo', fontSize: 15, color: AppColors.textDark),
                          decoration: _decoration(
                            label: 'رقم الهاتف',
                            icon: Icons.phone_outlined,
                          ),
                          validator: (v) =>
                              (v == null || v.trim().isEmpty) ? 'أدخل رقم الهاتف' : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordCtr,
                          obscureText: _obscure,
                          style: const TextStyle(fontFamily: 'Cairo', fontSize: 15, color: AppColors.textDark),
                          decoration: _decoration(
                            label: 'كلمة المرور',
                            icon: Icons.lock_outlined,
                            suffix: IconButton(
                              icon: Icon(
                                _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                color: AppColors.textGray,
                                size: 20,
                              ),
                              onPressed: () => setState(() => _obscure = !_obscure),
                            ),
                          ),
                          validator: (v) =>
                              (v == null || v.length < 6) ? 'كلمة المرور قصيرة جداً' : null,
                        ),
                        if (auth.error != null) ...[
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEE2E2),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFFCA5A5)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline, color: AppColors.error, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
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
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        AppButton(
                          label: 'دخول',
                          height: 52,
                          fontSize: 17,
                          isLoading: auth.isLoading,
                          onPressed: _submit,
                        ),
                        const SizedBox(height: 20),
                        TextButton(
                          onPressed: auth.isLoading ? null : () => context.push('/register'),
                          child: const Text(
                            'إنشاء حساب جديد',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 15,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
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
}
