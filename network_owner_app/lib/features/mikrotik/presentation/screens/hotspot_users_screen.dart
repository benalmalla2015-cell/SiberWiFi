import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/hotspot_user_status.dart';
import '../../data/router_model.dart';
import '../providers/mikrotik_provider.dart';

/// Full hotspot-user management: status filters + counters, search,
/// bulk select/delete, per-user edit/enable/disable/delete, session
/// kick, and add/edit dialogs — all through [runRouterOp] short
/// connections so the read-only session stays untouched.
class HotspotUsersScreen extends ConsumerStatefulWidget {
  final MikrotikRouterConfig router;
  final int initialTab;
  const HotspotUsersScreen(
      {super.key, required this.router, this.initialTab = 0});

  @override
  ConsumerState<HotspotUsersScreen> createState() =>
      _HotspotUsersScreenState();
}

class _HotspotUsersScreenState extends ConsumerState<HotspotUsersScreen> {
  String _query = '';
  HotspotUserStatus? _filter;
  final Set<String> _selected = {};
  bool get _selecting => _selected.isNotEmpty;

  void _refresh() =>
      ref.invalidate(routerSessionProvider(widget.router));

  Future<void> _op(
    Future<void> Function(dynamic svc) action, {
    String done = 'تم التنفيذ بنجاح',
  }) async {
    try {
      await runRouterOp(widget.router, action);
      _selected.clear();
      _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(done), behavior: SnackBarBehavior.floating),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذّر التنفيذ: $e'),
            backgroundColor: AppColors.accent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<bool> _confirm(String title, String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  void _deleteUsers(List<Map<String, String>> targets) async {
    final ids = targets.map((u) => u['.id'] ?? '').toList();
    if (ids.isEmpty) return;
    if (!await _confirm('حذف مستخدمين',
        'سيتم حذف ${ids.length} مستخدم نهائياً من الراوتر. لا يمكن التراجع.')) {
      return;
    }
    await _op((svc) => svc.removeHotspotUsers(ids),
        done: 'تم حذف ${ids.length} مستخدم');
  }

  void _toggleUser(Map<String, String> u, bool enable) {
    final id = u['.id'] ?? '';
    if (id.isEmpty) return;
    _op(
      (svc) => enable
          ? svc.enableHotspotUsers([id])
          : svc.disableHotspotUsers([id]),
      done: enable ? 'تم تفعيل ${u['name']}' : 'تم تعطيل ${u['name']}',
    );
  }

  void _disconnectSession(Map<String, String> a) {
    final id = a['.id'] ?? '';
    if (id.isEmpty) return;
    _op((svc) => svc.disconnectHotspotActive(id),
        done: 'تم قطع اتصال ${a['user']}');
  }

  void _editDialog({Map<String, String>? user, List<String>? profiles}) {
    showDialog(
      context: context,
      builder: (_) => _UserFormDialog(
        router: widget.router,
        user: user,
        profiles: profiles ?? const [],
        onSaved: _refresh,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final snap = ref.watch(routerSessionProvider(widget.router));

    return DefaultTabController(
      length: 3,
      initialIndex: widget.initialTab,
      child: Scaffold(
        backgroundColor: AppColors.white,
        appBar: AppBar(
          title: _selecting
              ? Text('تم تحديد ${_selected.length}')
              : const Text('مستخدمو Hotspot'),
          actions: [
            if (_selecting)
              IconButton(
                tooltip: 'إلغاء التحديد',
                icon: const Icon(Icons.close),
                onPressed: () => setState(_selected.clear),
              ),
          ],
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: 'المستخدمون'),
              Tab(text: 'النشطون'),
              Tab(text: 'الباقات'),
            ],
          ),
        ),
        body: snap.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _ErrorRetry(
            message: '$e',
            onRetry: _refresh,
          ),
          data: (s) => TabBarView(
            children: [
              _buildUsersTab(s),
              _buildActiveTab(s),
              _ProfilesTab(
                profiles: s.profiles,
                router: widget.router,
                onChanged: _refresh,
              ),
            ],
          ),
        ),
        floatingActionButton: snap.maybeWhen(
          data: (s) => _selecting
              ? FloatingActionButton.extended(
                  backgroundColor: AppColors.accent,
                  onPressed: () => _deleteUsers(s.users
                      .where((u) => _selected.contains(u['.id']))
                      .toList()),
                  icon: const Icon(Icons.delete_outline),
                  label: Text('حذف (${_selected.length})'),
                )
              : FloatingActionButton.extended(
                  onPressed: () => _editDialog(
                      profiles:
                          s.profiles.map((p) => p['name'] ?? '').toList()),
                  icon: const Icon(Icons.add),
                  label: const Text('مستخدم جديد'),
                ),
          orElse: () => null,
        ),
      ),
    );
  }

