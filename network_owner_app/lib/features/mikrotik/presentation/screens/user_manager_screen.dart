import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/feature_keys.dart';
import '../../data/router_model.dart';
import '../../data/router_os_service.dart';
import '../providers/entitlement_provider.dart';
import '../providers/mikrotik_provider.dart';
import '../widgets/premium_lock_card.dart';

/// User Manager — ROS /user-manager users and priced packages.
class UserManagerScreen extends ConsumerWidget {
  final MikrotikRouterConfig router;
  const UserManagerScreen({super.key, required this.router});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allowed =
        ref.watch(featureAllowedProvider(MikroFeatures.userManager));
    if (!allowed) return const PremiumLockCard();
    return _UmBody(router: router);
  }
}

class _UmBody extends ConsumerStatefulWidget {
  final MikrotikRouterConfig router;
  const _UmBody({required this.router});

  @override
  ConsumerState<_UmBody> createState() => _UmBodyState();
}

class _UmBodyState extends ConsumerState<_UmBody> {
  String _query = '';

  void _refresh() => ref.invalidate(_umSnapshotProvider(widget.router));

  Future<void> _op(
    Future<void> Function(RouterOsService svc) action, {
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
    final snap = ref.watch(_umSnapshotProvider(widget.router));

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.white,
        appBar: AppBar(
          title: const Text('User Manager'),
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: 'المستخدمون'),
              Tab(text: 'الباقات'),
            ],
          ),
        ),
        body: snap.when(
          loading: () =>
              const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('خطأ: $e',
                    style:
                        const TextStyle(color: AppColors.textGray)),
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
            children: [_usersTab(s), _packagesTab(s)],
          ),
        ),
      ),
    );
  }

  Widget _usersTab(_UmSnapshot s) {
    final visible = s.users.where((u) {
      if (_query.isEmpty) return true;
      return '${u['name'] ?? ''} ${u['comment'] ?? ''}'
          .toLowerCase()
          .contains(_query.toLowerCase());
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: const InputDecoration(
                    hintText: 'بحث...',
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => _UmUserDialog(
                      router: widget.router, onSaved: _refresh),
                ),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('مستخدم'),
              ),
            ],
          ),
        ),
        Expanded(
          child: visible.isEmpty
              ? const _EmptyHint('لا يوجد مستخدمون')
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: visible.length,
                  itemBuilder: (_, i) {
                    final u = visible[i];
                    final disabled = u['disabled'] == 'true' ||
                        u['disabled'] == 'yes';
                    return _RowCard(
                      icon: Icons.manage_accounts_outlined,
                      iconColor: disabled
                          ? AppColors.textLight
                          : AppColors.primary,
                      title: u['name'] ?? '—',
                      subtitle: 'دخول متزامن: ${u['shared-users'] ?? '1'}'
                          '${(u['comment'] ?? '').isNotEmpty ? ' • ${u['comment']}' : ''}',
                      badge: disabled ? 'معطل' : null,
                      badgeColor: AppColors.textGray,
                      onDelete: () => _op(
                        (svc) =>
                            svc.removeUmUsers([u['.id'] ?? '']),
                        done: 'تم حذف ${u['name']}',
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _packagesTab(_UmSnapshot s) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: ElevatedButton.icon(
              onPressed: () => showDialog(
                context: context,
                builder: (_) => _UmPackageDialog(
                    router: widget.router, onSaved: _refresh),
              ),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('باقة جديدة'),
            ),
          ),
        ),
        Expanded(
          child: s.profiles.isEmpty
              ? const _EmptyHint('لا توجد باقات')
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: s.profiles.length,
                  itemBuilder: (_, i) {
                    final p = s.profiles[i];
                    return _RowCard(
                      icon: Icons.inventory_2_outlined,
                      iconColor: AppColors.accent,
                      title: p['name'] ?? '—',
                      subtitle: [
                        if ((p['price'] ?? '').isNotEmpty)
                          'السعر: ${p['price']} ر.ي',
                        if ((p['validity'] ?? '').isNotEmpty)
                          'الصلاحية: ${p['validity']}',
                        if ((p['shared-users'] ?? '').isNotEmpty)
                          'أجهزة: ${p['shared-users']}',
                        if ((p['rate-limit'] ?? '').isNotEmpty)
                          'السرعة: ${p['rate-limit']}',
                      ].join(' • '),
                      onDelete: () => _op(
                        (svc) =>
                            svc.removeUmProfile(p['.id'] ?? ''),
                        done: 'تم حذف ${p['name']}',
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ── Snapshot provider ──────────────────────────────────────────

class _UmSnapshot {
  final List<Map<String, String>> users;
  final List<Map<String, String>> profiles;
  _UmSnapshot({required this.users, required this.profiles});
}

final _umSnapshotProvider = FutureProvider.autoDispose
    .family<_UmSnapshot, MikrotikRouterConfig>((ref, cfg) async {
  final svc = await RouterOsService.connect(cfg);
  ref.onDispose(svc.close);
  final users = await svc.umUsers();
  final profiles = await svc.umProfiles();
  return _UmSnapshot(users: users, profiles: profiles);
});

// ── Add user dialog ────────────────────────────────────────────

class _UmUserDialog extends ConsumerStatefulWidget {
  final MikrotikRouterConfig router;
  final VoidCallback onSaved;
  const _UmUserDialog({required this.router, required this.onSaved});

  @override
  ConsumerState<_UmUserDialog> createState() => _UmUserDialogState();
}

class _UmUserDialogState extends ConsumerState<_UmUserDialog> {
  final _name = TextEditingController();
  final _pass = TextEditingController();
  final _shared = TextEditingController(text: '1');
  final _comment = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _pass.dispose();
    _shared.dispose();
    _comment.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await runRouterOp(widget.router, (svc) => svc.addUmUser(
            name: _name.text.trim(),
            password: _pass.text,
            sharedUsers: _shared.text.trim(),
            comment:
                _comment.text.isEmpty ? null : _comment.text.trim(),
          ));
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
      title: const Text('مستخدم جديد'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                  labelText: 'اسم المستخدم'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _pass,
              decoration: const InputDecoration(
                  labelText: 'كلمة المرور'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _shared,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'دخول متزامن (أجهزة)',
                helperText: '1 = جهاز واحد • 2 = جهازان بنفس الحساب',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _comment,
              decoration: const InputDecoration(
                  labelText: 'تعليق (اختياري)'),
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
              : const Text('إضافة'),
        ),
      ],
    );
  }
}

// ── Add package dialog ─────────────────────────────────────────

class _UmPackageDialog extends ConsumerStatefulWidget {
  final MikrotikRouterConfig router;
  final VoidCallback onSaved;
  const _UmPackageDialog(
      {required this.router, required this.onSaved});

  @override
  ConsumerState<_UmPackageDialog> createState() =>
      _UmPackageDialogState();
}

class _UmPackageDialogState extends ConsumerState<_UmPackageDialog> {
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _validity = TextEditingController();
  final _uptime = TextEditingController();
  final _shared = TextEditingController(text: '1');
  final _data = TextEditingController();
  final _rate = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [
      _name,
      _price,
      _validity,
      _uptime,
      _shared,
      _data,
      _rate
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final attrs = <String, String>{'name': _name.text.trim()};
      if (_price.text.isNotEmpty) attrs['price'] = _price.text.trim();
      if (_validity.text.isNotEmpty) {
        attrs['validity'] = _validity.text.trim();
      }
      if (_shared.text.isNotEmpty) {
        attrs['shared-users'] = _shared.text.trim();
      }
      if (_rate.text.isNotEmpty) {
        attrs['rate-limit'] = _rate.text.trim();
      }
      if (_uptime.text.isNotEmpty || _data.text.isNotEmpty) {
        // User-Manager limits live on profile-limitation rows in v7;
        // store the intent in the profile comment for now so the
        // information travels with the package on the router.
        final parts = <String>[
          if (_uptime.text.isNotEmpty) 'uptime:${_uptime.text.trim()}',
          if (_data.text.isNotEmpty) 'data:${_data.text.trim()}',
        ];
        attrs['comment'] = parts.join(' ');
      }
      await runRouterOp(
          widget.router, (svc) => svc.addUmProfile(attrs));
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
      title: const Text('باقة User Manager'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('المعلومات الأساسية',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                    fontSize: 13)),
            const SizedBox(height: 8),
            TextField(
              controller: _name,
              decoration:
                  const InputDecoration(labelText: 'اسم الباقة'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _price,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'السعر (ر.ي)'),
            ),
            const SizedBox(height: 14),
            const Text('الصلاحية والوقت',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                    fontSize: 13)),
            const SizedBox(height: 8),
            TextField(
              controller: _validity,
              decoration: const InputDecoration(
                  labelText: 'الصلاحية الكلية (مثال: 30d, 1w)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _uptime,
              decoration: const InputDecoration(
                  labelText: 'ساعات الارتباط Uptime (اختياري)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _shared,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'عدد الدخول بنفس الوقت',
                helperText: '1 = جهاز واحد • 2 = جهازان',
              ),
            ),
            const SizedBox(height: 14),
            const Text('البيانات والسرعة',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                    fontSize: 13)),
            const SizedBox(height: 8),
            TextField(
              controller: _data,
              decoration: const InputDecoration(
                  labelText: 'الرصيد (مثال: 1G, 500M — اختياري)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _rate,
              decoration: const InputDecoration(
                  labelText: 'تحديد السرعة (مثال: 2M/2M — اختياري)'),
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
              : const Text('حفظ وبرمجة الباقة'),
        ),
      ],
    );
  }
}

// ── Shared widgets ─────────────────────────────────────────────

class _RowCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title, subtitle;
  final String? badge;
  final Color? badgeColor;
  final VoidCallback? onDelete;

  const _RowCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.badge,
    this.badgeColor,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(icon, color: iconColor),
        title: Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 14)),
        subtitle: subtitle.isEmpty
            ? null
            : Text(subtitle,
                style: const TextStyle(
                    color: AppColors.textGray, fontSize: 11)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (badge != null)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (badgeColor ?? AppColors.textGray)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(badge!,
                    style: TextStyle(
                        color: badgeColor ?? AppColors.textGray,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ),
            if (onDelete != null)
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    color: AppColors.accent, size: 20),
                onPressed: onDelete,
              ),
          ],
        ),
      ),
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
