import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/feature_keys.dart';
import '../../data/router_model.dart';
import '../../data/router_os_service.dart';
import '../providers/mikrotik_provider.dart';
import '../widgets/feature_gate.dart';
import '../widgets/ui_states.dart';

/// Remote-access state pulled in one session: cloud DDNS, IP services
/// and certificates.
class _RemoteState {
  const _RemoteState({
    required this.cloud,
    required this.services,
    required this.certificates,
    required this.apiFilterRule,
  });

  final Map<String, String> cloud;
  final List<Map<String, String>> services;
  final List<Map<String, String>> certificates;

  /// True when our firewall input rule for the API port exists.
  final bool apiFilterRule;

  Map<String, String>? service(String name) {
    for (final s in services) {
      if (s['name'] == name) return s;
    }
    return null;
  }
}

const _certName = 'saiber-api-ssl';
const _fwComment = 'saiber-remote-api';

final _remoteStateProvider = FutureProvider.autoDispose
    .family<_RemoteState, MikrotikRouterConfig>((ref, cfg) {
  return runRouterOp(cfg, (svc) async {
    final cloud = await svc.cloudStatus();
    final services = await svc.ipServices();
    final certs = await svc.certificates();
    final filters = await svc.table('/ip/firewall/filter');
    final hasRule = filters.any((f) => f['comment'] == _fwComment);
    return _RemoteState(
      cloud: cloud,
      services: services,
      certificates: certs,
      apiFilterRule: hasRule,
    );
  });
});

/// Sprint 10 — Remote access: DDNS + API-SSL service + certificate +
/// firewall allow + one-tap remote connection profile.
class RemoteAccessScreen extends ConsumerStatefulWidget {
  final MikrotikRouterConfig router;
  const RemoteAccessScreen({super.key, required this.router});

  @override
  ConsumerState<RemoteAccessScreen> createState() =>
      _RemoteAccessScreenState();
}

class _RemoteAccessScreenState extends ConsumerState<RemoteAccessScreen> {
  final _portCtrl = TextEditingController(text: '8729');
  final _addressCtrl = TextEditingController();
  bool _busy = false;
  bool _fieldsInit = false;

  MikrotikRouterConfig get router => widget.router;

