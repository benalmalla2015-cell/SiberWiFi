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

// ══════════════════════════════════════════════════════════════
// Declarative section specs — one generic table screen drives
// every RouterOS admin menu instead of a bespoke screen per table.
// ══════════════════════════════════════════════════════════════

enum _FieldType { text, number, dropdown, toggle, multiline }

class _FieldSpec {
  final String key, label;
  final String hint;
  final _FieldType type;
  final Map<String, String>? labeledOptions;
  final String? optionsPath;
  final bool required;
  final List<(String, String)>? quickFill;

  const _FieldSpec(
    this.key,
    this.label, {
    this.hint = '',
    this.type = _FieldType.text,
    this.labeledOptions,
    this.optionsPath,
    this.required = false,
    this.quickFill,
  });
}

class _SectionSpec {
  final String title, apiPath, feature;
  final IconData icon;
  final Color color;
  final List<_FieldSpec> fields;
  final String Function(Map<String, String>) rowTitle;
  final String Function(Map<String, String>) rowSubtitle;
  final bool addable, editable, deletable, toggleable, readonly;

  const _SectionSpec({
    required this.title,
    required this.apiPath,
    required this.feature,
    required this.icon,
    this.color = AppColors.primary,
    this.fields = const [],
    required this.rowTitle,
    required this.rowSubtitle,
    this.addable = true,
    this.editable = true,
    this.deletable = true,
    this.toggleable = true,
    this.readonly = false,
  });
}

String _str(Map<String, String> m, String k, [String fallback = '—']) =>
    (m[k] ?? '').isEmpty ? fallback : m[k]!;