  // ── Users tab ────────────────────────────────────────────────

  Widget _buildUsersTab(RouterSnapshot s) {
    final activeNames =
        s.active.map((a) => a['user'] ?? '').toSet();
    final classified = {
      for (final u in s.users)
        u['.id'] ?? u['name'] ?? '': classifyHotspotUser(u, activeNames),
    };

    int countOf(HotspotUserStatus st) =>
        classified.values.where((v) => v == st).length;

    final visible = s.users.where((u) {
      final st = classified[u['.id'] ?? u['name'] ?? ''];
      if (_filter != null && st != _filter) return false;
      if (_query.isNotEmpty) {
        final q = _query.toLowerCase();
        final hay = '${u['name'] ?? ''} ${u['profile'] ?? ''} '
            '${u['comment'] ?? ''}'.toLowerCase();
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: const InputDecoration(
              hintText: 'بحث بالاسم أو الباقة...',
              prefixIcon: Icon(Icons.search),
              isDense: true,
            ),
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              _StatusChip(
                label: 'الكل (${s.users.length})',
                selected: _filter == null,
                color: AppColors.primary,
                onTap: () => setState(() => _filter = null),
              ),
              for (final st in HotspotUserStatus.values)
                _StatusChip(
                  label: '${st.label} (${countOf(st)})',
                  selected: _filter == st,
                  color: _statusColor(st),
                  onTap: () => setState(
                      () => _filter = _filter == st ? null : st),
                ),
            ],
          ),
        ),
        if (visible.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: () => setState(() {
                    final allIds =
                        visible.map((u) => u['.id'] ?? '').toSet();
                    if (_selected.containsAll(allIds)) {
                      _selected.clear();
                    } else {
                      _selected
                        ..clear()
                        ..addAll(allIds);
                    }
                  }),
                  icon: Icon(
                    _selected.containsAll(
                            visible.map((u) => u['.id'] ?? '').toSet())
                        ? Icons.check_box
                        : Icons.check_box_outline_blank,
                    size: 18,
                  ),
                  label: const Text('تحديد الكل'),
                ),
                const Spacer(),
                Text('${visible.length} نتيجة',
                    style: const TextStyle(
                        color: AppColors.textGray, fontSize: 11)),
              ],
            ),
          ),
        Expanded(
          child: visible.isEmpty
              ? const _EmptyHint('لا يوجد مستخدمون مطابقون')
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                  itemCount: visible.length,
                  itemBuilder: (_, i) {
                    final u = visible[i];
                    final st = classified[u['.id'] ?? u['name'] ?? '']!;
                    return _buildUserCard(u, st, s);
                  },
                ),
        ),
      ],
    );
  }

  Color _statusColor(HotspotUserStatus st) => switch (st) {
        HotspotUserStatus.active => AppColors.success,
        HotspotUserStatus.idle => AppColors.lightBlue,
        HotspotUserStatus.expired => AppColors.warning,
        HotspotUserStatus.disabled => AppColors.textGray,
      };

  Widget _buildUserCard(
      Map<String, String> u, HotspotUserStatus st, RouterSnapshot s) {
    final id = u['.id'] ?? '';
    final checked = _selected.contains(id);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onLongPress: () => setState(() => _selected.add(id)),
      onTap: _selecting
          ? () => setState(() {
                checked ? _selected.remove(id) : _selected.add(id);
              })
          : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: checked
              ? AppColors.primary.withValues(alpha: 0.05)
              : AppColors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: checked ? AppColors.primary : AppColors.divider,
          ),
        ),
        child: ListTile(
          dense: true,
          leading: _selecting
              ? Icon(
                  checked
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color: checked ? AppColors.primary : AppColors.textLight,
                )
              : Icon(Icons.person_outline, color: _statusColor(st)),
          title: Text(u['name'] ?? '—',
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 14)),
          subtitle: Text(
            'الباقة: ${u['profile'] ?? 'default'}'
            '${(u['limit-uptime'] ?? '').isNotEmpty ? ' • المدة: ${u['limit-uptime']}' : ''}'
            ' • الاستهلاك: ${hotspotUsageLabel(u)}',
            style: const TextStyle(
                color: AppColors.textGray, fontSize: 11),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Badge(text: st.label, color: _statusColor(st)),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert,
                    color: AppColors.textGray, size: 20),
                onSelected: (v) {
                  switch (v) {
                    case 'edit':
                      _editDialog(
                        user: u,
                        profiles: s.profiles
                            .map((p) => p['name'] ?? '')
                            .toList(),
                      );
                    case 'toggle':
                      _toggleUser(
                          u, st == HotspotUserStatus.disabled);
                    case 'select':
                      setState(() => _selected.add(id));
                    case 'delete':
                      _deleteUsers([u]);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                      value: 'edit', child: Text('تعديل')),
                  PopupMenuItem(
                    value: 'toggle',
                    child: Text(st == HotspotUserStatus.disabled
                        ? 'تفعيل'
                        : 'تعطيل'),
                  ),
                  const PopupMenuItem(
                      value: 'select', child: Text('تحديد')),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('حذف',
                        style: TextStyle(color: AppColors.accent)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Active sessions tab ──────────────────────────────────────

  Widget _buildActiveTab(RouterSnapshot s) {
    if (s.active.isEmpty) {
      return const _EmptyHint('لا توجد جلسات نشطة حالياً');
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: s.active.length,
      itemBuilder: (_, i) {
        final a = s.active[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.divider),
          ),
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.wifi, color: AppColors.success),
            title: Text(a['user'] ?? '—',
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 14)),
            subtitle: Text(
              'IP: ${a['address'] ?? '—'} • منذ ${a['uptime'] ?? '—'}'
              '${(a['mac-address'] ?? '').isNotEmpty ? ' • ${a['mac-address']}' : ''}\n'
              '⬇ ${a['bytes-in'] ?? '0'} • ⬆ ${a['bytes-out'] ?? '0'}',
              style: const TextStyle(
                  color: AppColors.textGray, fontSize: 11),
            ),
            isThreeLine: true,
            trailing: IconButton(
              tooltip: 'قطع الاتصال',
              icon: const Icon(Icons.wifi_off_outlined,
                  color: AppColors.accent),
              onPressed: () => _disconnectSession(a),
            ),
          ),
        );
      },
    );
  }
}

