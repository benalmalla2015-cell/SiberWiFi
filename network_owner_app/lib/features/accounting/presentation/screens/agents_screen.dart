import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../mikrotik/presentation/widgets/ui_states.dart';
import '../../data/acc_api.dart';
import '../../providers/acc_providers.dart';

/// «المستخدمون» — operating sub-accounts (PLAN §1): admin,
/// distributor and pos roles bound to existing app logins.
class AgentsScreen extends ConsumerWidget {
  const AgentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agentsAsync = ref.watch(accAgentsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('المستخدمون')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showForm(context, ref, null),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('إضافة مستخدم'),
        backgroundColor: AppColors.primary,
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(accAgentsProvider),
        child: agentsAsync.when(
          loading: () => const LoadingState(),
          error: (e, _) => ErrorRetry(
            message: 'تعذّر تحميل المستخدمين\n$e',
            onRetry: () => ref.invalidate(accAgentsProvider),
          ),
          data: (agents) {
            if (agents.isEmpty) {
              return const EmptyState(
                'لا يوجد مستخدمون — أضف موزعاً أو نقطة بيع',
                icon: Icons.group_outlined,
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: agents.length,
              itemBuilder: (_, i) => _AgentCard(
                agent: agents[i],
                onEdit: () => _showForm(context, ref, agents[i]),
                onToggle: () => _toggleStatus(context, ref, agents[i]),
                onDelete: () => _confirmDelete(context, ref, agents[i]),
              ),
            );
          },
        ),
      ),
    );
  }

  void _showForm(BuildContext ctx, WidgetRef ref, AccAgent? agent) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _AgentFormSheet(agent: agent),
    );
  }

  Future<void> _toggleStatus(
      BuildContext ctx, WidgetRef ref, AccAgent a) async {
    try {
      final msg = await ref.read(accApiProvider).updateAgent(a.id, {
        'status': a.isActive ? 'suspended' : 'active',
      });
      ref.invalidate(accAgentsProvider);
      if (ctx.mounted) _toast(ctx, msg, ok: true);
    } catch (e) {
      if (ctx.mounted) _toast(ctx, '$e');
    }
  }

  Future<void> _confirmDelete(
      BuildContext ctx, WidgetRef ref, AccAgent a) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('حذف المستخدم'),
        content: Text(
            'حذف «${a.displayName}» يلغي دخوله لقسم المحاسبة فوراً. متابعة؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('حذف', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final msg = await ref.read(accApiProvider).deleteAgent(a.id);
      ref.invalidate(accAgentsProvider);
      if (ctx.mounted) _toast(ctx, msg, ok: true);
    } catch (e) {
      if (ctx.mounted) _toast(ctx, '$e');
    }
  }

  static void _toast(BuildContext ctx, String msg, {bool ok = false}) {
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: ok ? AppColors.success : AppColors.error,
    ));
  }
}

class _AgentCard extends StatelessWidget {
  final AccAgent agent;
  final VoidCallback onEdit, onToggle, onDelete;
  const _AgentCard({
    required this.agent,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });

  static const _roleIcons = {
    'admin': Icons.admin_panel_settings_outlined,
    'distributor': Icons.local_shipping_outlined,
    'pos': Icons.point_of_sale_outlined,
  };
  static const _roleColors = {
    'admin': AppColors.primary,
    'distributor': AppColors.lightBlue,
    'pos': AppColors.success,
  };

  @override
  Widget build(BuildContext context) {
    final color = _roleColors[agent.role] ?? AppColors.textGray;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                      _roleIcons[agent.role] ?? Icons.person_outline,
                      color: color,
                      size: 26),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(agent.displayName,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      if (agent.userName != null)
                        Text(agent.userName!,
                            style: const TextStyle(
                                color: AppColors.textGray, fontSize: 12)),
                    ],
                  ),
                ),
                _chip(agent.roleLabel, color),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if ((agent.phone ?? agent.userPhone)?.isNotEmpty == true)
                  _infoChip(Icons.phone_outlined,
                      agent.phone ?? agent.userPhone!),
                _infoChip(
                  agent.cashAllowed ? Icons.payments_outlined : Icons.money_off_outlined,
                  agent.cashAllowed ? 'نقد مسموح' : 'بلا نقد',
                ),
                if (agent.creditAllowed)
                  _infoChip(Icons.credit_score_outlined, 'آجل مسموح'),
                if (agent.commissionMode != null &&
                    agent.commissionMode != 'none')
                  _infoChip(Icons.percent,
                      'عمولة ${agent.commissionValue ?? ''} ${agent.commissionMode == 'percent' ? '٪' : ''}'),
                _chip(agent.isActive ? 'نشط' : 'موقوف',
                    agent.isActive ? AppColors.success : AppColors.error),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 15),
                    label: const Text('تعديل',
                        style: TextStyle(fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 8)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onToggle,
                    icon: Icon(
                        agent.isActive
                            ? Icons.pause_circle_outline
                            : Icons.play_circle_outline,
                        size: 15,
                        color: AppColors.warning),
                    label: Text(agent.isActive ? 'إيقاف' : 'تفعيل',
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.warning)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      side: const BorderSide(color: AppColors.warning),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline,
                        size: 15, color: AppColors.error),
                    label: const Text('حذف',
                        style:
                            TextStyle(fontSize: 13, color: AppColors.error)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      side: const BorderSide(color: AppColors.error),
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

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  Widget _infoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.inputBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.textGray),
          const SizedBox(width: 4),
          Text(label,
              style:
                  const TextStyle(fontSize: 11, color: AppColors.textGray)),
        ],
      ),
    );
  }
}