List<_SectionSpec> _sections() => [
      _SectionSpec(
        title: 'عناوين IP',
        apiPath: '/ip/address',
        feature: MikroFeatures.networkTools,
        icon: Icons.language,
        fields: [
          const _FieldSpec('address', 'العنوان (IP/قناع)',
              hint: '192.168.88.1/24', required: true),
          const _FieldSpec('interface', 'الواجهة',
              type: _FieldType.dropdown,
              optionsPath: '/interface'),
          const _FieldSpec('comment', 'تعليق'),
        ],
        rowTitle: (r) => _str(r, 'address'),
        rowSubtitle: (r) =>
            'الواجهة: ${_str(r, 'interface')} • الشبكة: ${_str(r, 'network')}',
      ),
      _SectionSpec(
        title: 'المسارات',
        apiPath: '/ip/route',
        feature: MikroFeatures.networkTools,
        icon: Icons.alt_route,
        fields: [
          const _FieldSpec('dst-address', 'الوجهة',
              hint: '0.0.0.0/0', required: true),
          const _FieldSpec('gateway', 'البوابة', required: true),
          const _FieldSpec('distance', 'المسافة',
              type: _FieldType.number),
          const _FieldSpec('comment', 'تعليق'),
        ],
        rowTitle: (r) => _str(r, 'dst-address'),
        rowSubtitle: (r) =>
            'البوابة: ${_str(r, 'gateway')} • مسافة: ${_str(r, 'distance', '1')}',
      ),
      _SectionSpec(
        title: 'خوادم DHCP',
        apiPath: '/ip/dhcp-server',
        feature: MikroFeatures.networkTools,
        icon: Icons.dns_outlined,
        fields: [
          const _FieldSpec('name', 'الاسم', required: true),
          const _FieldSpec('interface', 'الواجهة',
              type: _FieldType.dropdown,
              optionsPath: '/interface',
              required: true),
          const _FieldSpec('address-pool', 'مجموعة العناوين',
              type: _FieldType.dropdown, optionsPath: '/ip/pool'),
          const _FieldSpec('lease-time', 'مدة الإيجار',
              hint: '10m, 1h, 1d'),
        ],
        rowTitle: (r) => _str(r, 'name'),
        rowSubtitle: (r) =>
            '${_str(r, 'interface')} • ${_str(r, 'address-pool')}',
      ),
      _SectionSpec(
        title: 'عملاء DHCP',
        apiPath: '/ip/dhcp-client',
        feature: MikroFeatures.networkTools,
        icon: Icons.cloud_download_outlined,
        fields: [
          const _FieldSpec('interface', 'الواجهة',
              type: _FieldType.dropdown,
              optionsPath: '/interface',
              required: true),
          const _FieldSpec('host-name', 'اسم المضيف'),
          const _FieldSpec('client-id', 'معرّف العميل'),
          const _FieldSpec('use-peer-dns', 'استخدام DNS من الخادم',
              type: _FieldType.toggle),
          const _FieldSpec('use-peer-ntp', 'استخدام NTP من الخادم',
              type: _FieldType.toggle),
          const _FieldSpec('add-default-route', 'مسار افتراضي',
              type: _FieldType.dropdown,
              labeledOptions: {
                'نعم': 'yes',
                'لا': 'no',
                'خاص': 'special-classless',
              }),
        ],
        rowTitle: (r) => _str(r, 'interface'),
        rowSubtitle: (r) =>
            'IP: ${_str(r, 'address', 'بانتظار')} • ${_str(r, 'status')}',
      ),
      _SectionSpec(
        title: 'إيجارات DHCP',
        apiPath: '/ip/dhcp-server/lease',
        feature: MikroFeatures.networkTools,
        icon: Icons.assignment_outlined,
        fields: [
          const _FieldSpec('address', 'عنوان IP ثابت',
              required: true),
          const _FieldSpec('mac-address', 'عنوان MAC',
              required: true),
          const _FieldSpec('host-name', 'اسم المضيف'),
          const _FieldSpec('comment', 'تعليق'),
        ],
        rowTitle: (r) =>
            _str(r, 'host-name', _str(r, 'address')),
        rowSubtitle: (r) =>
            '${_str(r, 'address')} • ${_str(r, 'mac-address')} • ${_str(r, 'status', 'ثابت')}',
      ),
      _SectionSpec(
        title: 'مجموعات العناوين',
        apiPath: '/ip/pool',
        feature: MikroFeatures.networkTools,
        icon: Icons.view_list_outlined,
        fields: [
          const _FieldSpec('name', 'اسم المجموعة', required: true),
          const _FieldSpec('ranges', 'نطاق العناوين',
              hint: '192.168.88.10-192.168.88.250',
              required: true),
          const _FieldSpec('comment', 'تعليق'),
        ],
        rowTitle: (r) => _str(r, 'name'),
        rowSubtitle: (r) => _str(r, 'ranges'),
      ),
      _SectionSpec(
        title: 'إدخالات DNS الثابتة',
        apiPath: '/ip/dns/static',
        feature: MikroFeatures.networkTools,
        icon: Icons.public,
        fields: [
          const _FieldSpec('name', 'النطاق', required: true),
          const _FieldSpec('address', 'عنوان IP', required: true),
          const _FieldSpec('comment', 'تعليق'),
        ],
        rowTitle: (r) => _str(r, 'name'),
        rowSubtitle: (r) => _str(r, 'address'),
      ),
      _SectionSpec(
        title: 'جدول ARP',
        apiPath: '/ip/arp',
        feature: MikroFeatures.networkTools,
        icon: Icons.table_chart_outlined,
        fields: [
          const _FieldSpec('address', 'عنوان IP', required: true),
          const _FieldSpec('mac-address', 'عنوان MAC',
              required: true),
          const _FieldSpec('interface', 'الواجهة',
              type: _FieldType.dropdown,
              optionsPath: '/interface'),
          const _FieldSpec('published', 'منشور (IP ثابت)',
              type: _FieldType.toggle),
          const _FieldSpec('comment', 'تعليق'),
        ],
        rowTitle: (r) => _str(r, 'address'),
        rowSubtitle: (r) =>
            '${_str(r, 'mac-address')} • ${_str(r, 'interface')}',
      ),
      _SectionSpec(
        title: 'قواعد NAT',
        apiPath: '/ip/firewall/nat',
        feature: MikroFeatures.nat,
        icon: Icons.swap_horiz,
        color: const Color(0xFF8B5CF6),
        fields: [
          const _FieldSpec('chain', 'السلسلة',
              type: _FieldType.dropdown,
              labeledOptions: {
                'مصدر srcnat': 'srcnat',
                'وجهة dstnat': 'dstnat',
              },
              required: true),
          const _FieldSpec('action', 'الإجراء',
              type: _FieldType.dropdown,
              labeledOptions: {
                'تمويه masquerade': 'masquerade',
                'وجهة dst-nat': 'dst-nat',
                'netmap': 'netmap',
                'توجيه منافذ redirect': 'redirect',
                'قبول accept': 'accept',
                'same': 'same',
              },
              required: true),
          const _FieldSpec('protocol', 'البروتوكول',
              type: _FieldType.dropdown,
              labeledOptions: {
                'الكل': '',
                'TCP': 'tcp',
                'UDP': 'udp',
                'ICMP': 'icmp',
              }),
          const _FieldSpec('src-address', 'عنوان المصدر'),
          const _FieldSpec('dst-address', 'عنوان الوجهة'),
          const _FieldSpec('src-port', 'منفذ المصدر'),
          const _FieldSpec('dst-port', 'منفذ الوجهة'),
          const _FieldSpec('in-interface', 'واجهة الدخول',
              type: _FieldType.dropdown,
              optionsPath: '/interface'),
          const _FieldSpec('out-interface', 'واجهة الخروج',
              type: _FieldType.dropdown,
              optionsPath: '/interface'),
          const _FieldSpec('to-addresses', 'إلى العنوان'),
          const _FieldSpec('to-ports', 'إلى المنفذ'),
          const _FieldSpec('comment', 'تعليق'),
        ],
        rowTitle: (r) =>
            '${_str(r, 'chain')} → ${_str(r, 'action')}',
        rowSubtitle: (r) =>
            '${_str(r, 'src-address', '*')} → ${_str(r, 'dst-address', _str(r, 'to-addresses', '*'))}'
            '${(r['comment'] ?? '').isNotEmpty ? ' • ${r['comment']}' : ''}',
      ),
      _SectionSpec(
        title: 'جدار الحماية (Filter)',
        apiPath: '/ip/firewall/filter',
        feature: MikroFeatures.firewall,
        icon: Icons.security,
        color: AppColors.accent,
        fields: [
          const _FieldSpec('chain', 'السلسلة',
              type: _FieldType.dropdown,
              labeledOptions: {
                'دخول input': 'input',
                'توجيه forward': 'forward',
                'خروج output': 'output',
              },
              required: true),
          const _FieldSpec('action', 'الإجراء',
              type: _FieldType.dropdown,
              labeledOptions: {
                'قبول accept': 'accept',
                'رفض drop': 'drop',
                'رفض برد reject': 'reject',
                'عودة return': 'return',
                'إضافة لقائمة المصدر': 'add-src-to-address-list',
                'إضافة لقائمة الوجهة': 'add-dst-to-address-list',
                'passthrough': 'passthrough',
              },
              required: true),
          const _FieldSpec('protocol', 'البروتوكول',
              type: _FieldType.dropdown,
              labeledOptions: {
                'الكل': '',
                'TCP': 'tcp',
                'UDP': 'udp',
                'ICMP': 'icmp',
                'GRE': 'gre',
              }),
          const _FieldSpec('src-address', 'عنوان المصدر'),
          const _FieldSpec('dst-address', 'عنوان الوجهة'),
          const _FieldSpec('src-port', 'منفذ المصدر'),
          const _FieldSpec('dst-port', 'منفذ الوجهة'),
          const _FieldSpec('in-interface', 'واجهة الدخول',
              type: _FieldType.dropdown,
              optionsPath: '/interface'),
          const _FieldSpec('out-interface', 'واجهة الخروج',
              type: _FieldType.dropdown,
              optionsPath: '/interface'),
          const _FieldSpec('connection-state', 'حالة الاتصال',
              type: _FieldType.dropdown,
              labeledOptions: {
                'الكل': '',
                'established': 'established',
                'related': 'related',
                'new': 'new',
                'invalid': 'invalid',
              }),
          const _FieldSpec('comment', 'تعليق'),
        ],
        rowTitle: (r) =>
            '${_str(r, 'chain')} → ${_str(r, 'action')}',
        rowSubtitle: (r) =>
            '${_str(r, 'src-address', '*')} → ${_str(r, 'dst-address', '*')}'
            '${(r['protocol'] ?? '').isNotEmpty ? ' • ${r['protocol']}' : ''}'
            '${(r['comment'] ?? '').isNotEmpty ? ' • ${r['comment']}' : ''}',
      ),
      _SectionSpec(
        title: 'علامات Mangle',
        apiPath: '/ip/firewall/mangle',
        feature: MikroFeatures.firewall,
        icon: Icons.label_outline,
        color: const Color(0xFF8B5CF6),
        fields: [
          const _FieldSpec('chain', 'السلسلة',
              type: _FieldType.dropdown,
              labeledOptions: {
                'قبل التوجيه prerouting': 'prerouting',
                'بعد التوجيه postrouting': 'postrouting',
                'دخول input': 'input',
                'توجيه forward': 'forward',
                'خروج output': 'output',
              },
              required: true),
          const _FieldSpec('action', 'الإجراء',
              type: _FieldType.dropdown,
              labeledOptions: {
                'علامة حزمة mark-packet': 'mark-packet',
                'علامة اتصال mark-connection': 'mark-connection',
                'علامة توجيه mark-routing': 'mark-routing',
                'قبول accept': 'accept',
                'passthrough': 'passthrough',
                'تغيير TTL': 'change-ttl',
              },
              required: true),
          const _FieldSpec('new-packet-mark', 'علامة الحزمة الجديدة'),
          const _FieldSpec('new-connection-mark',
              'علامة الاتصال الجديدة'),
          const _FieldSpec('new-ttl', 'TTL الجديد',
              hint: 'set:1, increment, decrement'),
          const _FieldSpec('src-address', 'عنوان المصدر'),
          const _FieldSpec('dst-address', 'عنوان الوجهة'),
          const _FieldSpec('protocol', 'البروتوكول',
              type: _FieldType.dropdown,
              labeledOptions: {
                'الكل': '',
                'TCP': 'tcp',
                'UDP': 'udp',
                'ICMP': 'icmp',
              }),
          const _FieldSpec('comment', 'تعليق'),
        ],
        rowTitle: (r) =>
            '${_str(r, 'chain')} → ${_str(r, 'action')}',
        rowSubtitle: (r) =>
            '${_str(r, 'new-packet-mark', _str(r, 'new-connection-mark', ''))}'
            '${(r['comment'] ?? '').isNotEmpty ? ' • ${r['comment']}' : ''}',
      ),
      _SectionSpec(
        title: 'قوائم العناوين',
        apiPath: '/ip/firewall/address-list',
        feature: MikroFeatures.firewall,
        icon: Icons.playlist_add,
        color: AppColors.warning,
        fields: [
          const _FieldSpec('list', 'اسم القائمة', required: true),
          const _FieldSpec('address', 'عنوان IP أو نطاق',
              required: true),
          const _FieldSpec('timeout', 'مهلة الانتهاء',
              type: _FieldType.dropdown,
              labeledOptions: {
                'دائم': '',
                'دقيقة': '1m',
                '5 دقائق': '5m',
                '10 دقائق': '10m',
                '30 دقيقة': '30m',
                'ساعة': '1h',
                'ساعتان': '2h',
                '6 ساعات': '6h',
                '12 ساعة': '12h',
                'يوم': '1d',
                'يومان': '2d',
                'أسبوع': '7d',
                'شهر': '30d',
              }),
          const _FieldSpec('comment', 'تعليق'),
        ],
        rowTitle: (r) => _str(r, 'list'),
        rowSubtitle: (r) =>
            '${_str(r, 'address')}${(r['timeout'] ?? '').isNotEmpty ? ' • تنتهي: ${r['timeout']}' : ''}',
      ),
      _SectionSpec(
        title: 'بروتوكولات Layer7',
        apiPath: '/ip/firewall/layer7-protocol',
        feature: MikroFeatures.firewall,
        icon: Icons.layers_outlined,
        color: const Color(0xFF0EA5E9),
        fields: [
          const _FieldSpec('name', 'اسم البروتوكول',
              required: true),
          const _FieldSpec(
            'regexp',
            'التعبير النمطي Regex',
            type: _FieldType.multiline,
            required: true,
            quickFill: [
              ('YouTube', r'^.+(youtube.com|youtu.be).*$'),
              ('Facebook', r'^.+(facebook.com|fb.com|fbcdn.net).*$'),
              ('Instagram',
                  r'^.+(instagram.com|cdninstagram.com).*$'),
              ('WhatsApp', r'^.+(whatsapp.net|whatsapp.com).*$'),
              ('Telegram', r'^.+(telegram.org|t.me).*$'),
              ('TikTok',
                  r'^.+(tiktok.com|tiktokcdn.com|musical.ly).*$'),
              ('PUBG', r'^.+(pubgmobile.com|proximabeta.com).*$'),
            ],
          ),
          const _FieldSpec('comment', 'تعليق'),
        ],
        rowTitle: (r) => _str(r, 'name'),
        rowSubtitle: (r) => _str(r, 'regexp'),
      ),
      _SectionSpec(
        title: 'الاتصالات النشطة',
        apiPath: '/ip/firewall/connection',
        feature: MikroFeatures.firewall,
        icon: Icons.hub,
        readonly: true,
        addable: false,
        editable: false,
        deletable: false,
        toggleable: false,
        fields: const [],
        rowTitle: (r) =>
            '${_str(r, 'src-address')} → ${_str(r, 'dst-address')}',
        rowSubtitle: (r) =>
            '${_str(r, 'protocol')} • ${_str(r, 'tcp-state', '—')}',
      ),
      _SectionSpec(
        title: 'حظر/تجاوز Hotspot',
        apiPath: '/ip/hotspot/ip-binding',
        feature: MikroFeatures.firewall,
        icon: Icons.block,
        color: AppColors.accent,
        fields: [
          const _FieldSpec('address', 'عنوان IP', required: true),
          const _FieldSpec('mac-address', 'عنوان MAC (اختياري)'),
          const _FieldSpec('type', 'نوع الربط',
              type: _FieldType.dropdown,
              labeledOptions: {
                'محظور': 'blocked',
                'تجاوز': 'bypassed',
                'عادي': 'regular',
              },
              required: true),
          const _FieldSpec('comment', 'ملاحظات'),
        ],
        rowTitle: (r) => _str(r, 'address'),
        rowSubtitle: (r) =>
            '${_str(r, 'mac-address', '—')} • ${_str(r, 'type', 'regular')}',
      ),
      _SectionSpec(
        title: 'طوابير السرعة Queues',
        apiPath: '/queue/simple',
        feature: MikroFeatures.queues,
        icon: Icons.speed,
        color: AppColors.lightBlue,
        fields: [
          const _FieldSpec('name', 'اسم الطابور', required: true),
          const _FieldSpec('target', 'الهدف',
              hint: '192.168.88.0/24 أو IP جهاز', required: true),
          const _FieldSpec('max-limit', 'الحد الأقصى للسرعة',
              hint: '4M/4M أو 512K/1M',
              quickFill: [
                ('256K', '256K/256K'),
                ('512K', '512K/512K'),
                ('1M', '1M/1M'),
                ('2M', '2M/2M'),
                ('4M', '4M/4M'),
                ('8M', '8M/8M'),
                ('10M', '10M/10M'),
                ('20M', '20M/20M'),
              ]),
          const _FieldSpec('limit-at', 'الحد الأدنى',
              hint: 'مثال: 1M/1M'),
          const _FieldSpec('burst-limit', 'اندفاع Burst',
              hint: 'مثال: 8M/8M'),
          const _FieldSpec('comment', 'تعليق'),
        ],
        rowTitle: (r) => _str(r, 'name'),
        rowSubtitle: (r) =>
            '${_str(r, 'target')} • ${_str(r, 'max-limit', 'بلا حد')}',
      ),
      _SectionSpec(
        title: 'سيرفرات Hotspot',
        apiPath: '/ip/hotspot/server',
        feature: MikroFeatures.hotspotUsers,
        icon: Icons.wifi_tethering,
        color: AppColors.success,
        fields: const [],
        addable: false,
        editable: false,
        deletable: false,
        rowTitle: (r) => _str(r, 'name'),
        rowSubtitle: (r) =>
            'الواجهة: ${_str(r, 'interface')} • ${r['disabled'] == 'true' ? 'متوقف' : 'يعمل'}',
      ),
    ];