// ── Add / Edit user dialog ─────────────────────────────────────

class _UserFormDialog extends ConsumerStatefulWidget {
  final MikrotikRouterConfig router;
  final Map<String, String>? user;
  final List<String> profiles;
  final VoidCallback onSaved;

  const _UserFormDialog({
    required this.router,
    this.user,
    required this.profiles,
    required this.onSaved,
  });

  @override
  ConsumerState<_UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends ConsumerState<_UserFormDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.user?['name'] ?? '');
  late final TextEditingController _pass =
      TextEditingController(text: widget.user?['password'] ?? '');
  late final TextEditingController _limit =
      TextEditingController(text: widget.user?['limit-uptime'] ?? '');
  late final TextEditingController _comment =
      TextEditingController(text: widget.user?['comment'] ?? '');
  late String _profile = widget.user?['profile'] ?? 'default';
  bool _busy = false;

  bool get _editing => widget.user != null;

  @override
  void dispose() {
    _name.dispose();
    _pass.dispose();
    _limit.dispose();
    _comment.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await runRouterOp(widget.router, (svc) async {
        if (_editing) {
          await svc.setHotspotUser(widget.user!['.id']!, {
            'name': _name.text.trim(),
            if (_pass.text.isNotEmpty) 'password': _pass.text,
            'profile': _profile,
            if (_limit.text.isNotEmpty) 'limit-uptime': _limit.text.trim(),
            if (_comment.text.isNotEmpty) 'comment': _comment.text.trim(),
          });
        } else {
          await svc.addHotspotUser(
            name: _name.text.trim(),
            password: _pass.text.isEmpty ? null : _pass.text,
            profile: _profile,
            comment:
                _comment.text.isEmpty ? null : _comment.text.trim(),
            limitUptime:
                _limit.text.isEmpty ? null : _limit.text.trim(),
          );
        }
      });
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذّر الحفظ: $e'),
            backgroundColor: AppColors.accent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_editing ? 'تعديل مستخدم' : 'مستخدم جديد'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration:
                  const InputDecoration(labelText: 'اسم المستخدم / الكود'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _pass,
              decoration: const InputDecoration(
                  labelText: 'كلمة المرور (اختياري)'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _profile,
              decoration: const InputDecoration(labelText: 'الباقة'),
              items: widget.profiles
                  .map((p) =>
                      DropdownMenuItem(value: p, child: Text(p)))
                  .toList(),
              onChanged: (v) => setState(() => _profile = v ?? _profile),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _limit,
              decoration: const InputDecoration(
                labelText: 'حد المدة (مثال: 1h أو 1d — اختياري)',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _comment,
              decoration: const InputDecoration(
                  labelText: 'ملاحظات (اختياري)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Text(_editing ? 'حفظ' : 'إضافة'),
        ),
      ],
    );
  }
}