class _AgentFormSheet extends ConsumerStatefulWidget {
  final AccAgent? agent;
  const _AgentFormSheet({this.agent});

  @override
  ConsumerState<_AgentFormSheet> createState() => _AgentFormSheetState();
}

class _AgentFormSheetState extends ConsumerState<_AgentFormSheet> {
  final _phoneCtr = TextEditingController();
  final _nameCtr = TextEditingController();
  final _agentPhoneCtr = TextEditingController();
  final _commissionCtr = TextEditingController();
  String _role = 'pos';
  String? _commissionMode;
  bool _cash = true;
  bool _credit = false;
  bool _active = true;
  bool _loading = false;

  bool get _isEdit => widget.agent != null;

  @override
  void initState() {
    super.initState();
    final a = widget.agent;
    if (a != null) {
      _role = a.role;
      _nameCtr.text = a.displayName;
      _agentPhoneCtr.text = a.phone ?? '';
      _cash = a.cashAllowed;
      _credit = a.creditAllowed;
      _active = a.isActive;
      _commissionMode = a.commissionMode;
      if (a.commissionValue != null) {
        _commissionCtr.text = a.commissionValue!.toStringAsFixed(0);
      }
    }
  }

  @override
  void dispose() {
    _phoneCtr.dispose();
    _nameCtr.dispose();
    _agentPhoneCtr.dispose();
    _commissionCtr.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_nameCtr.text.trim().isEmpty) {
      AgentsScreen._toast(context, 'أدخل اسم المستخدم');
      return;
    }
    if (!_isEdit && _phoneCtr.text.trim().isEmpty) {
      AgentsScreen._toast(context, 'أدخل رقم جوال حساب المستخدم');
      return;
    }
    setState(() => _loading = true);
    try {
      final api = ref.read(accApiProvider);
      final data = <String, dynamic>{
        'display_name': _nameCtr.text.trim(),
        'role': _role,
        'agent_phone': _agentPhoneCtr.text.trim(),
        'cash_allowed': _cash,
        'credit_allowed': _credit,
        'commission_mode': ?_commissionMode,
        'commission_value': _commissionCtr.text.trim().isEmpty
            ? null
            : num.tryParse(_commissionCtr.text.trim()),
        if (_isEdit) 'status': _active ? 'active' : 'suspended',
      };
      final msg = _isEdit
          ? await api.updateAgent(widget.agent!.id, data)
          : await api.createAgent(
              {...data, 'phone': _phoneCtr.text.trim()});
      if (mounted) {
        Navigator.pop(context);
        ref.invalidate(accAgentsProvider);
        AgentsScreen._toast(context, msg, ok: true);
      }
    } catch (e) {
      if (mounted) AgentsScreen._toast(context, '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 20,
          right: 20,
          top: 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_isEdit ? 'تعديل المستخدم' : 'إضافة مستخدم جديد',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            if (!_isEdit)
              TextField(
                controller: _phoneCtr,
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'رقم جوال حساب المستخدم في التطبيق *',
                  hintText: 'مثال: 777123456',
                  prefixIcon: Icon(Icons.phone_iphone),
                ),
              ),
            if (!_isEdit) const SizedBox(height: 12),
            TextField(
              controller: _nameCtr,
              decoration: const InputDecoration(
                labelText: 'الاسم الظاهر *',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _role,
              decoration: const InputDecoration(
                labelText: 'الدور *',
                prefixIcon: Icon(Icons.manage_accounts_outlined),
              ),
              items: AccAgent.roles.entries
                  .map((e) =>
                      DropdownMenuItem(value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: (v) => setState(() => _role = v ?? 'pos'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _agentPhoneCtr,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'هاتف التواصل (اختياري)',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title:
                  const Text('بيع نقدي مسموح', style: TextStyle(fontSize: 14)),
              value: _cash,
              onChanged: (v) => setState(() => _cash = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('بيع آجل (دين) مسموح',
                  style: TextStyle(fontSize: 14)),
              value: _credit,
              onChanged: (v) => setState(() => _credit = v),
            ),
            const SizedBox(height: 4),
            DropdownButtonFormField<String?>(
              initialValue: _commissionMode,
              decoration: const InputDecoration(
                labelText: 'نمط العمولة',
                prefixIcon: Icon(Icons.percent),
              ),
              items: const [
                DropdownMenuItem(value: null, child: Text('بدون')),
                DropdownMenuItem(value: 'percent', child: Text('نسبة ٪')),
                DropdownMenuItem(value: 'fixed', child: Text('مبلغ ثابت')),
                DropdownMenuItem(value: 'points', child: Text('نقاط')),
              ],
              onChanged: (v) => setState(() => _commissionMode = v),
            ),
            if (_commissionMode != null) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _commissionCtr,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'قيمة العمولة',
                  prefixIcon: Icon(Icons.numbers),
                ),
              ),
            ],
            if (_isEdit)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title:
                    const Text('حساب نشط', style: TextStyle(fontSize: 14)),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(_isEdit ? 'حفظ التعديلات' : 'إنشاء الحساب'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
