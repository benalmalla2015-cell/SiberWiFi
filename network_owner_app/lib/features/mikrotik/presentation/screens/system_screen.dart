import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/feature_keys.dart';
import '../../data/router_model.dart';
import '../../data/telegram_settings.dart';
import '../providers/entitlement_provider.dart';
import '../providers/mikrotik_provider.dart';
import '../widgets/premium_lock_card.dart';
import '../widgets/ui_states.dart';

/// System administration — reboot, backup/restore, users & groups,
/// schedulers & scripts, hotspot login pages, Telegram alerts.
class SystemScreen extends ConsumerWidget {
  final MikrotikRouterConfig router;
  const SystemScreen({super.key, required this.router});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allowed =
        ref.watch(featureAllowedProvider(MikroFeatures.systemAdmin));
    if (!allowed) return const PremiumLockCard();
    return _Body(router: router);
  }
}

class _Body extends StatelessWidget {
  final MikrotikRouterConfig router;
  const _Body({required this.router});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        backgroundColor: AppColors.white,
        appBar: AppBar(
          title: const Text('النظام'),
          bottom: const TabBar(
            isScrollable: true,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: 'الجهاز'),
              Tab(text: 'النسخ الاحتياطي'),
              Tab(text: 'المستخدمون'),
              Tab(text: 'المجدولات'),
              Tab(text: 'صفحات الهوتسبوت'),
              Tab(text: 'Telegram'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _DeviceTab(router: router),
            _BackupTab(router: router),
            _UsersTab(router: router),
            _SchedTab(router: router),
            _HotspotPagesTab(router: router),
            const _TelegramTab(),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Device tab — info + reboot
// ══════════════════════════════════════════════════════════════

class _DeviceTab extends ConsumerStatefulWidget {
  final MikrotikRouterConfig router;
  const _DeviceTab({required this.router});

  @override
  ConsumerState<_DeviceTab> createState() => _DeviceTabState();
}

class _DeviceTabState extends ConsumerState<_DeviceTab> {
  Map<String, String>? _res;
  String? _identity;
  bool _loading = true;
  bool _rebooting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await runRouterOp(widget.router, (svc) async {
        final res = await svc.systemResource();
        final id = await svc.identity();
        return (res, id);
      });
      if (mounted) {
        setState(() {
          _res = r.$1;
          _identity = r.$2;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reboot() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إعادة تشغيل الراوتر'),
        content: const Text(
            'سيتم قطع الاتصال عن كل المستخدمين مؤقتاً وإعادة تشغيل الجهاز. هل أنت متأكد؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent),
            child: const Text('إعادة التشغيل'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _rebooting = true);
    try {
      await runRouterOp(widget.router, (svc) => svc.reboot());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('تم إرسال أمر إعادة التشغيل — سيعود الراوتر خلال دقيقة'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (_) {
      // RouterOS drops the API connection on reboot — that's success.
    } finally {
      if (mounted) setState(() => _rebooting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const LoadingState();
    }
    final r = _res ?? {};
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Card(
          title: 'معلومات النظام',
          icon: Icons.router_outlined,
          children: [
            _InfoRow('اسم الجهاز', _identity ?? '—'),
            _InfoRow('الإصدار', r['version'] ?? '—'),
            _InfoRow('اللوحة', r['board-name'] ?? '—'),
            _InfoRow('المعالج', '${r['cpu-load'] ?? '0'}%'),
            _InfoRow(
                'الذاكرة',
                '${((int.tryParse(r['free-memory'] ?? '0') ?? 0) / 1048576).toStringAsFixed(1)}MB متاحة'),
            _InfoRow(
                'المساحة',
                '${((int.tryParse(r['free-hdd-space'] ?? '0') ?? 0) / 1048576).toStringAsFixed(1)}MB متاحة'),
            _InfoRow('مدة التشغيل', r['uptime'] ?? '—'),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _rebooting ? null : _reboot,
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent),
            icon: _rebooting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.restart_alt),
            label: const Text('إعادة تشغيل الراوتر'),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'ملاحظة: يُقطع اتصال كل المستخدمين لحظة إعادة التشغيل',
          style: TextStyle(fontSize: 11, color: AppColors.textGray),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Backup tab
// ══════════════════════════════════════════════════════════════

class _BackupTab extends ConsumerStatefulWidget {
  final MikrotikRouterConfig router;
  const _BackupTab({required this.router});

  @override
  ConsumerState<_BackupTab> createState() => _BackupTabState();
}

class _BackupTabState extends ConsumerState<_BackupTab> {
  List<Map<String, String>> _files = [];
  bool _loading = true;
  bool _busy = false;

  List<Map<String, String>> get _backups => _files
      .where((f) => f['type'] == 'backup' || (f['name'] ?? '').endsWith('.backup'))
      .toList();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final f = await runRouterOp(
          widget.router, (svc) => svc.files());
      if (mounted) {
        setState(() {
          _files = f;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    setState(() => _busy = true);
    final name =
        'backup-${DateTime.now().toString().substring(0, 16).replaceAll(RegExp(r'[-: ]'), '')}';
    try {
      await runRouterOp(
          widget.router, (svc) => svc.createBackup(name));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('تم إنشاء النسخة $name.backup'),
            behavior: SnackBarBehavior.floating));
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('تعذّر: $e'),
            backgroundColor: AppColors.accent));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      await runRouterOp(widget.router,
          (svc) => svc.exportConfig(file: 'saiber-export'));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('تم إنشاء ملف saiber-export.rsc'),
            behavior: SnackBarBehavior.floating));
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('تعذّر: $e'),
            backgroundColor: AppColors.accent));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore(Map<String, String> f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('استعادة النسخة'),
        content: Text(
            'استعادة "${f['name']}"؟ سيعيد الراوتر التشغيل ويستبدل الإعدادات الحالية.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent),
            child: const Text('استعادة'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await runRouterOp(widget.router,
          (svc) => svc.loadBackup(f['name'] ?? ''));
    } catch (_) {
      // connection drops during restore — expected
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('جارٍ استعادة النسخة — الراوتر يعيد التشغيل'),
          behavior: SnackBarBehavior.floating));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const LoadingState();
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _busy ? null : _create,
                icon: const Icon(Icons.backup_outlined),
                label: const Text('نسخة جديدة'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _export,
                icon: const Icon(Icons.file_download_outlined),
                label: const Text('تصدير RSC'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_backups.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: Text('لا توجد نسخ احتياطية',
                  style: TextStyle(color: AppColors.textGray)),
            ),
          )
        else
          for (final f in _backups)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.divider),
              ),
              child: ListTile(
                leading: const Icon(Icons.archive_outlined,
                    color: AppColors.lightBlue),
                title: Text(f['name'] ?? '—',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13)),
                subtitle: Text(
                    'الحجم: ${((int.tryParse(f['size'] ?? '0') ?? 0) / 1024).toStringAsFixed(0)} KB'
                    '${(f['creation-time'] ?? '').isNotEmpty ? ' • ${f['creation-time']}' : ''}',
                    style: const TextStyle(
                        color: AppColors.textGray, fontSize: 11)),
                trailing: TextButton(
                  onPressed: () => _restore(f),
                  child: const Text('استعادة'),
                ),
              ),
            ),
        const SizedBox(height: 10),
        const Text(
          'تُحفظ النسخ على الراوتر نفسه — تحميلها للجوال يتطلب FTP (قيد التطوير)',
          style: TextStyle(fontSize: 11, color: AppColors.textLight),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Users & groups tab
// ══════════════════════════════════════════════════════════════

class _UsersTab extends ConsumerStatefulWidget {
  final MikrotikRouterConfig router;
  const _UsersTab({required this.router});

  @override
  ConsumerState<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends ConsumerState<_UsersTab> {
  List<Map<String, String>> _users = [];
  List<Map<String, String>> _groups = [];
  bool _loading = true;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await runRouterOp(widget.router, (svc) async {
        final u = await svc.systemUsers();
        final g = await svc.systemGroups();
        return (u, g);
      });
      if (mounted) {
        setState(() {
          _users = res.$1;
          _groups = res.$2;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _addUser() {
    final name = TextEditingController();
    final pass = TextEditingController();
    final comment = TextEditingController();
    String group = 'read';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('مستخدم نظام جديد'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: name,
                    decoration: const InputDecoration(
                        labelText: 'اسم المستخدم')),
                const SizedBox(height: 10),
                TextField(
                    controller: pass,
                    obscureText: true,
                    decoration: const InputDecoration(
                        labelText: 'كلمة المرور')),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: group,
                  decoration: const InputDecoration(
                      labelText: 'المجموعة'),
                  items: _groups
                      .map((g) => DropdownMenuItem(
                          value: g['name'],
                          child: Text(g['name'] ?? '')))
                      .toList(),
                  onChanged: (v) =>
                      setD(() => group = v ?? 'read'),
                ),
                const SizedBox(height: 10),
                TextField(
                    controller: comment,
                    decoration: const InputDecoration(
                        labelText: 'تعليق (اختياري)')),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () async {
                if (name.text.trim().isEmpty) return;
                try {
                  await runRouterOp(
                      widget.router,
                      (svc) => svc.addSystemUser(
                            name: name.text.trim(),
                            password: pass.text,
                            group: group,
                            comment: comment.text.trim(),
                          ));
                  if (ctx.mounted) Navigator.pop(ctx);
                  _load();
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                        content: Text('تعذّر: $e'),
                        backgroundColor: AppColors.accent));
                  }
                }
              },
              child: const Text('إضافة'),
            ),
          ],
        ),
      ),
    );
  }

  void _addGroup() {
    final name = TextEditingController();
    final comment = TextEditingController();
    final policies = <String, bool>{
      'read': true,
      'write': false,
      'policy': false,
      'test': false,
      'reboot': false,
      'sniff': false,
      'sensitive': false,
      'api': false,
      'winbox': false,
      'web': false,
      'ftp': false,
      'telnet': false,
      'ssh': false,
    };
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('مجموعة صلاحيات'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                    controller: name,
                    decoration: const InputDecoration(
                        labelText: 'اسم المجموعة')),
                const SizedBox(height: 10),
                const Text('السياسات:',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13)),
                Wrap(
                  spacing: 4,
                  children: [
                    for (final e in policies.entries)
                      FilterChip(
                        label: Text(e.key,
                            style: const TextStyle(fontSize: 11)),
                        selected: e.value,
                        onSelected: (v) =>
                            setD(() => policies[e.key] = v),
                      ),
                  ],
                ),
                TextField(
                    controller: comment,
                    decoration: const InputDecoration(
                        labelText: 'تعليق (اختياري)')),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () async {
                if (name.text.trim().isEmpty) return;
                final sel = policies.entries
                    .where((e) => e.value)
                    .map((e) => e.key)
                    .toList();
                try {
                  await runRouterOp(
                      widget.router,
                      (svc) => svc.addSystemGroup(
                            name: name.text.trim(),
                            policies: sel,
                            comment: comment.text.trim(),
                          ));
                  if (ctx.mounted) Navigator.pop(ctx);
                  _load();
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                        content: Text('تعذّر: $e'),
                        backgroundColor: AppColors.accent));
                  }
                }
              },
              child: const Text('إضافة'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const LoadingState();
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(
                        value: 0, label: Text('المستخدمون')),
                    ButtonSegment(
                        value: 1, label: Text('المجموعات')),
                  ],
                  selected: {_tab},
                  onSelectionChanged: (s) =>
                      setState(() => _tab = s.first),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _tab == 0 ? _addUser : _addGroup,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ),
        Expanded(
          child: _tab == 0 ? _usersList() : _groupsList(),
        ),
      ],
    );
  }

  Widget _usersList() {
    if (_users.isEmpty) {
      return const EmptyState('لا يوجد مستخدمون');
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _users.length,
      itemBuilder: (_, i) {
        final u = _users[i];
        final disabled =
            u['disabled'] == 'true' || u['disabled'] == 'yes';
        return _RowCard(
          icon: Icons.manage_accounts_outlined,
          iconColor:
              disabled ? AppColors.textLight : AppColors.primary,
          title: u['name'] ?? '—',
          subtitle:
              'المجموعة: ${u['group'] ?? '—'}${(u['comment'] ?? '').isNotEmpty ? ' • ${u['comment']}' : ''}',
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline,
                color: AppColors.accent, size: 20),
            onPressed: () async {
              try {
                await runRouterOp(widget.router,
                    (svc) => svc.removeSystemUser(u['.id'] ?? ''));
                _load();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text('تعذّر: $e'),
                          backgroundColor: AppColors.accent));
                }
              }
            },
          ),
        );
      },
    );
  }

  Widget _groupsList() {
    if (_groups.isEmpty) {
      return const EmptyState('لا توجد مجموعات');
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _groups.length,
      itemBuilder: (_, i) {
        final g = _groups[i];
        return _RowCard(
          icon: Icons.group_outlined,
          iconColor: AppColors.lightBlue,
          title: g['name'] ?? '—',
          subtitle: 'السياسات: ${g['policy'] ?? '—'}',
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline,
                color: AppColors.accent, size: 20),
            onPressed: () async {
              try {
                await runRouterOp(widget.router,
                    (svc) => svc.removeSystemGroup(g['.id'] ?? ''));
                _load();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text('تعذّر: $e'),
                          backgroundColor: AppColors.accent));
                }
              }
            },
          ),
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Schedulers & scripts tab
// ══════════════════════════════════════════════════════════════