// ── Shared small widgets ───────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  const _StatusChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: ChoiceChip(
        label: Text(label,
            style: TextStyle(
              fontSize: 12,
              color: selected ? Colors.white : color,
              fontWeight: FontWeight.w600,
            )),
        selected: selected,
        selectedColor: color,
        backgroundColor: color.withValues(alpha: 0.08),
        side: BorderSide(color: color.withValues(alpha: 0.4)),
        onSelected: (_) => onTap(),
      ),
    );
  }
}

class _ProfilesTab extends ConsumerWidget {
  final List<Map<String, String>> profiles;
  final MikrotikRouterConfig router;
  final VoidCallback onChanged;
  const _ProfilesTab(
      {required this.profiles,
      required this.router,
      required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: ElevatedButton.icon(
              onPressed: () => showDialog(
                context: context,
                builder: (_) => _ProfileFormDialog(
                    router: router, onSaved: onChanged),
              ),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('باقة جديدة'),
            ),
          ),
        ),
        Expanded(
          child: profiles.isEmpty
              ? const _EmptyHint('لا توجد باقات')
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  itemCount: profiles.length,
                  itemBuilder: (_, i) {
                    final p = profiles[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(14),
                        border:
                            Border.all(color: AppColors.divider),
                      ),
                      child: ListTile(
                        dense: true,
                        leading: const Icon(Icons.speed,
                            color: AppColors.accent),
                        title: Text(p['name'] ?? '—',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14)),
                        subtitle: Text(
                          'السرعة: ${p['rate-limit'] ?? 'غير محددة'}'
                          '${(p['shared-users'] ?? '').isNotEmpty ? ' • مستخدمون: ${p['shared-users']}' : ''}'
                          '${(p['session-timeout'] ?? '').isNotEmpty ? ' • جلسة: ${p['session-timeout']}' : ''}',
                          style: const TextStyle(
                              color: AppColors.textGray,
                              fontSize: 11),
                        ),
                        trailing: PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert,
                              color: AppColors.textGray, size: 20),
                          onSelected: (v) async {
                            if (v == 'edit') {
                              showDialog(
                                context: context,
                                builder: (_) => _ProfileFormDialog(
                                  router: router,
                                  profile: p,
                                  onSaved: onChanged,
                                ),
                              );
                            } else if (v == 'delete') {
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title:
                                      const Text('حذف الباقة'),
                                  content: Text(
                                      'حذف ${p['name']}؟ لن تتأثر حسابات المستخدمين الموجودة.'),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(
                                              ctx, false),
                                      child: const Text('إلغاء'),
                                    ),
                                    ElevatedButton(
                                      onPressed: () =>
                                          Navigator.pop(
                                              ctx, true),
                                      style: ElevatedButton
                                          .styleFrom(
                                              backgroundColor:
                                                  AppColors
                                                      .accent),
                                      child: const Text('حذف'),
                                    ),
                                  ],
                                ),
                              );
                              if (ok == true) {
                                try {
                                  await runRouterOp(router,
                                      (svc) => svc
                                          .removeHotspotProfile(
                                              p['.id'] ?? ''));
                                  onChanged();
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(SnackBar(
                                      content: Text(
                                          'تعذّر الحذف: $e'),
                                      backgroundColor:
                                          AppColors.accent,
                                    ));
                                  }
                                }
                              }
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                                value: 'edit',
                                child: Text('تعديل')),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('حذف',
                                  style: TextStyle(
                                      color: AppColors.accent)),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Create/edit a hotspot user-profile (باقة) — name, speed split
