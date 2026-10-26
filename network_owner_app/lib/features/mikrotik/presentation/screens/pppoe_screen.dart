import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/router_model.dart';
import '../../data/router_os_service.dart';
import '../providers/mikrotik_provider.dart';
import '../providers/entitlement_provider.dart';
import '../../data/feature_keys.dart';
import '../widgets/premium_lock_card.dart';

/// PPPoE / Broadband (برودباند) management — secrets list with
/// connected/idle/disabled counters, active sessions with kick,
/// profiles, and an add/edit dialog mirroring the MikroNet form
/// (service type, remote address, routes, comment, enable toggle).
class PppoeScreen extends ConsumerWidget {
  final MikrotikRouterConfig router;
  const PppoeScreen({super.key, required this.router});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allowed = ref.watch(featureAllowedProvider(MikroFeatures.pppoe));
    if (!allowed) return const PremiumLockCard();
    return _PppoeBody(router: router);
  }
}

class _PppoeBody extends ConsumerStatefulWidget {
  final MikrotikRouterConfig router;
  const _PppoeBody({required this.router});

  @override
  ConsumerState<_PppoeBody> createState() => _PppoeBodyState();
}

class _PppoeBodyState extends ConsumerState<_PppoeBody> {
  String _query = '';
  _PppStatus? _filter;

  void _refresh() =>
      ref.invalidate(_pppSnapshotProvider(widget.router));