  @override
  void dispose() {
    _portCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  void _reload() => ref.invalidate(_remoteStateProvider(router));

  Future<void> _run(Future<void> Function(RouterOsService) op,
      {String? okMessage}) async {
    setState(() => _busy = true);
    try {
      await runRouterOp(router, op);
      _reload();
      if (okMessage != null && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(okMessage)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(_remoteStateProvider(router));

    return Scaffold(
      appBar: AppBar(
        title: const Text('الوصول عن بُعد'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
        ],
      ),
      body: FeatureGate(
        feature: MikroFeatures.remoteAccess,
        child: state.when(
          loading: () => const LoadingState(),
          error: (e, _) => ErrorRetry(
            message: 'تعذّر قراءة إعدادات الراوتر',
            onRetry: _reload,
          ),
          data: (s) => _buildBody(context, s),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, _RemoteState s) {
    if (_busy) {
      return const LoadingState();
    }

    final ddnsOn = s.cloud['ddns-enabled'] == 'yes';
    final dnsName = s.cloud['dns-name'] ?? '';
    final apiSsl = s.service('api-ssl');
    final sslOn = apiSsl?['disabled'] == 'false';
    final sslPort = apiSsl?['port'] ?? '8729';
    final certOk = s.certificates
        .any((c) => c['name'] == _certName && c['signed'] == 'yes');

    if (!_fieldsInit) {
      _fieldsInit = true;
      _portCtrl.text = sslPort;
      _addressCtrl.text = apiSsl?['address'] ?? '';
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _DdnsCard(
          enabled: ddnsOn,
          cloud: s.cloud,
          onToggle: (v) => _run(
            (svc) => svc.setCloud({'ddns-enabled': v ? 'yes' : 'no'}),
            okMessage: v ? 'تم تفعيل DDNS' : 'تم إيقاف DDNS',
          ),
        ),
        const SizedBox(height: 14),
        _ServiceCard(
          apiSsl: apiSsl,
          certOk: certOk,
          portCtrl: _portCtrl,
          addressCtrl: _addressCtrl,
          onApply: () => _applyService(s, sslPort),
          onToggle: (v) => _run(
            (svc) => svc.setIpService(
              apiSsl?['.id'] ?? '*7',
              {'disabled': v ? 'false' : 'true'},
            ),
            okMessage: v
                ? 'تم تفعيل خدمة API-SSL'
                : 'تم إيقاف خدمة API-SSL',
          ),
        ),
        const SizedBox(height: 14),
        _CertCard(
          certOk: certOk,
          onCreate: () => _run((svc) async {
            await svc.addCertificate({
              'name': _certName,
              'common-name':
                  dnsName.isNotEmpty ? dnsName : 'router.local',
              'days-valid': '3650',
              'key-usage': 'key-cert-sign,crl-sign,tls-server',
            });
            await svc.signCertificate(_certName);
            if (apiSsl != null) {
              await svc.setIpService(
                  apiSsl['.id']!, {'certificate': _certName});
            }
          }, okMessage: 'تم إنشاء الشهادة وربطها بخدمة API-SSL'),
        ),
        const SizedBox(height: 14),
        _FirewallCard(
          ruleExists: s.apiFilterRule,
          sslPort: sslPort,
          onAdd: () => _run(
            (svc) => svc.tableAdd('/ip/firewall/filter', {
              'chain': 'input',
              'protocol': 'tcp',
              'dst-port': _portCtrl.text.trim().isEmpty
                  ? sslPort
                  : _portCtrl.text.trim(),
              'action': 'accept',
              'comment': _fwComment,
            }),
            okMessage: 'تمت إضافة قاعدة السماح في الفايروول',
          ),
        ),
        const SizedBox(height: 14),
        _ProfileCard(
          canCreate: ddnsOn && dnsName.isNotEmpty && sslOn,
          dnsName: dnsName,
          sslPort: sslPort,
          onCreate: () => _createRemoteProfile(dnsName, sslPort),
        ),
        const SizedBox(height: 14),
        const _SafetyCard(),
      ],
    );
  }

  Future<void> _applyService(_RemoteState s, String currentPort) async {
    final apiSsl = s.service('api-ssl');
    if (apiSsl == null) return;
    final attrs = <String, String>{};
    final port = _portCtrl.text.trim();
    if (port.isNotEmpty && port != currentPort) {
      attrs['port'] = port;
    }
    final addr = _addressCtrl.text.trim();
    attrs['address'] = addr; // empty = any source
    await _run(
      (svc) => svc.setIpService(apiSsl['.id']!, attrs),
      okMessage: 'تم تحديث إعدادات الخدمة',
    );
  }

  Future<void> _createRemoteProfile(String dnsName, String sslPort) async {
    final remote = MikrotikRouterConfig(
      id: '${router.id}-remote',
      name: '${router.name.isEmpty ? router.host : router.name} — عن بُعد',
      host: dnsName,
      port: int.tryParse(_portCtrl.text.trim()) ??
          int.tryParse(sslPort) ??
          8729,
      username: router.username,
      password: router.password,
      useSsl: true,
      remoteId: router.remoteId,
      createdAt: DateTime.now(),
    );
    await ref.read(routersProvider.notifier).save(remote);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('تم حفظ ملف الاتصال عن بُعد في قائمة الأجهزة')),
    );
    // Verify it actually connects — best effort, report outcome.
    try {
      final identity = await runRouterOp(
          remote, (svc) => svc.identity());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('الاختبار نجح — $identity')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'حُفظ الملف لكن الاختبار فشل — تحقق من الشهادة والمنفذ')),
      );
    }
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14.5)),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _DdnsCard extends StatelessWidget {
  const _DdnsCard({
    required this.enabled,
    required this.cloud,
    required this.onToggle,
  });

  final bool enabled;
  final Map<String, String> cloud;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final dnsName = cloud['dns-name'] ?? '';
    final publicIp = cloud['public-address'] ?? '';
    final status = cloud['status'] ?? '';

    return _Card(
      icon: Icons.cloud_outlined,
      title: 'اسم DNS السحابي (IP → Cloud)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  enabled
                      ? 'DDNS مفعّل — الراوتر يحدّث عنوانه تلقائياً'
                      : 'DDNS متوقف — فعّله ليحصل الراوتر على اسم ثابت',
                  style: const TextStyle(
                      color: AppColors.textGray, fontSize: 12.5),
                ),
              ),
              Switch(value: enabled, onChanged: onToggle),
            ],
          ),
          if (enabled && dnsName.isNotEmpty) ...[
            const SizedBox(height: 8),
            _InfoLine(
                label: 'اسم DNS',
                value: dnsName,
                copyable: true),
            _InfoLine(label: 'العنوان العام', value: publicIp),
            _InfoLine(label: 'الحالة', value: status),
          ],
        ],
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({
    required this.apiSsl,
    required this.certOk,
    required this.portCtrl,
    required this.addressCtrl,
    required this.onApply,
    required this.onToggle,
  });

  final Map<String, String>? apiSsl;
  final bool certOk;
  final TextEditingController portCtrl;
  final TextEditingController addressCtrl;
  final VoidCallback onApply;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final enabled = apiSsl?['disabled'] == 'false';
    return _Card(
      icon: Icons.lock_outline,
      title: 'خدمة API-SSL',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  enabled
                      ? 'الخدمة تعمل على المنفذ ${apiSsl?['port'] ?? '8729'}'
                      : 'الخدمة متوقفة',
                  style: const TextStyle(
                      color: AppColors.textGray, fontSize: 12.5),
                ),
              ),
              Switch(value: enabled, onChanged: onToggle),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: portCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'منفذ API-SSL',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: addressCtrl,
            decoration: const InputDecoration(
              labelText: 'السماح من عناوين (اختياري)',
              hintText: 'مثال: 10.0.0.0/8,203.0.113.5 — فارغ = الكل',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onApply,
              icon: const Icon(Icons.save_outlined, size: 18),
              label: const Text('تطبيق إعدادات الخدمة'),
            ),
          ),
          if (!certOk) ...[
            const SizedBox(height: 8),
            const Text(
              'ملاحظة: أنشئ الشهادة أدناه قبل تفعيل الخدمة على راوتر فعلي.',
              style: TextStyle(color: AppColors.textGray, fontSize: 11.5),
            ),
          ],
        ],
      ),
    );
  }
}