/// into upload/download (RouterOS rate-limit "rx/tx"), shared
/// devices, session timeout, and optional on-login/on-logout
/// scripts like the v7 profile builders.
class _ProfileFormDialog extends ConsumerStatefulWidget {
  final MikrotikRouterConfig router;
  final Map<String, String>? profile;
  final VoidCallback onSaved;

  const _ProfileFormDialog({
    required this.router,
    this.profile,
    required this.onSaved,
  });

  @override
  ConsumerState<_ProfileFormDialog> createState() =>
      _ProfileFormDialogState();
}

class _ProfileFormDialogState
    extends ConsumerState<_ProfileFormDialog> {
  late final TextEditingController _name = TextEditingController(
      text: widget.profile?['name'] ?? '');
  late final TextEditingController _rx =
      TextEditingController(text: _splitRate(0));
  late final TextEditingController _tx =
      TextEditingController(text: _splitRate(1));
  late final TextEditingController _shared = TextEditingController(
      text: widget.profile?['shared-users'] ?? '1');
  late final TextEditingController _session = TextEditingController(
      text: widget.profile?['session-timeout'] ?? '');
  late final TextEditingController _onLogin =
      TextEditingController(text: widget.profile?['on-login'] ?? '');
  late final TextEditingController _onLogout = TextEditingController(
      text: widget.profile?['on-logout'] ?? '');
  bool _busy = false;

  bool get _editing => widget.profile != null;

  String _splitRate(int i) {
    final rl = widget.profile?['rate-limit'] ?? '';
    final parts = rl.split('/');
    return parts.length > i ? parts[i] : '';
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _rx,
      _tx,
      _shared,
      _session,
      _onLogin,
      _onLogout
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    setState(() => _busy = true);
    final rate =
        '${_rx.text.trim()}${_rx.text.trim().isNotEmpty || _tx.text.trim().isNotEmpty ? '/' : ''}${_tx.text.trim()}';
    try {
      await runRouterOp(widget.router, (svc) async {
        final attrs = <String, String>{
          'name': _name.text.trim(),
          if (rate.isNotEmpty) 'rate-limit': rate,
          if (_shared.text.isNotEmpty)
            'shared-users': _shared.text.trim(),
          if (_session.text.isNotEmpty)
            'session-timeout': _session.text.trim(),
          if (_onLogin.text.isNotEmpty)
            'on-login': _onLogin.text.trim(),
          if (_onLogout.text.isNotEmpty)
            'on-logout': _onLogout.text.trim(),
        };
        if (_editing) {
          await svc.setHotspotProfile(
              widget.profile!['.id']!, attrs);
        } else {
          await svc.addHotspotProfile(
            name: _name.text.trim(),
            rateLimit: rate.isEmpty ? null : rate,
            sharedUsers:
                _shared.text.isEmpty ? null : _shared.text.trim(),
            sessionTimeout: _session.text.isEmpty
                ? null
                : _session.text.trim(),
            onLogin:
                _onLogin.text.isEmpty ? null : _onLogin.text.trim(),
            onLogout: _onLogout.text.isEmpty
                ? null
                : _onLogout.text.trim(),
          );
        }
      });
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('تعذّر الحفظ: $e'),
          backgroundColor: AppColors.accent,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_editing ? 'تعديل باقة' : 'باقة جديدة'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                  labelText: 'اسم الباقة'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _rx,
                    decoration: const InputDecoration(
                        labelText: 'الرفع (مثال: 1M)'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _tx,
                    decoration: const InputDecoration(
                        labelText: 'التحميل (مثال: 1M)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _shared,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'عدد الأجهزة بنفس الوقت',
                helperText: '1 = جهاز واحد • 2 = جهازان',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _session,
              decoration: const InputDecoration(
                  labelText: 'مهلة الجلسة (مثال: 1h, 1d — اختياري)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _onLogin,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'سكربت On-Login (اختياري)',
                helperText: 'يُنفَّذ على الراوتر عند دخول المستخدم',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _onLogout,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'سكربت On-Logoff (اختياري)',
                helperText: 'يُنفَّذ عند انتهاء/قطع الجلسة',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Text(_editing ? 'حفظ' : 'إضافة'),
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  const _Badge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String text;
  const _EmptyHint(this.text);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.inbox_outlined,
              size: 48, color: AppColors.divider),
          const SizedBox(height: 12),
          Text(text, style: const TextStyle(color: AppColors.textGray)),
        ],
      ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorRetry({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off_outlined,
                size: 48, color: AppColors.textLight),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textGray)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}
