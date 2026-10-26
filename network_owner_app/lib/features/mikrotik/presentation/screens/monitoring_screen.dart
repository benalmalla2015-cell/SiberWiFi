import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/feature_keys.dart';
import '../../data/router_model.dart';
import '../../data/router_os_service.dart';
import '../providers/entitlement_provider.dart';
import '../providers/mikrotik_provider.dart';
import '../widgets/premium_lock_card.dart';
import '../widgets/ui_states.dart';

/// Network monitoring & diagnostics hub — live traffic chart,
/// device health, neighbors, netwatch, logs, and quick tools.
class MonitoringScreen extends ConsumerWidget {
  final MikrotikRouterConfig router;
  const MonitoringScreen({super.key, required this.router});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allowed =
        ref.watch(featureAllowedProvider(MikroFeatures.monitoring));
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
          title: const Text('المراقبة والأدوات'),
          bottom: const TabBar(
            isScrollable: true,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: 'بث مباشر'),
              Tab(text: 'صحة الجهاز'),
              Tab(text: 'الأجهزة والجيران'),
              Tab(text: 'مراقبة شبكة'),
              Tab(text: 'السجلات'),
              Tab(text: 'أدوات'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _LiveTrafficTab(router: router),
            _HealthTab(router: router),
            _NeighborsTab(router: router),
            _NetwatchTab(router: router),
            _LogsTab(router: router),
            _ToolsTab(router: router),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Live traffic tab — polls monitor-traffic(once) every 1.5s on a
// single long-lived connection; plots rx/tx with fl_chart.
// ══════════════════════════════════════════════════════════════

class _LiveTrafficTab extends ConsumerStatefulWidget {
  final MikrotikRouterConfig router;
  const _LiveTrafficTab({required this.router});

  @override
  ConsumerState<_LiveTrafficTab> createState() => _LiveTrafficTabState();
}

class _LiveTrafficTabState extends ConsumerState<_LiveTrafficTab> {
  RouterOsService? _svc;
  Timer? _timer;
  List<String> _ifaces = [];
  String? _iface;
  bool _streaming = false;
  String? _error;
  int _rx = 0, _tx = 0;
  final List<FlSpot> _rxSpots = [];
  final List<FlSpot> _txSpots = [];
  int _tick = 0;
  static const _window = 60; // points kept on screen

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _svc?.close();
    super.dispose();
  }

  Future<void> _boot() async {
    try {
      _svc = await RouterOsService.connect(widget.router);
      final ifs = await _svc!.interfaceDetails();
      if (!mounted) return;
      setState(() {
        _ifaces = ifs.map((i) => i['name'] ?? '').toList();
        _iface = _ifaces.isNotEmpty ? _ifaces.first : null;
        _error = null;
      });
      _startStream();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _startStream() {
    if (_svc == null || _iface == null) return;
    _timer?.cancel();
    _streaming = true;
    _timer = Timer.periodic(
        const Duration(milliseconds: 1500), (_) => _poll());
    _poll();
  }

  Future<void> _poll() async {
    final svc = _svc;
    final ifn = _iface;
    if (svc == null || ifn == null) return;
    try {
      final m = await svc.interfaceMonitorOnce(ifn);
      if (!mounted) return;
      setState(() {
        _rx = int.tryParse(
                m['rx-bits-per-second'] ?? m['rx-bps'] ?? '0') ??
            0;
        _tx = int.tryParse(
                m['tx-bits-per-second'] ?? m['tx-bps'] ?? '0') ??
            0;
        _rxSpots.add(FlSpot(_tick.toDouble(), _rx.toDouble()));
        _txSpots.add(FlSpot(_tick.toDouble(), _tx.toDouble()));
        _tick++;
        if (_rxSpots.length > _window) _rxSpots.removeAt(0);
        if (_txSpots.length > _window) _txSpots.removeAt(0);
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = '$e');
        _stopStream();
      }
    }
  }

  void _stopStream() {
    _timer?.cancel();
    setState(() => _streaming = false);
  }

  String _rate(int bps) {
    if (bps >= 1000000000) {
      return '${(bps / 1e9).toStringAsFixed(1)} Gbps';
    }
    if (bps >= 1000000) return '${(bps / 1e6).toStringAsFixed(1)} Mbps';
    if (bps >= 1000) return '${(bps / 1e3).toStringAsFixed(1)} Kbps';
    return '$bps bps';
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null && _ifaces.isEmpty) {
      return ErrorRetry(message: _error!, onRetry: _boot);
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButtonFormField<String>(
          initialValue: _iface,
          decoration: const InputDecoration(
              labelText: 'الواجهة', prefixIcon: Icon(Icons.cable)),
          items: _ifaces
              .map((n) => DropdownMenuItem(value: n, child: Text(n)))
              .toList(),
          onChanged: (v) => setState(() {
            _iface = v;
            _rxSpots.clear();
            _txSpots.clear();
            _rx = _tx = 0;
            if (_streaming) _startStream();
          }),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _RateCard(
                label: 'تحميل (RX)',
                value: _rate(_rx),
                color: AppColors.success,
                icon: Icons.download_outlined,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _RateCard(
                label: 'رفع (TX)',
                value: _rate(_tx),
                color: AppColors.accent,
                icon: Icons.upload_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          height: 220,
          padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
          decoration: BoxDecoration(
            color: AppColors.inputBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.divider),
          ),
          child: LineChart(
            LineChartData(
              gridData: const FlGridData(show: false),
              titlesData: const FlTitlesData(show: false),
              borderData: FlBorderData(show: false),
              lineBarsData: [
                LineChartBarData(
                  spots: _rxSpots,
                  color: AppColors.success,
                  barWidth: 2.5,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: AppColors.success.withValues(alpha: 0.12),
                  ),
                ),
                LineChartBarData(
                  spots: _txSpots,
                  color: AppColors.accent,
                  barWidth: 2.5,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: AppColors.accent.withValues(alpha: 0.1),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _legend(AppColors.success, 'تحميل'),
            const SizedBox(width: 16),
            _legend(AppColors.accent, 'رفع'),
          ],
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () {
              if (_streaming) {
                _stopStream();
              } else {
                setState(() => _streaming = true);
                _startStream();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  _streaming ? AppColors.textGray : AppColors.primary,
            ),
            icon: Icon(_streaming
                ? Icons.stop_outlined
                : Icons.play_arrow_outlined),
            label: Text(_streaming ? 'إيقاف البث' : 'بدء البث المباشر'),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('خطأ في البث: $_error',
                style: const TextStyle(
                    color: AppColors.accent, fontSize: 12),
                textAlign: TextAlign.center),
          ),
      ],
    );
  }

  Widget _legend(Color c, String label) => Row(
        children: [
          Container(
              width: 10,
              height: 10,
              decoration:
                  BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textGray)),
        ],
      );
}

// ══════════════════════════════════════════════════════════════
// Health & resources tab
// ══════════════════════════════════════════════════════════════

class _HealthTab extends ConsumerStatefulWidget {
  final MikrotikRouterConfig router;
  const _HealthTab({required this.router});

  @override
  ConsumerState<_HealthTab> createState() => _HealthTabState();
}

class _HealthTabState extends ConsumerState<_HealthTab> {
  Map<String, String>? _resource;
  List<Map<String, String>>? _health;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await runRouterOp(widget.router, (svc) async {
        final r = await svc.systemResource();
        List<Map<String, String>> h = [];
        try {
          h = await svc.systemHealth();
        } catch (_) {
          h = []; // boards without sensors
        }
        return (r, h);
      });
      if (mounted) {
        setState(() {
          _resource = res.$1;
          _health = res.$2;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Expanded(
                child: Text(k,
                    style: const TextStyle(
                        color: AppColors.textGray, fontSize: 13))),
            Text(v,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 13)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const LoadingState();
    }
    if (_error != null) {
      return ErrorRetry(message: _error!, onRetry: _load);
    }
    final r = _resource ?? {};
    final totalMem =
        int.tryParse(r['total-memory'] ?? '0') ?? 0;
    final freeMem = int.tryParse(r['free-memory'] ?? '0') ?? 0;
    final usedMem =
        totalMem > 0 ? ((totalMem - freeMem) / totalMem * 100) : 0.0;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Section(
            title: 'موارد النظام',
            icon: Icons.memory,
            children: [
              _row('الإصدار', r['version'] ?? '—'),
              _row('اللوحة', r['board-name'] ?? '—'),
              _row('المعالج', '${r['cpu-load'] ?? '0'}%'),
              _row(
                'الذاكرة',
                '${(freeMem / 1048576).toStringAsFixed(1)}MB متاحة '
                    '(${usedMem.toStringAsFixed(0)}% مستخدمة)',
              ),
              _row('مدة التشغيل', r['uptime'] ?? '—'),
              _row('المعمارية', r['architecture-name'] ?? '—'),
            ],
          ),
          const SizedBox(height: 14),
          _Section(
            title: 'صحة الجهاز',
            icon: Icons.monitor_heart_outlined,
            children: (_health ?? []).isEmpty
                ? [
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                          'مستشعرات الصحة غير متوفرة في هذا الجهاز',
                          style: TextStyle(
                              color: AppColors.textGray,
                              fontSize: 12)),
                    ),
                  ]
                : [
                    for (final h in _health!)
                      _row(h['name'] ?? '—',
                          '${h['value'] ?? '—'} ${h['type'] ?? ''}'),
                  ],
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Neighbors & connected devices tab
// ══════════════════════════════════════════════════════════════

class _NeighborsTab extends ConsumerStatefulWidget {
  final MikrotikRouterConfig router;
  const _NeighborsTab({required this.router});

  @override
  ConsumerState<_NeighborsTab> createState() => _NeighborsTabState();
}

class _NeighborsTabState extends ConsumerState<_NeighborsTab> {
  List<Map<String, String>> _neighbors = [];
  List<Map<String, String>> _hosts = [];
  List<Map<String, String>> _leases = [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await runRouterOp(widget.router, (svc) async {
        List<Map<String, String>> n = [], h = [], l = [];
        try {
          n = await svc.neighbors();
        } catch (_) {}
        try {
          h = await svc.hotspotHosts();
        } catch (_) {}
        try {
          l = await svc.dhcpLeases();
        } catch (_) {}
        return (n, h, l);
      });
      if (mounted) {
        setState(() {
          _neighbors = res.$1;
          _hosts = res.$2;
          _leases = res.$3;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const LoadingState();
    }
    if (_error != null) {
      return ErrorRetry(message: _error!, onRetry: _load);
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: _CountCard(
                    label: 'أجهزة متصلة',
                    count: _hosts.length,
                    color: AppColors.success,
                    icon: Icons.devices),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _CountCard(
                    label: 'أجهزة مجاورة',
                    count: _neighbors.length,
                    color: AppColors.lightBlue,
                    icon: Icons.hub_outlined),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _CountCard(
                    label: 'إيجارات DHCP',
                    count: _leases.length,
                    color: AppColors.warning,
                    icon: Icons.dns_outlined),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _Section(
            title: 'الأجهزة المجاورة (Neighbor)',
            icon: Icons.hub_outlined,
            children: _neighbors.isEmpty
                ? [
                    const Text('لا توجد أجهزة مجاورة',
                        style: TextStyle(
                            color: AppColors.textGray, fontSize: 12)),
                  ]
                : [
                    for (final n in _neighbors)
                      _deviceRow(
                        n['identity'] ?? n['mac-address'] ?? '—',
                        'IP: ${n['address'] ?? '—'} • ${n['interface'] ?? ''} • ${n['version'] ?? ''}',
                      ),
                  ],
          ),
          const SizedBox(height: 14),
          _Section(
            title: 'الأجهزة المتصلة (Hotspot Hosts)',
            icon: Icons.devices,
            children: _hosts.isEmpty
                ? [
                    const Text('لا توجد أجهزة متصلة',
                        style: TextStyle(
                            color: AppColors.textGray, fontSize: 12)),
                  ]
                : [
                    for (final h in _hosts)
                      _deviceRow(
                        h['mac-address'] ?? '—',
                        'IP: ${h['address'] ?? '—'} • ${h['uptime'] ?? ''}',
                      ),
                  ],
          ),
        ],
      ),
    );
  }

  Widget _deviceRow(String title, String sub) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            const Icon(Icons.smartphone_outlined,
                size: 18, color: AppColors.lightBlue),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                  Text(sub,
                      style: const TextStyle(
                          color: AppColors.textGray, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      );
}

// ══════════════════════════════════════════════════════════════
// Netwatch tab
// ══════════════════════════════════════════════════════════════

class _NetwatchTab extends ConsumerStatefulWidget {
  final MikrotikRouterConfig router;
  const _NetwatchTab({required this.router});

  @override
  ConsumerState<_NetwatchTab> createState() => _NetwatchTabState();
}

class _NetwatchTabState extends ConsumerState<_NetwatchTab> {
  List<Map<String, String>> _items = [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await runRouterOp(
          widget.router, (svc) => svc.netwatch());
      if (mounted) {
        setState(() {
          _items = list;
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _toggle(Map<String, String> n) async {
    final id = n['.id'] ?? '';
    final disabled =
        n['disabled'] == 'true' || n['disabled'] == 'yes';
    try {
      await runRouterOp(widget.router,
          (svc) => svc.setNetwatch(id, {
                'disabled': disabled ? 'no' : 'yes',
              }));
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('تعذّر: $e'),
            backgroundColor: AppColors.accent));
      }
    }
  }

  Future<void> _delete(Map<String, String> n) async {
    try {
      await runRouterOp(widget.router,
          (svc) => svc.removeNetwatch(n['.id'] ?? ''));
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('تعذّر: $e'),
            backgroundColor: AppColors.accent));
      }
    }
  }

  void _addDialog() {
    final host = TextEditingController();
    final interval = TextEditingController(text: '1m');
    final timeout = TextEditingController(text: '1000');
    final comment = TextEditingController();
    String type = 'simple';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('إضافة مراقبة شبكة'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: host,
                  decoration: const InputDecoration(
                      labelText: 'عنوان IP أو اسم مضيف'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration:
                      const InputDecoration(labelText: 'نوع الاختبار'),
                  items: const [
                    DropdownMenuItem(
                        value: 'simple', child: Text('بسيط (Ping)')),
                    DropdownMenuItem(
                        value: 'icmp', child: Text('ICMP')),
                    DropdownMenuItem(
                        value: 'tcp-conn',
                        child: Text('اتصال TCP')),
                    DropdownMenuItem(
                        value: 'http-get', child: Text('HTTP GET')),
                  ],
                  onChanged: (v) => setD(() => type = v ?? 'simple'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: interval,
                        decoration: const InputDecoration(
                            labelText: 'الفاصل'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: timeout,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'المهلة (ms)'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: comment,
                  decoration: const InputDecoration(
                      labelText: 'تعليق (اختياري)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (host.text.trim().isEmpty) return;
                try {
                  await runRouterOp(
                      widget.router,
                      (svc) => svc.addNetwatch(
                            host: host.text.trim(),
                            type: type,
                            interval: interval.text.trim(),
                            timeout: timeout.text.trim(),
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
    if (_error != null) {
      return ErrorRetry(message: _error!, onRetry: _load);
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: ElevatedButton.icon(
              onPressed: _addDialog,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('إضافة مراقبة'),
            ),
          ),
        ),
        Expanded(
          child: _items.isEmpty
              ? const EmptyState('لا توجد مراقبات شبكة')
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _items.length,
                  itemBuilder: (_, i) {
                    final n = _items[i];
                    final up = n['status'] == 'up';
                    final disabled = n['disabled'] == 'true' ||
                        n['disabled'] == 'yes';
                    return _RowCard(
                      icon: up
                          ? Icons.check_circle_outline
                          : Icons.error_outline,
                      iconColor: disabled
                          ? AppColors.textLight
                          : up
                              ? AppColors.success
                              : AppColors.accent,
                      title: n['host'] ?? '—',
                      subtitle:
                          'الحالة: ${n['status'] ?? '—'} • فاصل: ${n['interval'] ?? '—'}'
                          '${(n['comment'] ?? '').isNotEmpty ? ' • ${n['comment']}' : ''}',
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
                            onPressed: () => _toggle(n),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: AppColors.accent, size: 20),
                            onPressed: () => _delete(n),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Logs tab
// ══════════════════════════════════════════════════════════════

class _LogsTab extends ConsumerStatefulWidget {
  final MikrotikRouterConfig router;
  const _LogsTab({required this.router});

  @override
  ConsumerState<_LogsTab> createState() => _LogsTabState();
}

class _LogsTabState extends ConsumerState<_LogsTab> {
  List<Map<String, String>> _logs = [];
  String? _error;
  bool _loading = true;
  String _query = '';
  bool _errorsOnly = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await runRouterOp(
          widget.router, (svc) => svc.systemLogs());
      if (mounted) {
        setState(() {
          _logs = list.reversed.toList(); // newest first
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  bool _isError(Map<String, String> l) =>
      (l['topics'] ?? '').contains('error') ||
      (l['topics'] ?? '').contains('critical') ||
      (l['topics'] ?? '').contains('warning');

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const LoadingState();
    }
    if (_error != null) {
      return ErrorRetry(message: _error!, onRetry: _load);
    }
    final visible = _logs.where((l) {
      if (_errorsOnly && !_isError(l)) return false;
      if (_query.isNotEmpty) {
        final q = _query.toLowerCase();
        if (!'${l['message'] ?? ''} ${l['topics'] ?? ''}'
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
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: const InputDecoration(
                    hintText: 'بحث في السجلات...',
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('أخطاء فقط',
                    style: TextStyle(fontSize: 12)),
                selected: _errorsOnly,
                selectedColor:
                    AppColors.accent.withValues(alpha: 0.15),
                onSelected: (v) =>
                    setState(() => _errorsOnly = v),
              ),
            ],
          ),
        ),
        Expanded(
          child: visible.isEmpty
              ? const EmptyState('لا توجد سجلات')
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: visible.length,
                  itemBuilder: (_, i) {
                    final l = visible[i];
                    final err = _isError(l);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: err
                            ? AppColors.accent
                                .withValues(alpha: 0.04)
                            : AppColors.inputBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: err
                              ? AppColors.accent
                                  .withValues(alpha: 0.2)
                              : AppColors.divider,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            err
                                ? Icons.error_outline
                                : Icons.info_outline,
                            size: 16,
                            color: err
                                ? AppColors.accent
                                : AppColors.textLight,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l['time'] ?? l['.id'] ?? '',
                                  style: const TextStyle(
                                      fontSize: 10,
                                      color: AppColors.textLight),
                                ),
                                Text(
                                  l['message'] ?? '',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textDark),
                                ),
                                if ((l['topics'] ?? '').isNotEmpty)
                                  Text(
                                    l['topics']!,
                                    style: const TextStyle(
                                        fontSize: 10,
                                        color: AppColors.textGray),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Quick tools tab — Ping + Fetch
// ══════════════════════════════════════════════════════════════

class _ToolsTab extends ConsumerStatefulWidget {
  final MikrotikRouterConfig router;
  const _ToolsTab({required this.router});

  @override
  ConsumerState<_ToolsTab> createState() => _ToolsTabState();
}

class _ToolsTabState extends ConsumerState<_ToolsTab> {
  final _hostCtrl = TextEditingController(text: '8.8.8.8');
  int _count = 4;
  bool _pinging = false;
  List<Map<String, String>> _pingResults = [];

  final _urlCtrl = TextEditingController();
  String _fetchMethod = 'get';
  bool _fetching = false;
  Map<String, String>? _fetchResult;

  Future<void> _ping() async {
    if (_hostCtrl.text.trim().isEmpty) return;
    setState(() {
      _pinging = true;
      _pingResults = [];
    });
    try {
      final res = await runRouterOp(
          widget.router,
          (svc) => svc.ping(_hostCtrl.text.trim(), count: _count));
      if (mounted) setState(() => _pingResults = res);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('تعذّر: $e'),
            backgroundColor: AppColors.accent));
      }
    } finally {
      if (mounted) setState(() => _pinging = false);
    }
  }

  Future<void> _fetch() async {
    if (_urlCtrl.text.trim().isEmpty) return;
    setState(() {
      _fetching = true;
      _fetchResult = null;
    });
    try {
      final res = await runRouterOp(
          widget.router,
          (svc) => svc.fetchUrl(_urlCtrl.text.trim(),
              method: _fetchMethod));
      if (mounted) {
        setState(() => _fetchResult =
            res.isNotEmpty ? res.first : {'status': 'empty'});
      }
    } catch (e) {
      if (mounted) {
        setState(() => _fetchResult = {'error': '$e'});
      }
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Section(
          title: 'اختبار الاتصال Ping',
          icon: Icons.network_ping,
          children: [
            TextField(
              controller: _hostCtrl,
              decoration: const InputDecoration(
                  labelText: 'عنوان IP أو اسم مضيف'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _count,
                    decoration:
                        const InputDecoration(labelText: 'العدد'),
                    items: const [4, 8, 10, 20]
                        .map((n) =>
                            DropdownMenuItem(value: n, child: Text('$n')))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _count = v ?? 4),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _pinging ? null : _ping,
                    icon: _pinging
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white))
                        : const Icon(Icons.play_arrow),
                    label: Text(_pinging ? 'جارٍ الاختبار...' : 'بدء Ping'),
                  ),
                ),
              ],
            ),
            if (_pingResults.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final p in _pingResults)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_outline,
                          size: 14, color: AppColors.success),
                      const SizedBox(width: 6),
                      Text(
                        'seq ${p['seq'] ?? '—'} • ${p['time'] ?? '—'}ms • ${p['size'] ?? ''}B',
                        style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            color: AppColors.textDark),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        _Section(
          title: 'تحميل البيانات (Fetch)',
          icon: Icons.download_for_offline_outlined,
          children: [
            TextField(
              controller: _urlCtrl,
              decoration: const InputDecoration(
                  labelText: 'URL', hintText: 'http://example.com/file'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _fetchMethod,
                    decoration:
                        const InputDecoration(labelText: 'الطريقة'),
                    items: const ['get', 'post', 'put', 'head']
                        .map((m) =>
                            DropdownMenuItem(value: m, child: Text(m)))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _fetchMethod = v ?? 'get'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _fetching ? null : _fetch,
                    icon: _fetching
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white))
                        : const Icon(Icons.download),
                    label: Text(_fetching ? 'جارٍ...' : 'تنفيذ'),
                  ),
                ),
              ],
            ),
            if (_fetchResult != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.inputBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Text(
                  _fetchResult!.entries
                      .map((e) => '${e.key}: ${e.value}')
                      .join('\n'),
                  style: const TextStyle(
                      fontSize: 11, fontFamily: 'monospace'),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Shared widgets
// ══════════════════════════════════════════════════════════════

class _Section extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  const _Section(
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

class _RateCard extends StatelessWidget {
  final String label, value;
  final Color color;
  final IconData icon;
  const _RateCard(
      {required this.label,
      required this.value,
      required this.color,
      required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value,
                  style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 15)),
              Text(label,
                  style: const TextStyle(
                      fontSize: 10, color: AppColors.textGray)),
            ],
          ),
        ],
      ),
    );
  }
}

class _CountCard extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final IconData icon;
  const _CountCard(
      {required this.label,
      required this.count,
      required this.color,
      required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text('$count',
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 18)),
          Text(label,
              style: const TextStyle(
                  fontSize: 10, color: AppColors.textGray),
              textAlign: TextAlign.center),
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
