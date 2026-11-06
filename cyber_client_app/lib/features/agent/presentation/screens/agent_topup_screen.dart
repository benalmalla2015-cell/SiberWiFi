import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_client.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/agent_api.dart';
import '../providers/agent_providers.dart';
import 'agent_qr_scan_screen.dart';

/// «شحن رصيد» — the agent's core flow (CYB-07):
///   74XXXXXXX → lookup name → amount → confirm → POST /cyber/topup
/// with a unique idempotency key per operation (kept stable across
/// retries of the SAME operation so a flaky network never charges twice).
class AgentTopupScreen extends ConsumerStatefulWidget {
  const AgentTopupScreen({super.key});

  @override
  ConsumerState<AgentTopupScreen> createState() => _AgentTopupScreenState();
}

class _AgentTopupScreenState extends ConsumerState<AgentTopupScreen> {
  final _sim = TextEditingController();
  final _amount = TextEditingController();

  bool _lookingUp = false;
  bool _submitting = false;
  Map<String, dynamic>? _subscriber;
  String? _error;
  Map<String, dynamic>? _lastResult;

  /// One key per operation; survives retries, rotates on success.
  String? _idemKey;

  static const _quickAmounts = [200, 500, 800, 1500];

  @override
  void dispose() {
    _sim.dispose();
    _amount.dispose();
    super.dispose();
  }

  String _newKey() =>
      'agt-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 20)}';

  void _resetLookup() {
    _subscriber = null;
    _lastResult = null;
    _idemKey = null;
  }

  Future<void> _scan() async {
    final sim = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const AgentQrScanScreen()),
    );
    if (sim != null && mounted) {
      setState(() {
        _sim.text = sim;
        _resetLookup();
      });
      await _lookup();
    }
  }

  Future<void> _lookup() async {
    final sim = _sim.text.trim();
    if (!AppConfig.simRegex.hasMatch(sim)) {
      setState(() {
        _error = 'أدخل رقم شريحة صحيحاً: ${AppConfig.simPrefix}XXXXXXX (9 أرقام تبدأ بـ ${AppConfig.simPrefix})';
        _subscriber = null;
      });
      return;
    }
    setState(() {
      _lookingUp = true;
      _error = null;
      _subscriber = null;
      _lastResult = null;
    });
    try {
      final sub = await ref.read(agentApiProvider).lookupSubscriber(sim);
      setState(() => _subscriber = sub);
    } catch (e) {
      setState(() => _error = ApiClient.errorMessage(e));
    } finally {
      if (mounted) setState(() => _lookingUp = false);
    }
  }

  double? get _amountValue {
    final v = double.tryParse(_amount.text.trim());
    return v != null && v >= 1 ? v : null;
  }

  Future<void> _submit() async {
    final sub = _subscriber;
    if (sub == null) {
      setState(() => _error = 'تحقق من رقم الشريحة أولاً');
      return;
    }
    final amount = _amountValue;
    if (amount == null) {
      setState(() => _error = 'أدخل مبلغاً صحيحاً (1 ريال فأكثر)');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الشحن'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ConfirmRow('المشترك', sub['full_name']?.toString() ?? ''),
            _ConfirmRow('الرقم', sub['sim_no']?.toString() ?? ''),
            _ConfirmRow('المبلغ', '${amount.toStringAsFixed(0)} ريال'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('شحن الآن'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      // Same key across retries of this operation — the server treats
      // a repeated key as the same charge, never a second one.
      _idemKey ??= _newKey();
      final result = await ref.read(agentApiProvider).topup(
            simNo: _sim.text.trim(),
            amount: amount,
            idempotencyKey: _idemKey!,
          );
      setState(() => _lastResult = result);
      ref.invalidate(agentTopupsProvider);
      ref.invalidate(agentEarningsProvider);
    } catch (e) {
      setState(() => _error = ApiClient.errorMessage(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _newOperation() {
    setState(() {
      _sim.clear();
      _amount.clear();
      _resetLookup();
    });
  }

  @override
  Widget build(BuildContext context) {
    final sub = _subscriber;
    final result = _lastResult;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Step 1: SIM number ──────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _sim,
                  keyboardType: TextInputType.number,
                  textDirection: TextDirection.ltr,
                  maxLength: AppConfig.simLength,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(AppConfig.simLength),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'رقم الشريحة',
                    hintText: '74XXXXXXX',
                    counterText: '',
                    prefixIcon: Icon(Icons.sim_card_outlined),
                  ),
                  onChanged: (_) {
                    if (_subscriber != null || _lastResult != null) {
                      setState(_resetLookup);
                    }
                  },
                  onSubmitted: (_) => _lookup(),
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: IconButton.filledTonal(
                  tooltip: 'مسح QR',
                  onPressed: _scan,
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _lookingUp ? null : _lookup,
            icon: _lookingUp
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.person_search_outlined),
            label: const Text('تحقق من المشترك'),
          ),

          // ── Step 2: identity confirmation ──────────────────
          if (sub != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.success.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.verified_user_rounded, color: AppColors.success, size: 30),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sub['full_name']?.toString() ?? '',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        Text(
                          'الحالة: ${sub['status'] ?? '—'}',
                          style: const TextStyle(color: AppColors.textGray, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textDirection: TextDirection.ltr,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: const InputDecoration(
                labelText: 'المبلغ (ريال)',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
              onChanged: (_) {
                if (_lastResult != null) setState(() => _lastResult = null);
              },
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _quickAmounts
                  .map((v) => ActionChip(
                        label: Text('$v'),
                        onPressed: () => setState(() => _amount.text = '$v'),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.bolt_rounded),
              label: Text(_submitting ? 'جارٍ الشحن…' : 'شحن الرصيد'),
            ),
          ],

          // ── Errors ──────────────────────────────────────────
          if (_error != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, color: AppColors.error),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_error!, style: const TextStyle(color: AppColors.error)),
                  ),
                ],
              ),
            ),
          ],

          // ── Result ──────────────────────────────────────────
          if (result != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.success, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 44),
                  const SizedBox(height: 8),
                  Text(
                    result['duplicate'] == true ? 'العملية مؤكدة مسبقاً' : 'تم الشحن بنجاح',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  _ConfirmRow('رقم العملية', '#${result['topup_id']}'),
                  _ConfirmRow('المشترك', result['sim_no']?.toString() ?? ''),
                  _ConfirmRow(
                    'المبلغ',
                    '${(result['amount'] as num?)?.toStringAsFixed(0) ?? ''} ${result['currency'] ?? ''}',
                  ),
                  _ConfirmRow(
                    'الرصيد الجديد',
                    '${(result['balance'] as num?)?.toStringAsFixed(0) ?? result['balance'] ?? ''} ${result['currency'] ?? ''}',
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _newOperation,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('عملية جديدة'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ConfirmRow extends StatelessWidget {
  final String label;
  final String value;
  const _ConfirmRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textGray, fontSize: 13)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
