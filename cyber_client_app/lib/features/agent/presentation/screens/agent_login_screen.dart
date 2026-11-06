import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/agent_api.dart';
import '../providers/agent_providers.dart';

/// Agent gate (بوابة دور «وكيل»): a sanctum login followed by the
/// /cyber/agent/profile check — only then does the agent shell open.
class AgentLoginScreen extends ConsumerStatefulWidget {
  const AgentLoginScreen({super.key});

  @override
  ConsumerState<AgentLoginScreen> createState() => _AgentLoginScreenState();
}

class _AgentLoginScreenState extends ConsumerState<AgentLoginScreen> {
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final phone = _phone.text.trim();
    if (phone.length != 9 || _password.text.isEmpty) {
      setState(() => _error = 'أدخل رقم الجوال (9 أرقام) وكلمة المرور');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(agentApiProvider);
      await api.login(phone: phone, password: _password.text);
      // Role gate — verifies this account can act as a CyberNet agent.
      final profile = await api.profile();
      ref.read(agentSessionProvider.notifier).signIn(profile);
    } catch (e) {
      setState(() => _error = ApiClient.errorMessage(e));
      await ref.read(agentApiProvider).logout();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.storefront_rounded, size: 72, color: AppColors.primary),
                  const SizedBox(height: 12),
                  const Text(
                    'بوابة الوكيل — سايبر نت',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textDark),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'سجّل دخولك بحساب الوكيل لشحن أرصدة المشتركين',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textGray),
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    textDirection: TextDirection.ltr,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(9),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'رقم الجوال',
                      prefixIcon: Icon(Icons.phone_outlined),
                      hintText: '7XXXXXXXX',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'كلمة المرور',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.error),
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  FilledButton.icon(
                    onPressed: _loading ? null : _submit,
                    icon: _loading
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.login_rounded),
                    label: Text(_loading ? 'جارٍ التحقق…' : 'دخول'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
