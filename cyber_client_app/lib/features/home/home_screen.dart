import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:uuid/uuid.dart';

import '../../core/api/cyber_api.dart';
import '../../core/config/app_config.dart';
import '../../core/models/models.dart';
import '../../core/services/device_service.dart';
import '../../core/services/subscriber_store.dart';
import '../../core/services/wifi_profile.dart';
import '../../core/theme/app_theme.dart';
import '../activity/activity_screen.dart';
import '../onboarding/register_screen.dart';

/// Telecom-style home: the 74 number up top, wallet balance, the active
/// package with remaining GB + expiry, «تفعيل» (device bind + Wi-Fi
/// profile), package activation, and the transaction log.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _api = CyberApi();
  final _wifi = WifiProfileService();

  String? _simNo;
  String? _deviceId;
  String? _fullName;

  SubscriberStatus? _status;
  List<CyberPackage>? _packages;
  bool _loading = true;
  String? _error;
  bool _activating = false;
  bool _wifiSuggested = false;
  bool _deleting = false;
  int? _subscribingPackage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _bootstrap() async {
    _simNo = await SubscriberStore.simNo();
    _fullName = await SubscriberStore.fullName();
    _deviceId = await SubscriberStore.deviceId() ?? await DeviceService.deviceId();
    _wifiSuggested = await SubscriberStore.wifiSuggested();
    await _refresh();
  }

  Future<void> _refresh() async {
    if (_simNo == null || _deviceId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _api.current(simNo: _simNo!, deviceId: _deviceId!),
        _api.packages(),
      ]);
      if (!mounted) return;
      setState(() {
        _status = results[0] as SubscriberStatus;
        _packages = results[1] as List<CyberPackage>;
        _loading = false;
      });
    } on CyberApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  /// «تفعيل» — 1) bind device_id + fcm_token on cyber_identities,
  /// 2) install the CyberNet Wi-Fi profile (suggestion / .mobileconfig).
  /// When ops have staged an EAP-TLS bundle the suggestion goes out as
  /// WPA2-Enterprise; otherwise it falls back to the open pilot profile.
  Future<void> _activate() async {
    if (_simNo == null || _deviceId == null) return;
    setState(() => _activating = true);
    try {
      final token = await DeviceService.fcmToken();
      await _api.bindDevice(simNo: _simNo!, deviceId: _deviceId!, fcmToken: token);
      IdentityCert? cert;
      try {
        cert = await _api.certificate(simNo: _simNo!, deviceId: _deviceId!);
      } on CyberApiException {
        cert = null;
      }
      final result = cert != null
          ? await _wifi.install(
              security: 'eap-tls',
              eapIdentity: cert.identity,
              eapDomain: cert.domain,
              caCertBase64: cert.caBase64,
              clientP12Base64: cert.p12Base64,
              p12Password: cert.p12Password,
            )
          : await _wifi.install();
      if (!result.ok &&
          (result.code == 'app_disallowed' || result.code == 'not_allowed')) {
        // Accidental «لا شكراً» on the system prompt latches the denial;
        // the native layer already retried after clearing the stale
        // suggestion, so land the user straight on the system's own
        // allow screen — no custom dialog in between.
        _toast('اسمح بتغيير اتصال Wi-Fi ثم عُد واضغط تفعيل');
        await _wifi.openPermissionSettings();
      } else {
        _toast(result.message);
      }
      if (result.ok) {
        await SubscriberStore.setWifiSuggested(true);
        if (mounted) setState(() => _wifiSuggested = true);
      }
    } on CyberApiException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _activating = false);
    }
  }

  /// «إيقاف» — removes the CyberNet suggestion so the phone stops
  /// auto-joining the network.
  Future<void> _deactivate() async {
    setState(() => _activating = true);
    try {
      final result = await _wifi.uninstall();
      _toast(result.message);
      if (result.ok) {
        await SubscriberStore.setWifiSuggested(false);
        if (mounted) setState(() => _wifiSuggested = false);
      }
    } finally {
      if (mounted) setState(() => _activating = false);
    }
  }

  Future<void> _subscribe(CyberPackage p) async {
    final confirm = await showModalBottomSheet<bool>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => _PackageConfirmSheet(
        package: p,
        balance: _status?.balance ?? 0,
      ),
    );
    if (confirm != true) return;

    setState(() => _subscribingPackage = p.id);
    try {
      await _api.subscribe(
        simNo: _simNo!,
        deviceId: _deviceId!,
        packageId: p.id,
        idempotencyKey: 'sub-${const Uuid().v4()}',
      );
      _toast('تم تفعيل ${p.nameAr} بنجاح');
      await _refresh();
    } on CyberApiException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _subscribingPackage = null);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _header()),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                child: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(48),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : _error != null
                        ? _errorBox()
                        : _body(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- header: brand + the number (telecom style) ----------

  Widget _header() {
    return Container(
      decoration: const BoxDecoration(
        gradient: CyberColors.headerGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
      ),
      padding: const EdgeInsets.fromLTRB(22, 54, 22, 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.sim_card, color: CyberColors.cyan, size: 22),
            const SizedBox(width: 8),
            const Text('سايبر نت',
                style: TextStyle(color: Colors.white70, fontSize: 14)),
            const Spacer(),
            if (_fullName != null)
              Flexible(
                child: Text(
                  _fullName!,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7), fontSize: 12.5),
                ),
              ),
          ]),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    _simNo ?? '—',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2.5,
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed: _simNo == null ? null : _copySim,
                icon: const Icon(Icons.copy_rounded, color: Colors.white70, size: 20),
                tooltip: 'نسخ',
              ),
            ],
          ),
          Text(
            'رقم شريحتك — للشحن والدعم',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
          ),
        ],
      ),
    );
  }

  void _copySim() {
    Clipboard.setData(ClipboardData(text: _simNo!));
    _toast('تم نسخ $_simNo');
  }

  // ---------- body ----------

  Widget _body() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 18),
        _balanceCard(),
        const SizedBox(height: 14),
        _subscriptionCard(),
        const SizedBox(height: 20),
        _activateButton(),
        const SizedBox(height: 22),
        _packagesSection(),
        const SizedBox(height: 18),
        _activityLink(),
      ],
    );
  }

  Widget _errorBox() {
    return Container(
      margin: const EdgeInsets.only(top: 24),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: CyberColors.divider),
      ),
      child: Column(children: [
        Text(_error!, textAlign: TextAlign.center),
        const SizedBox(height: 10),
        TextButton(onPressed: _refresh, child: const Text('إعادة المحاولة')),
      ]),
    );
  }

  Widget _balanceCard() {
    final balance = _status?.balance ?? 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: CyberColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.account_balance_wallet_outlined,
                color: CyberColors.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('رصيد المحفظة',
                  style: TextStyle(color: CyberColors.textGray, fontSize: 12.5)),
              const SizedBox(height: 2),
              Text(
                '${NumberFormat('#,###').format(balance)} ريال',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _subscriptionCard() {
    final sub = _status?.subscription;
    if (sub == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(children: [
            Icon(Icons.cloud_off_outlined, color: CyberColors.textGray.withValues(alpha: 0.7)),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('لا توجد باقة نشطة — فعّل باقة من الأسفل للاتصال',
                  style: TextStyle(color: CyberColors.textGray, fontSize: 13.5)),
            ),
          ]),
        ),
      );
    }
    final pkg = _packages?.where((p) => p.id == sub.packageId).firstOrNull;
    final title = pkg?.nameAr ?? sub.packageName ?? 'الباقة النشطة';
    final remainingGb = sub.remainingBytes == null
        ? null
        : sub.remainingBytes! / (1024 * 1024 * 1024);
    final dateFmt = DateFormat('d/M/y');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.rocket_launch_outlined, color: CyberColors.accent),
            const SizedBox(width: 8),
            Text(title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const Spacer(),
            _statusChip(sub.status),
          ]),
          const SizedBox(height: 16),
          if (remainingGb != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: 1 - sub.usedFraction,
                minHeight: 9,
                backgroundColor: CyberColors.divider,
                valueColor: const AlwaysStoppedAnimation(CyberColors.cyan),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'المتبقي: ${remainingGb.toStringAsFixed(2)} جيجا من ${((sub.dataLimitBytes ?? 0) / (1024 * 1024 * 1024)).toStringAsFixed(0)} جيجا',
              style: const TextStyle(fontSize: 12.5, color: CyberColors.textGray),
            ),
          ] else
            const Text('باقة غير محدودة البيانات',
                style: TextStyle(fontSize: 12.5, color: CyberColors.textGray)),
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.event_outlined, size: 16, color: CyberColors.textGray),
            const SizedBox(width: 6),
            Text(
              'تنتهي ${sub.endsAt != null ? dateFmt.format(sub.endsAt!.toLocal()) : '—'}'
              '${sub.daysLeft != null ? '  (متبقي ${sub.daysLeft} يوم)' : ''}',
              style: const TextStyle(fontSize: 12.5, color: CyberColors.textGray),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _statusChip(String status) {
    final map = {
      'active': ('نشطة', CyberColors.success),
      'exhausted': ('نفدت البيانات', CyberColors.warning),
      'expired': ('منتهية', CyberColors.accent),
      'cancelled': ('ملغاة', CyberColors.textGray),
    };
    final (label, color) = map[status] ?? (status, CyberColors.textGray);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.bold)),
    );
  }

  Widget _activateButton() {
    return Column(children: [
      Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: _wifiSuggested
              ? null
              : const LinearGradient(colors: [CyberColors.accent, Color(0xFFFF5A5F)]),
        ),
        child: ElevatedButton.icon(
          onPressed: _activating ? null : _activate,
          style: ElevatedButton.styleFrom(
            backgroundColor: _wifiSuggested ? CyberColors.success : Colors.transparent,
            shadowColor: Colors.transparent,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          icon: _activating
              ? const SizedBox(
                  height: 20, width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                )
              : Icon(_wifiSuggested ? Icons.wifi : Icons.wifi_find_rounded),
          label: Text(_wifiSuggested ? 'شبكة CyberNet مفعّلة' : 'تفعيل الاتصال التلقائي'),
        ),
      ),
      if (_wifiSuggested) ...[
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: _activating ? null : _deactivate,
          icon: const Icon(Icons.wifi_off_rounded, size: 18),
          label: const Text('إيقاف الاتصال التلقائي'),
          style: TextButton.styleFrom(foregroundColor: CyberColors.textGray),
        ),
      ],
    ]);
  }

  Widget _packagesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(children: [
          Text('الباقات',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          SizedBox(width: 8),
          Expanded(
            child: Text('فعّل باقة من رصيدك',
                style: TextStyle(fontSize: 12, color: CyberColors.textGray)),
          ),
        ]),
        const SizedBox(height: 12),
        if (_packages == null || _packages!.isEmpty)
          const Text('لا باقات متاحة حالياً',
              style: TextStyle(color: CyberColors.textGray, fontSize: 13))
        else
          SizedBox(
            height: 168,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _packages!.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, i) => _packageCard(_packages![i]),
            ),
          ),
      ],
    );
  }

  Widget _packageCard(CyberPackage p) {
    final affordable = (_status?.balance ?? 0) >= p.price;
    final busy = _subscribingPackage == p.id;
    return Container(
      width: 168,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: CyberColors.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(p.nameAr,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 6),
        Text(
          p.dataLimitGb != null
              ? '${p.dataLimitGb!.toStringAsFixed(0)} جيجا • ${p.durationDays} ${p.durationDays == 1 ? 'يوم' : 'أيام'}'
              : '${p.durationDays} ${p.durationDays == 1 ? 'يوم' : 'أيام'}',
          style: const TextStyle(color: CyberColors.textGray, fontSize: 12),
        ),
        const Spacer(),
        Text('${NumberFormat('#,###').format(p.price)} ريال',
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, color: CyberColors.primary)),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: busy || !affordable ? null : () => _subscribe(p),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 9),
              textStyle: const TextStyle(fontSize: 13, fontFamily: kFont),
            ),
            child: busy
                ? const SizedBox(
                    height: 16, width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text(affordable ? 'تفعيل' : 'رصيد غير كافٍ'),
          ),
        ),
      ]),
    );
  }

  Widget _activityLink() {
    return Column(children: [
      const Divider(),
      ListTile(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ActivityScreen()),
        ),
        leading: const Icon(Icons.receipt_long_outlined, color: CyberColors.primary),
        title: const Text('سجل المعاملات',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: const Text('شحن، اشتراكات، استهلاك', style: TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_left_rounded),
      ),
      ListTile(
        onTap: _resetEnrollment,
        leading: Icon(Icons.refresh_rounded, color: CyberColors.textGray.withValues(alpha: 0.6)),
        title: Text('إعادة تسجيل الشريحة',
            style: TextStyle(
                fontSize: 13, color: CyberColors.textGray.withValues(alpha: 0.8))),
      ),
      ListTile(
        onTap: _deleting ? null : _deleteAccount,
        leading: _deleting
            ? const SizedBox(
                height: 20, width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.delete_forever_outlined, color: CyberColors.accent),
        title: const Text('حذف الحساب نهائياً',
            style: TextStyle(
                fontSize: 13, color: CyberColors.accent, fontWeight: FontWeight.bold)),
        subtitle: const Text('يحذف رقمك وبياناتك من الخادم — لا يمكن التراجع',
            style: TextStyle(fontSize: 11)),
      ),
      const SizedBox(height: 8),
      Text(
        'API: ${AppConfig.baseUrl}',
        style: TextStyle(fontSize: 10, color: CyberColors.textGray.withValues(alpha: 0.5)),
      ),
    ]);
  }

  Future<void> _resetEnrollment() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إعادة التسجيل؟'),
        content: const Text('سيتم مسح بيانات الشريحة من هذا الجهاز (رقمك يبقى محفوظاً على الخادم).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('مسح')),
        ],
      ),
    );
    if (ok != true) return;
    await SubscriberStore.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const RegisterScreen()),
      (_) => false,
    );
  }

  /// Google Play account-deletion requirement: wipes the subscriber's
  /// personal data server-side (documents, binding, certificate) then
  /// clears the local enrollment and returns to registration.
  Future<void> _deleteAccount() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الحساب نهائياً؟'),
        content: const Text(
          'سيتم حذف رقم شريحتك وجميع بياناتك (الوثائق، الاشتراكات، الرصيد) من الخادم نهائياً ولا يمكن استرجاعها. هل أنت متأكد؟',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف نهائي', style: TextStyle(color: CyberColors.accent)),
          ),
        ],
      ),
    );
    if (ok != true || _simNo == null || _deviceId == null) return;

    setState(() => _deleting = true);
    try {
      await _api.deleteAccount(simNo: _simNo!, deviceId: _deviceId!);
      await SubscriberStore.clear();
      if (!mounted) return;
      _toast('تم حذف الحساب نهائياً');
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const RegisterScreen()),
        (_) => false,
      );
    } on CyberApiException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }
}

class _PackageConfirmSheet extends StatelessWidget {
  const _PackageConfirmSheet({required this.package, required this.balance});
  final CyberPackage package;
  final double balance;

  @override
  Widget build(BuildContext context) {
    final after = balance - package.price;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('تفعيل ${package.nameAr}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 14),
        _row('السعر', '${NumberFormat('#,###').format(package.price)} ريال'),
        _row('البيانات',
            package.dataLimitGb != null ? '${package.dataLimitGb} جيجا' : 'غير محدود'),
        _row('المدة', '${package.durationDays} ${package.durationDays == 1 ? 'يوم' : 'أيام'}'),
        const Divider(height: 22),
        _row('رصيدك بعد التفعيل', '${NumberFormat('#,###').format(after)} ريال'),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('تأكيد التفعيل'),
          ),
        ),
      ]),
    );
  }

  Widget _row(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Text(k, style: const TextStyle(color: CyberColors.textGray, fontSize: 13)),
        const Spacer(),
        Text(v, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
      ]),
    );
  }
}