class _SchedTab extends ConsumerStatefulWidget {
  final MikrotikRouterConfig router;
  const _SchedTab({required this.router});

  @override
  ConsumerState<_SchedTab> createState() => _SchedTabState();
}

class _SchedTabState extends ConsumerState<_SchedTab> {
  List<Map<String, String>> _sched = [];
  List<Map<String, String>> _scripts = [];
  bool _loading = true;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await runRouterOp(widget.router, (svc) async {
        final s = await svc.table('/system/scheduler');
        final c = await svc.table('/system/script');
        return (s, c);
      });
      if (mounted) {
        setState(() {
          _sched = res.$1;
          _scripts = res.$2;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _add({required bool script}) {
    final name = TextEditingController();
    final field = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(script ? 'سكريبت جديد' : 'مجدولة جديدة'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: name,
                  decoration:
                      const InputDecoration(labelText: 'الاسم')),
              const SizedBox(height: 10),
              TextField(
                controller: field,
                maxLines: script ? 4 : 1,
                decoration: InputDecoration(
                  labelText: script
                      ? 'كود السكريبت'
                      : 'الفاصل الزمني (مثال: 1d, 4h)',
                  hintText: script
                      ? ':log info "تنبيه"'
                      : null,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              if (name.text.trim().isEmpty) return;
              try {
                await runRouterOp(widget.router, (svc) {
                  if (script) {
                    return svc.tableAdd('/system/script', {
                      'name': name.text.trim(),
                      'source': field.text.trim(),
                    });
                  }
                  return svc.tableAdd('/system/scheduler', {
                    'name': name.text.trim(),
                    'interval': field.text.trim().isEmpty
                        ? '1d'
                        : field.text.trim(),
                    'on-event': name.text.trim(),
                  });
                });
                if (ctx.mounted) Navigator.pop(ctx);
                _load();
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                      content: Text('تعذّر: $e'),
                      backgroundColor: AppColors.accent));
                }
              }
            },
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const LoadingState();
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(
                        value: 0, label: Text('المجدولات')),
                    ButtonSegment(
                        value: 1, label: Text('السكريبتات')),
                  ],
                  selected: {_tab},
                  onSelectionChanged: (s) =>
                      setState(() => _tab = s.first),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: () => _add(script: _tab == 1),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ),
        Expanded(
          child: _tab == 0 ? _schedList() : _scriptsList(),
        ),
      ],
    );
  }

  Widget _schedList() {
    if (_sched.isEmpty) {
      return const EmptyState('لا توجد مجدولات');
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _sched.length,
      itemBuilder: (_, i) {
        final s = _sched[i];
        final disabled =
            s['disabled'] == 'true' || s['disabled'] == 'yes';
        return _RowCard(
          icon: Icons.schedule,
          iconColor: disabled
              ? AppColors.textLight
              : AppColors.warning,
          title: s['name'] ?? '—',
          subtitle:
              'الفاصل: ${s['interval'] ?? '—'} • التالي: ${s['next-run'] ?? '—'}'
              '${(s['on-event'] ?? '').isNotEmpty ? ' • ${s['on-event']}' : ''}',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(
                    disabled
                        ? Icons.play_circle_outline
                        : Icons.pause_circle_outline,
                    color: AppColors.primary,
                    size: 20),
                onPressed: () async {
                  await runRouterOp(
                      widget.router,
                      (svc) => svc.tableSet('/system/scheduler',
                          s['.id'] ?? '', {
                            'disabled': disabled ? 'no' : 'yes',
                          }));
                  _load();
                },
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    color: AppColors.accent, size: 20),
                onPressed: () async {
                  await runRouterOp(
                      widget.router,
                      (svc) => svc.tableRemove(
                          '/system/scheduler', [s['.id'] ?? '']));
                  _load();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _scriptsList() {
    if (_scripts.isEmpty) {
      return const EmptyState('لا توجد سكريبتات');
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _scripts.length,
      itemBuilder: (_, i) {
        final s = _scripts[i];
        return _RowCard(
          icon: Icons.code,
          iconColor: AppColors.lightBlue,
          title: s['name'] ?? '—',
          subtitle: (s['source'] ?? '').length > 60
              ? '${s['source']!.substring(0, 60)}…'
              : s['source'] ?? '—',
          trailing: IconButton(
            icon: const Icon(Icons.play_arrow,
                color: AppColors.success),
            tooltip: 'تشغيل',
            onPressed: () async {
              try {
                await runRouterOp(widget.router,
                    (svc) => svc.runScript(s['name'] ?? ''));
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('تم تشغيل السكريبت'),
                          behavior: SnackBarBehavior.floating));
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text('تعذّر: $e'),
                          backgroundColor: AppColors.accent));
                }
              }
            },
          ),
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Hotspot pages tab — server profiles (html-directory, login-by)
// ══════════════════════════════════════════════════════════════

class _HotspotPagesTab extends ConsumerStatefulWidget {
  final MikrotikRouterConfig router;
  const _HotspotPagesTab({required this.router});

  @override
  ConsumerState<_HotspotPagesTab> createState() =>
      _HotspotPagesTabState();
}

class _HotspotPagesTabState extends ConsumerState<_HotspotPagesTab> {
  List<Map<String, String>> _profiles = [];
  List<Map<String, String>> _files = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await runRouterOp(widget.router, (svc) async {
        final p = await svc.hotspotServerProfiles();
        final f = await svc.files();
        return (p, f);
      });
      if (mounted) {
        setState(() {
          _profiles = res.$1;
          _files = res.$2;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _editProfile(Map<String, String> p) {
    final htmlDir =
        TextEditingController(text: p['html-directory'] ?? '');
    final cookie = TextEditingController(
        text: p['http-cookie-lifetime'] ?? '');
    final logins = <String, bool>{
      'http-chap': (p['login-by'] ?? '').contains('http-chap'),
      'http-pap': (p['login-by'] ?? '').contains('http-pap'),
      'cookie': (p['login-by'] ?? '').contains('cookie'),
      'trial': (p['login-by'] ?? '').contains('trial'),
      'mac': (p['login-by'] ?? '').contains('mac'),
    };
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('إعدادات ${p['name']}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: htmlDir,
                  decoration: const InputDecoration(
                    labelText: 'مجلد صفحات الدخول',
                    helperText:
                        'اسم المجلد على الراوتر الذي يخدم الصفحات',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: cookie,
                  decoration: const InputDecoration(
                      labelText: 'مدة الكوكيز (مثال: 1d)'),
                ),
                const SizedBox(height: 10),
                const Text('طرق الدخول:',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13)),
                Wrap(
                  spacing: 4,
                  children: [
                    for (final e in logins.entries)
                      FilterChip(
                        label: Text(e.key,
                            style: const TextStyle(fontSize: 11)),
                        selected: e.value,
                        onSelected: (v) =>
                            setD(() => logins[e.key] = v),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () async {
                try {
                  await runRouterOp(
                      widget.router,
                      (svc) => svc.setHotspotServerProfile(
                          p['.id'] ?? '', {
                            if (htmlDir.text.isNotEmpty)
                              'html-directory':
                                  htmlDir.text.trim(),
                            if (cookie.text.isNotEmpty)
                              'http-cookie-lifetime':
                                  cookie.text.trim(),
                            'login-by': logins.entries
                                .where((e) => e.value)
                                .map((e) => e.key)
                                .join(','),
                          }));
                  if (ctx.mounted) Navigator.pop(ctx);
                  _load();
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                        content: Text('تعذّر: $e'),
                        backgroundColor: AppColors.accent));
                  }
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const LoadingState();
    }
    final hotspotFiles = _files
        .where((f) =>
            (f['name'] ?? '').contains('hotspot') ||
            (f['name'] ?? '').endsWith('.html'))
        .toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Card(
          title: 'ملفات صفحات الدخول على الراوتر',
          icon: Icons.folder_open,
          children: hotspotFiles.isEmpty
              ? [
                  const Text('لا توجد ملفات',
                      style: TextStyle(
                          color: AppColors.textGray,
                          fontSize: 12)),
                ]
              : [
                  for (final f in hotspotFiles)
                    _InfoRow(
                        f['name'] ?? '—',
                        f['type'] == 'directory'
                            ? 'مجلد'
                            : '${f['size'] ?? '0'} B'),
                ],
        ),
        const SizedBox(height: 14),
        for (final p in _profiles)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.divider),
            ),
            child: ListTile(
              leading: const Icon(Icons.web_asset_outlined,
                  color: AppColors.primary),
              title: Text(p['name'] ?? '—',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14)),
              subtitle: Text(
                'المجلد: ${p['html-directory'] ?? 'hotspot'} • '
                'دخول: ${p['login-by'] ?? '—'}',
                style: const TextStyle(
                    color: AppColors.textGray, fontSize: 11),
              ),
              trailing: const Icon(Icons.edit_outlined,
                  color: AppColors.primary, size: 18),
              onTap: () => _editProfile(p),
            ),
          ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'قوالب صفحات جاهزة بهوية شبكتك أصبحت متاحة — الراوتر يسحبها تلقائياً دون FTP',
                style: TextStyle(fontSize: 11, color: AppColors.textGray),
              ),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: () => context.push('/mikrotik/hotspot-pages',
                    extra: widget.router),
                child: const Text('فتح متجر قوالب الصفحات ←',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Telegram tab — bot settings + test
// ══════════════════════════════════════════════════════════════

class _TelegramTab extends StatefulWidget {
  const _TelegramTab();

  @override
  State<_TelegramTab> createState() => _TelegramTabState();
}

class _TelegramTabState extends State<_TelegramTab> {
  final _token = TextEditingController();
  final _chat = TextEditingController();
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await TelegramSettings.instance.load();
    if (mounted) {
      setState(() {
        _token.text = TelegramSettings.instance.token;
        _chat.text = TelegramSettings.instance.chatId;
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    await TelegramSettings.instance
        .save(_token.text, _chat.text);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('تم حفظ الإعدادات'),
          behavior: SnackBarBehavior.floating));
    }
  }

  Future<void> _test() async {
    setState(() => _sending = true);
    final err = await TelegramSettings.instance.sendMessage(
        'تنبيه تجريبي من تطبيق سايبر لإدارة المايكروتك ✅');
    if (mounted) {
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(err ?? 'تم إرسال الرسالة بنجاح'),
        backgroundColor:
            err == null ? AppColors.success : AppColors.accent,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  void dispose() {
    _token.dispose();
    _chat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const LoadingState();
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Card(
          title: 'إعداد بوت Telegram — خطوة بخطوة',
          icon: Icons.telegram,
          children: const [
            _InfoRow('1', 'أنشئ بوتاً عبر @BotFather وخذ الـ Token'),
            _InfoRow('2', 'أرسل أي رسالة للبوت ثم جلب Chat ID عبر getUpdates'),
            _InfoRow('3', 'الصق القيمتين هنا واحفظ'),
          ],
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _token,
          decoration: const InputDecoration(
              labelText: 'Bot Token',
              hintText: '123456789:ABCdefGHI...'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _chat,
          decoration: const InputDecoration(
              labelText: 'Chat ID', hintText: 'مثال: 123456789'),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_outlined),
                label: const Text('حفظ'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _sending ? null : _test,
                icon: _sending
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2))
                    : const Icon(Icons.send_outlined),
                label: Text(_sending ? 'جارٍ...' : 'رسالة تجربة'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Shared widgets
// ══════════════════════════════════════════════════════════════

class _Card extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  const _Card(
      {required this.title,
      required this.icon,
      required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: AppColors.primary)),
            ],
          ),
          const Divider(height: 18, color: AppColors.divider),
          ...children,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String k, v;
  const _InfoRow(this.k, this.v);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(k,
                style: const TextStyle(
                    color: AppColors.textGray, fontSize: 12)),
          ),
          Expanded(
            child: Text(v,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _RowCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title, subtitle;
  final Widget? trailing;
  const _RowCard(
      {required this.icon,
      required this.iconColor,
      required this.title,
      required this.subtitle,
      this.trailing});

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
        subtitle: Text(subtitle,
            style: const TextStyle(
                color: AppColors.textGray, fontSize: 11)),
        trailing: trailing,
      ),
    );
  }
}