class _CertCard extends StatelessWidget {
  const _CertCard({required this.certOk, required this.onCreate});

  final bool certOk;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return _Card(
      icon: Icons.verified_user_outlined,
      title: 'شهادة TLS',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            certOk
                ? 'شهادة «$_certName» موقعة وجاهزة.'
                : 'لا توجد شهادة جاهزة — أنشئ شهادة موقعة ذاتياً لخدمة API-SSL.',
            style:
                const TextStyle(color: AppColors.textGray, fontSize: 12.5),
          ),
          if (!certOk) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add_moderator_outlined, size: 18),
                label: const Text('إنشاء شهادة موقعة ذاتياً'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FirewallCard extends StatelessWidget {
  const _FirewallCard({
    required this.ruleExists,
    required this.sslPort,
    required this.onAdd,
  });

  final bool ruleExists;
  final String sslPort;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return _Card(
      icon: Icons.security_outlined,
      title: 'قاعدة الفايروول',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ruleExists
                ? 'قاعدة السماح موجودة بالفعل ($_fwComment).'
                : 'أضف قاعدة تسمح بمرور منفذ API-SSL عبر سلسلة input.',
            style:
                const TextStyle(color: AppColors.textGray, fontSize: 12.5),
          ),
          if (!ruleExists) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add, size: 18),
                label: Text('إضافة قاعدة سماح للمنفذ $sslPort'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.canCreate,
    required this.dnsName,
    required this.sslPort,
    required this.onCreate,
  });

  final bool canCreate;
  final String dnsName;
  final String sslPort;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return _Card(
      icon: Icons.travel_explore_outlined,
      title: 'ملف اتصال عن بُعد',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            canCreate
                ? 'سيُحفظ ملف اتصال جديد: $dnsName:$sslPort (SSL)'
                : 'فعّل DDNS وخدمة API-SSL أولاً لإنشاء ملف الاتصال.',
            style:
                const TextStyle(color: AppColors.textGray, fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: canCreate ? onCreate : null,
              icon: const Icon(Icons.bookmark_add_outlined, size: 18),
              label: const Text('حفظ ملف الاتصال واختباره'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SafetyCard extends StatelessWidget {
  const _SafetyCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFD9B3)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_outlined,
                  color: Color(0xFFD97706), size: 20),
              SizedBox(width: 8),
              Text('إرشادات أمان',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13.5)),
            ],
          ),
          SizedBox(height: 8),
          Text(
            '• استخدم كلمة مرور قوية لمستخدم API\n'
            '• قيّد «السماح من عناوين» بعناوين IP موثوقة إن أمكن\n'
            '• غيّر المنفذ الافتراضي 8729 إلى منفذ غير شائع\n'
            '• أبقِ خدمة api العادية مقيدة على الشبكة المحلية',
            style: TextStyle(fontSize: 12, height: 1.7),
          ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value, this.copyable = false});

  final String label;
  final String value;
  final bool copyable;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(label,
                style: const TextStyle(
                    color: AppColors.textGray, fontSize: 12)),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: const TextStyle(fontSize: 12.5),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (copyable && value.isNotEmpty)
            InkWell(
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: value));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم النسخ')),
                  );
                }
              },
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.copy, size: 16, color: AppColors.primary),
              ),
            ),
        ],
      ),
    );
  }
}
