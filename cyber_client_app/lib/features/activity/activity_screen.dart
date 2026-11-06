import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/api/cyber_api.dart';
import '../../core/models/models.dart';
import '../../core/services/subscriber_store.dart';
import '../../core/theme/app_theme.dart';

/// سجل المعاملات — top-ups, subscriptions, and RADIUS usage sessions
/// served by GET /cyber/activity (CYB-05 fragment).
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  final _api = CyberApi();
  ActivityData? _data;
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
      final sim = await SubscriberStore.simNo();
      final dev = await SubscriberStore.deviceId();
      if (sim == null || dev == null) {
        setState(() {
          _error = 'لا توجد شريحة مسجلة على هذا الجهاز';
          _loading = false;
        });
        return;
      }
      final data = await _api.activity(simNo: sim, deviceId: dev);
      if (mounted) {
        setState(() {
          _data = data;
          _loading = false;
        });
      }
    } on CyberApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('سجل المعاملات')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _errorBox()
              : _list(),
    );
  }

  Widget _errorBox() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(_error!),
        const SizedBox(height: 10),
        TextButton(onPressed: _load, child: const Text('إعادة المحاولة')),
      ]),
    );
  }

  Widget _list() {
    final d = _data!;
    if (d.topups.isEmpty && d.subscriptions.isEmpty && d.sessions.isEmpty) {
      return const Center(
        child: Text('لا معاملات بعد', style: TextStyle(color: CyberColors.textGray)),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          if (d.topups.isNotEmpty) ...[
            _section('الشحن', Icons.add_circle_outline, CyberColors.success),
            ...d.topups.map(_topupTile),
          ],
          if (d.subscriptions.isNotEmpty) ...[
            _section('الاشتراكات', Icons.rocket_launch_outlined, CyberColors.primary),
            ...d.subscriptions.map(_subTile),
          ],
          if (d.sessions.isNotEmpty) ...[
            _section('الاستهلاك', Icons.data_usage_rounded, CyberColors.cyan),
            ...d.sessions.map(_sessionTile),
          ],
        ],
      ),
    );
  }

  Widget _section(String title, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Row(children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      ]),
    );
  }

  Widget _tile({required Widget leading, required String title, String? subtitle, String? trailing}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: leading,
        title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: subtitle != null ? Text(subtitle, style: const TextStyle(fontSize: 12)) : null,
        trailing: trailing != null
            ? Text(trailing, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold))
            : null,
      ),
    );
  }

  String _date(DateTime? dt) =>
      dt == null ? '—' : DateFormat('d/M/y HH:mm').format(dt.toLocal());

  String _gb(int bytes) => '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} جيجا';

  Widget _topupTile(TopupRecord t) => _tile(
        leading: const Icon(Icons.add_circle, color: CyberColors.success),
        title: 'شحن رصيد +${NumberFormat('#,###').format(t.amount)} ريال',
        subtitle: _date(t.at),
        trailing: t.status == 'completed' ? 'مكتمل' : t.status,
      );

  Widget _subTile(SubscriptionInfo s) => _tile(
        leading: const Icon(Icons.rocket_launch, color: CyberColors.primary),
        title: s.packageName ?? 'اشتراك #${s.id}',
        subtitle: '${_date(s.startsAt)} ← ${_date(s.endsAt)}'
            '${s.dataLimitBytes != null ? ' • ${_gb(s.consumedBytes)} / ${_gb(s.dataLimitBytes!)}' : ''}',
        trailing: s.price != null ? '-${NumberFormat('#,###').format(s.price)}' : s.status,
      );

  Widget _sessionTile(SessionRecord s) => _tile(
        leading: Icon(
          s.status == 'active' ? Icons.wifi : Icons.wifi_off_outlined,
          color: s.status == 'active' ? CyberColors.success : CyberColors.textGray,
        ),
        title: s.host ?? 'جلسة شبكة',
        subtitle: '${_date(s.startedAt)} — ${_date(s.lastSeenAt)}',
        trailing: _gb(s.totalOctets),
      );
}