  Future<void> _op(
    Future<void> Function(dynamic svc) action, {
    String done = 'تم التنفيذ بنجاح',
  }) async {
    try {
      await runRouterOp(widget.router, action);
      _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(done), behavior: SnackBarBehavior.floating));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('تعذّر التنفيذ: $e'),
          backgroundColor: AppColors.accent,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final snap = ref.watch(_pppSnapshotProvider(widget.router));

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.white,
        appBar: AppBar(
          title: const Text('مستخدمو PPPoE'),
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: 'المستخدمون'),
              Tab(text: 'النشطون'),
              Tab(text: 'البروفايلات'),
            ],
          ),
        ),
        body: snap.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('خطأ: $e',
                    style: const TextStyle(color: AppColors.textGray)),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          ),
          data: (s) => TabBarView(
            children: [
              _usersTab(s),
              _activeTab(s),
              _profilesTab(s),
            ],
          ),
        ),
        floatingActionButton: snap.maybeWhen(
          data: (s) => FloatingActionButton.extended(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => _PppUserDialog(
                router: widget.router,
                profiles:
                    s.profiles.map((p) => p['name'] ?? '').toList(),
                onSaved: _refresh,
              ),
            ),
            icon: const Icon(Icons.add),
            label: const Text('مستخدم جديد'),
          ),
          orElse: () => null,
        ),
      ),
    );
  }

  // ── Secrets tab ──────────────────────────────────────────────

  Widget _usersTab(_PppSnapshot s) {
    final activeNames =
        s.active.map((a) => a['name'] ?? '').toSet();
    _PppStatus st(Map<String, String> u) {
      if (u['disabled'] == 'true' || u['disabled'] == 'yes') {
        return _PppStatus.disabled;
      }
      return activeNames.contains(u['name'])
          ? _PppStatus.connected
          : _PppStatus.idle;
    }

    int countOf(_PppStatus v) => s.users.where((u) => st(u) == v).length;

    final visible = s.users.where((u) {
      if (_filter != null && st(u) != _filter) return false;
      if (_query.isNotEmpty) {
        final q = _query.toLowerCase();
        if (!'${u['name'] ?? ''} ${u['profile'] ?? ''} '
                '${u['comment'] ?? ''}'
            .toLowerCase()
            .contains(q)) {
          return false;
        }
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
              hintText: 'بحث بالاسم أو البروفايل...',
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
              _chip('الكل (${s.users.length})', _filter == null,
                  AppColors.primary,
                  () => setState(() => _filter = null)),
              _chip('متصل (${countOf(_PppStatus.connected)})',
                  _filter == _PppStatus.connected, AppColors.success,
                  () => setState(() => _filter =
                      _filter == _PppStatus.connected
                          ? null
                          : _PppStatus.connected)),
              _chip('غير متصل (${countOf(_PppStatus.idle)})',
                  _filter == _PppStatus.idle, AppColors.lightBlue,
                  () => setState(() => _filter =
                      _filter == _PppStatus.idle
                          ? null
                          : _PppStatus.idle)),
              _chip('معطل (${countOf(_PppStatus.disabled)})',
                  _filter == _PppStatus.disabled, AppColors.textGray,
                  () => setState(() => _filter =
                      _filter == _PppStatus.disabled
                          ? null
                          : _PppStatus.disabled)),
            ],
          ),
        ),
        Expanded(
          child: visible.isEmpty
              ? const _EmptyHint('لا يوجد مستخدمون')
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                  itemCount: visible.length,
                  itemBuilder: (_, i) {
                    final u = visible[i];
                    final status = st(u);
                    final id = u['.id'] ?? '';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: ListTile(
                        dense: true,
                        leading: Icon(
                          status == _PppStatus.connected
                              ? Icons.wifi
                              : status == _PppStatus.disabled
                                  ? Icons.person_off_outlined
                                  : Icons.person_outline,
                          color: _color(status),
                        ),
                        title: Text(u['name'] ?? '—',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14)),
                        subtitle: Text(
                          'الخدمة: ${u['service'] ?? 'pppoe'} • '
                          'البروفايل: ${u['profile'] ?? 'default'}'
                          '${(u['comment'] ?? '').isNotEmpty ? '\n${u['comment']}' : ''}',
                          style: const TextStyle(
                              color: AppColors.textGray, fontSize: 11),
                        ),
                        isThreeLine:
                            (u['comment'] ?? '').isNotEmpty,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _Badge(
                                text: _label(status),
                                color: _color(status)),
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert,
                                  color: AppColors.textGray,
                                  size: 20),
                              onSelected: (v) async {
                                switch (v) {
                                  case 'edit':
                                    showDialog(
                                      context: context,
                                      builder: (_) => _PppUserDialog(
                                        router: widget.router,
                                        user: u,
                                        profiles: s.profiles
                                            .map((p) =>
                                                p['name'] ?? '')
                                            .toList(),
                                        onSaved: _refresh,
                                      ),
                                    );
                                  case 'toggle':
                                    _op(
                                      (svc) => status ==
                                              _PppStatus.disabled
                                          ? svc.enablePppSecrets([id])
                                          : svc.disablePppSecrets(
                                              [id]),
                                      done: status ==
                                              _PppStatus.disabled
                                          ? 'تم تفعيل ${u['name']}'
                                          : 'تم تعطيل ${u['name']}',
                                    );
                                  case 'delete':
                                    final ok = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('حذف مستخدم'),
                                        content: Text(
                                            'حذف ${u['name']} نهائياً؟'),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(
                                                    ctx, false),
                                            child:
                                                const Text('إلغاء'),
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
                                            child:
                                                const Text('حذف'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (ok == true) {
                                      _op(
                                          (svc) => svc
                                              .removePppSecrets(
                                                  [id]),
                                          done:
                                              'تم حذف ${u['name']}');
                                    }
                                }
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(
                                    value: 'edit',
                                    child: Text('تعديل')),
                                PopupMenuItem(
                                  value: 'toggle',
                                  child: Text(status ==
                                          _PppStatus.disabled
                                      ? 'تفعيل'
                                      : 'تعطيل'),
                                ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Text('حذف',
                                      style: TextStyle(
                                          color: AppColors.accent)),
                                ),
                              ],
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

  Widget _activeTab(_PppSnapshot s) {
    if (s.active.isEmpty) {
      return const _EmptyHint('لا توجد جلسات PPPoE نشطة');
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
            leading:
                const Icon(Icons.cable, color: AppColors.success),
            title: Text(a['name'] ?? '—',
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 14)),
            subtitle: Text(
              'الخدمة: ${a['service'] ?? 'pppoe'} • '
              'IP: ${a['address'] ?? '—'} • منذ ${a['uptime'] ?? '—'}',
              style: const TextStyle(
                  color: AppColors.textGray, fontSize: 11),
            ),
            trailing: IconButton(
              tooltip: 'قطع الاتصال',
              icon: const Icon(Icons.link_off,
                  color: AppColors.accent),
              onPressed: () => _op(
                (svc) =>
                    svc.disconnectPppActive(a['.id'] ?? ''),
                done: 'تم قطع اتصال ${a['name']}',
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _profilesTab(_PppSnapshot s) {
    if (s.profiles.isEmpty) {
      return const _EmptyHint('لا توجد بروفايلات PPP');
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: s.profiles.length,
      itemBuilder: (_, i) {
        final p = s.profiles[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.divider),
          ),
          child: ListTile(
            dense: true,
            leading:
                const Icon(Icons.speed, color: AppColors.accent),
            title: Text(p['name'] ?? '—',
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 14)),
            subtitle: Text(
              'السرعة: ${p['rate-limit'] ?? 'غير محددة'}'
              '${(p['local-address'] ?? '').isNotEmpty ? ' • ${p['local-address']}' : ''}',
              style: const TextStyle(
                  color: AppColors.textGray, fontSize: 11),
            ),
          ),
        );
      },
    );
  }

  Widget _chip(String label, bool sel, Color c, VoidCallback tap) =>
      Padding(
        padding: const EdgeInsetsDirectional.only(end: 8),
        child: ChoiceChip(
          label: Text(label,
              style: TextStyle(
                  fontSize: 12,
                  color: sel ? Colors.white : c,
                  fontWeight: FontWeight.w600)),
          selected: sel,
          selectedColor: c,
          backgroundColor: c.withValues(alpha: 0.08),
          side: BorderSide(color: c.withValues(alpha: 0.4)),
          onSelected: (_) => tap(),
        ),
      );

  Color _color(_PppStatus s) => switch (s) {
        _PppStatus.connected => AppColors.success,
        _PppStatus.idle => AppColors.lightBlue,
        _PppStatus.disabled => AppColors.textGray,
      };

  String _label(_PppStatus s) => switch (s) {
        _PppStatus.connected => 'متصل',
        _PppStatus.idle => 'غير متصل',
        _PppStatus.disabled => 'معطل',
      };
}

enum _PppStatus { connected, idle, disabled }

// ── PPP snapshot provider ──────────────────────────────────────

class _PppSnapshot {
  final List<Map<String, String>> users;
  final List<Map<String, String>> active;
  final List<Map<String, String>> profiles;
  _PppSnapshot(
      {required this.users,
      required this.active,
      required this.profiles});
}

final _pppSnapshotProvider = FutureProvider.autoDispose
    .family<_PppSnapshot, MikrotikRouterConfig>((ref, cfg) async {
  final svc = await RouterOsService.connect(cfg);
  ref.onDispose(svc.close);
  final users = await svc.pppSecrets();
  final active = await svc.pppActive();
  final profiles = await svc.pppProfiles();
  return _PppSnapshot(
      users: users, active: active, profiles: profiles);
});

// ── Add / Edit PPP secret dialog ───────────────────────────────

const _services = ['pppoe', 'pptp', 'l2tp', 'ovpn', 'sstp', 'any'];

class _PppUserDialog extends ConsumerStatefulWidget {
  final MikrotikRouterConfig router;
  final Map<String, String>? user;
  final List<String> profiles;
  final VoidCallback onSaved;

  const _PppUserDialog({
    required this.router,
    this.user,
    required this.profiles,
    required this.onSaved,
  });

  @override
  ConsumerState<_PppUserDialog> createState() => _PppUserDialogState();
}

class _PppUserDialogState extends ConsumerState<_PppUserDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.user?['name'] ?? '');
  late final TextEditingController _pass =
      TextEditingController(text: widget.user?['password'] ?? '');
  late final TextEditingController _remote = TextEditingController(
      text: widget.user?['remote-address'] ?? '');
  late final TextEditingController _routes =
      TextEditingController(text: widget.user?['routes'] ?? '');
  late final TextEditingController _comment =
      TextEditingController(text: widget.user?['comment'] ?? '');
  late String _service = widget.user?['service'] ?? 'pppoe';
  late String _profile = widget.user?['profile'] ?? 'default';
  late bool _enabled = widget.user?['disabled'] != 'true' &&
      widget.user?['disabled'] != 'yes';
  bool _busy = false;

  bool get _editing => widget.user != null;

  @override
  void dispose() {
    _name.dispose();
    _pass.dispose();
    _remote.dispose();
    _routes.dispose();
    _comment.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await runRouterOp(widget.router, (svc) async {
        if (_editing) {
          await svc.setPppSecret(widget.user!['.id']!, {
            'name': _name.text.trim(),
            if (_pass.text.isNotEmpty) 'password': _pass.text,
            'service': _service,
            'profile': _profile,
            if (_remote.text.isNotEmpty)
              'remote-address': _remote.text.trim(),
            if (_routes.text.isNotEmpty) 'routes': _routes.text.trim(),
            if (_comment.text.isNotEmpty)
              'comment': _comment.text.trim(),
            'disabled': _enabled ? 'no' : 'yes',
          });
        } else {
          await svc.addPppSecret(
            name: _name.text.trim(),
            password: _pass.text,
            service: _service,
            profile: _profile,
            remoteAddress:
                _remote.text.isEmpty ? null : _remote.text.trim(),
            routes: _routes.text.isEmpty ? null : _routes.text.trim(),
            comment:
                _comment.text.isEmpty ? null : _comment.text.trim(),
            disabled: !_enabled,
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
      title: Text(_editing ? 'تعديل مستخدم PPPoE' : 'مستخدم PPPoE جديد'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('معلومات الدخول',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                    fontSize: 13)),
            const SizedBox(height: 8),
            TextField(
              controller: _name,
              decoration:
                  const InputDecoration(labelText: 'اسم المستخدم'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _pass,
              decoration:
                  const InputDecoration(labelText: 'كلمة المرور'),
            ),
            const SizedBox(height: 14),
            const Text('الإعدادات المتقدمة',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                    fontSize: 13)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _service,
              decoration:
                  const InputDecoration(labelText: 'الخدمة'),
              items: _services
                  .map((s) =>
                      DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: (v) =>
                  setState(() => _service = v ?? _service),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _profile,
              decoration:
                  const InputDecoration(labelText: 'البروفايل'),
              items: widget.profiles
                  .map((p) =>
                      DropdownMenuItem(value: p, child: Text(p)))
                  .toList(),
              onChanged: (v) =>
                  setState(() => _profile = v ?? _profile),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _remote,
              decoration: const InputDecoration(
                  labelText: 'العنوان البعيد (اختياري)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _routes,
              decoration: const InputDecoration(
                  labelText: 'مسارات Routes (اختياري)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _comment,
              decoration: const InputDecoration(
                  labelText: 'ملاحظات إضافية (اختياري)'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('المستخدم مفعّل',
                  style: TextStyle(fontSize: 14)),
              value: _enabled,
              activeThumbColor: AppColors.success,
              onChanged: (v) => setState(() => _enabled = v),
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
          Text(text,
              style: const TextStyle(color: AppColors.textGray)),
        ],
      ),
    );
  }
}