// ══════════════════════════════════════════════════════════════
// Menu screen — grid of sections + tethering-block toggle
// ══════════════════════════════════════════════════════════════

class AdvancedNetworkScreen extends ConsumerWidget {
  final MikrotikRouterConfig router;
  const AdvancedNetworkScreen({super.key, required this.router});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sections = _sections();
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(title: const Text('الشبكة المتقدمة')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _TetheringCard(router: router),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.95,
            ),
            itemCount: sections.length,
            itemBuilder: (_, i) {
              final s = sections[i];
              final allowed =
                  ref.watch(featureAllowedProvider(s.feature));
              return _MenuTile(
                spec: s,
                locked: !allowed,
                onTap: () {
                  if (!allowed) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const Scaffold(
                              body: PremiumLockCard())),
                    );
                    return;
                  }
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          _TableScreen(spec: s, router: router),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final _SectionSpec spec;
  final bool locked;
  final VoidCallback onTap;
  const _MenuTile(
      {required this.spec, required this.locked, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: spec.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(spec.icon, color: spec.color, size: 22),
                ),
                if (locked)
                  Positioned(
                    left: -2,
                    top: -2,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle),
                      child: const Icon(Icons.lock,
                          size: 12, color: AppColors.warning),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                spec.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Tethering block — TTL=1 mangle rule per interface
// ══════════════════════════════════════════════════════════════

class _TetheringCard extends ConsumerStatefulWidget {
  final MikrotikRouterConfig router;
  const _TetheringCard({required this.router});

  @override
  ConsumerState<_TetheringCard> createState() => _TetheringCardState();
}

class _TetheringCardState extends ConsumerState<_TetheringCard> {
  List<Map<String, String>> _ifaces = [];
  Map<String, String> _ruleIds = {}; // iface -> mangle rule .id
  bool _loading = true;

  static const _mark = 'saiber-ttl-block-';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await runRouterOp(widget.router, (svc) async {
        final ifs = await svc.interfaceDetails();
        final rules = await svc.table('/ip/firewall/mangle');
        return (ifs, rules);
      });
      final ids = <String, String>{};
      for (final r in res.$2) {
        final c = r['comment'] ?? '';
        if (c.startsWith(_mark)) {
          ids[c.substring(_mark.length)] = r['.id'] ?? '';
        }
      }
      if (mounted) {
        setState(() {
          _ifaces = res.$1;
          _ruleIds = ids;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(String iface) async {
    try {
      await runRouterOp(widget.router, (svc) async {
        final id = _ruleIds[iface];
        if (id != null) {
          await svc.tableRemove('/ip/firewall/mangle', [id]);
        } else {
          await svc.tableAdd('/ip/firewall/mangle', {
            'chain': 'postrouting',
            'action': 'change-ttl',
            'new-ttl': 'set:1',
            'out-interface': iface,
            'comment': '$_mark$iface',
          });
        }
      });
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_ruleIds.containsKey(iface)
              ? 'تم منع مشاركة الإنترنت على $iface'
              : 'تم إلغاء المنع على $iface'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('تعذّر: $e'),
            backgroundColor: AppColors.accent));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.bluetooth_disabled,
                  color: Colors.white, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text('منع مشاركة الإنترنت (Tethering)',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text('يمنع الأجهزة من مشاركة إنترنت الشبكة عبر TTL=1',
              style:
                  TextStyle(color: Colors.white70, fontSize: 11)),
          const SizedBox(height: 10),
          if (_loading)
            const Center(
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white)))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final i in _ifaces)
                  _IfaceChip(
                    name: i['name'] ?? '',
                    blocked: _ruleIds.containsKey(i['name']),
                    onTap: () => _toggle(i['name'] ?? ''),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _IfaceChip extends StatelessWidget {
  final String name;
  final bool blocked;
  final VoidCallback onTap;
  const _IfaceChip(
      {required this.name,
      required this.blocked,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: blocked
              ? AppColors.accent.withValues(alpha: 0.25)
              : Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: blocked
                ? AppColors.accent
                : Colors.white.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
                blocked
                    ? Icons.block
                    : Icons.check_circle_outline,
                color: Colors.white,
                size: 14),
            const SizedBox(width: 5),
            Text('$name ${blocked ? '— محظور' : ''}',
                style: const TextStyle(
                    color: Colors.white, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Generic table screen
// ══════════════════════════════════════════════════════════════

class _TableScreen extends ConsumerStatefulWidget {
  final _SectionSpec spec;
  final MikrotikRouterConfig router;
  const _TableScreen({required this.spec, required this.router});

  @override
  ConsumerState<_TableScreen> createState() => _TableScreenState();
}

class _TableScreenState extends ConsumerState<_TableScreen> {
  List<Map<String, String>> _rows = [];
  final Map<String, List<String>> _optCache = {};
  String _query = '';
  bool _loading = true;
  String? _error;

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
        final rows = await svc.table(widget.spec.apiPath);
        for (final f in widget.spec.fields) {
          if (f.optionsPath != null &&
              !_optCache.containsKey(f.key)) {
            try {
              final opts = await svc.table(f.optionsPath!);
              _optCache[f.key] = opts
                  .map((o) => o['name'] ?? '')
                  .where((s) => s.isNotEmpty)
                  .toList();
            } catch (_) {
              _optCache[f.key] = [];
            }
          }
        }
        return rows;
      });
      if (mounted) {
        setState(() {
          _rows = res;
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

  Future<void> _op(
    Future<void> Function(RouterOsService svc) fn,
    String done,
  ) async {
    try {
      await runRouterOp(widget.router, fn);
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(done),
            behavior: SnackBarBehavior.floating));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('تعذّر: $e'),
            backgroundColor: AppColors.accent,
            behavior: SnackBarBehavior.floating));
      }
    }
  }

  void _form({Map<String, String>? row}) {
    showDialog(
      context: context,
      builder: (_) => _RowFormDialog(
        spec: widget.spec,
        row: row,
        options: _optCache,
        onSave: (attrs) {
          if (row != null) {
            _op(
                (svc) => svc.tableSet(widget.spec.apiPath,
                    row['.id'] ?? '', attrs),
                'تم الحفظ');
          } else {
            _op((svc) => svc.tableAdd(widget.spec.apiPath, attrs),
                'تمت الإضافة');
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final visible = _rows.where((r) {
      if (_query.isEmpty) return true;
      return '${spec.rowTitle(r)} ${spec.rowSubtitle(r)}'
          .toLowerCase()
          .contains(_query.toLowerCase());
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(title: Text(spec.title)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                hintText: 'بحث...',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const LoadingState()
                : _error != null
                    ? ErrorRetry(
                        message: 'خطأ: $_error', onRetry: _load)
                    : visible.isEmpty
                        ? const EmptyState('لا توجد عناصر')
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(
                                12, 4, 12, 96),
                            itemCount: visible.length,
                            itemBuilder: (_, i) {
                              final r = visible[i];
                              final disabled =
                                  r['disabled'] == 'true' ||
                                      r['disabled'] == 'yes';
                              return Container(
                                margin: const EdgeInsets.only(
                                    bottom: 8),
                                decoration: BoxDecoration(
                                  color: AppColors.white,
                                  borderRadius:
                                      BorderRadius.circular(14),
                                  border: Border.all(
                                      color: AppColors.divider),
                                ),
                                child: ListTile(
                                  dense: true,
                                  leading: Icon(spec.icon,
                                      color: disabled
                                          ? AppColors.textLight
                                          : spec.color),
                                  title: Text(spec.rowTitle(r),
                                      style: const TextStyle(
                                          fontWeight:
                                              FontWeight.w700,
                                          fontSize: 13)),
                                  subtitle: Text(
                                      spec.rowSubtitle(r),
                                      style: const TextStyle(
                                          color:
                                              AppColors.textGray,
                                          fontSize: 11)),
                                  trailing: spec.readonly
                                      ? null
                                      : PopupMenuButton<String>(
                                          icon: const Icon(
                                              Icons.more_vert,
                                              color: AppColors
                                                  .textGray,
                                              size: 20),
                                          onSelected: (v) async {
                                            final id =
                                                r['.id'] ?? '';
                                            switch (v) {
                                              case 'edit':
                                                _form(row: r);
                                              case 'toggle':
                                                _op(
                                                  (svc) => disabled
                                                      ? svc.tableEnable(
                                                          spec.apiPath,
                                                          [id])
                                                      : svc.tableDisable(
                                                          spec.apiPath,
                                                          [id]),
                                                  disabled
                                                      ? 'تم التفعيل'
                                                      : 'تم التعطيل',
                                                );
                                              case 'delete':
                                                final ok =
                                                    await showDialog<
                                                        bool>(
                                                  context:
                                                      context,
                                                  builder: (ctx) =>
                                                      AlertDialog(
                                                    title: const Text(
                                                        'حذف'),
                                                    content: Text(
                                                        'حذف "${spec.rowTitle(r)}"؟'),
                                                    actions: [
                                                      TextButton(
                                                        onPressed: () =>
                                                            Navigator.pop(
                                                                ctx,
                                                                false),
                                                        child: const Text(
                                                            'إلغاء'),
                                                      ),
                                                      ElevatedButton(
                                                        onPressed: () =>
                                                            Navigator.pop(
                                                                ctx,
                                                                true),
                                                        style: ElevatedButton
                                                            .styleFrom(
                                                                backgroundColor:
                                                                    AppColors.accent),
                                                        child: const Text(
                                                            'حذف'),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                                if (ok == true) {
                                                  _op(
                                                      (svc) => svc
                                                          .tableRemove(
                                                              spec.apiPath,
                                                              [
                                                                id
                                                              ]),
                                                      'تم الحذف');
                                                }
                                            }
                                          },
                                          itemBuilder: (_) => [
                                            if (spec.editable)
                                              const PopupMenuItem(
                                                  value: 'edit',
                                                  child: Text(
                                                      'تعديل')),
                                            if (spec.toggleable)
                                              PopupMenuItem(
                                                value: 'toggle',
                                                child: Text(
                                                    disabled
                                                        ? 'تفعيل'
                                                        : 'تعطيل'),
                                              ),
                                            if (spec.deletable)
                                              const PopupMenuItem(
                                                value: 'delete',
                                                child: Text(
                                                    'حذف',
                                                    style: TextStyle(
                                                        color: AppColors
                                                            .accent)),
                                              ),
                                          ],
                                        ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
      floatingActionButton: spec.addable
          ? FloatingActionButton.extended(
              onPressed: () => _form(),
              icon: const Icon(Icons.add),
              label: const Text('إضافة'),
            )
          : null,
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Generic add/edit form dialog
// ══════════════════════════════════════════════════════════════

class _RowFormDialog extends StatefulWidget {
  final _SectionSpec spec;
  final Map<String, String>? row;
  final Map<String, List<String>> options;
  final ValueChanged<Map<String, String>> onSave;

  const _RowFormDialog({
    required this.spec,
    this.row,
    required this.options,
    required this.onSave,
  });

  @override
  State<_RowFormDialog> createState() => _RowFormDialogState();
}

class _RowFormDialogState extends State<_RowFormDialog> {
  final Map<String, TextEditingController> _ctrls = {};
  final Map<String, String> _values = {};
  final Map<String, bool> _bools = {};

  @override
  void initState() {
    super.initState();
    for (final f in widget.spec.fields) {
      final cur = widget.row?[f.key] ?? '';
      switch (f.type) {
        case _FieldType.dropdown:
          _values[f.key] = cur;
        case _FieldType.toggle:
          _bools[f.key] = cur == 'yes' || cur == 'true';
        default:
          _ctrls[f.key] = TextEditingController(text: cur);
      }
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    for (final f in widget.spec.fields) {
      if (f.required) {
        final v = switch (f.type) {
          _FieldType.dropdown => _values[f.key] ?? '',
          _FieldType.toggle => '',
          _ => _ctrls[f.key]?.text.trim() ?? '',
        };
        if (v.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('الحقل مطلوب: ${f.label}'),
              backgroundColor: AppColors.accent));
          return;
        }
      }
    }
    final attrs = <String, String>{};
    for (final f in widget.spec.fields) {
      switch (f.type) {
        case _FieldType.dropdown:
          final v = _values[f.key] ?? '';
          if (v.isNotEmpty) attrs[f.key] = v;
        case _FieldType.toggle:
          attrs[f.key] = (_bools[f.key] ?? false) ? 'yes' : 'no';
        default:
          final v = _ctrls[f.key]?.text.trim() ?? '';
          if (v.isNotEmpty) attrs[f.key] = v;
      }
    }
    widget.onSave(attrs);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.row != null;
    return AlertDialog(
      title:
          Text(editing ? 'تعديل' : 'إضافة — ${widget.spec.title}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final f in widget.spec.fields) ...[
              _buildField(f),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: _save,
          child: Text(editing ? 'حفظ' : 'إضافة'),
        ),
      ],
    );
  }

  Widget _buildField(_FieldSpec f) {
    switch (f.type) {
      case _FieldType.dropdown:
        final opts = f.labeledOptions != null
            ? f.labeledOptions!
            : <String, String>{
                for (final o in widget.options[f.key] ?? <String>[])
                  o: o,
              };
        return DropdownButtonFormField<String>(
          initialValue: (_values[f.key]?.isNotEmpty ?? false)
              ? _values[f.key]
              : null,
          decoration: InputDecoration(
              labelText: f.label + (f.required ? ' *' : '')),
          isExpanded: true,
          items: opts.entries
              .map((e) => DropdownMenuItem(
                  value: e.value, child: Text(e.key)))
              .toList(),
          onChanged: (v) => setState(() => _values[f.key] = v ?? ''),
        );
      case _FieldType.toggle:
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(f.label, style: const TextStyle(fontSize: 13)),
          value: _bools[f.key] ?? false,
          onChanged: (v) => setState(() => _bools[f.key] = v),
        );
      case _FieldType.multiline:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _ctrls[f.key],
              maxLines: 3,
              decoration: InputDecoration(
                  labelText: f.label + (f.required ? ' *' : ''),
                  hintText: f.hint.isEmpty ? null : f.hint),
            ),
            if (f.quickFill != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final q in f.quickFill!)
                      ActionChip(
                        label: Text(q.$1,
                            style: const TextStyle(fontSize: 11)),
                        onPressed: () => setState(
                            () => _ctrls[f.key]!.text = q.$2),
                      ),
                  ],
                ),
              ),
          ],
        );
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _ctrls[f.key],
              keyboardType: f.type == _FieldType.number
                  ? TextInputType.number
                  : TextInputType.text,
              decoration: InputDecoration(
                  labelText: f.label + (f.required ? ' *' : ''),
                  hintText: f.hint.isEmpty ? null : f.hint),
            ),
            if (f.quickFill != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final q in f.quickFill!)
                      ActionChip(
                        label: Text(q.$1,
                            style: const TextStyle(fontSize: 11)),
                        onPressed: () => setState(
                            () => _ctrls[f.key]!.text = q.$2),
                      ),
                  ],
                ),
              ),
          ],
        );
    }
  }
}
